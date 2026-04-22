import UIKit
import Accelerate
import os.log

/// 图片处理配置
struct ImageProcessorConfig {
    /// 最大内存使用量 (MB)
    var maxMemoryMB: Int = 512
    /// 分块大小 (像素)
    var chunkHeight: Int = 1024
    /// 4K 图片阈值
    var highResolutionThreshold: CGFloat = 3840
    /// 是否使用 Metal 加速
    var useMetalAcceleration: Bool = true
    /// JPEG 压缩质量
    var compressionQuality: CGFloat = 0.95
    /// 最大并发处理数
    var maxConcurrentOperations: Int = 3
}

/// 图片分块
struct ImageChunk {
    let id: UUID
    let rect: CGRect
    let imageData: Data
    let isLast: Bool
}

/// 内存管理器
final class MemoryManager {
    static let shared = MemoryManager()
    
    private var currentMemoryUsage: Int = 0
    private let lock = NSLock()
    private var warnings: [String] = []
    
    /// 最大允许内存 (MB)
    var maxMemoryMB: Int = 512
    
    private init() {}
    
    /// 申请内存
    func allocate(bytes: Int, identifier: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        let currentMB = currentMemoryUsage / 1024 / 1024
        let requestedMB = bytes / 1024 / 1024
        let maxBytes = maxMemoryMB * 1024 * 1024
        
        if currentMemoryUsage + bytes > maxBytes {
            warnings.append("内存申请被拒绝: \(identifier) 请求 \(requestedMB)MB, 当前 \(currentMB)MB")
            return false
        }
        
        currentMemoryUsage += bytes
        return true
    }
    
    /// 释放内存
    func deallocate(bytes: Int) {
        lock.lock()
        defer { lock.unlock() }
        currentMemoryUsage = max(0, currentMemoryUsage - bytes)
    }
    
    /// 获取当前内存使用量 (MB)
    func currentUsageMB() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return currentMemoryUsage / 1024 / 1024
    }
    
    /// 检查是否有足够内存
    func hasAvailableMemory(requestedMB: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let maxBytes = maxMemoryMB * 1024 * 1024
        return currentMemoryUsage + (requestedMB * 1024 * 1024) <= maxBytes
    }
    
    /// 获取警告信息
    func getWarnings() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return warnings
    }
    
    /// 清除警告
    func clearWarnings() {
        lock.lock()
        defer { lock.unlock() }
        warnings.removeAll()
    }
    
    /// 重置内存使用量（拼接完成后调用）
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        currentMemoryUsage = 0
        warnings.removeAll()
    }
}

/// 图片处理器
actor ImageProcessor {
    private let config: ImageProcessorConfig
    private let memoryManager: MemoryManager
    private var processingQueue: [UUID: Task<Void, Error>] = [:]
    private let processorLogger = Logger(subsystem: "com.longscreenshot", category: "ImageProcessor")
    
    init(config: ImageProcessorConfig = ImageProcessorConfig()) {
        self.config = config
        self.memoryManager = MemoryManager.shared
    }
    
    // MARK: - 分块处理
    
    /// 将图片分块处理
    func processImageInChunks(
        image: UIImage,
        progress: StitchingProgress,
        processor: @escaping (CGImage, CGRect) async throws -> CGImage?
    ) async throws -> [ImageChunk] {
        guard let cgImage = image.cgImage else {
            throw StitchError.invalidImageData
        }
        
        let imageWidth = cgImage.width
        let imageHeight = cgImage.height
        let bytesPerPixel = 4
        let estimatedMemoryPerChunk = imageWidth * config.chunkHeight * bytesPerPixel
        
        var chunks: [ImageChunk] = []
        var currentY = 0
        var chunkIndex = 0
        let totalChunks = Int(ceil(Double(imageHeight) / Double(config.chunkHeight)))
        
        while currentY < imageHeight {
            try await progress.checkCancellation()
            
            // 等待内存可用
            while !memoryManager.hasAvailableMemory(requestedMB: estimatedMemoryPerChunk / 1024 / 1024) {
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                try await progress.checkCancellation()
            }
            
            let chunkHeight = min(config.chunkHeight, imageHeight - currentY)
            let chunkRect = CGRect(
                x: 0,
                y: currentY,
                width: imageWidth,
                height: chunkHeight
            )
            
            // 裁剪分块
            guard let chunkCGImage = cgImage.cropping(to: chunkRect) else {
                throw StitchError.processingFailed
            }
            
            // 处理分块
            if let processedImage = try await processor(chunkCGImage, chunkRect) {
                let imageData = try convertToData(processedImage)
                let chunk = ImageChunk(
                    id: UUID(),
                    rect: chunkRect,
                    imageData: imageData,
                    isLast: currentY + chunkHeight >= imageHeight
                )
                chunks.append(chunk)
                
                // 申请内存记录
                _ = memoryManager.allocate(bytes: imageData.count, identifier: "chunk_\(chunkIndex)")
            }
            
            currentY += chunkHeight
            chunkIndex += 1
            
            // 更新进度
            await progress.updatePhaseProgress(.processing, progress: Double(chunkIndex) / Double(totalChunks))
        }
        
        return chunks
    }
    
    // MARK: - 图片压缩与优化
    
    /// 压缩图片以减少内存占用
    func compressImage(_ image: UIImage, maxDimension: CGFloat? = nil) async throws -> UIImage {
        let targetSize: CGSize
        
        if let maxDim = maxDimension {
            let scale = min(1.0, maxDim / max(image.size.width, image.size.height))
            targetSize = CGSize(
                width: image.size.width * scale,
                height: image.size.height * scale
            )
        } else {
            targetSize = image.size
        }
        
        return try await Task.detached(priority: .utility) {
            let format = UIGraphicsImageRendererFormat()
            format.scale = image.scale
            
            let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
            
            let compressedImage = renderer.image { context in
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }
            
            return compressedImage
        }.value
    }
    
    /// 检查是否需要分块处理
    func shouldUseChunking(for image: UIImage) -> Bool {
        let maxDimension = max(image.size.width, image.size.height)
        let isHighResolution = maxDimension >= config.highResolutionThreshold
        let estimatedMemory = Int(image.size.width * image.size.height * 4) // RGBA
        let exceedsMemory = estimatedMemory > config.maxMemoryMB * 1024 * 1024 / 2
        
        return isHighResolution || exceedsMemory
    }
    
    // MARK: - 图像融合
    
    /// 渐变融合两张图片
    func blendImages(
        topImage: UIImage,
        bottomImage: UIImage,
        overlapHeight: Int,
        progress: StitchingProgress
    ) async throws -> UIImage {
        try await progress.checkCancellation()

        processorLogger.info("🎨 开始渐变融合: 重叠高度=\(overlapHeight)px")
        processorLogger.info("🎨 顶部图片: \(topImage.size.width)×\(topImage.size.height), scale=\(topImage.scale)")
        processorLogger.info("🎨 底部图片: \(bottomImage.size.width)×\(bottomImage.size.height), scale=\(bottomImage.scale)")

        return try await Task.detached(priority: .userInitiated) { [self] in
            // 统一使用最大宽度，确保对齐
            let maxWidth = max(topImage.size.width, bottomImage.size.width)
            let topHeight = topImage.size.height
            let bottomHeight = bottomImage.size.height
            let totalHeight = topHeight + bottomHeight - CGFloat(overlapHeight)

            let format = UIGraphicsImageRendererFormat()
            format.scale = topImage.scale

            let size = CGSize(width: maxWidth, height: totalHeight)
            let renderer = UIGraphicsImageRenderer(size: size, format: format)

            self.processorLogger.info("🎨 画布尺寸: \(maxWidth)×\(totalHeight)")

            let blendedImage = renderer.image { context in
                // 计算居中对齐的X偏移
                let topXOffset = (maxWidth - topImage.size.width) / 2
                let bottomXOffset = (maxWidth - bottomImage.size.width) / 2

                // 绘制上半部分（不含重叠区）
                let topNonOverlapHeight = topHeight - CGFloat(overlapHeight)
                if topNonOverlapHeight > 0 {
                    self.processorLogger.debug("🎨 绘制顶部非重叠区: y=0, height=\(topNonOverlapHeight)")
                    // 绘制顶部图片的非重叠区域
                    let topRect = CGRect(x: topXOffset, y: 0, width: topImage.size.width, height: topNonOverlapHeight)
                    topImage.draw(in: topRect)
                }

                // 渐变融合重叠区
                if overlapHeight > 0 {
                    self.processorLogger.debug("🎨 绘制渐变融合区: y=\(topNonOverlapHeight), height=\(overlapHeight)")
                    self.drawBlendedOverlap(
                        context: context,
                        topImage: topImage,
                        bottomImage: bottomImage,
                        overlapHeight: overlapHeight,
                        yOffset: Int(topNonOverlapHeight),
                        width: Int(maxWidth),
                        topXOffset: topXOffset,
                        bottomXOffset: bottomXOffset
                    )
                }

                // 绘制下半部分（不含重叠区）
                let bottomNonOverlapHeight = bottomHeight - CGFloat(overlapHeight)
                if bottomNonOverlapHeight > 0 {
                    self.processorLogger.debug("🎨 绘制底部非重叠区: y=\(topHeight), height=\(bottomNonOverlapHeight)")
                    let bottomY = topHeight
                    let bottomRect = CGRect(x: bottomXOffset, y: bottomY, width: bottomImage.size.width, height: bottomNonOverlapHeight)
                    bottomImage.draw(in: bottomRect)
                }
            }

            self.processorLogger.info("🎨 渐变融合完成: 输出尺寸=\(blendedImage.size.width)×\(blendedImage.size.height)")
            return blendedImage
        }.value
    }
    
    /// 绘制渐变融合区域
    private func drawBlendedOverlap(
        context: UIGraphicsImageRendererContext,
        topImage: UIImage,
        bottomImage: UIImage,
        overlapHeight: Int,
        yOffset: Int,
        width: Int,
        topXOffset: CGFloat,
        bottomXOffset: CGFloat
    ) {
        guard overlapHeight > 0 else { return }
        
        let cgContext = context.cgContext
        let overlapRect = CGRect(x: 0, y: CGFloat(yOffset), width: CGFloat(width), height: CGFloat(overlapHeight))
        
        guard let gradientImage = createGradientMask(width: width, height: overlapHeight) else { return }
        
        cgContext.saveGState()
        
        // 步骤1：绘制底部图片（第二张图）的顶部重叠区域
        // CGImage 坐标系原点在左下角，y 向上增长
        // 底部图片的"顶部"在 CGImage 中对应 y = (totalPixelHeight - overlapPixelHeight)
        let bottomPixelHeight = bottomImage.cgImage?.height ?? Int(bottomImage.size.height * bottomImage.scale)
        let bottomOverlapPixelHeight = Int(CGFloat(overlapHeight) * bottomImage.scale)
        if let bottomCGImage = bottomImage.cgImage?.cropping(to: CGRect(
            x: 0,
            y: bottomPixelHeight - bottomOverlapPixelHeight,
            width: Int(bottomImage.size.width * bottomImage.scale),
            height: bottomOverlapPixelHeight
        )) {
            cgContext.saveGState()
            cgContext.translateBy(x: 0, y: CGFloat(yOffset + overlapHeight))
            cgContext.scaleBy(x: 1, y: -1)
            cgContext.draw(bottomCGImage, in: CGRect(
                x: bottomXOffset,
                y: 0,
                width: bottomImage.size.width,
                height: CGFloat(overlapHeight)
            ))
            cgContext.restoreGState()
        }
        
        // 步骤2：使用渐变遮罩绘制顶部图片（第一张图）的底部重叠区域
        // 顶部图片的"底部"在 CGImage 中对应 y = 0 到 overlapPixelHeight
        cgContext.saveGState()
        cgContext.clip(to: overlapRect, mask: gradientImage)
        
        let topOverlapPixelHeight = Int(CGFloat(overlapHeight) * topImage.scale)
        if let topCGImage = topImage.cgImage?.cropping(to: CGRect(
            x: 0,
            y: 0,
            width: Int(topImage.size.width * topImage.scale),
            height: topOverlapPixelHeight
        )) {
            cgContext.translateBy(x: 0, y: CGFloat(yOffset + overlapHeight))
            cgContext.scaleBy(x: 1, y: -1)
            cgContext.draw(topCGImage, in: CGRect(
                x: topXOffset,
                y: 0,
                width: topImage.size.width,
                height: CGFloat(overlapHeight)
            ))
        }
        cgContext.restoreGState()
        
        cgContext.restoreGState()
    }
    
    /// 创建渐变遮罩
    /// 渐变方向：从上到下
    /// - 顶部（y=0）：黑色（0）-> 显示底部图片
    /// - 底部（y=height）：白色（1）-> 显示顶部图片
    /// 这样在遮罩作用下，融合区从上到下逐渐从图2过渡到图1
    private func createGradientMask(width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGImageAlphaInfo.none.rawValue
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        
        // 渐变颜色：从黑到白
        // 黑色部分显示底部图片，白色部分显示顶部图片
        let colors: [CGColor] = [
            UIColor.black.cgColor,  // 顶部：显示底部图片
            UIColor.white.cgColor   // 底部：显示顶部图片
        ]
        let locations: [CGFloat] = [0.0, 1.0]
        
        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: colors as CFArray,
            locations: locations
        ) else { return nil }
        
        // CGContext坐标系：原点在左下角，但这里我们使用从上到下的渐变
        let startPoint = CGPoint(x: 0, y: 0)
        let endPoint = CGPoint(x: 0, y: height)
        
        context.drawLinearGradient(
            gradient,
            start: startPoint,
            end: endPoint,
            options: []
        )
        
        return context.makeImage()
    }
    
    // MARK: - 辅助方法
    
    private func convertToData(_ cgImage: CGImage) throws -> Data {
        guard let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: config.compressionQuality) else {
            throw StitchError.processingFailed
        }
        return data
    }
}


