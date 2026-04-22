import UIKit
import Accelerate
import os.log

// MARK: - 日志工具
private let logger = Logger(subsystem: "com.longscreenshot", category: "ImageStitcher")

// MARK: - 错误类型

enum StitchError: Error, LocalizedError {
    case insufficientImages
    case invalidImageData
    case stitchingFailed
    case cancelled
    case processingFailed
    case outOfMemory
    case custom(String)
    
    var errorDescription: String? {
        switch self {
        case .insufficientImages:
            return "需要至少两张图片进行拼接"
        case .invalidImageData:
            return "图片数据无效"
        case .stitchingFailed:
            return "拼接失败"
        case .cancelled:
            return "操作已取消"
        case .processingFailed:
            return "图片处理失败"
        case .outOfMemory:
            return "内存不足"
        case .custom(let message):
            return message
        }
    }
}

// MARK: - 拼接配置

struct StitchingConfig {
    /// 最大支持图片数
    var maxImages: Int = 20
    /// 是否启用重叠检测
    var enableOverlapDetection: Bool = true
    /// 是否启用渐变融合
    var enableBlending: Bool = true
    /// 输出质量 (0.0 - 1.0)
    var outputQuality: CGFloat = 0.95
    /// 快速模式（降低质量换取速度）
    var fastMode: Bool = false
    /// 内存限制 (MB)
    var memoryLimitMB: Int = 512
    
    /// 默认配置
    static let `default` = StitchingConfig()
    
    /// 高性能配置
    static let highPerformance = StitchingConfig(
        maxImages: 20,
        enableOverlapDetection: true,
        enableBlending: true,
        outputQuality: 0.90,
        fastMode: true,
        memoryLimitMB: 256
    )
    
    /// 高质量配置
    static let highQuality = StitchingConfig(
        maxImages: 10,
        enableOverlapDetection: true,
        enableBlending: true,
        outputQuality: 0.98,
        fastMode: false,
        memoryLimitMB: 1024
    )
}

// MARK: - 拼接结果

struct StitchingResult {
    let image: UIImage
    let processedCount: Int
    let totalHeight: CGFloat
    let overlaps: [OverlapInfo]
    let processingTime: TimeInterval
    let memoryPeakUsage: Int
    
    struct OverlapInfo {
        let index: Int
        let height: Int
        let confidence: Double
    }
}

// MARK: - 图片加载器

actor ImageLoader {
    private let memoryManager: MemoryManager
    private var loadedImages: [UUID: UIImage] = [:]
    
    init(memoryManager: MemoryManager = .shared) {
        self.memoryManager = memoryManager
    }
    
    /// 批量加载图片（带内存管理）
    func loadImages(
        _ images: [UIImage],
        progress: StitchingProgress
    ) async throws -> [UIImage] {
        logger.info("[Step 1/5] 开始加载图片，共 \(images.count) 张")
        
        guard !images.isEmpty else {
            logger.error("[Step 1/5] 失败：图片数组为空")
            throw StitchError.insufficientImages
        }
        
        var loadedImages: [UIImage] = []
        let totalCount = images.count
        
        for (index, image) in images.enumerated() {
            try await progress.checkCancellation()
            
            let originalSize = image.size
            let scale = image.scale
            logger.debug("[Step 1/5] 处理第 \(index + 1)/\(totalCount) 张图片，原始尺寸: \(originalSize.width)×\(originalSize.height), scale: \(scale)")
            
            // 等待内存可用
            let estimatedMemory = estimateMemoryUsage(for: image)
            logger.debug("[Step 1/5] 估算内存占用: \(estimatedMemory)MB")
            
            while !self.memoryManager.hasAvailableMemory(requestedMB: estimatedMemory) {
                logger.warning("[Step 1/5] 内存不足，等待中... 当前使用: \(self.memoryManager.currentUsageMB())MB")
                try await Task.sleep(nanoseconds: 5_000_000) // 5ms
                try await progress.checkCancellation()
            }
            
            // 预加载图片数据
            let optimizedImage = try await optimizeImage(image)
            let finalSize = optimizedImage.size
            
            if finalSize != originalSize {
                logger.info("[Step 1/5] 第 \(index + 1) 张图片已降采样: \(originalSize.width)×\(originalSize.height) → \(finalSize.width)×\(finalSize.height)")
            } else {
                logger.debug("[Step 1/5] 第 \(index + 1) 张图片无需降采样")
            }
            
            loadedImages.append(optimizedImage)
            
            // 记录内存使用
            let actualMemory = estimateMemoryUsage(for: optimizedImage)
            _ = self.memoryManager.allocate(bytes: actualMemory * 1024 * 1024, identifier: "image_\(index)")
            logger.debug("[Step 1/5] 实际内存占用: \(actualMemory)MB，总使用: \(self.memoryManager.currentUsageMB())MB")
            
            // 更新进度
            let progressValue = Double(index + 1) / Double(totalCount)
            await progress.updatePhaseProgress(.loading, progress: progressValue)
        }
        
        logger.info("[Step 1/5] 图片加载完成，共 \(loadedImages.count) 张")
        return loadedImages
    }
    
    /// 估算图片内存占用 (MB)
    private func estimateMemoryUsage(for image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        let bytesPerPixel = 4 // RGBA
        let width = cgImage.width
        let height = cgImage.height
        let bytes = width * height * bytesPerPixel
        return bytes / 1024 / 1024 + 1
    }
    
    /// 优化图片（如果需要）
    private func optimizeImage(_ image: UIImage) async throws -> UIImage {
        // 检查是否需要降采样
        let maxDimension: CGFloat = 4096 // 4K
        let currentMax = max(image.size.width, image.size.height)
        
        if currentMax > maxDimension {
            let scale = maxDimension / currentMax
            let newSize = CGSize(
                width: image.size.width * scale,
                height: image.size.height * scale
            )
            
            return try await Task.detached(priority: .utility) {
                let format = UIGraphicsImageRendererFormat()
                format.scale = image.scale
                
                let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
                return renderer.image { context in
                    image.draw(in: CGRect(origin: .zero, size: newSize))
                }
            }.value
        }
        
        return image
    }
    
    /// 释放已加载的图片
    func releaseImages() {
        loadedImages.removeAll()
    }
}

// MARK: - 主拼接器

actor ImageStitcher {
    
    // MARK: - 属性
    
    private let config: StitchingConfig
    private let imageLoader: ImageLoader
    private let imageProcessor: ImageProcessor
    private let overlapDetector: OverlapDetector
    private let memoryManager: MemoryManager
    
    // MARK: - 初始化
    
    init(config: StitchingConfig = .default) {
        self.config = config
        self.memoryManager = MemoryManager.shared
        self.memoryManager.maxMemoryMB = config.memoryLimitMB
        self.imageLoader = ImageLoader(memoryManager: memoryManager)
        self.imageProcessor = ImageProcessor(config: ImageProcessorConfig(
            maxMemoryMB: config.memoryLimitMB,
            useMetalAcceleration: !config.fastMode
        ))
        self.overlapDetector = OverlapDetector()
    }
    
    // MARK: - 公共接口
    
    /// 拼接多张图片（带进度回调）
    func stitch(
        images: [UIImage],
        progress: StitchingProgress = StitchingProgress()
    ) async throws -> StitchingResult {
        let startTime = Date()
        logger.info("🚀 开始长截图拼接，共 \(images.count) 张图片")
        
        // 验证输入
        try validateInput(images)
        
        // 重置进度
        await progress.reset()
        await progress.updatePhase(.loading)
        
        // 1. 加载图片
        logger.info("📸 [Step 1/5] 加载图片...")
        let loadedImages = try await imageLoader.loadImages(images, progress: progress)
        
        // 2. 检测重叠区域，并获取裁剪后的图片
        logger.info("🔍 [Step 2/5] 检测重叠区域...")
        await progress.updatePhase(.analyzing)
        let (overlaps, croppedImages) = try await detectOverlaps(images: loadedImages, progress: progress)
        
        // 3. 处理图像融合
        logger.info("⚙️ [Step 3/5] 预处理图片...")
        await progress.updatePhase(.processing)
        let processedImages = try await processImages(
            images: croppedImages,
            overlaps: overlaps,
            progress: progress
        )
        
        // 4. 执行拼接
        logger.info("🧩 [Step 4/5] 执行拼接...")
        await progress.updatePhase(.stitching)
        let stitchedImage = try await performStitching(
            images: processedImages,
            overlaps: overlaps,
            progress: progress
        )
        
        // 5. 最终处理
        logger.info("✨ [Step 5/5] 最终处理...")
        await progress.updatePhase(.finalizing)
        let finalImage = try await finalizeImage(stitchedImage, progress: progress)
        
        let processingTime = Date().timeIntervalSince(startTime)
        let memoryPeak = memoryManager.currentUsageMB()
        
        logger.info("✅ 拼接完成！")
        logger.info("📊 最终尺寸: \(finalImage.size.width)×\(finalImage.size.height)")
        logger.info("⏱️ 处理时间: \(String(format: "%.2f", processingTime))秒")
        logger.info("💾 峰值内存: \(memoryPeak)MB")
        
        // 清理内存
        await imageLoader.releaseImages()
        memoryManager.clearWarnings()
        memoryManager.reset()
        
        // 构建结果
        let overlapInfos = overlaps.enumerated().map { index, result in
            StitchingResult.OverlapInfo(
                index: index,
                height: Int(result.bestStitchPosition.overlapHeight),
                confidence: result.confidence
            )
        }
        
        return StitchingResult(
            image: finalImage,
            processedCount: images.count,
            totalHeight: finalImage.size.height,
            overlaps: overlapInfos,
            processingTime: processingTime,
            memoryPeakUsage: memoryPeak
        )
    }
    
    /// 快速拼接（无进度回调）
    func stitchQuickly(images: [UIImage]) async throws -> UIImage? {
        let result = try await stitch(images: images)
        return result.image
    }
    
    /// 取消当前任务
    func cancel(progress: StitchingProgress) async {
        await progress.cancel()
    }
    
    // MARK: - 私有方法
    
    /// 验证输入
    private func validateInput(_ images: [UIImage]) throws {
        guard images.count >= 2 else {
            throw StitchError.insufficientImages
        }
        
        guard images.count <= config.maxImages else {
            throw StitchError.custom("超出最大支持图片数 (\(config.maxImages))")
        }
        
        for (index, image) in images.enumerated() {
            guard image.cgImage != nil else {
                throw StitchError.custom("第 \(index + 1) 张图片数据无效")
            }
        }
    }
    
    /// 检测重叠区域
    private func detectOverlaps(
        images: [UIImage],
        progress: StitchingProgress
    ) async throws -> ([OverlapResult], [UIImage]) {
        guard config.enableOverlapDetection else {
            logger.info("[Step 2/5] 重叠检测已禁用，跳过")
            return (Array(repeating: .noOverlap, count: images.count - 1), images)
        }
        
        logger.info("[Step 2/5] 开始检测 \(images.count - 1) 对相邻图片的重叠区域")
        
        var results: [OverlapResult] = []
        var croppedImages: [UIImage] = []
        
        for i in 0..<(images.count - 1) {
            try await progress.checkCancellation()
            
            logger.debug("[Step 2/5] 检测第 \(i + 1)/\(images.count - 1) 对重叠...")
            let result = await overlapDetector.detectOverlap(between: images[i], and: images[i + 1])
            
            if result.hasOverlap {
                logger.info("[Step 2/5] 第 \(i + 1) 对: 找到重叠，高度=\(result.bestStitchPosition.overlapHeight)px, 相似度=\(String(format: "%.2f", result.similarityScore)), 质量=\(result.bestStitchPosition.quality.rawValue)")
            } else {
                logger.warning("[Step 2/5] 第 \(i + 1) 对: 未找到有效重叠，将直接拼接")
            }
            
            results.append(result)
            
            // 收集裁剪后的图片（如果是第一张，需要裁剪）
            if i == 0 {
                let cropped = cropFixedAreasIfNeeded(from: images[i], topCrop: result.topCrop1, bottomCrop: result.bottomCrop1)
                croppedImages.append(cropped)
            }
            
            // 裁剪第二张图片
            let croppedNext = cropFixedAreasIfNeeded(from: images[i + 1], topCrop: result.topCrop2, bottomCrop: result.bottomCrop2)
            croppedImages.append(croppedNext)
            
            let detectProgress = Double(i + 1) / Double(images.count - 1)
            await progress.updatePhaseProgress(.analyzing, progress: detectProgress)
        }
        
        let totalOverlap = results.reduce(0) { $0 + ($1.hasOverlap ? Int($1.bestStitchPosition.overlapHeight) : 0) }
        logger.info("[Step 2/5] 重叠检测完成，总重叠高度: \(totalOverlap)px")
        
        return (results, croppedImages)
    }
    
    /// 裁剪图片的固定区域（如果需要）
    private func cropFixedAreasIfNeeded(from image: UIImage, topCrop: CGFloat, bottomCrop: CGFloat) -> UIImage {
        if topCrop <= 0 && bottomCrop <= 0 {
            return image
        }
        
        guard let cgImage = image.cgImage else {
            return image
        }
        
        let scale = image.scale
        let topCropPixels = topCrop * scale
        let bottomCropPixels = bottomCrop * scale
        let cropHeight = cgImage.height - Int(topCropPixels) - Int(bottomCropPixels)
        
        guard cropHeight > 0 else {
            return image
        }
        
        let cropRect = CGRect(
            x: 0,
            y: Int(topCropPixels),
            width: cgImage.width,
            height: cropHeight
        )
        
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
            return image
        }
        
        return UIImage(cgImage: croppedCGImage, scale: scale, orientation: image.imageOrientation)
    }
    
    /// 处理图片（压缩、分块等）
    private func processImages(
        images: [UIImage],
        overlaps: [OverlapResult],
        progress: StitchingProgress
    ) async throws -> [UIImage] {
        logger.info("[Step 3/5] 开始预处理图片...")
        
        // 在快速模式下跳过复杂处理
        guard !config.fastMode else {
            logger.info("[Step 3/5] 快速模式，跳过预处理")
            return images
        }
        
        var processedImages: [UIImage] = images
        var compressedCount = 0
        
        // 对大图片进行预处理
        for (index, image) in images.enumerated() {
            try await progress.checkCancellation()
            
            let originalSize = image.size
            if await imageProcessor.shouldUseChunking(for: image) {
                logger.info("[Step 3/5] 第 \(index + 1) 张图片尺寸较大 \(originalSize.width)×\(originalSize.height)，进行压缩...")
                // 压缩大图片
                processedImages[index] = try await imageProcessor.compressImage(
                    image,
                    maxDimension: 3840
                )
                let newSize = processedImages[index].size
                logger.info("[Step 3/5] 第 \(index + 1) 张压缩完成: \(originalSize.width)×\(originalSize.height) → \(newSize.width)×\(newSize.height)")
                compressedCount += 1
            } else {
                logger.debug("[Step 3/5] 第 \(index + 1) 张图片无需压缩")
            }
        }
        
        logger.info("[Step 3/5] 预处理完成，压缩了 \(compressedCount)/\(images.count) 张图片")
        return processedImages
    }
    
    /// 执行拼接
    private func performStitching(
        images: [UIImage],
        overlaps: [OverlapResult],
        progress: StitchingProgress
    ) async throws -> UIImage {
        logger.info("[Step 4/5] 开始执行拼接...")
        
        guard var resultImage = images.first else {
            logger.error("[Step 4/5] 失败：图片数组为空")
            throw StitchError.insufficientImages
        }
        
        // 统一所有图片尺寸（基于第一张图片的宽度）
        let targetWidth = resultImage.size.width
        logger.info("[Step 4/5] 统一图片宽度为 \(targetWidth)px")
        
        var normalizedImages: [UIImage] = [resultImage]
        
        for i in 1..<images.count {
            let normalizedImage = await normalizeImageSize(images[i], targetWidth: targetWidth)
            if normalizedImage.size != images[i].size {
                logger.info("[Step 4/5] 第 \(i + 1) 张图片已调整尺寸: \(images[i].size.width)×\(images[i].size.height) → \(normalizedImage.size.width)×\(normalizedImage.size.height)")
            }
            normalizedImages.append(normalizedImage)
        }
        
        logger.info("[Step 4/5] 开始逐对拼接，共 \(normalizedImages.count - 1) 次拼接操作")
        
        for i in 1..<normalizedImages.count {
            try await progress.checkCancellation()
            
            let nextImage = normalizedImages[i]
            let overlap = overlaps[i - 1]
            
            logger.info("[Step 4/5] 第 \(i)/\(normalizedImages.count - 1) 次拼接:")
            logger.info("  - 当前结果图尺寸: \(resultImage.size.width)×\(resultImage.size.height)")
            logger.info("  - 下一张图尺寸: \(nextImage.size.width)×\(nextImage.size.height)")
            
            // 确保重叠高度不超过图片实际高度
            let maxOverlap = min(Int(resultImage.size.height), Int(nextImage.size.height))
            let overlapHeight = min(Int(overlap.bestStitchPosition.overlapHeight), maxOverlap)
            
            logger.info("  - 重叠高度: \(overlapHeight)px (最大允许: \(maxOverlap)px)")
            
            logger.info("  - 使用纯裁剪拼接模式")
            // 纯裁剪拼接：使用 yOffset 和 overlapHeight 正确裁剪两张图片
            // yOffset 现在已经是裁剪后图片空间的坐标，直接使用
            let yOffset = overlap.bestStitchPosition.yOffset
            
            logger.info("  - yOffset: \(yOffset)px, overlapHeight: \(overlapHeight)px")
            resultImage = try await simpleStitch(
                top: resultImage,
                bottom: nextImage,
                overlapHeight: overlapHeight,
                yOffset: yOffset
            )
            
            logger.info("  - 拼接后尺寸: \(resultImage.size.width)×\(resultImage.size.height)")
            
            // 更新进度
            let stitchProgress = Double(i) / Double(normalizedImages.count - 1)
            await progress.updatePhaseProgress(.stitching, progress: stitchProgress)
        }
        
        logger.info("[Step 4/5] 拼接完成，最终尺寸: \(resultImage.size.width)×\(resultImage.size.height)")
        return resultImage
    }
    
    /// 统一图片尺寸（缩放到目标宽度，保持宽高比）
    private func normalizeImageSize(_ image: UIImage, targetWidth: CGFloat) -> UIImage {
        // 如果宽度差异小于2像素，视为相同
        if abs(image.size.width - targetWidth) < 2 {
            return image
        }
        
        // 计算缩放比例
        let scale = targetWidth / image.size.width
        let newSize = CGSize(width: targetWidth, height: image.size.height * scale)
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    /// 简单拼接（无融合）
    /// 当有重叠区域时，只绘制两张图的非重叠部分，避免覆盖
    /// - Parameters:
    ///   - top: 顶部图片（当前结果图）
    ///   - bottom: 底部图片（下一张要拼接的图片）
    ///   - overlapHeight: 重叠区域高度（底部图片顶部有多少像素与顶部图片重叠）
    ///   - yOffset: 顶部图片中重叠区域的起始位置（从顶部图片顶部开始的偏移）
    private func simpleStitch(top: UIImage, bottom: UIImage, overlapHeight: Int = 0, yOffset: CGFloat = 0) async throws -> UIImage {
        return try await Task.detached(priority: .userInitiated) {
            let maxWidth = max(top.size.width, bottom.size.width)
            let topHeight = top.size.height
            let bottomHeight = bottom.size.height
            
            // 计算实际的重叠高度（取最小值，防止越界）
            let actualOverlapHeight = CGFloat(min(overlapHeight, Int(topHeight), Int(bottomHeight)))
            
            // 计算顶部图片需要保留的高度（从顶部到重叠区域起始位置）
            let topKeepHeight = min(yOffset, topHeight)
            
            // 计算底部图片需要保留的高度（从重叠区域结束位置到底部）
            let bottomKeepHeight = bottomHeight - actualOverlapHeight
            
            // 总高度 = 顶部保留高度 + 底部保留高度
            let totalHeight = topKeepHeight + bottomKeepHeight
            
            let format = UIGraphicsImageRendererFormat()
            format.scale = top.scale
            
            let size = CGSize(width: maxWidth, height: totalHeight)
            let renderer = UIGraphicsImageRenderer(size: size, format: format)
            
            return renderer.image { context in
                let topXOffset = (maxWidth - top.size.width) / 2
                let bottomXOffset = (maxWidth - bottom.size.width) / 2
                
                // 绘制顶部图片的非重叠部分（从顶部到 yOffset）
                if topKeepHeight > 0 {
                    let topPixelHeight = top.cgImage?.height ?? Int(topHeight * top.scale)
                    let topPixelWidth = top.cgImage?.width ?? Int(top.size.width * top.scale)
                    let topKeepPixelHeight = Int(topKeepHeight * top.scale)
                    
                    // CGImage 坐标系：y=0 在左上角
                    // 要取顶部图片的顶部 topKeepHeight 像素，直接从 y=0 开始
                    if topKeepPixelHeight > 0, let croppedTop = top.cgImage?.cropping(to: CGRect(
                        x: 0,
                        y: 0,
                        width: topPixelWidth,
                        height: topKeepPixelHeight
                    )) {
                        let croppedImage = UIImage(cgImage: croppedTop, scale: top.scale, orientation: top.imageOrientation)
                        croppedImage.draw(in: CGRect(
                            x: topXOffset,
                            y: 0,
                            width: top.size.width,
                            height: topKeepHeight
                        ))
                    } else {
                        // 裁剪失败，回退到直接绘制
                        top.draw(in: CGRect(
                            x: topXOffset,
                            y: 0,
                            width: top.size.width,
                            height: topKeepHeight
                        ))
                    }
                }
                
                // 绘制底部图片的非重叠部分（从 overlapHeight 到底部）
                if bottomKeepHeight > 0 {
                    let overlapCGHeight = actualOverlapHeight * bottom.scale
                    let bottomPixelHeight = bottom.cgImage?.height ?? Int(bottomHeight * bottom.scale)
                    let bottomPixelWidth = bottom.cgImage?.width ?? Int(bottom.size.width * bottom.scale)
                    // CGImage 坐标系：y=0 在左上角
                    // 要取底部图片从 overlapHeight 到底部的部分，直接从 y=overlapCGHeight 开始
                    let cropY = Int(overlapCGHeight)
                    let cropHeight = bottomPixelHeight - cropY
                    
                    if cropHeight > 0, let croppedBottom = bottom.cgImage?.cropping(to: CGRect(
                        x: 0,
                        y: cropY,
                        width: bottomPixelWidth,
                        height: cropHeight
                    )) {
                        let croppedImage = UIImage(cgImage: croppedBottom, scale: bottom.scale, orientation: bottom.imageOrientation)
                        // 绘制位置：在顶部保留部分的下方
                        let drawY = topKeepHeight
                        croppedImage.draw(in: CGRect(
                            x: bottomXOffset,
                            y: drawY,
                            width: bottom.size.width,
                            height: bottomKeepHeight
                        ))
                    } else {
                        // 裁剪失败，回退到直接绘制
                        bottom.draw(in: CGRect(
                            x: bottomXOffset,
                            y: topKeepHeight,
                            width: bottom.size.width,
                            height: bottomHeight
                        ))
                    }
                }
            }
        }.value
    }
    
    /// 最终处理
    private func finalizeImage(
        _ image: UIImage,
        progress: StitchingProgress
    ) async throws -> UIImage {
        try await progress.checkCancellation()
        
        // 检查是否需要压缩输出
        let maxOutputSize: CGFloat = 16384 // 最大输出尺寸
        let maxDimension = max(image.size.width, image.size.height)
        
        if maxDimension > maxOutputSize {
            let scale = maxOutputSize / maxDimension
            let newSize = CGSize(
                width: image.size.width * scale,
                height: image.size.height * scale
            )
            
            return try await Task.detached(priority: .utility) {
                let format = UIGraphicsImageRendererFormat()
                format.scale = image.scale
                
                let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
                return renderer.image { context in
                    image.draw(in: CGRect(origin: .zero, size: newSize))
                }
            }.value
        }
        
        await progress.updatePhaseProgress(.finalizing, progress: 1.0)
        return image
    }
    
    // MARK: - 静态方法（简化接口）
    
    /// 静态快速拼接方法
    static func stitch(images: [UIImage]) async -> UIImage? {
        guard images.count > 1 else { return nil }
        
        let stitcher = ImageStitcher(config: .default)
        return try? await stitcher.stitchQuickly(images: images)
    }
    
    /// 静态高质量拼接方法
    static func stitchHighQuality(images: [UIImage]) async -> UIImage? {
        guard images.count > 1 else { return nil }
        
        let stitcher = ImageStitcher(config: .highQuality)
        return try? await stitcher.stitchQuickly(images: images)
    }
}

// MARK: - 使用示例

extension ImageStitcher {
    /// 使用示例代码
    static func exampleUsage() async {
        let images: [UIImage] = [] // 你的图片数组
        let progress = StitchingProgress()
        
        // 设置进度回调
        progress.progressHandler = { currentProgress, phase in
            print("进度: \(Int(currentProgress * 100))%, 阶段: \(phase.rawValue)")
        }
        
        do {
            let stitcher = ImageStitcher(config: .default)
            let result = try await stitcher.stitch(images: images, progress: progress)
            
            print("拼接完成!")
            print("图片尺寸: \(result.image.size)")
            print("处理时间: \(result.processingTime)秒")
            print("峰值内存: \(result.memoryPeakUsage)MB")
            
            // 保存图片
            // UIImageWriteToSavedPhotosAlbum(result.image, nil, nil, nil)
            
        } catch {
            print("拼接失败: \(error.localizedDescription)")
        }
    }
}
