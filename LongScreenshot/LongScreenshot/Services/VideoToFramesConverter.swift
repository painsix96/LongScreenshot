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
/// 内部完成帧提取、固定区域检测、重叠检测和合成的完整流程
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
    
    /// 直接从视频生成长截图（使用新算法）
    /// - Parameters:
    ///   - videoAsset: 相册中的视频 PHAsset
    ///   - progress: 进度追踪器
    /// - Returns: 生成的长截图，失败返回 nil
    func generateLongScreenshot(
        from videoAsset: PHAsset,
        progress: StitchingProgress
    ) async -> UIImage? {
        let startTime = CFAbsoluteTimeGetCurrent()
        logger.info("🚀 开始视频生成长截图（新算法）")

        do {
            // 获取视频 AVAsset
            let avAsset = try await loadAVAsset(from: videoAsset)
            let duration = try await avAsset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            
            // 获取视频轨道信息
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
            
            // 检查视频时长
            guard durationSeconds >= 1 else {
                logger.error("❌ 视频时长过短，至少需要 1 秒")
                return nil
            }
            
            progress.updatePhase(.loading)
            progress.updatePhaseProgress(.loading, progress: 0.1)
            
            // 步骤 0: 智能检测固定区域
            let fixedAreaStart = CFAbsoluteTimeGetCurrent()
            let (topCropPixels, bottomCropPixels) = try await detectFixedAreas(from: avAsset, progress: progress)
            let fixedAreaDuration = CFAbsoluteTimeGetCurrent() - fixedAreaStart
            
            logger.info("📊 固定区域检测完成: 顶部 \(topCropPixels)px, 底部 \(bottomCropPixels)px, 耗时 \(String(format: "%.3f", fixedAreaDuration))s")
            
            // 步骤 1: 提取并处理帧
            let frameExtractionStart = CFAbsoluteTimeGetCurrent()
            let (processedFrames, topFixedArea, bottomFixedArea) = try await extractAndProcessFrames(from: avAsset, topCrop: topCropPixels, bottomCrop: bottomCropPixels, progress: progress)
            let frameExtractionDuration = CFAbsoluteTimeGetCurrent() - frameExtractionStart
            
            logger.info("📊 帧提取完成: 共 \(processedFrames.count) 帧, 耗时 \(String(format: "%.3f", frameExtractionDuration))s")
            
            guard processedFrames.count >= 2 else {
                logger.error("❌ 帧数量不足，无法合成，至少需要 2 帧")
                return nil
            }
            
            // 记录第一帧的尺寸
            if let firstFrame = processedFrames.first {
                logger.info("📐 第一帧尺寸: \(firstFrame.width)×\(firstFrame.height)")
            }
            
            // 记录固定区域尺寸
            if let topArea = topFixedArea {
                logger.info("📐 顶部固定区域尺寸: \(topArea.width)×\(topArea.height)")
            }
            if let bottomArea = bottomFixedArea {
                logger.info("📐 底部固定区域尺寸: \(bottomArea.width)×\(bottomArea.height)")
            }
            
            progress.updatePhase(.processing)
            progress.updatePhaseProgress(.processing, progress: 0.7)
            
            // 步骤 2: 合成所有帧
            let compositeStart = CFAbsoluteTimeGetCurrent()
            let longScreenshot = compositeFrames(processedFrames, topFixedArea: topFixedArea, bottomFixedArea: bottomFixedArea)
            let compositeDuration = CFAbsoluteTimeGetCurrent() - compositeStart
            
            logger.info("📊 合成完成: 耗时 \(String(format: "%.3f", compositeDuration))s")
            
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
    
    // MARK: - 新算法实现
    
    /// 智能检测视频的固定区域高度
    /// - Parameters:
    ///   - asset: 视频 AVAsset
    ///   - progress: 进度追踪器
    /// - Returns: (顶部固定区域高度, 底部固定区域高度)
    private func detectFixedAreas(
        from asset: AVAsset,
        progress: StitchingProgress
    ) async throws -> (CGFloat, CGFloat) {
        logger.info("🔍 开始智能检测固定区域")
        
        // 提取关键帧（均匀分布在视频中）
        let keyFrames = try await extractKeyFrames(from: asset, count: 6)
        
        guard keyFrames.count >= 3 else {
            logger.warning("⚠️ 关键帧数量不足，使用默认裁剪值")
            return (80, 80)
        }
        
        logger.info("✅ 提取了 \(keyFrames.count) 个关键帧用于分析")
        
        // 分析顶部固定区域
        let topCrop = detectTopFixedArea(from: keyFrames)
        
        // 分析底部固定区域
        let bottomCrop = detectBottomFixedArea(from: keyFrames)
        
        logger.info("📊 固定区域检测结果: 顶部 \(topCrop)px, 底部 \(bottomCrop)px")
        
        return (topCrop, bottomCrop)
    }
    
    /// 提取关键帧用于固定区域分析
    private func extractKeyFrames(from asset: AVAsset, count: Int) async throws -> [CGImage] {
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        
        // 计算采样时间点
        var sampleTimes: [CMTime] = []
        let step = durationSeconds / Double(count + 1)
        
        for i in 1...count {
            let time = Double(i) * step
            sampleTimes.append(CMTime(seconds: time, preferredTimescale: 600))
        }
        
        logger.info("🎬 提取 \(count) 个关键帧，时间点: \(sampleTimes.map { String(format: "%.2f", CMTimeGetSeconds($0)) }.joined(separator: ", "))")
        
        // 提取关键帧
        return try await withCheckedThrowingContinuation { continuation in
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.requestedTimeToleranceBefore = .zero
            imageGenerator.requestedTimeToleranceAfter = .zero
            
            // 设置最大尺寸，提高分析速度
            imageGenerator.maximumSize = CGSize(width: 720, height: 0)
            
            var keyFrames: [CGImage] = []
            var errors: [Error] = []
            
            let timeValues = sampleTimes.map { NSValue(time: $0) }
            imageGenerator.generateCGImagesAsynchronously(forTimes: timeValues) { [self] requestedTime, cgImage, actualTime, result, error in
                if let error = error {
                    logger.warning("⚠️ 提取关键帧失败 @ \(String(format: "%.2f", CMTimeGetSeconds(requestedTime)))s: \(error.localizedDescription)")
                    errors.append(error)
                } else if let cgImage = cgImage {
                    keyFrames.append(cgImage)
                }
                
                // 检查是否完成
                if keyFrames.count + errors.count == sampleTimes.count {
                    continuation.resume(returning: keyFrames)
                }
            }
        }
    }
    
    /// 检测顶部固定区域高度
    private func detectTopFixedArea(from frames: [CGImage]) -> CGFloat {
        guard frames.count >= 2 else { return 80 }
        
        let firstFrame = frames[0]
        let width = firstFrame.width
        let height = firstFrame.height
        
        // 最大检测高度（不超过屏幕高度的30%）
        let maxCheckHeight = min(Int(CGFloat(height) * 0.3), 500)
        
        // 分析步长（像素）
        let step = 10
        
        // 相似度阈值（0-1，越高越严格）
        let similarityThreshold: Double = 0.9
        
        logger.info("🔍 分析顶部固定区域，最大检测高度: \(maxCheckHeight)px")
        
        // 从顶部开始，逐步向下分析
        for currentHeight in stride(from: step, through: maxCheckHeight, by: step) {
            var totalSimilarity: Double = 0
            var comparisonCount = 0
            
            // 比较所有帧的当前高度区域
            for i in 1..<frames.count {
                let frame1 = frames[0]
                let frame2 = frames[i]
                
                // 提取顶部区域
                let rect1 = CGRect(x: 0, y: 0, width: width, height: currentHeight)
                let rect2 = CGRect(x: 0, y: 0, width: frame2.width, height: currentHeight)
                
                guard let region1 = frame1.cropping(to: rect1),
                      let region2 = frame2.cropping(to: rect2) else {
                    continue
                }
                
                // 计算相似度
                let similarity = calculateImageSimilarity(region1, region2)
                totalSimilarity += similarity
                comparisonCount += 1
            }
            
            // 计算平均相似度
            if comparisonCount > 0 {
                let avgSimilarity = totalSimilarity / Double(comparisonCount)
                logger.debug("📊 顶部高度 \(currentHeight)px, 平均相似度: \(String(format: "%.3f", avgSimilarity))")
                
                // 如果相似度低于阈值，说明进入了内容区域
                if avgSimilarity < similarityThreshold {
                    // 回退到上一个高度
                    let fixedHeight = max(currentHeight - step, 0)
                    logger.info("✅ 顶部固定区域高度: \(fixedHeight)px")
                    return CGFloat(fixedHeight)
                }
            }
        }
        
        // 如果所有高度都相似，使用默认值
        logger.warning("⚠️ 无法检测顶部固定区域，使用默认值")
        return 80
    }
    
    /// 检测底部固定区域高度
    private func detectBottomFixedArea(from frames: [CGImage]) -> CGFloat {
        guard frames.count >= 2 else { return 80 }
        
        let firstFrame = frames[0]
        let width = firstFrame.width
        let height = firstFrame.height
        
        // 最大检测高度（不超过屏幕高度的30%）
        let maxCheckHeight = min(Int(CGFloat(height) * 0.3), 500)
        
        // 分析步长（像素）
        let step = 10
        
        // 相似度阈值（0-1，越高越严格）
        let similarityThreshold: Double = 0.9
        
        logger.info("🔍 分析底部固定区域，最大检测高度: \(maxCheckHeight)px")
        
        // 从底部开始，逐步向上分析
        for currentHeight in stride(from: step, through: maxCheckHeight, by: step) {
            var totalSimilarity: Double = 0
            var comparisonCount = 0
            
            // 比较所有帧的当前高度区域
            for i in 1..<frames.count {
                let frame1 = frames[0]
                let frame2 = frames[i]
                
                // 提取底部区域
                let rect1 = CGRect(x: 0, y: height - currentHeight, width: width, height: currentHeight)
                let rect2 = CGRect(x: 0, y: frame2.height - currentHeight, width: frame2.width, height: currentHeight)
                
                guard let region1 = frame1.cropping(to: rect1),
                      let region2 = frame2.cropping(to: rect2) else {
                    continue
                }
                
                // 计算相似度
                let similarity = calculateImageSimilarity(region1, region2)
                totalSimilarity += similarity
                comparisonCount += 1
            }
            
            // 计算平均相似度
            if comparisonCount > 0 {
                let avgSimilarity = totalSimilarity / Double(comparisonCount)
                logger.debug("📊 底部高度 \(currentHeight)px, 平均相似度: \(String(format: "%.3f", avgSimilarity))")
                
                // 如果相似度低于阈值，说明进入了内容区域
                if avgSimilarity < similarityThreshold {
                    // 回退到上一个高度
                    let fixedHeight = max(currentHeight - step, 0)
                    logger.info("✅ 底部固定区域高度: \(fixedHeight)px")
                    return CGFloat(fixedHeight)
                }
            }
        }
        
        // 如果所有高度都相似，使用默认值
        logger.warning("⚠️ 无法检测底部固定区域，使用默认值")
        return 80
    }
    
    /// 计算两个图像的相似度（0-1）
    private func calculateImageSimilarity(_ image1: CGImage, _ image2: CGImage) -> Double {
        // 确保两个图像尺寸相同
        let width = min(image1.width, image2.width)
        let height = min(image1.height, image2.height)
        
        guard width > 0 && height > 0 else { return 0 }
        
        // 缩小图像以提高计算速度
        let downscaleFactor: CGFloat = 0.2
        let smallWidth = max(10, Int(CGFloat(width) * downscaleFactor))
        let smallHeight = max(10, Int(CGFloat(height) * downscaleFactor))
        
        // 创建缩小后的图像
        guard let smallImage1 = resizeImage(image1, to: CGSize(width: smallWidth, height: smallHeight)),
              let smallImage2 = resizeImage(image2, to: CGSize(width: smallWidth, height: smallHeight)) else {
            return 0
        }
        
        // 提取像素数据
        guard let data1 = getImageData(smallImage1),
              let data2 = getImageData(smallImage2) else {
            return 0
        }
        
        // 计算差异
        let pixelCount = data1.count
        var totalDifference: Double = 0
        
        for i in 0..<pixelCount {
            let diff = abs(Int(data1[i]) - Int(data2[i]))
            totalDifference += Double(diff)
        }
        
        // 计算相似度（0-1）
        let maxDifference = Double(pixelCount * 255)
        let similarity = 1.0 - (totalDifference / maxDifference)
        
        return similarity
    }
    
    /// 调整图像尺寸
    private func resizeImage(_ image: CGImage, to size: CGSize) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: image.bitmapInfo.rawValue
        ) else {
            return nil
        }
        
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }
    
    /// 获取图像的像素数据
    private func getImageData(_ image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4 // RGBA
        let bytesPerRow = width * bytesPerPixel
        
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }
    
    /// 批量提取并处理视频帧
    private func extractAndProcessFrames(
        from asset: AVAsset,
        topCrop: CGFloat,
        bottomCrop: CGFloat,
        progress: StitchingProgress
    ) async throws -> ([CGImage], CGImage?, CGImage?) { // 返回 (内容帧, 顶部固定区域, 底部固定区域)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        
        // 配置常量
        let kFrameIntervalSeconds: Double = 1.0 // 增加帧间隔，减少重复内容
        let kMaxFrameCount: Int = 50
        let kMaxOutputWidth: CGFloat = 1080
        
        logger.info("🔧 帧提取配置: 帧间隔=\(kFrameIntervalSeconds)s, 最大帧数=\(kMaxFrameCount), 最大宽度=\(kMaxOutputWidth)px, 顶部裁剪=\(topCrop)px, 底部裁剪=\(bottomCrop)px")
        
        // 计算采样时间点
        var sampleTimes: [CMTime] = []
        var currentTime: Double = 0
        
        // 根据帧间隔计算时间点
        while currentTime < durationSeconds && sampleTimes.count < kMaxFrameCount {
            sampleTimes.append(CMTime(seconds: currentTime, preferredTimescale: 600))
            currentTime += kFrameIntervalSeconds
        }
        
        // 确保包含最后一帧
        if let last = sampleTimes.last, durationSeconds - CMTimeGetSeconds(last) > kFrameIntervalSeconds * 0.5 {
            sampleTimes.append(CMTime(seconds: durationSeconds - 0.01, preferredTimescale: 600))
        }
        
        // 如果帧数超过上限，均匀降采样
        if sampleTimes.count > kMaxFrameCount {
            logger.info("📉 帧数超过上限 \(sampleTimes.count)/\(kMaxFrameCount)，进行降采样")
            let step = Double(sampleTimes.count) / Double(kMaxFrameCount)
            var thinned: [CMTime] = []
            for i in 0..<kMaxFrameCount {
                let index = Int(Double(i) * step)
                if index < sampleTimes.count {
                    thinned.append(sampleTimes[index])
                }
            }
            sampleTimes = thinned
        }
        
        logger.info("🎬 计划提取 \(sampleTimes.count) 帧，时间点: \(sampleTimes.map { String(format: "%.2f", CMTimeGetSeconds($0)) }.joined(separator: ", "))")
        
        // 使用 AVAssetImageGenerator 批量提取帧
        return try await withCheckedThrowingContinuation { continuation in
            // 配置图像生成器
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.requestedTimeToleranceBefore = .zero
            imageGenerator.requestedTimeToleranceAfter = .zero
            
            // 设置最大尺寸，从源头控制内存
            imageGenerator.maximumSize = CGSize(width: kMaxOutputWidth, height: 0)
            logger.info("📐 设置最大提取尺寸: \(kMaxOutputWidth)px")
            
            // 准备数据结构
            var frameData: [(time: CMTime, image: CGImage)] = [] // 保存时间点和图像，用于排序
            var topFixedArea: CGImage? // 顶部固定区域
            var bottomFixedArea: CGImage? // 底部固定区域
            var errors: [Error] = []
            let totalCount = sampleTimes.count
            
            // 转换时间点
            let timeValues = sampleTimes.map { NSValue(time: $0) }
            logger.info("🚀 开始批量提取 \(totalCount) 帧")
            
            // 批量异步提取
            imageGenerator.generateCGImagesAsynchronously(forTimes: timeValues) { [self] requestedTime, cgImage, actualTime, result, error in
                if let error = error {
                    logger.warning("⚠️ 提取帧失败 @ requested=\(String(format: "%.2f", CMTimeGetSeconds(requestedTime)))s, actual=\(String(format: "%.2f", CMTimeGetSeconds(actualTime)))s: \(error.localizedDescription)")
                    errors.append(error)
                } else if let cgImage = cgImage {
                    logger.debug("🎬 提取帧 @ requested=\(String(format: "%.2f", CMTimeGetSeconds(requestedTime)))s, actual=\(String(format: "%.2f", CMTimeGetSeconds(actualTime)))s, size=\(cgImage.width)×\(cgImage.height)")
                    
                    // 提取顶部固定区域（从第一帧）
                    if topFixedArea == nil && CMTimeGetSeconds(requestedTime) <= 0.1 {
                        let topRect = CGRect(
                            x: 0,
                            y: 0,
                            width: cgImage.width,
                            height: Int(topCrop)
                        )
                        if let topArea = cgImage.cropping(to: topRect) {
                            topFixedArea = topArea
                            logger.debug("✅ 提取顶部固定区域: \(topArea.width)×\(topArea.height)")
                        }
                    }
                    
                    // 提取底部固定区域（从最后一帧）
                    if bottomFixedArea == nil && CMTimeGetSeconds(requestedTime) >= durationSeconds - 0.1 {
                        let bottomRect = CGRect(
                            x: 0,
                            y: cgImage.height - Int(bottomCrop),
                            width: cgImage.width,
                            height: Int(bottomCrop)
                        )
                        if let bottomArea = cgImage.cropping(to: bottomRect) {
                            bottomFixedArea = bottomArea
                            logger.debug("✅ 提取底部固定区域: \(bottomArea.width)×\(bottomArea.height)")
                        }
                    }
                    
                    // 裁剪内容区域
                    let width = cgImage.width
                    let height = cgImage.height
                    
                    let cropRect = CGRect(
                        x: 0,
                        y: CGFloat(Int(topCrop)),
                        width: CGFloat(width),
                        height: CGFloat(height) - topCrop - bottomCrop
                    )
                    
                    let cropRectString = String(describing: cropRect)
                    logger.debug("✂️ 裁剪区域: \(cropRectString)")
                    
                    if let croppedImage = cgImage.cropping(to: cropRect) {
                        logger.debug("✅ 裁剪完成: \(croppedImage.width)×\(croppedImage.height)")
                        // 使用 actualTime 而不是 requestedTime 来排序，确保顺序正确
                        frameData.append((time: actualTime, image: croppedImage))
                    } else {
                        logger.warning("⚠️ 裁剪失败")
                    }
                }
                
                // 更新进度
                let progressValue = Double(frameData.count) / Double(totalCount)
                progress.updatePhaseProgress(.loading, progress: 0.1 + progressValue * 0.6)
                
                // 检查是否完成
                if frameData.count + errors.count == totalCount {
                    logger.info("📊 帧提取完成: 成功 \(frameData.count)/\(totalCount) 帧, 失败 \(errors.count) 帧")

                    // 按实际时间顺序排序帧
                    frameData.sort { CMTimeGetSeconds($0.time) < CMTimeGetSeconds($1.time) }
                    let sortedFrames = frameData.map { $0.image }

                    // 去除过于相似的帧
                    let uniqueFrames = filterSimilarFrames(sortedFrames)

                    if uniqueFrames.count >= 2 {
                        logger.info("✅ 帧处理完成: 原始 \(sortedFrames.count) 帧, 去重后 \(uniqueFrames.count) 帧")

                        // 检测并移除帧之间的重叠区域
                        let finalFrames = detectAndRemoveOverlaps(from: uniqueFrames)
                        logger.info("✅ 重叠移除完成: 去重后 \(uniqueFrames.count) 帧, 最终 \(finalFrames.count) 帧")

                        continuation.resume(returning: (finalFrames, topFixedArea, bottomFixedArea))
                    } else {
                        logger.error("❌ 有效帧数量不足: \(uniqueFrames.count) 帧")
                        continuation.resume(throwing: VideoStitchingError.insufficientFrames)
                    }
                }
            }
        }
    }
    
    /// 过滤过于相似的帧
    private func filterSimilarFrames(_ frames: [CGImage]) -> [CGImage] {
        guard frames.count >= 2 else { return frames }
        
        var uniqueFrames: [CGImage] = [frames[0]]
        let similarityThreshold: Double = 0.90 // 降低相似度阈值，更严格地过滤重复内容
        
        for i in 1..<frames.count {
            let currentFrame = frames[i]
            
            // 与所有已保留的帧比较相似度
            var maxSimilarity: Double = 0
            for uniqueFrame in uniqueFrames {
                let similarity = calculateImageSimilarity(currentFrame, uniqueFrame)
                maxSimilarity = max(maxSimilarity, similarity)
            }
            
            logger.debug("📊 帧 \(i) 与所有已保留帧的最大相似度: \(String(format: "%.3f", maxSimilarity))")
            
            if maxSimilarity < similarityThreshold {
                uniqueFrames.append(currentFrame)
                logger.debug("✅ 保留帧 \(i) (最大相似度 \(String(format: "%.3f", maxSimilarity)))")
            } else {
                logger.debug("⚠️ 跳过相似帧 \(i) (最大相似度 \(String(format: "%.3f", maxSimilarity)) >= \(String(format: "%.2f", similarityThreshold)))")
            }
        }
        
        return uniqueFrames
    }
    
    /// 处理单帧提取结果
    private func handleFrameExtraction(
        cgImage: CGImage?,
        error: Error?,
        requestedTime: CMTime,
        actualTime: CMTime,
        topCrop: CGFloat,
        bottomCrop: CGFloat
    ) -> (CGImage?, Error?) {
        if let error = error {
            logger.warning("⚠️ 提取帧失败 @ \(String(format: "%.2f", CMTimeGetSeconds(requestedTime)))s: \(error.localizedDescription)")
            return (nil, error)
        } else if let cgImage = cgImage {
            logger.debug("🎬 提取帧 @ requested=\(String(format: "%.2f", CMTimeGetSeconds(requestedTime)))s, actual=\(String(format: "%.2f", CMTimeGetSeconds(actualTime)))s, size=\(cgImage.width)×\(cgImage.height)")
            
            // 立即裁剪，不缓存原始帧
            let width = cgImage.width
            let height = cgImage.height
            
            // 计算裁剪区域
            let cropRect = CGRect(
                x: 0,
                y: CGFloat(Int(topCrop)),
                width: CGFloat(width),
                height: CGFloat(height) - topCrop - bottomCrop
            )
            
            let cropRectString = String(describing: cropRect)
            logger.debug("✂️ 裁剪区域: \(cropRectString)")
            
            // 使用零拷贝裁剪
            if let croppedImage = cgImage.cropping(to: cropRect) {
                logger.debug("✅ 裁剪完成: \(croppedImage.width)×\(croppedImage.height)")
                return (croppedImage, nil)
            } else {
                logger.warning("⚠️ 裁剪失败")
                return (nil, nil)
            }
        }
        return (nil, nil)
    }
    
    /// 合成所有帧为长截图
    private func compositeFrames(_ frames: [CGImage], topFixedArea: CGImage?, bottomFixedArea: CGImage?) -> UIImage? {
        guard frames.count >= 2 else {
            logger.error("❌ 帧数量不足，无法合成")
            return nil
        }
        
        // 配置常量
        let kJPEGCompressionQuality: CGFloat = 0.92
        
        // 计算画布尺寸
        let maxWidth = frames.map { $0.width }.max() ?? 0
        var totalHeight = frames.reduce(0) { $0 + $1.height }
        
        // 添加顶部和底部固定区域的高度
        if let topArea = topFixedArea {
            totalHeight += topArea.height
        }
        if let bottomArea = bottomFixedArea {
            totalHeight += bottomArea.height
        }
        
        logger.info("🧩 开始合成: \(frames.count) 帧, 最大宽度 \(maxWidth)px, 总高度 \(totalHeight)px")
        
        // 记录每帧的尺寸
        for (index, frame) in frames.enumerated() {
            logger.debug("📐 第 \(index + 1) 帧尺寸: \(frame.width)×\(frame.height)")
        }
        
        // 创建 CGContext
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: maxWidth,
                  height: totalHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            logger.error("❌ 创建 CGContext 失败")
            return nil
        }
        
        logger.info("✅ CGContext 创建成功: \(maxWidth)×\(totalHeight)px")
        
        // 填充白色背景
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: maxWidth, height: totalHeight))
        logger.debug("🎨 填充白色背景完成")
        
        // 绘制所有帧
        var currentY: Int = 0
        
        // 绘制底部固定区域（在 CGContext 底部，即 UIKit 顶部）
        if let bottomArea = bottomFixedArea {
            let bottomWidth = bottomArea.width
            let bottomHeight = bottomArea.height
            let x = (maxWidth - bottomWidth) / 2
            let rect = CGRect(x: x, y: currentY, width: bottomWidth, height: bottomHeight)
            
            logger.debug("🖼️ 绘制底部固定区域: 位置 (\(x), \(currentY)), 尺寸 \(bottomWidth)×\(bottomHeight)")
            context.draw(bottomArea, in: rect)
            
            currentY += bottomHeight
            logger.debug("✅ 底部固定区域绘制完成，当前 Y 位置: \(currentY)")
        }
        
        // 绘制内容帧（倒序绘制，因为视频向上滚动，新内容从下面出现）
        // 最新的帧应该在最上面，最老的帧应该在最下面
        let reversedFrames = frames.reversed()
        for (index, cgImage) in reversedFrames.enumerated() {
            autoreleasepool { // 每帧使用 autoreleasepool 释放内存
                let frameWidth = cgImage.width
                let frameHeight = cgImage.height
                
                // 计算居中位置
                let x = (maxWidth - frameWidth) / 2
                let rect = CGRect(x: x, y: currentY, width: frameWidth, height: frameHeight)
                
                // 计算原始帧的索引（倒序后的第N帧对应正序的第几帧）
                let originalIndex = frames.count - 1 - index
                logger.debug("🖼️ 绘制第 \(originalIndex + 1) 帧 (倒序后第 \(index + 1) 帧): 位置 (\(x), \(currentY)), 尺寸 \(frameWidth)×\(frameHeight)")
                
                // 绘制帧
                context.draw(cgImage, in: rect)
                
                currentY += frameHeight
                logger.debug("✅ 绘制完成，当前 Y 位置: \(currentY)")
            }
        }
        
        // 绘制顶部固定区域（在 CGContext 顶部，即 UIKit 底部）
        if let topArea = topFixedArea {
            let topWidth = topArea.width
            let topHeight = topArea.height
            let x = (maxWidth - topWidth) / 2
            let rect = CGRect(x: x, y: currentY, width: topWidth, height: topHeight)
            
            logger.debug("🖼️ 绘制顶部固定区域: 位置 (\(x), \(currentY)), 尺寸 \(topWidth)×\(topHeight)")
            context.draw(topArea, in: rect)
            
            currentY += topHeight
            logger.debug("✅ 顶部固定区域绘制完成，当前 Y 位置: \(currentY)")
        }
        
        // 生成最终 CGImage
        guard let finalCGImage = context.makeImage() else {
            logger.error("❌ 生成最终 CGImage 失败")
            return nil
        }
        
        logger.info("✅ 生成最终 CGImage 成功: \(finalCGImage.width)×\(finalCGImage.height)px")
        
        // 检查内存大小，超过 50MB 则压缩为 JPEG
        let imageSize = finalCGImage.width * finalCGImage.height * 4 // RGBA 8-bit
        let imageSizeMB = Double(imageSize) / (1024 * 1024)
        
        logger.info("🎨 合成完成: \(finalCGImage.width)×\(finalCGImage.height)px, 大小 \(String(format: "%.2f", imageSizeMB))MB")
        
        if imageSizeMB > 50 {
            logger.info("📦 图像过大，压缩为 JPEG (质量: \(kJPEGCompressionQuality))")
            let uiImage = UIImage(cgImage: finalCGImage, scale: 1.0, orientation: .up)
            if let jpegData = uiImage.jpegData(compressionQuality: kJPEGCompressionQuality),
               let compressedImage = UIImage(data: jpegData) {
                let compressedSizeMB = Double(jpegData.count) / (1024 * 1024)
                logger.info("✅ 压缩完成: 大小 \(String(format: "%.2f", compressedSizeMB))MB, 压缩率 \(String(format: "%.2f%%", (1 - compressedSizeMB / imageSizeMB) * 100))")
                return compressedImage
            } else {
                logger.warning("⚠️ 压缩失败，使用原始图像")
            }
        }
        
        // 转换为 UIImage
        let finalImage = UIImage(cgImage: finalCGImage, scale: 1.0, orientation: .up)
        logger.info("✅ 转换为 UIImage 成功: \(Int(finalImage.size.width))×\(Int(finalImage.size.height))")
        
        return finalImage
    }

    // MARK: - 视频帧重叠检测算法（独立实现，不依赖图片拼接算法）

    /// 视频帧重叠检测配置
    private struct VideoOverlapConfig {
        // 搜索范围
        var maxOverlapPercent: Double = 0.85 // 最大可能重叠比例（85%）
        var minOverlapPercent: Double = 0.05 // 最小重叠比例（5%）

        // 相似度阈值
        var similarityThreshold: Double = 0.70 // 最低相似度要求
        var highSimilarityThreshold: Double = 0.82 // 高相似度阈值，用于提前退出

        // 搜索步长
        var coarseStep: Int = 80 // 粗粒度搜索步长
        var fineStep: Int = 4 // 细粒度搜索步长

        // 多尺度搜索
        var analysisScale: CGFloat = 0.25 // 分析时缩放比例（25%，提高速度）
        var fineSearchRange: CGFloat = 30 // 细粒度搜索范围

        // 像素匹配权重
        var pixelMatchWeight: Double = 0.7 // 像素匹配权重
        var hashMatchWeight: Double = 0.3 // 哈希匹配权重
    }

    /// 检测两个视频帧之间的重叠高度
    /// - Parameters:
    ///   - upperFrame: 上方的帧（较早的帧，底部有重叠区域）
    ///   - lowerFrame: 下方的帧（较晚的帧，顶部有重叠区域）
    /// - Returns: 重叠高度（像素），如果没有检测到有效重叠返回0
    private func detectVideoFrameOverlap(
        upperFrame: CGImage,
        lowerFrame: CGImage
    ) -> CGFloat {
        let width1 = CGFloat(upperFrame.width)
        let height1 = CGFloat(upperFrame.height)
        let width2 = CGFloat(lowerFrame.width)
        let height2 = CGFloat(lowerFrame.height)

        // 确保宽度一致
        guard abs(width1 - width2) < 2 else {
            logger.warning("⚠️ 帧宽度不一致: \(Int(width1)) vs \(Int(width2))")
            return 0
        }

        // 缩放到分析尺寸
        let config = VideoOverlapConfig()
        let scale = config.analysisScale

        guard let scaledUpper = resizeCGImage(upperFrame, to: CGSize(width: width1 * scale, height: height1 * scale)),
              let scaledLower = resizeCGImage(lowerFrame, to: CGSize(width: width2 * scale, height: height2 * scale)) else {
            logger.warning("⚠️ 缩放帧失败")
            return 0
        }

        let scaledWidth = CGFloat(scaledUpper.width)
        let scaledHeight1 = CGFloat(scaledUpper.height)
        let scaledHeight2 = CGFloat(scaledLower.height)

        // 计算搜索范围
        let minOverlap = scaledHeight1 * config.minOverlapPercent
        let maxOverlap = min(scaledHeight1 * config.maxOverlapPercent, scaledHeight2 * 0.95)

        // 阶段1：粗粒度搜索
        let coarseStep = max(Int(CGFloat(config.coarseStep) * scale), 5)
        let coarseResult = findBestOverlapCoarse(
            upperFrame: scaledUpper,
            lowerFrame: scaledLower,
            searchRange: (min: minOverlap, max: maxOverlap),
            step: coarseStep
        )

        // 阶段2：细粒度搜索
        if coarseResult.score >= config.similarityThreshold {
            let fineRange = config.fineSearchRange * scale
            let fineMin = max(coarseResult.overlap - fineRange, minOverlap)
            let fineMax = min(coarseResult.overlap + fineRange, maxOverlap)
            let fineStep = max(Int(CGFloat(config.fineStep) * scale), 1)

            let fineResult = findBestOverlapFine(
                upperFrame: scaledUpper,
                lowerFrame: scaledLower,
                searchRange: (min: fineMin, max: fineMax),
                step: fineStep
            )

            // 选择更好的结果
            if fineResult.score > coarseResult.score {
                let originalOverlap = fineResult.overlap / scale
                logger.debug("📊 重叠检测: 缩放后重叠=\(fineResult.overlap)px, 原始重叠=\(String(format: "%.1f", originalOverlap))px, 相似度=\(String(format: "%.3f", fineResult.score))")
                return originalOverlap
            } else {
                let originalOverlap = coarseResult.overlap / scale
                logger.debug("📊 重叠检测: 缩放后重叠=\(coarseResult.overlap)px, 原始重叠=\(String(format: "%.1f", originalOverlap))px, 相似度=\(String(format: "%.3f", coarseResult.score))")
                return originalOverlap
            }
        }

        let originalOverlap = coarseResult.overlap / scale
        logger.debug("📊 重叠检测: 粗粒度结果 overlap=\(String(format: "%.1f", originalOverlap))px, score=\(String(format: "%.3f", coarseResult.score))")
        return originalOverlap
    }

    /// 粗粒度搜索最佳重叠位置
    private func findBestOverlapCoarse(
        upperFrame: CGImage,
        lowerFrame: CGImage,
        searchRange: (min: CGFloat, max: CGFloat),
        step: Int
    ) -> (overlap: CGFloat, score: Double) {
        let height1 = CGFloat(upperFrame.height)
        let height2 = CGFloat(lowerFrame.height)
        let width = CGFloat(upperFrame.width)

        let validMinOverlap = max(searchRange.min, 10)
        let validMaxOverlap = min(searchRange.max, height1, height2)

        guard validMinOverlap < validMaxOverlap else {
            return (0, 0)
        }

        // 从大到小搜索
        let startY = Int(validMaxOverlap)
        let endY = Int(validMinOverlap)

        var bestOverlap: CGFloat = 0
        var bestScore: Double = 0

        for overlapHeight in stride(from: startY, through: endY, by: -step) {
            let overlap = CGFloat(overlapHeight)

            // 提取 upperFrame 的底部区域
            let region1 = CGRect(
                x: 0,
                y: max(0, height1 - overlap),
                width: width,
                height: min(overlap, height1)
            )

            // 提取 lowerFrame 的顶部区域
            let region2 = CGRect(
                x: 0,
                y: 0,
                width: width,
                height: min(overlap, height2)
            )

            guard let cropped1 = upperFrame.cropping(to: region1),
                  let cropped2 = lowerFrame.cropping(to: region2) else {
                continue
            }

            // 计算相似度
            let similarity = calculatePixelSimilarityVideo(cropped1, cropped2)

            if similarity > bestScore {
                bestScore = similarity
                bestOverlap = overlap
            }

            // 高相似度且重叠足够大时提前退出
            if bestScore >= 0.82 && overlap >= validMinOverlap * 2 {
                break
            }
        }

        return (bestOverlap, bestScore)
    }

    /// 细粒度搜索最佳重叠位置
    private func findBestOverlapFine(
        upperFrame: CGImage,
        lowerFrame: CGImage,
        searchRange: (min: CGFloat, max: CGFloat),
        step: Int
    ) -> (overlap: CGFloat, score: Double) {
        let height1 = CGFloat(upperFrame.height)
        let height2 = CGFloat(lowerFrame.height)
        let width = CGFloat(upperFrame.width)

        let startY = Int(searchRange.max)
        let endY = Int(searchRange.min)

        guard startY >= endY else {
            return (searchRange.min, 0)
        }

        var bestOverlap: CGFloat = 0
        var bestScore: Double = 0

        for overlapHeight in stride(from: startY, through: endY, by: -step) {
            let overlap = CGFloat(overlapHeight)

            // 提取 upperFrame 的底部区域
            let region1 = CGRect(
                x: 0,
                y: max(0, height1 - overlap),
                width: width,
                height: min(overlap, height1)
            )

            // 提取 lowerFrame 的顶部区域
            let region2 = CGRect(
                x: 0,
                y: 0,
                width: width,
                height: min(overlap, height2)
            )

            guard let cropped1 = upperFrame.cropping(to: region1),
                  let cropped2 = lowerFrame.cropping(to: region2) else {
                continue
            }

            // 计算相似度
            let similarity = calculatePixelSimilarityVideo(cropped1, cropped2)

            if similarity > bestScore {
                bestScore = similarity
                bestOverlap = overlap
            }
        }

        return (bestOverlap, bestScore)
    }

    /// 计算两个区域的像素相似度（视频专用）
    private func calculatePixelSimilarityVideo(_ image1: CGImage, _ image2: CGImage) -> Double {
        let width1 = image1.width
        let height1 = image1.height
        let width2 = image2.width
        let height2 = image2.height

        // 确保尺寸一致
        guard width1 == width2, height1 == height2 else {
            return 0
        }

        guard let pixels1 = getRGBADataVideo(from: image1),
              let pixels2 = getRGBADataVideo(from: image2) else {
            return 0
        }

        let totalPixels = width1 * height1
        let minSampleCount = max(totalPixels / 20, 500)
        let sampleStep = max(totalPixels / minSampleCount, 1)

        var totalDiff: Double = 0
        var sampleCount = 0

        for i in stride(from: 0, to: totalPixels * 4, by: sampleStep * 4) {
            let r1 = Double(pixels1[i])
            let g1 = Double(pixels1[i + 1])
            let b1 = Double(pixels1[i + 2])

            let r2 = Double(pixels2[i])
            let g2 = Double(pixels2[i + 1])
            let b2 = Double(pixels2[i + 2])

            // 使用曼哈顿距离
            let diff = (abs(r1 - r2) + abs(g1 - g2) + abs(b1 - b2)) / (255.0 * 3.0)
            totalDiff += diff
            sampleCount += 1
        }

        let avgDiff = totalDiff / Double(sampleCount)
        return 1.0 - avgDiff
    }

    /// 获取 RGBA 数据（视频专用）
    private func getRGBADataVideo(from image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bitsPerComponent = 8

        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: width * bytesPerPixel,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    /// 缩放 CGImage（视频专用）
    private func resizeCGImage(_ image: CGImage, to size: CGSize) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// 检测并移除视频帧之间的重叠区域
    /// - Parameter frames: 已排序的视频帧（从老到新）
    /// - Returns: 移除重叠后的帧数组
    private func detectAndRemoveOverlaps(from frames: [CGImage]) -> [CGImage] {
        guard frames.count >= 2 else { return frames }

        var processedFrames: [CGImage] = []
        processedFrames.append(frames[0]) // 第一帧完整保留

        logger.info("📊 开始重叠检测，共 \(frames.count) 帧")

        for i in 1..<frames.count {
            let upperFrame = frames[i - 1]
            let lowerFrame = frames[i]

            // 检测重叠高度
            let overlapHeight = detectVideoFrameOverlap(upperFrame: upperFrame, lowerFrame: lowerFrame)

            let lowerHeight = CGFloat(lowerFrame.height)
            let upperHeight = CGFloat(upperFrame.height)

            logger.info("📊 帧 \(i) 与帧 \(i-1): 重叠高度=\(String(format: "%.1f", overlapHeight))px, 上帧高度=\(Int(upperHeight))px, 下帧高度=\(Int(lowerHeight))px")

            if overlapHeight > 0 {
                // 裁剪掉 lowerFrame 的顶部重叠区域
                let cropRect = CGRect(
                    x: CGFloat(0),
                    y: overlapHeight,
                    width: CGFloat(lowerFrame.width),
                    height: CGFloat(lowerFrame.height) - overlapHeight
                )

                if let croppedFrame = lowerFrame.cropping(to: cropRect) {
                    logger.info("✅ 裁剪帧 \(i): 原始高度=\(lowerFrame.height), 裁剪后高度=\(croppedFrame.height), 移除重叠=\(String(format: "%.1f", overlapHeight))px")
                    processedFrames.append(croppedFrame)
                } else {
                    logger.warning("⚠️ 裁剪帧 \(i) 失败，使用原始帧")
                    processedFrames.append(lowerFrame)
                }
            } else {
                logger.info("⚠️ 未检测到重叠，保留帧 \(i) 原始高度=\(lowerFrame.height)")
                processedFrames.append(lowerFrame)
            }
        }

        return processedFrames
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
