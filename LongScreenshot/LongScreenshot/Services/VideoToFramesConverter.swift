import UIKit
import AVFoundation
import Photos
import os.log

enum VideoStitchingError: Error, LocalizedError {
    case insufficientFrames
    case videoTooShort
    case videoExtractionFailed
    case noScrollDetected
    case invalidSelection
    case videoTooLong

    var errorDescription: String? {
        switch self {
        case .insufficientFrames:
            return "视频帧数不足，无法拼接"
        case .videoTooShort:
            return "视频时长过短，请录制至少 2 秒的滚动过程"
        case .videoExtractionFailed:
            return "视频解码失败，请检查视频格式"
        case .noScrollDetected:
            return "未检测到滚动内容，请录制页面滚动的过程"
        case .invalidSelection:
            return "请单独选择视频进行处理，不要同时选择图片和视频"
        case .videoTooLong:
            return "视频时长超过限制，请录制 60 秒以内的滚动过程"
        }
    }
}

actor VideoToFramesConverter {

    private let logger = Logger(subsystem: "com.longscreenshot", category: "VideoToFramesConverter")

    struct Config {
        var maxVideoDuration: TimeInterval = 60
        var maxExtractWidth: CGFloat = 1080
    }

    private var _config = Config()

    var config: Config {
        get { _config }
    }

    func setConfigMaxExtractWidth(_ width: CGFloat) {
        _config.maxExtractWidth = width
    }

    func convertToFrames(
        from videoAsset: PHAsset,
        progress: StitchingProgress
    ) async throws -> [UIImage] {
        logger.info("🚀 开始视频转帧转换")

        let avAsset = try await loadAVAsset(from: videoAsset)
        let duration = try await avAsset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        logger.info("🎬 视频信息: duration=\(durationSeconds)s")

        guard durationSeconds >= 1 else {
            throw VideoStitchingError.videoTooShort
        }

        guard durationSeconds <= _config.maxVideoDuration else {
            throw VideoStitchingError.videoTooLong
        }

        progress.updatePhase(.loading)
        progress.updatePhaseProgress(.loading, progress: 0.1)

        let frameExtractor = VideoFrameExtractor()
        await frameExtractor.setConfigMaxExtractWidth(_config.maxExtractWidth)

        let (frames, _) = try await frameExtractor.extractFramesAdaptive(
            from: avAsset,
            progress: progress
        )

        guard frames.count >= 2 else {
            throw VideoStitchingError.insufficientFrames
        }

        progress.updatePhaseProgress(.loading, progress: 1.0)

        logger.info("✅ 视频转帧完成: 共 \(frames.count) 帧")

        return frames
    }

    func generateLongScreenshot(
        from videoAsset: PHAsset,
        progress: StitchingProgress
    ) async -> UIImage? {
        let startTime = CFAbsoluteTimeGetCurrent()
        logger.info("🚀 开始视频生成长截图（照片流算法）")

        do {
            let avAsset = try await loadAVAsset(from: videoAsset)
            let duration = try await avAsset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)

            let tracks = try await avAsset.load(.tracks)
            let videoTracks = tracks.filter { $0.mediaType == .video }
            var videoSize: CGSize = .zero
            if let videoTrack = videoTracks.first {
                let naturalSize = try await videoTrack.load(.naturalSize)
                let preferredTransform = try await videoTrack.load(.preferredTransform)
                let isRotated = abs(preferredTransform.a) < 0.1
                videoSize = isRotated ? CGSize(width: naturalSize.height, height: naturalSize.width) : naturalSize
            }

            logger.info("🎬 视频信息: duration=\(String(format: "%.2f", durationSeconds))s, size=\(Int(videoSize.width))×\(Int(videoSize.height))")

            guard durationSeconds >= 1 else {
                logger.error("❌ 视频时长过短，至少需要 1 秒")
                return nil
            }

            progress.updatePhase(.loading)
            progress.updatePhaseProgress(.loading, progress: 0.1)

            let frameExtractionStart = CFAbsoluteTimeGetCurrent()
            let (frames, grayscaleDataList) = try await extractFullFrames(from: avAsset, progress: progress)
            let frameExtractionDuration = CFAbsoluteTimeGetCurrent() - frameExtractionStart

            logger.info("📊 帧提取完成: 共 \(frames.count) 帧, 耗时 \(String(format: "%.3f", frameExtractionDuration))s")

            guard frames.count >= 2 else {
                logger.error("❌ 帧数量不足，无法合成，至少需要 2 帧")
                return nil
            }

            if let firstFrame = frames.first {
                logger.info("📐 第一帧尺寸: \(Int(firstFrame.size.width))×\(Int(firstFrame.size.height))")
            }

            progress.updatePhase(.processing)
            progress.updatePhaseProgress(.processing, progress: 0.5)

            let builder = VideoScreenshotBuilder()
            let longScreenshot = builder.build(frames: frames, grayscaleDataList: grayscaleDataList)

            progress.updatePhaseProgress(.processing, progress: 1.0)

            let totalDuration = CFAbsoluteTimeGetCurrent() - startTime

            if let longScreenshot = longScreenshot {
                logger.info("✅ 视频生成长截图完成: 最终尺寸 \(Int(longScreenshot.size.width))×\(Int(longScreenshot.size.height)), 总耗时 \(String(format: "%.3f", totalDuration))s")
                return longScreenshot
            } else {
                logger.error("❌ 视频生成长截图失败")
                return nil
            }
        } catch {
            let totalDuration = CFAbsoluteTimeGetCurrent() - startTime
            logger.error("❌ 视频生成长截图失败: \(error.localizedDescription), 总耗时 \(String(format: "%.3f", totalDuration))s")
            return nil
        }
    }

    private func extractFullFrames(from asset: AVAsset, progress: StitchingProgress) async throws -> ([UIImage], [FrameGrayscaleData?]) {
        let frameExtractor = VideoFrameExtractor()
        await frameExtractor.setConfigMaxExtractWidth(_config.maxExtractWidth)
        let (frames, grayscaleDataList) = try await frameExtractor.extractFramesAdaptive(from: asset, progress: progress)
        return (frames, grayscaleDataList)
    }

    private func loadAVAsset(from phAsset: PHAsset) async throws -> AVAsset {
        return try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat

            PHImageManager.default().requestAVAsset(
                forVideo: phAsset,
                options: options
            ) { asset, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let asset = asset else {
                    continuation.resume(throwing: VideoStitchingError.videoExtractionFailed)
                    return
                }

                continuation.resume(returning: asset)
            }
        }
    }
}
