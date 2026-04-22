import UIKit
import Accelerate
import os.log

// MARK: - 固定区域检测器

/// 自动识别截图中固定不变的顶部区域（导航栏）和底部区域（TabBar）
/// 算法原理：
/// 1. 将多帧图像转为灰度像素矩阵
/// 2. 对每一行像素，使用 Accelerate vDSP 计算多帧之间的逐像素绝对差值和（SAD）
/// 3. 从顶部向下扫描，找到第一个"行差异均值 > 阈值"的行，该行以上即为固定顶部区域
/// 4. 从底部向上扫描，找到第一个"行差异均值 > 阈值"的行，该行以下即为固定底部区域
struct FixedRegionDetector {

    private let logger = Logger(subsystem: "com.longscreenshot", category: "FixedRegionDetector")

    /// 行差异阈值（基于 0~255 像素值），默认 8.0
    var differenceThreshold: Float = 8.0

    /// 检测固定区域高度
    /// - Parameter frames: 至少 2 帧 UIImage，按滚动顺序排列
    /// - Returns: (topHeight: 顶部固定区域高度, bottomHeight: 底部固定区域高度)，单位：像素（已乘以 scale）
    func detect(frames: [UIImage]) -> (topHeight: Int, bottomHeight: Int) {
        guard frames.count >= 2 else {
            logger.warning("⚠️ 输入帧数不足，至少需要 2 帧，实际 \(frames.count) 帧")
            return (0, 0)
        }

        // 提取所有帧的灰度像素数据和尺寸信息
        let grayDataList = frames.compactMap { extractGrayscaleData(from: $0) }
        guard grayDataList.count == frames.count else {
            logger.error("❌ 部分帧转灰度失败")
            return (0, 0)
        }

        // 确保所有帧尺寸一致
        let firstSize = grayDataList[0].size
        let consistentData = grayDataList.filter { $0.size == firstSize }
        guard consistentData.count == grayDataList.count else {
            logger.error("❌ 帧尺寸不一致")
            return (0, 0)
        }

        let width = firstSize.width
        let height = firstSize.height
        let frameCount = consistentData.count
        let pixelCount = width * height

        logger.info("🔍 开始检测固定区域: \(width)×\(height), 帧数=\(frameCount)")

        // 一次性将所有帧的像素数据转为 Float 数组
        var floatPixelsList = [[Float]]()
        floatPixelsList.reserveCapacity(frameCount)
        for data in consistentData {
            var floatPixels = [Float](repeating: 0, count: pixelCount)
            vDSP_vfltu8(data.pixels, 1, &floatPixels, 1, vDSP_Length(pixelCount))
            floatPixelsList.append(floatPixels)
        }

        // 计算每一行的多帧 SAD 均值
        var rowDiffs = [Float](repeating: 0, count: height)

        let referenceFloat = floatPixelsList[0]
        let rowPixelCount = vDSP_Length(width)

        // 预分配差值数组，避免重复分配
        var rowDiff = [Float](repeating: 0, count: width)
        var rowAbsDiff = [Float](repeating: 0, count: width)

        for row in 0..<height {
            let rowStart = row * width

            var rowSAD: Float = 0
            var validComparisons = 0

            for frameIndex in 1..<frameCount {
                let otherFloat = floatPixelsList[frameIndex]

                // 使用指针偏移代替 ArraySlice，避免每次循环创建新数组
                // diff = other - ref
                vDSP_vsub(
                    otherFloat.withUnsafeBufferPointer { $0.baseAddress! + rowStart }, 1,
                    referenceFloat.withUnsafeBufferPointer { $0.baseAddress! + rowStart }, 1,
                    &rowDiff, 1,
                    rowPixelCount
                )

                // 计算绝对值
                vDSP_vabs(rowDiff, 1, &rowAbsDiff, 1, rowPixelCount)

                // 计算均值
                var meanDiff: Float = 0
                vDSP_meanv(rowAbsDiff, 1, &meanDiff, rowPixelCount)

                rowSAD += meanDiff
                validComparisons += 1
            }

            if validComparisons > 0 {
                rowDiffs[row] = rowSAD / Float(validComparisons)
            }
        }

        // 从顶部向下扫描，找到第一个差异超过阈值的行
        var topFixedHeight = 0
        for row in 0..<height {
            if rowDiffs[row] > differenceThreshold {
                topFixedHeight = row
                break
            }
        }

        // 从底部向上扫描，找到第一个差异超过阈值的行（忽略小干扰区域）
        var bottomFixedHeight = 0
        var consecutiveDiffRows = 0
        let minInterferenceHeight = 50 // 最小干扰区域高度
        
        for row in (0..<height).reversed() {
            if rowDiffs[row] > differenceThreshold {
                consecutiveDiffRows += 1
            } else {
                // 如果遇到连续的非差异行，重置计数
                consecutiveDiffRows = 0
            }
            
            // 只有当连续差异行达到最小干扰高度时，才认为找到真正的边界
            if consecutiveDiffRows >= minInterferenceHeight {
                bottomFixedHeight = height - 1 - row
                break
            }
        }

        logger.info("✅ 固定区域检测完成: 顶部=\(topFixedHeight)px, 底部=\(bottomFixedHeight)px")

        return (topFixedHeight, bottomFixedHeight)
    }

    // MARK: - 私有辅助方法

    /// 提取 UIImage 的灰度像素数据
    private func extractGrayscaleData(from image: UIImage) -> (pixels: [UInt8], size: (width: Int, height: Int))? {
        guard let cgImage = image.cgImage else {
            logger.error("❌ 无法获取 CGImage")
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width
        var pixels = [UInt8](repeating: 0, count: width * height)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            logger.error("❌ 无法创建灰度 CGContext")
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return (pixels, (width, height))
    }
}
