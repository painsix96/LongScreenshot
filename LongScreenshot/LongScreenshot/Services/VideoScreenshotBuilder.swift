import UIKit
import os.log

// MARK: - 视频长截图构建器（照片流算法的视频流专用版本）

/// 视频长截图构建器，整合固定区域检测和长图合成
/// 算法流程：
/// 1. 使用 VideoFixedRegionDetector 检测顶部/底部固定区域
/// 2. 使用 VideoLongScreenshotCompositor 进行逐帧偏移匹配和切片合成
/// 3. 接缝处做 Alpha 渐变融合
struct VideoScreenshotBuilder {

    private let logger = Logger(subsystem: "com.longscreenshot", category: "VideoScreenshotBuilder")

    /// 固定区域检测器
    private let fixedRegionDetector = VideoFixedRegionDetector()

    /// 长截图合成器
    private let compositor = VideoLongScreenshotCompositor()

    /// 构建长截图
    /// - Parameter frames: 视频提取的帧数组（顺序排列，从老到新）
    /// - Returns: 拼接完成的长图，失败返回 nil
    func build(frames: [UIImage]) -> UIImage? {
        guard frames.count >= 2 else {
            logger.error("❌ 至少需要 2 帧进行构建，实际 \(frames.count) 帧")
            return nil
        }

        logger.info("🚀 开始视频长截图构建，共 \(frames.count) 帧")

        // 步骤 1: 检测固定区域
        let (topHeight, bottomHeight) = fixedRegionDetector.detect(frames: frames)
        logger.info("📐 固定区域检测: 顶部=\(topHeight)px, 底部=\(bottomHeight)px")

        // 步骤 2: 合成长截图
        guard let result = compositor.composite(
            frames: frames,
            topHeight: topHeight,
            bottomHeight: bottomHeight
        ) else {
            logger.error("❌ 长截图合成失败")
            return nil
        }

        logger.info("✅ 视频长截图构建完成: \(result.size.width)×\(result.size.height)")
        return result
    }

    /// 异步构建长截图
    /// - Parameters:
    ///   - frames: 视频提取的帧数组
    ///   - completion: 完成回调，在主线程返回结果
    func buildAsync(frames: [UIImage], completion: @escaping (UIImage?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.build(frames: frames)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
}
