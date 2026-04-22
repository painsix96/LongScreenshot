import UIKit
import Accelerate
import os.log

// MARK: - 长截图构建器

/// 对外统一入口，一键生成长截图
/// 整合固定区域检测、垂直偏移匹配、长图合成三个模块
struct LongScreenshotBuilder {

    private let logger = Logger(subsystem: "com.longscreenshot", category: "LongScreenshotBuilder")

    /// 固定区域检测器
    var fixedRegionDetector = FixedRegionDetector()

    /// 长图合成器
    var compositor = LongScreenshotCompositor()

    /// 一键生成长截图（同步版本）
    /// - Parameter frames: 按滚动顺序排列的连续截图（至少 2 张）
    /// - Returns: 拼接完成的长图，失败返回 nil
    func build(frames: [UIImage]) -> UIImage? {
        guard frames.count >= 2 else {
            logger.error("❌ 至少需要 2 张图片，实际 \(frames.count) 张")
            return nil
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        logger.info("🚀 开始长截图构建，共 \(frames.count) 帧")

        // 步骤 1：检测固定区域
        let (topHeight, bottomHeight) = fixedRegionDetector.detect(frames: frames)
        logger.info("📐 固定区域检测: 顶部=\(topHeight)px, 底部=\(bottomHeight)px")

        // 步骤 2：合成长图
        guard let result = compositor.composite(
            frames: frames,
            topHeight: topHeight,
            bottomHeight: bottomHeight
        ) else {
            logger.error("❌ 长图合成失败")
            return nil
        }

        let duration = CFAbsoluteTimeGetCurrent() - startTime
        logger.info("✅ 长截图构建完成: \(result.size.width)×\(result.size.height), 耗时 \(String(format: "%.3f", duration))s")

        return result
    }

    /// 异步版本，在后台线程处理，主线程回调
    /// - Parameters:
    ///   - frames: 按滚动顺序排列的连续截图（至少 3 张）
    ///   - completion: 完成回调，在主线程执行
    func buildAsync(frames: [UIImage], completion: @escaping (UIImage?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.build(frames: frames)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
}
