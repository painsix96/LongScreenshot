import UIKit
import Accelerate
import os.log

// MARK: - 匹配结果

/// 垂直偏移匹配结果
struct VerticalOffsetMatchResult {
    /// 模板在第二帧中的匹配起始行
    let matchedY: Int
    /// 实际使用的模板高度
    let templateHeight: Int
    /// 内容区高度
    let contentHeight: Int
    
    /// 滚动偏移量：第二帧相对第一帧向下滚动的距离
    /// 计算公式：contentHeight - templateHeight - matchedY
    var scrollOffset: Int { contentHeight - templateHeight - matchedY }
}

// MARK: - 垂直偏移匹配器

/// 给定相邻两帧的内容区图像，精确计算第二帧相对第一帧的垂直滚动偏移量
/// 算法原理：
/// 1. 将输入的 CGImage 转为灰度图
/// 2. 取第一帧内容区底部 templateHeight 行作为模板
/// 3. 在第二帧内容区顶部 60% 高度内逐行滑动模板
/// 4. 对每个位置使用 vDSP 计算 SAD（绝对差值和）
/// 5. 取 SAD 最小值对应的行为最佳匹配位置
/// 6. 引入次优匹配验证：最优 SAD 必须小于次优 SAD 的 0.8 倍，否则返回 nil
struct VerticalOffsetMatcher {

    private let logger = Logger(subsystem: "com.longscreenshot", category: "VerticalOffsetMatcher")

    /// 模板高度（像素），默认 200px
    /// 注：增大模板高度提高匹配准确性，特别是对于包含图片等复杂内容的截图
    var templateHeight: Int = 200

    /// 次优匹配比率阈值，默认 0.95（最优 SAD 必须 < 次优 SAD * 0.95）
    /// 注：放宽阈值以应对滚动幅度小、内容相似度高的场景
    var secondBestRatio: Float = 0.95

    /// 绝对质量阈值：最佳匹配的相似度超过此值时，可跳过唯一性检查
    /// 相似度 = 1 - (bestSAD / 最大可能差值)，范围 0~1
    var absoluteQualityThreshold: Float = 0.92

    /// 搜索范围比例，默认 1.0（搜索第二帧全部高度）
    /// 注：增大搜索范围以覆盖更多可能的匹配位置
    var searchRangeRatio: Float = 1.0

    /// 匹配相邻两帧内容区，计算垂直偏移量
    /// - Parameters:
    ///   - prevContent: 前一帧的内容区 CGImage（已裁剪掉固定区域）
    ///   - currContent: 当前帧的内容区 CGImage（已裁剪掉固定区域）
    /// - Returns: 匹配结果，包含 matchedY、templateHeight 和 scrollOffset；nil 表示匹配失败
    func match(prevContent: CGImage, currContent: CGImage) -> VerticalOffsetMatchResult? {
        let width = min(prevContent.width, currContent.width)
        let prevHeight = prevContent.height
        let currHeight = currContent.height

        guard width > 0, prevHeight > 0, currHeight > 0 else {
            logger.error("❌ 输入图像尺寸无效: prev=\(prevContent.width)×\(prevHeight), curr=\(currContent.width)×\(currHeight)")
            return nil
        }

        // 提取灰度像素数据
        guard let prevGray = extractGrayscalePixels(from: prevContent),
              let currGray = extractGrayscalePixels(from: currContent) else {
            logger.error("❌ 灰度像素提取失败")
            return nil
        }

        // 确保使用统一的宽度（取较小值）
        let effectiveWidth = min(width, prevGray.width, currGray.width)
        let effectivePrevHeight = min(prevHeight, prevGray.height)
        let effectiveCurrHeight = min(currHeight, currGray.height)

        // 模板高度：取默认值和实际高度的较小值
        let actualTemplateHeight = min(templateHeight, effectivePrevHeight)
        guard actualTemplateHeight > 0 else {
            logger.error("❌ 模板高度无效: \(actualTemplateHeight)")
            return nil
        }

        // 搜索范围：第二帧全部高度
        let searchRange = min(Int(Float(effectiveCurrHeight) * searchRangeRatio), effectiveCurrHeight - actualTemplateHeight)
        guard searchRange > 0 else {
            logger.error("❌ 搜索范围无效: currHeight=\(effectiveCurrHeight), templateHeight=\(actualTemplateHeight)")
            return nil
        }

        logger.info("🔍 开始模板匹配: templateHeight=\(actualTemplateHeight), searchRange=\(searchRange), width=\(effectiveWidth)")

        let templatePixelCount = actualTemplateHeight * effectiveWidth
        let templatePixelCountVDSP = vDSP_Length(templatePixelCount)

        // 提取模板：第一帧底部 actualTemplateHeight 行
        let templatePixels = extractTemplate(pixels: prevGray.pixels, width: effectiveWidth, height: effectivePrevHeight, templateHeight: actualTemplateHeight)

        // 预先将模板和当前帧转为 Float 数组
        var templateFloat = [Float](repeating: 0, count: templatePixelCount)
        vDSP_vfltu8(templatePixels, 1, &templateFloat, 1, templatePixelCountVDSP)

        var currFloat = [Float](repeating: 0, count: effectiveCurrHeight * effectiveWidth)
        vDSP_vfltu8(currGray.pixels, 1, &currFloat, 1, vDSP_Length(effectiveCurrHeight * effectiveWidth))

        // 预分配差值数组
        var diff = [Float](repeating: 0, count: templatePixelCount)
        var absDiff = [Float](repeating: 0, count: templatePixelCount)

        var bestSAD: Float = Float.greatestFiniteMagnitude
        var bestY = 0
        var secondBestSAD: Float = Float.greatestFiniteMagnitude

        for y in 0...searchRange {
            // 使用指针偏移代替 ArraySlice
            let candidateStart = y * effectiveWidth

            vDSP_vsub(
                templateFloat.withUnsafeBufferPointer { $0.baseAddress! }, 1,
                currFloat.withUnsafeBufferPointer { $0.baseAddress! + candidateStart }, 1,
                &diff, 1,
                templatePixelCountVDSP
            )
            vDSP_vabs(diff, 1, &absDiff, 1, templatePixelCountVDSP)

            var sad: Float = 0
            vDSP_sve(absDiff, 1, &sad, templatePixelCountVDSP)

            // 更新最优和次优
            if sad < bestSAD {
                secondBestSAD = bestSAD
                bestSAD = sad
                bestY = y
            } else if sad < secondBestSAD {
                secondBestSAD = sad
            }
        }

        logger.info("🔍 匹配结果: bestY=\(bestY), bestSAD=\(bestSAD), secondBestSAD=\(secondBestSAD)")

        // 次优匹配验证
        guard secondBestSAD != Float.greatestFiniteMagnitude else {
            logger.warning("⚠️ 只有一个有效匹配位置，无法验证唯一性")
            return nil
        }

        // 计算绝对相似度质量（0~1，越接近1表示匹配越好）
        let maxPossibleSAD = Float(templatePixelCount) * Float(255.0)
        let absoluteQuality = Float(1.0) - (bestSAD / maxPossibleSAD)
        logger.info("🔍 绝对质量: similarity=\(absoluteQuality)")

        // 验证策略：
        // 1. 如果绝对质量很高（如 > 0.92），说明匹配本身很可靠，放宽唯一性要求
        // 2. 否则，仍要求最佳匹配明显优于次优匹配
        let isHighQuality = absoluteQuality >= absoluteQualityThreshold
        let isUnique = bestSAD < secondBestSAD * secondBestRatio

        if !isUnique && !isHighQuality {
            logger.warning("⚠️ 匹配不唯一且质量不足: bestSAD=\(bestSAD) >= secondBestSAD * \(secondBestRatio)=\(secondBestSAD * secondBestRatio), quality=\(absoluteQuality) < \(absoluteQualityThreshold)")
            return nil
        }

        if isHighQuality && !isUnique {
            logger.info("✅ 绝对质量足够高(\(absoluteQuality))，跳过唯一性检查")
        }

        let result = VerticalOffsetMatchResult(
            matchedY: bestY,
            templateHeight: actualTemplateHeight,
            contentHeight: effectivePrevHeight
        )
        
        logger.info("✅ 匹配成功: matchedY=\(bestY), templateHeight=\(actualTemplateHeight), scrollOffset=\(result.scrollOffset)px")
        return result
    }

    // MARK: - 私有辅助方法

    /// 从像素数组中提取模板区域（底部 templateHeight 行）
    private func extractTemplate(pixels: [UInt8], width: Int, height: Int, templateHeight: Int) -> [UInt8] {
        let startY = height - templateHeight
        var result = [UInt8](repeating: 0, count: templateHeight * width)

        for row in 0..<templateHeight {
            let srcStart = (startY + row) * width
            let dstStart = row * width
            _ = result.withUnsafeMutableBufferPointer { dstPtr in
                pixels.withUnsafeBufferPointer { srcPtr in
                    memcpy(dstPtr.baseAddress! + dstStart, srcPtr.baseAddress! + srcStart, width)
                }
            }
        }

        return result
    }

    /// 提取 CGImage 的灰度像素数据
    private func extractGrayscalePixels(from cgImage: CGImage) -> (pixels: [UInt8], width: Int, height: Int)? {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        // 如果已经是灰度图，直接提取
        if cgImage.colorSpace?.model == .monochrome,
           cgImage.bitsPerPixel == 8,
           cgImage.bitsPerComponent == 8 {
            guard let dataProvider = cgImage.dataProvider,
                  let data = dataProvider.data,
                  let ptr = CFDataGetBytePtr(data) else { return nil }

            let bytesPerRow = cgImage.bytesPerRow
            if bytesPerRow == width {
                return (Array(UnsafeBufferPointer(start: ptr, count: width * height)), width, height)
            }

            var pixels = [UInt8](repeating: 0, count: width * height)
            for row in 0..<height {
                let srcOffset = row * bytesPerRow
                let dstOffset = row * width
                _ = pixels.withUnsafeMutableBufferPointer { dstPtr in
                    memcpy(dstPtr.baseAddress! + dstOffset, ptr + srcOffset, width)
                }
            }
            return (pixels, width, height)
        }

        // 否则转为灰度图
        let bytesPerRow = width
        var pixels = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            logger.error("❌ 无法创建灰度 CGContext")
            return nil
        }

        context.interpolationQuality = .none
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return (pixels, width, height)
    }
}
