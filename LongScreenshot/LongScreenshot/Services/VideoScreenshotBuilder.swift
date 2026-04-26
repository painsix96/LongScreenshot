import UIKit
import os.log

struct VideoScreenshotBuilder {

    private let logger = Logger(subsystem: "com.longscreenshot", category: "VideoScreenshotBuilder")

    private let fixedRegionDetector = VideoFixedRegionDetector()

    private let compositor = VideoLongScreenshotCompositor()

    func build(frames: [UIImage]) -> UIImage? {
        guard frames.count >= 2 else {
            logger.error("❌ 至少需要 2 帧进行构建，实际 \(frames.count) 帧")
            return nil
        }

        logger.info("🚀 开始视频长截图构建，共 \(frames.count) 帧")

        let (topHeight, bottomHeight) = fixedRegionDetector.detect(frames: frames)
        logger.info("📐 固定区域检测: 顶部=\(topHeight)px, 底部=\(bottomHeight)px")

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

    func build(frames: [UIImage], grayscaleDataList: [FrameGrayscaleData?]) -> UIImage? {
        guard frames.count >= 2 else {
            logger.error("❌ 至少需要 2 帧进行构建，实际 \(frames.count) 帧")
            return nil
        }

        logger.info("🚀 开始视频长截图构建，共 \(frames.count) 帧")

        let validGrayscale = grayscaleDataList.compactMap { $0 }
        let (topHeight, bottomHeight): (Int, Int)
        if validGrayscale.count == frames.count {
            (topHeight, bottomHeight) = fixedRegionDetector.detect(grayscaleDataList: validGrayscale)
        } else {
            (topHeight, bottomHeight) = fixedRegionDetector.detect(frames: frames)
        }
        logger.info("📐 固定区域检测: 顶部=\(topHeight)px, 底部=\(bottomHeight)px")

        guard let result = compositor.composite(
            frames: frames,
            grayscaleDataList: grayscaleDataList,
            topHeight: topHeight,
            bottomHeight: bottomHeight
        ) else {
            logger.error("❌ 长截图合成失败")
            return nil
        }

        logger.info("✅ 视频长截图构建完成: \(result.size.width)×\(result.size.height)")
        return result
    }

    func buildAsync(frames: [UIImage], completion: @escaping (UIImage?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.build(frames: frames)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
}
