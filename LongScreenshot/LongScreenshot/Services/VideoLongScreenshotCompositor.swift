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

        // 裁剪所有帧的内容区
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

        // 使用 VideoVerticalOffsetMatcher 逐帧计算偏移
        var matcher = VideoVerticalOffsetMatcher()
        var matchResults: [VideoVerticalOffsetMatchResult] = []
        var validIndices: [Int] = [0]
        var lastSuccessIndex = 0  // 记录最后一个成功匹配的帧索引
        var consecutiveSkips = 0   // 连续跳过的帧数
        var lastMatchedScrollOffset: Int? = nil  // 上一次成功的 scrollOffset
        var consecutiveOffsetDecreasing = 0  // scrollOffset 连续变小的次数
        let totalFrames = contentImages.count

        for i in 1..<contentImages.count {
            let prevContent = contentImages[lastSuccessIndex]
            let currContent = contentImages[i]

            // 平衡策略：
            // 1. 默认：严格阈值（防止动画区域重复）
            // 2. 连续跳过≥3帧或最后1帧：放宽阈值（防止内容缺失）
            let isLastFrame = i == totalFrames - 1
            let hasManySkips = consecutiveSkips >= 3

            if isLastFrame || hasManySkips {
                matcher.absoluteQualityThreshold = 0.85
                matcher.secondBestRatio = 0.98
                if isLastFrame {
                    logger.debug("🔄 最后一帧: 放宽阈值以捕获底部内容")
                } else {
                    logger.debug("🔄 连续跳过\(consecutiveSkips)帧: 放宽阈值尝试匹配")
                }
            } else {
                matcher.absoluteQualityThreshold = 0.92
                matcher.secondBestRatio = 0.95
            }

            if let result = matcher.match(prevContent: prevContent, currContent: currContent) {
                // 三重安全检查：
                // 1. matchedY范围检查（核心：防止滚动停止后的误匹配）
                // 2. scrollOffset范围检查（辅助：防止异常位移）
                // 3. SAD唯一性检查（新增：防止bestSAD和secondBestSAD太接近）
                let matchedY = result.matchedY
                let scrollOffset = result.scrollOffset
                let templateHeight = result.templateHeight
                let bestSAD = result.bestSAD
                let secondBestSAD = result.secondBestSAD
                
                // matchedY必须在合理的中间范围
                let minReasonableY = contentHeight / 4
                let maxReasonableY = contentHeight - templateHeight - 100
                
                // scrollOffset的合理范围
                let minReasonableOffset = 10
                let maxReasonableOffset = Int(Double(contentHeight) * 0.8)
                
                // SAD唯一性检查：bestSAD/secondBestSAD必须小于0.995
                let isSADUnique: Bool
                if secondBestSAD > 0 {
                    let sadRatio = bestSAD / secondBestSAD
                    isSADUnique = sadRatio < 0.995
                } else {
                    isSADUnique = true
                }
                
                let isMatchedYReasonable = matchedY >= minReasonableY && matchedY <= maxReasonableY
                let isScrollOffsetReasonable = scrollOffset > minReasonableOffset && scrollOffset < maxReasonableOffset
                
                if isMatchedYReasonable && isScrollOffsetReasonable && isSADUnique {
                    // 检查 scrollOffset 是否持续变小（进入静止区的信号）
                    var shouldStop = false
                    if let lastOffset = lastMatchedScrollOffset {
                        // 如果当前 scrollOffset 比上一次小超过40%，认为是进入静止区
                        if scrollOffset < lastOffset && Float(lastOffset - scrollOffset) / Float(lastOffset) > 0.4 {
                            consecutiveOffsetDecreasing += 1
                            if consecutiveOffsetDecreasing >= 2 {
                                logger.warning("⚠️ 检测到进入静止区：连续\(consecutiveOffsetDecreasing)帧scrollOffset变小，停止匹配")
                                shouldStop = true
                            }
                        } else {
                            consecutiveOffsetDecreasing = 0
                        }
                    }
                    
                    if shouldStop {
                        consecutiveSkips += 1
                        break  // 停止匹配
                    }
                    
                    matchResults.append(result)
                    validIndices.append(i)
                    lastSuccessIndex = i
                    lastMatchedScrollOffset = scrollOffset
                    consecutiveSkips = 0
                    logger.info("📐 第 \(i) 帧: matchedY=\(result.matchedY), scrollOffset=\(result.scrollOffset)px")
                } else {
                    var skipReason = ""
                    if !isMatchedYReasonable {
                        skipReason += "matchedY(\(matchedY))不在合理范围[\(minReasonableY)-\(maxReasonableY)"
                    } else if !isScrollOffsetReasonable {
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

        // 计算每帧的绘制信息
        // 第 0 帧：画完整内容区
        // 第 i 帧 (i>0)：
        //   - 新增内容高度 = scrollOffset
        //   - 为了融合，需要多取顶部 blendHeight 行作为融合区
        //   - 从内容区 startRow = contentHeight - scrollOffset - blendHeight 开始裁剪
        //   - 裁剪高度 = scrollOffset + blendHeight
        //   - 绘制时，融合区在顶部（与上一帧底部重叠），新增内容在底部
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

            // 融合区高度不能超过可用空间
            let actualBlendHeight = min(blendHeight, contentHeight - scrollOffset)

            // 从内容区底部往上数 scrollOffset + blendHeight 行开始裁剪
            let startRow = contentHeight - scrollOffset - actualBlendHeight
            let sliceHeight = scrollOffset + actualBlendHeight

            guard startRow >= 0, sliceHeight > 0 else {
                logger.warning("⚠️ 第 \(validIndices[i]) 帧切片计算无效: startRow=\(startRow), height=\(sliceHeight)")
                continue
            }

            sliceInfos.append((validIndices[i], startRow, sliceHeight))
            totalNewContentHeight += scrollOffset
        }

        // 最终高度 = 顶部固定区 + 第一帧完整内容区 + 所有后续帧新增内容 + 底部固定区
        let finalHeight = topHeight + contentHeight + totalNewContentHeight + bottomHeight

        logger.info("🎨 预计算完成: 总高度 \(finalHeight)px, 切片数 \(sliceInfos.count)")

        // 使用 UIGraphicsImageRenderer 进行绘制
        let format = UIGraphicsImageRendererFormat()
        format.scale = CGFloat(scale)
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: fullWidth, height: finalHeight),
            format: format
        )

        let finalImage = renderer.image { rendererContext in
            let context = rendererContext.cgContext

            // 填充白色背景
            UIColor.white.setFill()
            rendererContext.fill(CGRect(x: 0, y: 0, width: fullWidth, height: finalHeight))

            // 绘制顶部固定区域（第一帧的顶部）
            if topHeight > 0 {
                let topRect = CGRect(x: 0, y: 0, width: fullWidth, height: topHeight)
                if let topFixed = firstCG.cropping(to: topRect) {
                    let topUIImage = UIImage(cgImage: topFixed, scale: CGFloat(scale), orientation: .up)
                    topUIImage.draw(in: CGRect(x: 0, y: 0, width: fullWidth, height: topHeight))
                    logger.debug("✅ 绘制顶部固定区域: \(topHeight)px")
                }
            }

            // 绘制内容区切片
            var currentY = topHeight

            for i in 0..<sliceInfos.count {
                let info = sliceInfos[i]
                let frameIndex = info.frameIndex
                let startRow = info.startRow
                let sliceHeight = info.height
                let contentCG = contentImages[frameIndex]

                // 裁剪该帧需要绘制的内容切片
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
                    // 第一帧：直接绘制整个内容区
                    sliceUIImage.draw(in: CGRect(x: 0, y: currentY, width: fullWidth, height: sliceHeight))
                    currentY += sliceHeight
                    logger.debug("✅ 绘制第 0 帧内容区: \(sliceHeight)px, currentY=\(currentY)")
                } else {
                    // 后续帧：
                    // - 切片顶部 blendHeight 行为融合区（与上一帧底部重叠）
                    // - 切片底部 scrollOffset 行为新增内容
                    // - 整体从 currentY - blendHeight 开始绘制
                    let actualBlendHeight = min(blendHeight, sliceHeight)
                    let scrollOffset = sliceHeight - actualBlendHeight
                    let drawY = currentY - actualBlendHeight

                    if actualBlendHeight > 0 {
                        // 绘制融合区（切片顶部 actualBlendHeight 行）
                        let blendRect = CGRect(x: 0, y: 0, width: fullWidth, height: actualBlendHeight)
                        if let blendCG = sliceCG.cropping(to: blendRect) {
                            let blendUIImage = UIImage(cgImage: blendCG, scale: CGFloat(scale), orientation: .up)
                            let blendDrawRect = CGRect(x: 0, y: drawY, width: fullWidth, height: actualBlendHeight)

                            // 使用 alpha 渐变：从上到下 0 -> 1
                            // 顶部(alpha=0): 显示上一帧内容
                            // 底部(alpha=1): 显示当前帧内容
                            if let gradientMask = createGradientMask(width: fullWidth, height: actualBlendHeight) {
                                context.saveGState()
                                context.clip(to: blendDrawRect, mask: gradientMask)
                                blendUIImage.draw(in: blendDrawRect)
                                context.restoreGState()
                            } else {
                                blendUIImage.draw(in: blendDrawRect)
                            }
                        }

                        // 绘制新增内容（切片底部 scrollOffset 行）
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
                        // 无融合，直接绘制
                        sliceUIImage.draw(in: CGRect(x: 0, y: drawY, width: fullWidth, height: sliceHeight))
                        currentY = drawY + sliceHeight
                        logger.debug("✅ 绘制第 \(frameIndex) 帧: height=\(sliceHeight)px, currentY=\(currentY)")
                    }
                }
            }

            // 绘制底部固定区域（最后一帧的底部）
            if bottomHeight > 0 {
                // 计算实际需要的高度，确保覆盖到底部，避免白线
                let actualBottomHeight = finalHeight - currentY
                if actualBottomHeight > 0 {
                    // 使用最后一帧的底部固定区域，因为它包含最新的内容
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
                            // 使用实际高度确保覆盖到底部
                            bottomUIImage.draw(in: CGRect(x: 0, y: currentY, width: fullWidth, height: actualBottomHeight))
                            logger.debug("✅ 绘制底部固定区域: original=\(bottomHeight)px, actual=\(actualBottomHeight)px, y=\(currentY), finalHeight=\(finalHeight) (使用最后一帧)")
                        }
                    } else if let bottomFixed = firstCG.cropping(to: CGRect(x: 0, y: fullHeight - bottomHeight, width: fullWidth, height: bottomHeight)) {
                        // 回退到第一帧
                        let bottomUIImage = UIImage(cgImage: bottomFixed, scale: CGFloat(scale), orientation: .up)
                        // 使用实际高度确保覆盖到底部
                        bottomUIImage.draw(in: CGRect(x: 0, y: currentY, width: fullWidth, height: actualBottomHeight))
                        logger.debug("✅ 绘制底部固定区域: original=\(bottomHeight)px, actual=\(actualBottomHeight)px, y=\(currentY), finalHeight=\(finalHeight) (使用第一帧)")
                    }
                } else {
                    logger.warning("⚠️ 实际底部高度无效: \(actualBottomHeight)")
                }
            }
        }

        logger.info("✅ 长图合成完成: \(finalImage.size.width)×\(finalImage.size.height) (scale=\(scale))")
        return finalImage
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
