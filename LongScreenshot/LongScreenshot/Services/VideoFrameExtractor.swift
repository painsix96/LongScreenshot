import UIKit
import AVFoundation
import os.log

// MARK: - 视频帧提取器

/// 从视频中提取帧序列，支持自适应采样策略
actor VideoFrameExtractor {
    
    private let logger = Logger(subsystem: "com.longscreenshot", category: "VideoFrameExtractor")
    
    // MARK: - 配置
    
    struct Config {
        /// 目标采样帧率（从原始帧率降采样）
        var targetFPS: Double = 5
        /// 最大提取帧数（防止内存爆炸）
        var maxFrames: Int = 100
        /// 最小帧间隔（秒）
        var minFrameInterval: TimeInterval = 0.15
        /// 提取帧的最大宽度（像素），超过则降采样
        var maxExtractWidth: CGFloat = 1080
        /// 内容变化阈值（0-1），用于自适应采样
        var contentChangeThreshold: Double = 0.05
    }
    
    private var _config = Config()
    
    var config: Config {
        get { _config }
    }
    
    func setConfigMaxExtractWidth(_ width: CGFloat) {
        _config.maxExtractWidth = width
    }
    
    // MARK: - 主入口
    
    /// 从视频中提取帧序列（基于时间段的自适应采样）
    /// - Parameters:
    ///   - asset: 视频 AVAsset
    ///   - timeRange: 提取时间段（nil 表示整个视频）
    ///   - progress: 进度追踪器
    /// - Returns: 提取的 UIImage 帧数组
    func extractFrames(
        from asset: AVAsset,
        timeRange: CMTimeRange? = nil,
        progress: StitchingProgress
    ) async throws -> [UIImage] {
        let duration = try await asset.load(.duration)
        let effectiveRange = timeRange ?? CMTimeRange(start: .zero, duration: duration)
        
        logger.info("🎬 开始提取视频帧: duration=\(CMTimeGetSeconds(duration))s, range=[\(CMTimeGetSeconds(effectiveRange.start))-\(CMTimeGetSeconds(CMTimeRangeGetEnd(effectiveRange)))]")
        
        // 创建图像生成器
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        
        // 计算采样时间点
        let sampleTimes = calculateSampleTimes(for: effectiveRange)
        logger.info("🎬 计划采样 \(sampleTimes.count) 帧")
        
        guard sampleTimes.count >= 2 else {
            throw VideoStitchingError.insufficientFrames
        }
        
        // 提取所有帧
        var frames: [UIImage] = []
        let totalCount = sampleTimes.count
        
        for (index, time) in sampleTimes.enumerated() {
            try progress.checkCancellation()
            
            do {
                let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
                
                // 降采样如果尺寸过大
                let resizedImage = resizeIfNeeded(image, maxWidth: config.maxExtractWidth)
                frames.append(resizedImage)
                
                logger.debug("🎬 提取第 \(index + 1)/\(totalCount) 帧 @ \(CMTimeGetSeconds(time))s")
                
            } catch {
                logger.warning("⚠️ 提取第 \(index + 1) 帧失败: \(error.localizedDescription)")
                // 跳过失败的帧，继续处理
            }
            
            // 更新进度
            let progressValue = Double(index + 1) / Double(totalCount)
            progress.updatePhaseProgress(.loading, progress: progressValue)
        }
        
        guard frames.count >= 2 else {
            throw VideoStitchingError.insufficientFrames
        }
        
        logger.info("✅ 帧提取完成: 成功 \(frames.count)/\(totalCount) 帧")
        return frames
    }
    
    /// 自适应采样：根据内容变化密度动态调整采样率
    func extractFramesAdaptive(
        from asset: AVAsset,
        timeRange: CMTimeRange? = nil,
        progress: StitchingProgress
    ) async throws -> [UIImage] {
        let duration = try await asset.load(.duration)
        let effectiveRange = timeRange ?? CMTimeRange(start: .zero, duration: duration)
        let rangeDuration = CMTimeGetSeconds(effectiveRange.duration)
        
        logger.info("🎬 开始自适应采样: duration=\(rangeDuration)s")
        
        // 第一阶段：稀疏采样，分析内容变化
        let sparseInterval = max(rangeDuration / Double(_config.maxFrames), 0.5)
        let sparseTimes = stride(from: 0.0, to: rangeDuration, by: sparseInterval).map {
            CMTime(seconds: $0 + CMTimeGetSeconds(effectiveRange.start), preferredTimescale: 600)
        }
        
        guard sparseTimes.count >= 2 else {
            return try await extractFrames(from: asset, timeRange: effectiveRange, progress: progress)
        }
        
        // 提取稀疏帧用于分析
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        var sparseFrames: [UIImage] = []
        for time in sparseTimes {
            do {
                let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
                sparseFrames.append(resizeIfNeeded(image, maxWidth: _config.maxExtractWidth))
            } catch {
                logger.warning("⚠️ 稀疏采样帧提取失败: \(error.localizedDescription)")
            }
        }
        
        // 分析内容变化，确定高密度采样区域
        let denseRegions = analyzeContentChangeRegions(sparseFrames, interval: sparseInterval)
        
        // 第二阶段：根据分析结果进行精细采样
        var finalTimes: [CMTime] = []
        
        if denseRegions.isEmpty {
            // 无显著变化区域，均匀采样
            finalTimes = calculateSampleTimes(for: effectiveRange)
        } else {
            // 在变化剧烈区域加密采样
            for region in denseRegions {
                let regionStart = CMTimeGetSeconds(effectiveRange.start) + region.start
                let regionEnd = CMTimeGetSeconds(effectiveRange.start) + region.end
                let regionDuration = regionEnd - regionStart
                
                // 变化剧烈区域：按 minFrameInterval 采样
                let frameCount = max(Int(regionDuration / _config.minFrameInterval), 3)
                let step = regionDuration / Double(frameCount)
                
                for i in 0..<frameCount {
                    let time = regionStart + Double(i) * step
                    finalTimes.append(CMTime(seconds: time, preferredTimescale: 600))
                }
            }
            
            // 去重并排序
            finalTimes = Array(Set(finalTimes.map { CMTimeGetSeconds($0) }))
                .sorted()
                .map { CMTime(seconds: $0, preferredTimescale: 600) }
        }
        
        // 限制最大帧数
        if finalTimes.count > _config.maxFrames {
            let step = Double(finalTimes.count) / Double(_config.maxFrames)
            var thinned: [CMTime] = []
            for i in 0..<_config.maxFrames {
                let index = Int(Double(i) * step)
                if index < finalTimes.count {
                    thinned.append(finalTimes[index])
                }
            }
            finalTimes = thinned
        }
        
        logger.info("🎬 自适应采样: 最终计划提取 \(finalTimes.count) 帧")
        
        // 提取最终帧序列
        var frames: [UIImage] = []
        let totalCount = finalTimes.count
        
        for (index, time) in finalTimes.enumerated() {
            try progress.checkCancellation()
            
            do {
                let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
                let resizedImage = resizeIfNeeded(image, maxWidth: _config.maxExtractWidth)
                frames.append(resizedImage)
                
                logger.debug("🎬 提取第 \(index + 1)/\(totalCount) 帧 @ \(CMTimeGetSeconds(time))s")
                
            } catch {
                logger.warning("⚠️ 提取第 \(index + 1) 帧失败: \(error.localizedDescription)")
            }
            
            let progressValue = Double(index + 1) / Double(totalCount)
            progress.updatePhaseProgress(.loading, progress: progressValue)
        }
        
        guard frames.count >= 2 else {
            throw VideoStitchingError.insufficientFrames
        }
        
        logger.info("✅ 自适应采样完成: 成功 \(frames.count) 帧")
        return frames
    }
    
    // MARK: - 私有方法
    
    /// 计算均匀采样时间点
    private func calculateSampleTimes(for range: CMTimeRange) -> [CMTime] {
        let start = CMTimeGetSeconds(range.start)
        let duration = CMTimeGetSeconds(range.duration)
        let end = start + duration
        
        // 基于目标帧率计算采样间隔
        let interval = 1.0 / _config.targetFPS
        let estimatedCount = Int(duration / interval)
        
        // 如果预估帧数超过最大值，调整间隔
        let finalInterval: Double
        if estimatedCount > _config.maxFrames {
            finalInterval = duration / Double(_config.maxFrames)
        } else {
            finalInterval = interval
        }
        
        var times: [CMTime] = []
        var currentTime = start
        
        while currentTime < end && times.count < _config.maxFrames {
            times.append(CMTime(seconds: currentTime, preferredTimescale: 600))
            currentTime += finalInterval
        }
        
        // 确保包含最后一帧（如果距离足够远）
        if let last = times.last, end - CMTimeGetSeconds(last) > _config.minFrameInterval {
            times.append(CMTime(seconds: end - 0.01, preferredTimescale: 600))
        }
        
        return times
    }
    
    /// 分析内容变化剧烈的区域
    private func analyzeContentChangeRegions(_ frames: [UIImage], interval: Double) -> [(start: Double, end: Double)] {
        guard frames.count >= 2 else { return [] }
        
        var regions: [(start: Double, end: Double)] = []
        var currentRegionStart: Double?
        
        for i in 1..<frames.count {
            let similarity = calculateFrameSimilarity(frames[i-1], frames[i])
            let change = 1.0 - similarity
            let time = Double(i) * interval
            
            if change > _config.contentChangeThreshold {
                // 内容变化显著
                if currentRegionStart == nil {
                    currentRegionStart = time - interval
                }
            } else {
                // 内容变化平缓，结束当前区域
                if let start = currentRegionStart {
                    regions.append((start: start, end: time))
                    currentRegionStart = nil
                }
            }
        }
        
        // 处理最后一个区域
        if let start = currentRegionStart {
            let end = Double(frames.count - 1) * interval
            regions.append((start: start, end: end))
        }
        
        logger.info("🎬 内容变化区域分析: 发现 \(regions.count) 个变化区域")
        return regions
    }
    
    /// 计算两帧的相似度（0-1）
    private func calculateFrameSimilarity(_ image1: UIImage, _ image2: UIImage) -> Double {
        guard let cg1 = image1.cgImage, let cg2 = image2.cgImage else { return 0 }
        
        let width = min(cg1.width, cg2.width)
        let height = min(cg1.height, cg2.height)
        guard width > 0, height > 0 else { return 0 }
        
        // 降采样到较小尺寸进行比较（提高性能）
        let compareSize = CGSize(width: 100, height: 100)
        let resized1 = resizeImage(image1, to: compareSize)
        let resized2 = resizeImage(image2, to: compareSize)
        
        guard let smallCG1 = resized1.cgImage, let smallCG2 = resized2.cgImage else { return 0 }
        
        // 提取灰度数据并计算差异
        guard let gray1 = extractGrayscaleData(from: smallCG1),
              let gray2 = extractGrayscaleData(from: smallCG2) else { return 0 }
        
        let pixelCount = gray1.count
        guard pixelCount == gray2.count, pixelCount > 0 else { return 0 }
        
        var totalDiff: Double = 0
        for i in 0..<pixelCount {
            totalDiff += abs(Double(gray1[i]) - Double(gray2[i]))
        }
        
        let avgDiff = totalDiff / Double(pixelCount)
        let similarity = 1.0 - (avgDiff / 255.0)
        
        return max(0, min(1, similarity))
    }
    
    /// 如果图片宽度超过限制，进行降采样
    private func resizeIfNeeded(_ image: UIImage, maxWidth: CGFloat) -> UIImage {
        let width = image.size.width * image.scale
        if width <= maxWidth {
            return image
        }
        
        let scale = maxWidth / width
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return resizeImage(image, to: newSize)
    }
    
    /// 调整图片尺寸
    private func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
    
    /// 提取灰度数据
    private func extractGrayscaleData(from cgImage: CGImage) -> [UInt8]? {
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }
}
