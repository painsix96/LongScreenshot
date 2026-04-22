import UIKit
import Accelerate
import Vision
import CoreImage

// MARK: - 算法错误类型
enum ImageStitchingError: Error, LocalizedError {
    case insufficientImages
    case invalidImageData
    case overlapDetectionFailed
    case stitchingFailed
    case processingTimeout
    case qualityTooLow
    
    var errorDescription: String? {
        switch self {
        case .insufficientImages:
            return "至少需要两张图片进行拼接"
        case .invalidImageData:
            return "图片数据无效或损坏"
        case .overlapDetectionFailed:
            return "无法检测图片重叠区域"
        case .stitchingFailed:
            return "图片拼接失败"
        case .processingTimeout:
            return "处理超时，请尝试减少图片数量或降低分辨率"
        case .qualityTooLow:
            return "图片相似度过低，无法可靠拼接"
        }
    }
}

// MARK: - 拼接配置
struct StitchingConfiguration {
    // 相似度算法选择
    var similarityMethod: SimilarityMethod = .hybrid
    
    // 重叠检测配置
    var minSimilarityThreshold: Double = 0.70
    var maxProcessingTime: TimeInterval = 1.0 // 1秒超时
    var enableAutoDirection: Bool = true
    
    // 拼接质量
    var enableBlending: Bool = true
    var blendingRadius: Int = 10 // 混合过渡像素数
    var targetQuality: ImageQuality = .high
    
    // 性能优化
    var maxImageDimension: CGFloat = 1080
    var useParallelProcessing: Bool = true
    
    enum ImageQuality {
        case low // 快速处理
        case medium // 平衡
        case high // 最佳质量
        
        var scale: CGFloat {
            switch self {
            case .low: return 0.5
            case .medium: return 0.75
            case .high: return 1.0
            }
        }
    }
    
    // 预设配置
    static let `default` = StitchingConfiguration()
    
    static let fast = StitchingConfiguration(
        similarityMethod: .pixelDifference,
        minSimilarityThreshold: 0.65,
        maxProcessingTime: 0.5,
        enableAutoDirection: true,
        enableBlending: false,
        targetQuality: .medium,
        maxImageDimension: 720,
        useParallelProcessing: true
    )
    
    static let quality = StitchingConfiguration(
        similarityMethod: .hybrid,
        minSimilarityThreshold: 0.80,
        maxProcessingTime: 2.0,
        enableAutoDirection: true,
        enableBlending: true,
        blendingRadius: 20,
        targetQuality: .high,
        maxImageDimension: 1440,
        useParallelProcessing: true
    )
}

// MARK: - 拼接结果
struct ImageStitchingResult {
    let stitchedImage: UIImage
    let overlapResults: [OverlapResult]
    let totalProcessingTime: TimeInterval
    let averageSimilarity: Double
    let originalDimensions: CGSize
    let finalDimensions: CGSize
    let quality: StitchingQuality
    
    enum StitchingQuality: String {
        case excellent = "优秀"
        case good = "良好"
        case acceptable = "可接受"
        case poor = "较差"
        
        init(averageSimilarity: Double) {
            switch averageSimilarity {
            case 0.95...1.0: self = .excellent
            case 0.85..<0.95: self = .good
            case 0.70..<0.85: self = .acceptable
            default: self = .poor
            }
        }
    }
    
    var compressionRatio: Double {
        let originalHeight = originalDimensions.height
        let finalHeight = finalDimensions.height
        guard originalHeight > 0 else { return 1.0 }
        return Double(finalHeight) / Double(originalHeight)
    }
}

// MARK: - 图像拼接算法主类
actor ImageStitchingAlgorithm {
    
    // MARK: - 属性
    private let similarityCalculator = ImageSimilarity()
    private let overlapDetector = OverlapDetector()
    private var configuration: StitchingConfiguration
    
    // MARK: - 初始化
    init(configuration: StitchingConfiguration = .default) {
        self.configuration = configuration
    }
    
    // MARK: - 配置更新
    func updateConfiguration(_ config: StitchingConfiguration) {
        self.configuration = config
    }
    
    // MARK: - 主入口：拼接多张图片
    func stitchImages(_ images: [UIImage]) async throws -> ImageStitchingResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // 验证输入
        guard images.count >= 2 else {
            throw ImageStitchingError.insufficientImages
        }
        
        // 验证图片数据
        for (index, image) in images.enumerated() {
            guard image.cgImage != nil else {
                throw ImageStitchingError.invalidImageData
            }
        }
        
        // 预处理图片
        let preprocessedImages = try await preprocessImages(images)
        
        // 检测滚动方向
        let scrollDirection: ScrollDirection = configuration.enableAutoDirection
            ? await detectScrollDirection(preprocessedImages)
            : .vertical
        
        // 检测所有重叠区域
        let overlapResults = try await detectAllOverlaps(
            images: preprocessedImages,
            scrollDirection: scrollDirection
        )
        
        // 验证相似度
        let avgSimilarity = calculateAverageSimilarity(overlapResults)
        guard avgSimilarity >= configuration.minSimilarityThreshold else {
            throw ImageStitchingError.qualityTooLow
        }
        
        // 执行拼接
        let stitchedImage = try await performStitching(
            images: preprocessedImages,
            overlapResults: overlapResults,
            scrollDirection: scrollDirection
        )
        
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        
        // 计算尺寸信息
        let originalHeight = preprocessedImages.reduce(0) { $0 + $1.size.height }
        let totalOverlap = overlapResults.reduce(0) { $0 + ($1.hasOverlap ? $1.bestStitchPosition.overlapHeight : 0) }
        
        return ImageStitchingResult(
            stitchedImage: stitchedImage,
            overlapResults: overlapResults,
            totalProcessingTime: processingTime,
            averageSimilarity: avgSimilarity,
            originalDimensions: CGSize(
                width: preprocessedImages.first?.size.width ?? 0,
                height: originalHeight
            ),
            finalDimensions: stitchedImage.size,
            quality: ImageStitchingResult.StitchingQuality(averageSimilarity: avgSimilarity)
        )
    }
    
    // MARK: - 快速相似度计算（用于快速预览）
    func quickSimilarityCheck(
        image1: UIImage,
        image2: UIImage
    ) async -> SimilarityResult {
        // 使用像素差异算法进行快速比较
        return await similarityCalculator.calculateSimilarity(
            between: image1,
            and: image2,
            method: .pixelDifference
        )
    }
    
    // MARK: - 详细相似度分析
    func detailedSimilarityAnalysis(
        image1: UIImage,
        image2: UIImage
    ) async -> [SimilarityResult] {
        async let pHashResult = similarityCalculator.calculateSimilarity(
            between: image1,
            and: image2,
            method: .perceptualHash
        )
        async let pixelResult = similarityCalculator.calculateSimilarity(
            between: image1,
            and: image2,
            method: .pixelDifference
        )
        async let featureResult = similarityCalculator.calculateSimilarity(
            between: image1,
            and: image2,
            method: .featureMatching
        )
        async let hybridResult = similarityCalculator.calculateSimilarity(
            between: image1,
            and: image2,
            method: .hybrid
        )
        
        return await [pHashResult, pixelResult, featureResult, hybridResult]
    }
    
    // MARK: - 检测两张图片的重叠
    func detectOverlap(
        image1: UIImage,
        image2: UIImage,
        scrollDirection: ScrollDirection = .vertical
    ) async -> OverlapResult {
        return await overlapDetector.detectOverlap(
            between: image1,
            and: image2,
            scrollDirection: scrollDirection
        )
    }
}

// MARK: - 私有方法
private extension ImageStitchingAlgorithm {
    
    /// 预处理图片
    func preprocessImages(_ images: [UIImage]) async throws -> [UIImage] {
        let maxDim = configuration.maxImageDimension
        let scale = configuration.targetQuality.scale
        
        return images.compactMap { image in
            let size = image.size
            let shouldScale = size.width > maxDim || size.height > maxDim
            
            if shouldScale {
                let scaleFactor = min(maxDim / size.width, maxDim / size.height) * scale
                let newSize = CGSize(
                    width: size.width * scaleFactor,
                    height: size.height * scaleFactor
                )
                return resizeImage(image, to: newSize)
            }
            
            return image
        }
    }
    
    /// 调整图片尺寸
    func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
    
    /// 检测滚动方向
    func detectScrollDirection(_ images: [UIImage]) async -> ScrollDirection {
        guard images.count >= 2,
              let first = images.first?.cgImage,
              let last = images.last?.cgImage else {
            return .vertical
        }
        
        let aspectRatio1 = Double(first.width) / Double(first.height)
        let aspectRatio2 = Double(last.width) / Double(last.height)
        
        // 如果宽高比明显大于 1，可能是水平滚动
        if aspectRatio1 > 1.5 || aspectRatio2 > 1.5 {
            return .horizontal
        }
        
        return .vertical
    }
    
    /// 检测所有重叠区域
    func detectAllOverlaps(
        images: [UIImage],
        scrollDirection: ScrollDirection
    ) async throws -> [OverlapResult] {
        var results: [OverlapResult] = []
        
        // 设置超时
        let startTime = CFAbsoluteTimeGetCurrent()
        
        if configuration.useParallelProcessing {
            // 并行检测
            let batchResults = await overlapDetector.detectOverlapsBatch(
                images: images,
                scrollDirection: scrollDirection
            )
            results = batchResults.map { $0.result }
        } else {
            // 串行检测
            for i in 0..<(images.count - 1) {
                // 检查超时
                if CFAbsoluteTimeGetCurrent() - startTime > configuration.maxProcessingTime {
                    throw ImageStitchingError.processingTimeout
                }
                
                let result = await overlapDetector.detectOverlap(
                    between: images[i],
                    and: images[i + 1],
                    scrollDirection: scrollDirection
                )
                results.append(result)
            }
        }
        
        // 检查是否所有重叠检测都失败
        let successfulDetections = results.filter { $0.hasOverlap }.count
        guard successfulDetections > 0 else {
            throw ImageStitchingError.overlapDetectionFailed
        }
        
        return results
    }
    
    /// 计算平均相似度
    func calculateAverageSimilarity(_ results: [OverlapResult]) -> Double {
        let scores = results.filter { $0.hasOverlap }.map { $0.similarityScore }
        guard !scores.isEmpty else { return 0 }
        return scores.reduce(0, +) / Double(scores.count)
    }
    
    /// 执行拼接
    func performStitching(
        images: [UIImage],
        overlapResults: [OverlapResult],
        scrollDirection: ScrollDirection
    ) async throws -> UIImage {
        switch scrollDirection {
        case .vertical:
            return try await stitchVertically(images: images, overlapResults: overlapResults)
        case .horizontal:
            return try await stitchHorizontally(images: images, overlapResults: overlapResults)
        case .unknown:
            return try await stitchVertically(images: images, overlapResults: overlapResults)
        }
    }
    
    /// 垂直拼接
    func stitchVertically(images: [UIImage], overlapResults: [OverlapResult]) async throws -> UIImage {
        guard let first = images.first else {
            throw ImageStitchingError.stitchingFailed
        }
        
        let width = first.size.width
        var totalHeight: CGFloat = 0
        var imagePositions: [(image: UIImage, yOffset: CGFloat, overlap: CGFloat)] = []
        
        var currentY: CGFloat = 0
        for (index, image) in images.enumerated() {
            var overlapHeight: CGFloat = 0
            
            if index > 0 && index - 1 < overlapResults.count {
                let overlapResult = overlapResults[index - 1]
                if overlapResult.hasOverlap {
                    overlapHeight = overlapResult.bestStitchPosition.overlapHeight
                }
            }
            
            imagePositions.append((image, currentY, overlapHeight))
            currentY += image.size.height - overlapHeight
        }
        
        totalHeight = currentY
        
        // 创建最终图片
        let format = UIGraphicsImageRendererFormat()
        format.scale = first.scale
        format.opaque = true
        
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: totalHeight),
            format: format
        )
        
        let stitchedImage = renderer.image { context in
            // 填充白色背景
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: totalHeight))
            
            // 绘制每张图片
            for (index, position) in imagePositions.enumerated() {
                if index == 0 {
                    // 第一张图片直接绘制
                    position.image.draw(at: CGPoint(x: 0, y: position.yOffset))
                } else {
                    // 后续图片处理重叠区域
                    if configuration.enableBlending && position.overlap > 0 {
                        drawWithBlending(
                            image: position.image,
                            at: position.yOffset,
                            overlap: position.overlap,
                            in: context.cgContext,
                            width: width
                        )
                    } else {
                        // 简单裁剪重叠区域后绘制
                        drawWithoutOverlap(
                            image: position.image,
                            at: position.yOffset,
                            overlap: position.overlap
                        )
                    }
                }
            }
        }
        
        return stitchedImage
    }
    
    /// 水平拼接
    func stitchHorizontally(images: [UIImage], overlapResults: [OverlapResult]) async throws -> UIImage {
        guard let first = images.first else {
            throw ImageStitchingError.stitchingFailed
        }
        
        let height = first.size.height
        var totalWidth: CGFloat = 0
        var imagePositions: [(image: UIImage, xOffset: CGFloat, overlap: CGFloat)] = []
        
        var currentX: CGFloat = 0
        for (index, image) in images.enumerated() {
            var overlapWidth: CGFloat = 0
            
            if index > 0 && index - 1 < overlapResults.count {
                let overlapResult = overlapResults[index - 1]
                if overlapResult.hasOverlap {
                    overlapWidth = overlapResult.bestStitchPosition.overlapHeight
                }
            }
            
            imagePositions.append((image, currentX, overlapWidth))
            currentX += image.size.width - overlapWidth
        }
        
        totalWidth = currentX
        
        // 创建最终图片
        let format = UIGraphicsImageRendererFormat()
        format.scale = first.scale
        format.opaque = true
        
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: totalWidth, height: height),
            format: format
        )
        
        let stitchedImage = renderer.image { context in
            // 填充白色背景
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: totalWidth, height: height))
            
            // 绘制每张图片
            for (index, position) in imagePositions.enumerated() {
                if index == 0 {
                    position.image.draw(at: CGPoint(x: position.xOffset, y: 0))
                } else {
                    if configuration.enableBlending && position.overlap > 0 {
                        drawWithBlendingHorizontal(
                            image: position.image,
                            at: position.xOffset,
                            overlap: position.overlap,
                            in: context.cgContext,
                            height: height
                        )
                    } else {
                        drawWithoutOverlapHorizontal(
                            image: position.image,
                            at: position.xOffset,
                            overlap: position.overlap
                        )
                    }
                }
            }
        }
        
        return stitchedImage
    }
    
    /// 带混合的垂直绘制
    func drawWithBlending(
        image: UIImage,
        at yOffset: CGFloat,
        overlap: CGFloat,
        in context: CGContext,
        width: CGFloat
    ) {
        // 实现渐变混合
        let blendHeight = min(CGFloat(configuration.blendingRadius), overlap)
        
        // 绘制非重叠部分
        let nonOverlapRect = CGRect(
            x: 0,
            y: 0,
            width: width,
            height: image.size.height - overlap
        )
        
        if let nonOverlapImage = image.cgImage?.cropping(to: nonOverlapRect) {
            let uiNonOverlap = UIImage(cgImage: nonOverlapImage, scale: image.scale, orientation: image.imageOrientation)
            uiNonOverlap.draw(at: CGPoint(x: 0, y: yOffset))
        }
        
        // 绘制混合过渡区域
        let blendRect = CGRect(
            x: 0,
            y: image.size.height - overlap,
            width: width,
            height: blendHeight
        )
        
        if let blendImage = image.cgImage?.cropping(to: blendRect) {
            let uiBlend = UIImage(cgImage: blendImage, scale: image.scale, orientation: image.imageOrientation)
            uiBlend.draw(
                in: CGRect(
                    x: 0,
                    y: yOffset + image.size.height - overlap,
                    width: width,
                    height: blendHeight
                ),
                blendMode: .normal,
                alpha: 0.5
            )
        }
    }
    
    /// 简单裁剪重叠区域（垂直）
    func drawWithoutOverlap(image: UIImage, at yOffset: CGFloat, overlap: CGFloat) {
        let drawRect = CGRect(
            x: 0,
            y: 0,
            width: image.size.width,
            height: max(0, image.size.height - overlap)
        )
        
        if let cropped = image.cgImage?.cropping(to: drawRect) {
            let uiCropped = UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
            uiCropped.draw(at: CGPoint(x: 0, y: yOffset))
        }
    }
    
    /// 带混合的水平绘制
    func drawWithBlendingHorizontal(
        image: UIImage,
        at xOffset: CGFloat,
        overlap: CGFloat,
        in context: CGContext,
        height: CGFloat
    ) {
        let blendWidth = min(CGFloat(configuration.blendingRadius), overlap)
        
        // 绘制非重叠部分
        let nonOverlapRect = CGRect(
            x: 0,
            y: 0,
            width: image.size.width - overlap,
            height: height
        )
        
        if let nonOverlapImage = image.cgImage?.cropping(to: nonOverlapRect) {
            let uiNonOverlap = UIImage(cgImage: nonOverlapImage, scale: image.scale, orientation: image.imageOrientation)
            uiNonOverlap.draw(at: CGPoint(x: xOffset, y: 0))
        }
        
        // 绘制混合过渡区域
        let blendRect = CGRect(
            x: image.size.width - overlap,
            y: 0,
            width: blendWidth,
            height: height
        )
        
        if let blendImage = image.cgImage?.cropping(to: blendRect) {
            let uiBlend = UIImage(cgImage: blendImage, scale: image.scale, orientation: image.imageOrientation)
            uiBlend.draw(
                in: CGRect(
                    x: xOffset + image.size.width - overlap,
                    y: 0,
                    width: blendWidth,
                    height: height
                ),
                blendMode: .normal,
                alpha: 0.5
            )
        }
    }
    
    /// 简单裁剪重叠区域（水平）
    func drawWithoutOverlapHorizontal(image: UIImage, at xOffset: CGFloat, overlap: CGFloat) {
        let drawRect = CGRect(
            x: 0,
            y: 0,
            width: max(0, image.size.width - overlap),
            height: image.size.height
        )
        
        if let cropped = image.cgImage?.cropping(to: drawRect) {
            let uiCropped = UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
            uiCropped.draw(at: CGPoint(x: xOffset, y: 0))
        }
    }
}

// MARK: - 便捷方法扩展
extension ImageStitchingAlgorithm {
    
    /// 快速拼接（使用默认配置）
    static func quickStitch(images: [UIImage]) async throws -> UIImage {
        let algorithm = ImageStitchingAlgorithm(configuration: .fast)
        let result = try await algorithm.stitchImages(images)
        return result.stitchedImage
    }
    
    /// 高质量拼接
    static func qualityStitch(images: [UIImage]) async throws -> UIImage {
        let algorithm = ImageStitchingAlgorithm(configuration: .quality)
        let result = try await algorithm.stitchImages(images)
        return result.stitchedImage
    }
    
    /// 验证图片是否可以拼接
    static func validateImagesForStitching(
        images: [UIImage],
        minSimilarity: Double = 0.70
    ) async -> (isValid: Bool, results: [SimilarityResult]) {
        guard images.count >= 2 else {
            return (false, [])
        }
        
        let algorithm = ImageStitchingAlgorithm(configuration: .fast)
        var results: [SimilarityResult] = []
        
        for i in 0..<(images.count - 1) {
            let result = await algorithm.quickSimilarityCheck(
                image1: images[i],
                image2: images[i + 1]
            )
            results.append(result)
        }
        
        let isValid = results.allSatisfy { $0.score >= minSimilarity }
        return (isValid, results)
    }
}
