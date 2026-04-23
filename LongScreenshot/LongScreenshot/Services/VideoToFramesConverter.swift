import UIKit
import AVFoundation
import Photos
import os.log

// MARK: - 视频拼接错误

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

// MARK: - 视频转帧协调器

/// 将视频转换为可用于拼接的帧序列
/// 提取帧后，完全复用现有的照片拼接逻辑（OverlapDetector + ImageStitcher）
actor VideoToFramesConverter {

    private let logger = Logger(subsystem: "com.longscreenshot", category: "VideoToFramesConverter")

    // MARK: - 配置

    struct Config {
        /// 最大视频时长（秒）
        var maxVideoDuration: TimeInterval = 60
        /// 是否启用自适应采样
        var useAdaptiveSampling: Bool = true
        /// 视频提取最大宽度
        var maxExtractWidth: CGFloat = 1080
    }

    private var _config = Config()

    var config: Config {
        get { _config }
    }

    func setConfigMaxExtractWidth(_ width: CGFloat) {
        _config.maxExtractWidth = width
    }

    // MARK: - 主入口

    /// 将 PHAsset 视频转换为可用于拼接的帧数组
    /// 提取帧后，由调用方使用 OverlapDetector + ImageStitcher 处理
    /// - Parameters:
    ///   - videoAsset: 相册中的视频 PHAsset
    ///   - progress: 进度追踪器
    /// - Returns: 提取的原始帧数组（未裁剪固定区域）
    func convertToFrames(
        from videoAsset: PHAsset,
        progress: StitchingProgress
    ) async throws -> [UIImage] {
        logger.info("🚀 开始视频转帧转换")

        // 获取视频 AVAsset
        let avAsset = try await loadAVAsset(from: videoAsset)
        let duration = try await avAsset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        logger.info("🎬 视频信息: duration=\(durationSeconds)s")

        // 检查视频时长
        guard durationSeconds >= 1 else {
            throw VideoStitchingError.videoTooShort
        }

        guard durationSeconds <= _config.maxVideoDuration else {
            throw VideoStitchingError.videoTooLong
        }

        progress.updatePhase(.loading)
        progress.updatePhaseProgress(.loading, progress: 0.1)

        // 提取帧（整个视频）
        let frameExtractor = VideoFrameExtractor()
        await frameExtractor.setConfigMaxExtractWidth(_config.maxExtractWidth)

        let frames: [UIImage]
        if _config.useAdaptiveSampling {
            frames = try await frameExtractor.extractFramesAdaptive(
                from: avAsset,
                progress: progress
            )
        } else {
            frames = try await frameExtractor.extractFrames(
                from: avAsset,
                progress: progress
            )
        }

        guard frames.count >= 2 else {
            throw VideoStitchingError.insufficientFrames
        }

        progress.updatePhaseProgress(.loading, progress: 1.0)

        logger.info("✅ 视频转帧完成: 共 \(frames.count) 帧")

        return frames
    }

    // MARK: - 私有方法

    /// 从 PHAsset 加载 AVAsset
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
