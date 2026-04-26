import UIKit
import Accelerate
import os.log

// MARK: - 长截图合成器（视频流专用版本）

/// 将所有帧的新增内容区切片按顺序合成一张完整长图
/// 算法原理：
/// 1. 遍历所有帧，使用 VideoVerticalOffsetMatcher 逐帧求偏移，裁出每帧的新增内容切片
/// 2. 若某帧匹配失败，跳过该帧并记录警告日志，不中断流程
/// 3. 预计算所有切片高度，一次性创建目标 CGContext（避免多次重分配）
/// 4. 使用 CGContext 的 draw 方法逐片绘制
/// 5. 接缝处做 Alpha 渐变融合，融合区高度 blendHeight 默认 16px
/// 6. 最终输出 UIImage，scale 与输入帧一致
struct VideoLongScreenshotCompositor {

    private let logger = Logger(subsystem: "com.longscreenshot", category: "VideoLongScreenshotCompositor")

    /// 接缝融合区高度（像素），默认 16px
    var blendHeight: Int = 16

    /// 合成所有帧为一张长截图
    /// - Parameters:
    ///   - frames: 原始截图数组（顺序排列）
    ///   - topHeight: 顶部固定区域高度（像素）
    ///   - bottomHeight: 底部固定区域高度（像素）
    /// - Returns: 拼接完成的长图，失败返回 nil
    func composite(
        frames: [UIImage],
        topHeight: Int,
        bottomHeight: Int
    ) -> UIImage? {
        return composite(frames: frames, grayscaleDataList: nil, topHeight: topHeight, bottomHeight: bottomHeight)
    }

    func composite(
        frames: [UIImage],
        grayscaleDataList: [FrameGrayscaleData?]?,
        topHeight: Int,
        bottomHeight: Int
    ) -> UIImage? {
        guard frames.count >= 2 else {
            logger.error("❌ 至少需要 2 帧进行合成，实际 \(frames.count) 帧")
            return nil
        }

        let scale = frames[0].scale
        let firstCGImage = frames[0].cgImage
        guard let firstCG = firstCGImage else {
            logger.error("❌ 第一帧无法获取 CGImage")
            return nil
        }

        let fullWidth = firstCG.width
        let fullHeight = firstCG.height
        let contentHeight = fullHeight - topHeight - bottomHeight

        guard contentHeight > 0 else {
            logger.error("❌ 内容区高度无效: fullHeight=\(fullHeight), topHeight=\(topHeight), bottomHeight=\(bottomHeight)")
            return nil
        }

        logger.info("🧩 开始长图合成: \(frames.count) 帧, 尺寸 \(fullWidth)×\(fullHeight), 内容区高度 \(contentHeight)")

        var contentImages: [CGImage] = []
        for (index, frame) in frames.enumerated() {
            guard let cgImage = frame.cgImage else {
                logger.warning("⚠️ 第 \(index) 帧无法获取 CGImage，跳过")
                continue
            }

            let cropRect = CGRect(
                x: 0,
                y: topHeight,
                width: fullWidth,
                height: contentHeight
            )

            guard let cropped = cgImage.cropping(to: cropRect) else {
                logger.warning("⚠️ 第 \(index) 帧裁剪内容区失败，跳过")
                continue
            }

            contentImages.append(cropped)
        }

        guard contentImages.count >= 2 else {
            logger.error("❌ 有效内容区图像不足")
            return nil
        }

        let contentGrayscaleList: [FrameGrayscaleData?] = grayscaleDataList?.map { grayOpt in
            guard let gray = grayOpt else { return nil }
            return cropGrayscaleToContentArea(fullGray: gray, topHeight: topHeight, contentHeight: contentHeight)
        } ?? Array(repeating: nil, count: contentImages.count)

        var matcher = VideoVerticalOffsetMatcher()
        var matchResults: [VideoVerticalOffsetMatchResult] = []
        var validIndices: [Int] = [0]
        var lastSuccessIndex = 0
        var consecutiveSkips = 0
        var lastMatchedScrollOffset: Int? = nil
        var consecutiveOffsetDecreasing = 0
        let totalFrames = contentImages.count

        for i in 1..<contentImages.count {
            let isLastFrame = i == totalFrames - 1
            var result: VideoVerticalOffsetMatchResult? = nil
            var usedBaseIndex = lastSuccessIndex
            
            func performMatch(baseIndex: Int, qualityThreshold: Float, uniquenessRatio: Float) -> VideoVerticalOffsetMatchResult? {
                matcher.absoluteQualityThreshold = qualityThreshold
                matcher.secondBestRatio = uniquenessRatio
                
                let prevContent = contentImages[baseIndex]
                let currContent = contentImages[i]
                
                if let prevGray = contentGrayscaleList[baseIndex],
                   let currGray = contentGrayscaleList[i] {
                    return matcher.match(prevGray: prevGray, currGray: currGray)
                } else {
                    return matcher.match(prevContent: prevContent, currContent: currContent)
                }
            }
            
            func validateResult(_ result: VideoVerticalOffsetMatchResult) -> Bool {
                let matchedY = result.matchedY
                let scrollOffset = result.scrollOffset
                let templateHeight = result.templateHeight
                let bestSAD = result.bestSAD
                let secondBestSAD = result.secondBestSAD
                
                let minReasonableY = contentHeight / 4
                let maxReasonableY = contentHeight - templateHeight
                
                let minReasonableOffset = 5
                let maxReasonableOffset = contentHeight
                
                let isSADUnique: Bool
                if secondBestSAD > 0 {
                    let sadRatio = bestSAD / secondBestSAD
                    isSADUnique = sadRatio < 0.998
                } else {
                    isSADUnique = true
                }
                
                let isMatchedYReasonable = matchedY >= minReasonableY && matchedY <= maxReasonableY
                let isScrollOffsetReasonable = scrollOffset > minReasonableOffset && scrollOffset <= maxReasonableOffset
                
                return isMatchedYReasonable && isScrollOffsetReasonable && isSADUnique
            }
            
            func performMatchWithTemplateHeight(baseIndex: Int, qualityThreshold: Float, uniquenessRatio: Float, templateHeight: Int) -> VideoVerticalOffsetMatchResult? {
                matcher.templateHeight = templateHeight
                matcher.absoluteQualityThreshold = qualityThreshold
                matcher.secondBestRatio = uniquenessRatio
                
                let prevContent = contentImages[baseIndex]
                let currContent = contentImages[i]
                
                if let prevGray = contentGrayscaleList[baseIndex],
                   let currGray = contentGrayscaleList[i] {
                    return matcher.match(prevGray: prevGray, currGray: currGray)
                } else {
                    return matcher.match(prevContent: prevContent, currContent: currContent)
                }
            }
            
            func tryMultipleStrategies(baseIndex: Int) -> VideoVerticalOffsetMatchResult? {
                let templateHeights = [200, 100, 50]
                
                for templateHeight in templateHeights {
                    let qualityThreshold: Float = consecutiveSkips >= 2 ? 0.7 : (consecutiveSkips >= 1 ? 0.8 : 0.92)
                    let uniquenessRatio: Float = consecutiveSkips >= 2 ? 0.995 : (consecutiveSkips >= 1 ? 0.98 : 0.95)
                    
                    if let result = performMatchWithTemplateHeight(baseIndex: baseIndex, qualityThreshold: qualityThreshold, uniquenessRatio: uniquenessRatio, templateHeight: templateHeight) {
                        if consecutiveSkips >= 2 {
                            logger.info("⚠️ 连续跳过\(consecutiveSkips)帧，接受模板高度\(templateHeight)的匹配结果")
                            return result
                        }
                        
                        if validateResult(result) {
                            logger.info("✅ 模板高度\(templateHeight)匹配成功")
                            return result
                        }
                    }
                }
                return nil
            }
            
            if isLastFrame {
                logger.info("🔄 最后一帧: 尝试多种策略确保匹配成功")
                
                result = tryMultipleStrategies(baseIndex: lastSuccessIndex)
                if result == nil, i > 1 {
                    result = tryMultipleStrategies(baseIndex: i - 1)
                    usedBaseIndex = i - 1
                }
                
                if result == nil {
                    logger.info("⚠️ 最后一帧所有策略都失败，强制拼接")
                    let estimatedOffset = max(100, lastMatchedScrollOffset ?? 200)
                    let fallbackResult = VideoVerticalOffsetMatchResult(
                        matchedY: max(contentHeight / 4, contentHeight - 200 - estimatedOffset),
                        templateHeight: 100,
                        contentHeight: contentHeight,
                        bestSAD: 1000000,
                        secondBestSAD: 2000000
                    )
                    result = fallbackResult
                }
            } else if consecutiveSkips >= 2 {
                logger.info("🔄 连续跳过\(consecutiveSkips)帧: 积极尝试多种策略")
                
                result = tryMultipleStrategies(baseIndex: lastSuccessIndex)
                if result == nil {
                    result = tryMultipleStrategies(baseIndex: i - 1)
                    usedBaseIndex = i - 1
                }
                
                if result != nil {
                    logger.info("✅ 找到匹配结果，接受它")
                } else {
                    logger.info("⚠️ 所有策略都失败，强制拼接")
                    let estimatedOffset = max(80, lastMatchedScrollOffset ?? 150)
                    let fallbackResult = VideoVerticalOffsetMatchResult(
                        matchedY: max(contentHeight / 4, contentHeight - 100 - estimatedOffset),
                        templateHeight: 50,
                        contentHeight: contentHeight,
                        bestSAD: 1000000,
                        secondBestSAD: 2000000
                    )
                    result = fallbackResult
                }
            } else if consecutiveSkips >= 1 {
                logger.info("🔄 跳过\(consecutiveSkips)帧: 尝试多种模板高度")
                
                result = tryMultipleStrategies(baseIndex: lastSuccessIndex)
                if result == nil {
                    result = tryMultipleStrategies(baseIndex: i - 1)
                    usedBaseIndex = i - 1
                }
            } else {
                result = performMatchWithTemplateHeight(baseIndex: lastSuccessIndex, qualityThreshold: 0.92, uniquenessRatio: 0.95, templateHeight: 200)
                
                if let r = result, !validateResult(r) {
                    logger.info("🔄 lastSuccessIndex 匹配不理想，尝试 i-1")
                    result = performMatchWithTemplateHeight(baseIndex: i - 1, qualityThreshold: 0.88, uniquenessRatio: 0.97, templateHeight: 200)
                    usedBaseIndex = i - 1
                }
            }
            
            if let result = result {
                let matchedY = result.matchedY
                let scrollOffset = result.scrollOffset
                let templateHeight = result.templateHeight
                let bestSAD = result.bestSAD
                let secondBestSAD = result.secondBestSAD
                
                let isValid = validateResult(result)
                
                if isValid || isLastFrame || consecutiveSkips >= 1 {
                    var shouldStop = false
                    if !isLastFrame && consecutiveSkips < 5, let lastOffset = lastMatchedScrollOffset {
                        if scrollOffset < lastOffset && Float(lastOffset - scrollOffset) / Float(lastOffset) > 0.6 {
                            consecutiveOffsetDecreasing += 1
                            if consecutiveOffsetDecreasing >= 4 {
                                logger.warning("⚠️ 检测到进入静止区：连续\(consecutiveOffsetDecreasing)帧scrollOffset变小，停止匹配")
                                shouldStop = true
                            }
                        } else {
                            consecutiveOffsetDecreasing = 0
                        }
                    }
                    
                    if shouldStop {
                        consecutiveSkips += 1
                        if !isLastFrame {
                            continue
                        }
                    }
                    
                    if !isValid {
                        logger.info("⚠️ 接受不完美的匹配结果（连续跳过\(consecutiveSkips)帧）")
                    }
                    
                    matchResults.append(result)
                    validIndices.append(i)
                    lastSuccessIndex = i
                    lastMatchedScrollOffset = scrollOffset
                    consecutiveSkips = 0
                    logger.info("📐 第 \(i) 帧 (基准:\(usedBaseIndex), 模板:\(result.templateHeight)px): matchedY=\(result.matchedY), scrollOffset=\(result.scrollOffset)px")
                } else {
                    var skipReason = ""
                    let minReasonableY = contentHeight / 4
                    let maxReasonableY = contentHeight - templateHeight
                    if !(matchedY >= minReasonableY && matchedY <= maxReasonableY) {
                        skipReason += "matchedY(\(matchedY))不在合理范围[\(minReasonableY)-\(maxReasonableY)"
                    } else if !(scrollOffset > 5 && scrollOffset <= contentHeight) {
                        skipReason += "scrollOffset(\(scrollOffset))不在合理范围"
                    } else {
                        skipReason += "SAD匹配不唯一(best=\(bestSAD), second=\(secondBestSAD))"
                    }
                    logger.warning("⚠️ 第 \(i) 帧匹配成功但 \(skipReason)，跳过")
                    consecutiveSkips += 1
                }
            } else {
                consecutiveSkips += 1
                logger.warning("⚠️ 第 \(i) 帧匹配失败，连续跳过 \(consecutiveSkips) 帧")
            }
        }

        guard validIndices.count >= 2 else {
            logger.error("❌ 有效匹配帧数不足，无法合成")
            return nil
        }

        var sliceInfos: [(frameIndex: Int, startRow: Int, height: Int)] = []
        sliceInfos.append((0, 0, contentHeight))

        var totalNewContentHeight = 0

        for i in 1..<validIndices.count {
            let result = matchResults[i - 1]
            let scrollOffset = result.scrollOffset

            guard scrollOffset > 0 else {
                logger.warning("⚠️ 第 \(validIndices[i]) 帧滚动偏移量无效: \(scrollOffset)，跳过")
                continue
            }

            let actualBlendHeight = min(blendHeight, contentHeight - scrollOffset)

            let startRow = contentHeight - scrollOffset - actualBlendHeight
            let sliceHeight = scrollOffset + actualBlendHeight

            guard startRow >= 0, sliceHeight > 0 else {
                logger.warning("⚠️ 第 \(validIndices[i]) 帧切片计算无效: startRow=\(startRow), height=\(sliceHeight)")
                continue
            }

            sliceInfos.append((validIndices[i], startRow, sliceHeight))
            totalNewContentHeight += scrollOffset
        }

        let finalHeight = topHeight + contentHeight + totalNewContentHeight + bottomHeight

        logger.info("🎨 预计算完成: 总高度 \(finalHeight)px, 切片数 \(sliceInfos.count)")

        let format = UIGraphicsImageRendererFormat()
        format.scale = CGFloat(scale)
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: fullWidth, height: finalHeight),
            format: format
        )

        let finalImage = renderer.image { rendererContext in
            let context = rendererContext.cgContext

            UIColor.white.setFill()
            rendererContext.fill(CGRect(x: 0, y: 0, width: fullWidth, height: finalHeight))

            if topHeight > 0 {
                let topRect = CGRect(x: 0, y: 0, width: fullWidth, height: topHeight)
                if let topFixed = firstCG.cropping(to: topRect) {
                    let topUIImage = UIImage(cgImage: topFixed, scale: CGFloat(scale), orientation: .up)
                    topUIImage.draw(in: CGRect(x: 0, y: 0, width: fullWidth, height: topHeight))
                    logger.debug("✅ 绘制顶部固定区域: \(topHeight)px")
                }
            }

            var currentY = topHeight

            for i in 0..<sliceInfos.count {
                let info = sliceInfos[i]
                let frameIndex = info.frameIndex
                let startRow = info.startRow
                let sliceHeight = info.height
                let contentCG = contentImages[frameIndex]

                let sliceRect = CGRect(
                    x: 0,
                    y: startRow,
                    width: fullWidth,
                    height: sliceHeight
                )

                guard let sliceCG = contentCG.cropping(to: sliceRect) else {
                    logger.warning("⚠️ 裁剪第 \(frameIndex) 帧切片失败")
                    continue
                }

                let sliceUIImage = UIImage(cgImage: sliceCG, scale: CGFloat(scale), orientation: .up)

                if i == 0 {
                    sliceUIImage.draw(in: CGRect(x: 0, y: currentY, width: fullWidth, height: sliceHeight))
                    currentY += sliceHeight
                    logger.debug("✅ 绘制第 0 帧内容区: \(sliceHeight)px, currentY=\(currentY)")
                } else {
                    let actualBlendHeight = min(blendHeight, sliceHeight)
                    let scrollOffset = sliceHeight - actualBlendHeight
                    let drawY = currentY - actualBlendHeight

                    if actualBlendHeight > 0 {
                        let blendRect = CGRect(x: 0, y: 0, width: fullWidth, height: actualBlendHeight)
                        if let blendCG = sliceCG.cropping(to: blendRect) {
                            let blendUIImage = UIImage(cgImage: blendCG, scale: CGFloat(scale), orientation: .up)
                            let blendDrawRect = CGRect(x: 0, y: drawY, width: fullWidth, height: actualBlendHeight)

                            if let gradientMask = createGradientMask(width: fullWidth, height: actualBlendHeight) {
                                context.saveGState()
                                context.clip(to: blendDrawRect, mask: gradientMask)
                                blendUIImage.draw(in: blendDrawRect)
                                context.restoreGState()
                            } else {
                                blendUIImage.draw(in: blendDrawRect)
                            }
                        }

                        if scrollOffset > 0 {
                            let newRect = CGRect(x: 0, y: actualBlendHeight, width: fullWidth, height: scrollOffset)
                            if let newCG = sliceCG.cropping(to: newRect) {
                                let newUIImage = UIImage(cgImage: newCG, scale: CGFloat(scale), orientation: .up)
                                let newDrawRect = CGRect(x: 0, y: drawY + actualBlendHeight, width: fullWidth, height: scrollOffset)
                                newUIImage.draw(in: newDrawRect)
                            }
                        }

                        currentY = drawY + actualBlendHeight + scrollOffset
                        logger.debug("✅ 绘制第 \(frameIndex) 帧: 融合区=\(actualBlendHeight)px, 新增=\(scrollOffset)px, currentY=\(currentY)")
                    } else {
                        sliceUIImage.draw(in: CGRect(x: 0, y: drawY, width: fullWidth, height: sliceHeight))
                        currentY = drawY + sliceHeight
                        logger.debug("✅ 绘制第 \(frameIndex) 帧: height=\(sliceHeight)px, currentY=\(currentY)")
                    }
                }
            }

            if bottomHeight > 0 {
                let actualBottomHeight = finalHeight - currentY
                if actualBottomHeight > 0 {
                    let lastFrame = frames.last
                    if let lastCG = lastFrame?.cgImage {
                        let bottomRect = CGRect(
                            x: 0,
                            y: fullHeight - bottomHeight,
                            width: fullWidth,
                            height: bottomHeight
                        )
                        if let bottomFixed = lastCG.cropping(to: bottomRect) {
                            let bottomUIImage = UIImage(cgImage: bottomFixed, scale: CGFloat(scale), orientation: .up)
                            bottomUIImage.draw(in: CGRect(x: 0, y: currentY, width: fullWidth, height: actualBottomHeight))
                            logger.debug("✅ 绘制底部固定区域: original=\(bottomHeight)px, actual=\(actualBottomHeight)px, y=\(currentY), finalHeight=\(finalHeight) (使用最后一帧)")
                        }
                    } else if let bottomFixed = firstCG.cropping(to: CGRect(x: 0, y: fullHeight - bottomHeight, width: fullWidth, height: bottomHeight)) {
                        let bottomUIImage = UIImage(cgImage: bottomFixed, scale: CGFloat(scale), orientation: .up)
                        bottomUIImage.draw(in: CGRect(x: 0, y: currentY, width: fullWidth, height: actualBottomHeight))
                        logger.debug("✅ 绘制底部固定区域: original=\(bottomHeight)px, actual=\(actualBottomHeight)px, y=\(currentY), finalHeight=\(finalHeight) (使用第一帧)")
                    }
                } else {
                    logger.warning("⚠️ 实际底部高度无效: \(actualBottomHeight)")
                }
            }
        }

        let cropBottomPixels = 1
        let finalCGImage = finalImage.cgImage
        let finalWidth = Int(finalImage.size.width * finalImage.scale)
        let croppedHeight = max(1, finalHeight - cropBottomPixels)
        let cropRect = CGRect(x: 0, y: 0, width: finalWidth, height: croppedHeight)
        if let croppedCGImage = finalCGImage?.cropping(to: cropRect) {
            let croppedImage = UIImage(cgImage: croppedCGImage, scale: finalImage.scale, orientation: .up)
            logger.info("✅ 长图合成完成: \(croppedImage.size.width)×\(croppedImage.size.height) (scale=\(scale), 已裁剪底部 \(cropBottomPixels)px)")
            return croppedImage
        }

        logger.info("✅ 长图合成完成: \(finalImage.size.width)×\(finalImage.size.height) (scale=\(scale))")
        return finalImage
    }

    private func cropGrayscaleToContentArea(fullGray: FrameGrayscaleData, topHeight: Int, contentHeight: Int) -> FrameGrayscaleData? {
        let width = fullGray.width
        let fullHeight = fullGray.height
        guard topHeight + contentHeight <= fullHeight, topHeight >= 0, contentHeight > 0 else { return nil }

        let startOffset = topHeight * width
        let endOffset = (topHeight + contentHeight) * width
        let contentPixels = Array(fullGray.pixels[startOffset..<endOffset])

        return FrameGrayscaleData(pixels: contentPixels, width: width, height: contentHeight)
    }

    // MARK: - 私有辅助方法

    /// 创建渐变遮罩：从上到下，alpha 从 0 渐变到 1
    private func createGradientMask(width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGImageAlphaInfo.none.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        // 渐变颜色：从黑（0，完全透明）到白（255，完全不透明）
        let colors: [CGColor] = [
            UIColor.black.cgColor,
            UIColor.white.cgColor
        ]
        let locations: [CGFloat] = [0.0, 1.0]

        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: colors as CFArray,
            locations: locations
        ) else { return nil }

        // 从上到下渐变
        let startPoint = CGPoint(x: 0, y: 0)
        let endPoint = CGPoint(x: 0, y: height)

        context.drawLinearGradient(
            gradient,
            start: startPoint,
            end: endPoint,
            options: []
        )

        return context.makeImage()
    }
}
