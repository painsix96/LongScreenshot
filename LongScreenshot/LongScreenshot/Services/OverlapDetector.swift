import UIKit
import Accelerate
import Vision
import CoreImage
import os.log

// MARK: - 日志
private let overlapLogger = Logger(subsystem: "com.longscreenshot", category: "OverlapDetector")

// MARK: - 重叠检测结果
struct OverlapResult {
    let hasOverlap: Bool // 是否存在重叠
    let overlapRect1: CGRect // 在 image1 中的重叠区域
    let overlapRect2: CGRect // 在 image2 中的重叠区域
    let similarityScore: Double // 相似度分数 (0.0 - 1.0)
    let bestStitchPosition: StitchPosition // 最佳拼接位置
    let confidence: Double // 检测置信度
    let processingTime: TimeInterval
    let topCrop1: CGFloat // image1 的顶部裁剪高度
    let bottomCrop1: CGFloat // image1 的底部裁剪高度
    let topCrop2: CGFloat // image2 的顶部裁剪高度
    let bottomCrop2: CGFloat // image2 的底部裁剪高度
    
    struct StitchPosition {
        let yOffset: CGFloat // 在目标图片中的垂直偏移（垂直滚动时）
        let xOffset: CGFloat // 在目标图片中的水平偏移（水平滚动时）
        let overlapHeight: CGFloat // 重叠区域高度（垂直滚动时）
        let overlapWidth: CGFloat // 重叠区域宽度（水平滚动时）
        let quality: StitchQuality // 拼接质量评估
        
        init(yOffset: CGFloat = 0, xOffset: CGFloat = 0, overlapHeight: CGFloat = 0, overlapWidth: CGFloat = 0, quality: StitchQuality) {
            self.yOffset = yOffset
            self.xOffset = xOffset
            self.overlapHeight = overlapHeight
            self.overlapWidth = overlapWidth
            self.quality = quality
        }
    }
    
    enum StitchQuality: String {
        case excellent = "优秀" // 相似度 > 0.95
        case good = "良好" // 相似度 0.85-0.95
        case acceptable = "可接受" // 相似度 0.70-0.85
        case poor = "较差" // 相似度 < 0.70
        
        init(score: Double) {
            switch score {
            case 0.95...1.0: self = .excellent
            case 0.85..<0.95: self = .good
            case 0.70..<0.85: self = .acceptable
            default: self = .poor
            }
        }
    }
    
    // 空结果（无重叠）
    static let noOverlap = OverlapResult(
        hasOverlap: false,
        overlapRect1: .zero,
        overlapRect2: .zero,
        similarityScore: 0,
        bestStitchPosition: StitchPosition(quality: .poor),
        confidence: 0,
        processingTime: 0,
        topCrop1: 0,
        bottomCrop1: 0,
        topCrop2: 0,
        bottomCrop2: 0
    )
}

// MARK: - 滚动方向
enum ScrollDirection {
    case vertical // 垂直滚动（默认）
    case horizontal // 水平滚动
    case unknown // 未知方向
}

// MARK: - 重叠区域检测器
actor OverlapDetector {
    
    // MARK: - 配置参数
    struct Config {
        // 搜索范围
        var maxOverlapPercent: Double = 0.85 // 最大可能重叠比例（85%，应对长截图大重叠）
        var minOverlapPercent: Double = 0.05 // 最小重叠比例（5%）
        
        // 相似度阈值 - 提高阈值避免错误匹配
        var similarityThreshold: Double = 0.70 // 最低相似度要求（提高）
        var highSimilarityThreshold: Double = 0.82 // 高相似度阈值，用于提前退出
        var excellentSimilarityThreshold: Double = 0.95 // 优秀相似度阈值
        
        // 搜索步长 - 自适应步长
        // 注意：这些步长是在缩放后的图片上使用的
        // 缩放比例 analysisScale=0.25，所以实际步长 = coarseStep * 0.25
        // 为了搜索约 20-30 次，coarseStep 应该设置为 80（80*0.25=20）
        var coarseStep: Int = 80 // 粗粒度搜索步长（像素，在缩放后的图片上）
        var fineStep: Int = 4 // 细粒度搜索步长（像素，在缩放后的图片上）
        
        // 验证参数
        var verificationScale: CGFloat = 0.5 // 验证时缩放比例（50%，平衡速度和精度）
        var verificationThreshold: Double = 0.60 // 验证通过阈值（降低）
        
        // 裁剪固定区域
        var cropTopFixedArea: Bool = true // 是否裁剪顶部固定区域
        var cropBottomFixedArea: Bool = true // 是否裁剪底部固定区域
        var topFixedAreaHeight: CGFloat = 135 // 顶部固定区域默认高度（状态栏+导航栏）
        var bottomFixedAreaHeight: CGFloat = 55 // 底部固定区域默认高度（Home指示条）
        
        // 多尺度搜索
        var useMultiScaleSearch: Bool = true // 是否使用多尺度搜索
        var analysisScale: CGFloat = 0.25 // 分析时缩放比例（25%，提高速度）
        var fineSearchRange: CGFloat = 30 // 细粒度搜索范围（±30px）
        
        // 稳定性检查
        var enableStabilityCheck: Bool = true // 是否启用稳定性检查
        var stabilityThreshold: Double = 0.05 // 稳定性阈值（分数差距）
        
        // 哈希匹配权重
        var pixelMatchWeight: Double = 0.7 // 像素匹配权重（提高）
        var hashMatchWeight: Double = 0.3 // 哈希匹配权重（降低）
        
        // 新增：智能固定区域检测
        var useSmartFixedAreaDetection: Bool = true // 是否使用智能固定区域检测
        var fixedAreaSimilarityThreshold: Double = 0.90 // 固定区域相似度阈值（90%）
        var maxFixedAreaPercent: Double = 0.20 // 最大固定区域比例（20%）
        var sampleImageCount: Int = 3 // 采样图片数量
    }
    
    var config = Config()
    
    // MARK: - 主入口：检测重叠区域
    func detectOverlap(
        between image1: UIImage,
        and image2: UIImage,
        scrollDirection: ScrollDirection = .vertical
    ) async -> OverlapResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        let image1Size = image1.size
        let image2Size = image2.size
        
        overlapLogger.info("🔍 开始检测重叠: 图1(\(image1Size.width)×\(image1Size.height)) vs 图2(\(image2Size.width)×\(image2Size.height))")
        
        // 裁剪固定区域（状态栏和底部栏）后再进行重叠检测
        let (croppedImage1, topCrop1, bottomCrop1) = cropFixedAreas(from: image1)
        let (croppedImage2, topCrop2, bottomCrop2) = cropFixedAreas(from: image2)
        
        if topCrop1 > 0 || bottomCrop1 > 0 || topCrop2 > 0 || bottomCrop2 > 0 {
            overlapLogger.info("✂️ 裁剪固定区域: 图1(顶部:\(topCrop1)px, 底部:\(bottomCrop1)px) 图2(顶部:\(topCrop2)px, 底部:\(bottomCrop2)px)")
            overlapLogger.info("✂️ 裁剪后尺寸: 图1(\(croppedImage1.size.width)×\(croppedImage1.size.height)) 图2(\(croppedImage2.size.width)×\(croppedImage2.size.height))")
        }
        
        // 根据滚动方向处理
        let result: OverlapResult
        switch scrollDirection {
        case .vertical:
            result = await detectVerticalOverlap(croppedImage1, croppedImage2, startTime: startTime, originalImage1: image1, originalImage2: image2, topCrop1: topCrop1, bottomCrop1: bottomCrop1, topCrop2: topCrop2, bottomCrop2: bottomCrop2)
        case .horizontal:
            result = await detectHorizontalOverlap(croppedImage1, croppedImage2, startTime: startTime, originalImage1: image1, originalImage2: image2, topCrop1: topCrop1, bottomCrop1: bottomCrop1, topCrop2: topCrop2, bottomCrop2: bottomCrop2)
        case .unknown:
            // 尝试检测滚动方向
            let detectedDirection = await detectScrollDirection(croppedImage1, croppedImage2)
            overlapLogger.debug("📐 检测到滚动方向: \(detectedDirection == .horizontal ? "水平" : "垂直")")
            if detectedDirection == .horizontal {
                result = await detectHorizontalOverlap(croppedImage1, croppedImage2, startTime: startTime, originalImage1: image1, originalImage2: image2, topCrop1: topCrop1, bottomCrop1: bottomCrop1, topCrop2: topCrop2, bottomCrop2: bottomCrop2)
            } else {
                result = await detectVerticalOverlap(croppedImage1, croppedImage2, startTime: startTime, originalImage1: image1, originalImage2: image2, topCrop1: topCrop1, bottomCrop1: bottomCrop1, topCrop2: topCrop2, bottomCrop2: bottomCrop2)
            }
        }
        
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        if result.hasOverlap {
            overlapLogger.info("✅ 重叠检测完成: 高度=\(result.bestStitchPosition.overlapHeight)px, 相似度=\(String(format: "%.2f", result.similarityScore)), 质量=\(result.bestStitchPosition.quality.rawValue), 耗时=\(String(format: "%.3f", duration))s")
        } else {
            overlapLogger.warning("⚠️ 未找到有效重叠，耗时=\(String(format: "%.3f", duration))s")
        }
        
        return result
    }
    
    // MARK: - 批量检测重叠区域
    func detectOverlapsBatch(
        images: [UIImage],
        scrollDirection: ScrollDirection = .vertical
    ) async -> [(index: Int, result: OverlapResult)] {
        var results: [(index: Int, result: OverlapResult)] = []
        
        await withTaskGroup(of: (Int, OverlapResult).self) { group in
            for i in 0..<(images.count - 1) {
                group.addTask {
                    let result = await self.detectOverlap(
                        between: images[i],
                        and: images[i + 1],
                        scrollDirection: scrollDirection
                    )
                    return (i, result)
                }
            }
            
            for await (index, result) in group {
                results.append((index: index, result: result))
            }
        }
        
        // 按索引排序
        results.sort { $0.index < $1.index }
        
        return results
    }
    
    // MARK: - 裁剪固定区域
    /// 裁剪截图中的固定区域（状态栏和底部栏）
    /// 返回：(裁剪后的图片, 顶部裁剪高度, 底部裁剪高度)
    private func cropFixedAreas(from image: UIImage) -> (UIImage, CGFloat, CGFloat) {
        guard let cgImage = image.cgImage else {
            return (image, 0, 0)
        }
        
        // 使用 cgImage 的像素尺寸进行计算，避免 scale 混淆
        let pixelWidth = cgImage.width
        let pixelHeight = cgImage.height
        let scale = image.scale
        
        // 判断是否为 iPhone 截图（根据像素高度）
        let isIPhoneScreenshot = isLikelyIPhoneScreenshot(height: CGFloat(pixelHeight))
        
        var topCropPixels: CGFloat = 0
        var bottomCropPixels: CGFloat = 0
        
        if config.cropTopFixedArea && isIPhoneScreenshot {
            // 根据屏幕尺寸调整顶部裁剪高度（像素）
            topCropPixels = estimateTopFixedAreaHeight(pixelHeight: CGFloat(pixelHeight))
            topCropPixels = min(topCropPixels, CGFloat(pixelHeight) * 0.15) // 最多裁剪 15% 的高度
        }
        
        if config.cropBottomFixedArea && isIPhoneScreenshot {
            // 根据屏幕尺寸调整底部裁剪高度（像素）
            bottomCropPixels = estimateBottomFixedAreaHeight(pixelHeight: CGFloat(pixelHeight))
            bottomCropPixels = min(bottomCropPixels, CGFloat(pixelHeight) * 0.1) // 最多裁剪 10% 的高度
        }
        
        // 如果不需要裁剪，直接返回原图
        if topCropPixels <= 0 && bottomCropPixels <= 0 {
            return (image, 0, 0)
        }
        
        // 计算裁剪区域（像素坐标）
        let cropRect = CGRect(
            x: 0,
            y: topCropPixels,
            width: CGFloat(pixelWidth),
            height: CGFloat(pixelHeight) - topCropPixels - bottomCropPixels
        )
        
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
            overlapLogger.warning("✂️ 裁剪固定区域失败，使用原图")
            return (image, 0, 0)
        }
        
        let croppedImage = UIImage(cgImage: croppedCGImage, scale: scale, orientation: image.imageOrientation)
        // 返回逻辑坐标系的裁剪高度
        let topCrop = topCropPixels / scale
        let bottomCrop = bottomCropPixels / scale
        return (croppedImage, topCrop, bottomCrop)
    }
    
    // MARK: - 智能固定区域检测
    /// 检测多张图片中的固定区域（顶部和底部）
    /// 返回：(顶部裁剪高度, 底部裁剪高度)
    func detectSmartFixedAreas(from images: [UIImage]) async -> (CGFloat, CGFloat) {
        guard images.count >= 2 else {
            return (0, 0)
        }
        
        // 采样前几张图片进行检测
        let sampleCount = min(images.count, config.sampleImageCount)
        let sampleImages = Array(images.prefix(sampleCount))
        
        overlapLogger.info("🧠 智能检测固定区域，采样 \(sampleCount) 张图片")
        
        // 检测顶部固定区域
        let topFixedHeight = await detectTopFixedArea(from: sampleImages)
        
        // 检测底部固定区域
        let bottomFixedHeight = await detectBottomFixedArea(from: sampleImages)
        
        overlapLogger.info("🧠 智能检测结果: 顶部固定区域=\(topFixedHeight)px, 底部固定区域=\(bottomFixedHeight)px")
        
        return (topFixedHeight, bottomFixedHeight)
    }
    
    /// 检测顶部固定区域
    private func detectTopFixedArea(from images: [UIImage]) async -> CGFloat {
        guard images.count >= 2 else { return 0 }
        
        let maxCheckHeight = Int(images[0].size.height * config.maxFixedAreaPercent)
        var minFixedHeight: CGFloat = 0
        
        // 比较所有采样图片的顶部区域
        for i in 1..<images.count {
            let height = compareTopRegions(images[0], images[i], maxCheckHeight: maxCheckHeight)
            if i == 1 {
                minFixedHeight = height
            } else {
                minFixedHeight = min(minFixedHeight, height)
            }
        }
        
        return minFixedHeight
    }
    
    /// 检测底部固定区域
    private func detectBottomFixedArea(from images: [UIImage]) async -> CGFloat {
        guard images.count >= 2 else { return 0 }
        
        let maxCheckHeight = Int(images[0].size.height * config.maxFixedAreaPercent)
        var minFixedHeight: CGFloat = 0
        
        // 比较所有采样图片的底部区域
        for i in 1..<images.count {
            let height = compareBottomRegions(images[0], images[i], maxCheckHeight: maxCheckHeight)
            if i == 1 {
                minFixedHeight = height
            } else {
                minFixedHeight = min(minFixedHeight, height)
            }
        }
        
        return minFixedHeight
    }
    
    /// 比较两张图片的顶部区域，返回相同的高度
    private func compareTopRegions(_ image1: UIImage, _ image2: UIImage, maxCheckHeight: Int) -> CGFloat {
        guard let cgImage1 = image1.cgImage,
              let cgImage2 = image2.cgImage else {
            return 0
        }

        let width = min(cgImage1.width, cgImage2.width)
        let height1 = cgImage1.height
        let height2 = cgImage2.height
        let maxCheckPixels = min(maxCheckHeight, height1, height2)

        guard let data1 = getGrayscaleData(from: cgImage1),
              let data2 = getGrayscaleData(from: cgImage2) else {
            return 0
        }

        var sameHeight: CGFloat = 0
        let threshold = config.fixedAreaSimilarityThreshold

        // 逐行比较（从顶部开始）
        for y in 0..<maxCheckPixels {
            let row1 = data1[y * width..<min((y + 1) * width, data1.count)]
            let row2 = data2[y * width..<min((y + 1) * width, data2.count)]

            let similarity = calculateRowSimilarity(Array(row1), Array(row2))

            if similarity >= threshold {
                sameHeight = CGFloat(y + 1)
            } else {
                break
            }
        }

        return sameHeight / image1.scale
    }
    
    /// 比较两张图片的底部区域，返回相同的高度
    private func compareBottomRegions(_ image1: UIImage, _ image2: UIImage, maxCheckHeight: Int) -> CGFloat {
        guard let cgImage1 = image1.cgImage,
              let cgImage2 = image2.cgImage else {
            return 0
        }
        
        let width = min(cgImage1.width, cgImage2.width)
        let height1 = cgImage1.height
        let height2 = cgImage2.height
        let maxCheckPixels = min(maxCheckHeight, height1, height2)
        
        guard let data1 = getGrayscaleData(from: cgImage1),
              let data2 = getGrayscaleData(from: cgImage2) else {
            return 0
        }
        
        var sameHeight: CGFloat = 0
        let threshold = config.fixedAreaSimilarityThreshold
        
        // 从底部向上逐行比较
        // 使用各自图片的实际高度，确保比较的是每张图真正的底部区域
        for y in 0..<maxCheckPixels {
            let rowIndex1 = height1 - 1 - y
            let rowIndex2 = height2 - 1 - y
            
            let row1 = data1[rowIndex1 * width..<min((rowIndex1 + 1) * width, data1.count)]
            let row2 = data2[rowIndex2 * width..<min((rowIndex2 + 1) * width, data2.count)]
            
            let similarity = calculateRowSimilarity(Array(row1), Array(row2))
            
            if similarity >= threshold {
                sameHeight = CGFloat(y + 1)
            } else {
                break
            }
        }
        
        return sameHeight / image1.scale
    }
    
    /// 计算两行的相似度
    private func calculateRowSimilarity(_ row1: [UInt8], _ row2: [UInt8]) -> Double {
        guard row1.count == row2.count, !row1.isEmpty else { return 0 }
        
        var totalDiff: Double = 0
        let count = row1.count
        
        for i in 0..<count {
            let diff = abs(Double(row1[i]) - Double(row2[i]))
            totalDiff += diff
        }
        
        let avgDiff = totalDiff / Double(count)
        let similarity = 1.0 - (avgDiff / 255.0)
        
        return similarity
    }
    
    /// 获取灰度数据
    private func getGrayscaleData(from cgImage: CGImage) -> [UInt8]? {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        var pixels = [UInt8](repeating: 0, count: width * height)
        
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return pixels
    }
    
    // MARK: - 垂直方向重叠检测
    private func detectVerticalOverlap(
        _ image1: UIImage,
        _ image2: UIImage,
        startTime: CFAbsoluteTime,
        originalImage1: UIImage? = nil,
        originalImage2: UIImage? = nil,
        topCrop1: CGFloat = 0,
        bottomCrop1: CGFloat = 0,
        topCrop2: CGFloat = 0,
        bottomCrop2: CGFloat = 0
    ) async -> OverlapResult {
        
        guard let cgImage1 = image1.cgImage,
              let cgImage2 = image2.cgImage else {
            overlapLogger.error("❌ 无法获取 CGImage")
            return .noOverlap
        }
        
        let width1 = CGFloat(cgImage1.width)
        let width2 = CGFloat(cgImage2.width)
        let height1 = CGFloat(cgImage1.height)
        let height2 = CGFloat(cgImage2.height)
        
        // 如果有原始图片，记录裁剪前的原始尺寸
        // 注意：裁剪只是去掉了顶部和底部的固定区域，中间内容区域的比例没有变化
        // 所以重叠高度不需要乘以 heightRatio，直接按 1/scale 还原即可
        let originalHeight1 = originalImage1?.size.height ?? height1
        let originalHeight2 = originalImage2?.size.height ?? height2
        
        overlapLogger.debug("📐 原始尺寸: 图1(\(width1)×\(height1)) 图2(\(width2)×\(height2))")
        overlapLogger.debug("📐 裁剪前尺寸: 图1(\(originalImage1?.size.width ?? width1)×\(originalHeight1)) 图2(\(originalImage2?.size.width ?? width2)×\(originalHeight2))")
        
        // 检查图片尺寸是否合理
        guard width1 > 10, width2 > 10, height1 > 10, height2 > 10 else {
            overlapLogger.error("❌ 图片尺寸过小: 图1(\(width1)×\(height1)) 图2(\(width2)×\(height2))")
            return .noOverlap
        }
        
        // 统一图片宽度并缩放到分析尺寸（提高搜索速度）
        let analysisScale = config.analysisScale
        let (normalizedImage1, normalizedImage2, compareWidth, compareHeight1, compareHeight2) = normalizeImageSizes(image1, image2, analysisScale: analysisScale)
        
        guard let normCGImage1 = normalizedImage1.cgImage,
              let normCGImage2 = normalizedImage2.cgImage else {
            overlapLogger.error("❌ 无法获取归一化后的 CGImage")
            return .noOverlap
        }
        
        let scaledWidth = CGFloat(normCGImage1.width)
        let scaledHeight1 = CGFloat(normCGImage1.height)
        let scaledHeight2 = CGFloat(normCGImage2.height)
        let scale = scaledWidth / width1 // 缩放比例
        
        overlapLogger.debug("🔍 缩放分析尺寸: 图1(\(scaledWidth)×\(scaledHeight1)) 图2(\(scaledWidth)×\(scaledHeight2)) (scale=\(scale))")
        
        // 计算搜索范围（基于缩放后的尺寸）
        let minOverlap = scaledHeight1 * config.minOverlapPercent
        let maxOverlap = min(scaledHeight1 * config.maxOverlapPercent, scaledHeight2 * 0.95)
        
        overlapLogger.debug("🔍 搜索范围: min=\(String(format: "%.1f", minOverlap))px, max=\(String(format: "%.1f", maxOverlap))px")
        
        // 使用多尺度搜索策略
        let finalMatch: (overlap: CGFloat, score: Double, rect1: CGRect, rect2: CGRect)
        
        if config.useMultiScaleSearch {
            overlapLogger.debug("🔍 使用多尺度搜索策略")
            
            // 阶段1：粗粒度搜索（快速定位大致范围）
            let coarseStep = max(Int(CGFloat(self.config.coarseStep) * scale), 5)
            overlapLogger.debug("🔍 阶段1-粗粒度搜索: step=\(coarseStep)")
            
            let coarseResult = await findBestOverlap(
                image1: normCGImage1,
                image2: normCGImage2,
                searchRange: (min: CGFloat(minOverlap), max: CGFloat(maxOverlap)),
                step: coarseStep
            )
            
            overlapLogger.debug("🔍 粗粒度搜索结果: overlap=\(coarseResult.overlap)px, score=\(String(format: "%.3f", coarseResult.score))")
            
            // 阶段2：细粒度搜索（在粗粒度结果附近精确搜索）
            if coarseResult.score >= self.config.similarityThreshold {
                let fineRange = self.config.fineSearchRange * scale
                let fineMin = max(coarseResult.overlap - fineRange, CGFloat(minOverlap))
                let fineMax = min(coarseResult.overlap + fineRange, CGFloat(maxOverlap))
                let fineStep = max(Int(CGFloat(self.config.fineStep) * scale), 1)
                
                overlapLogger.debug("🔍 阶段2-细粒度搜索: range=[\(String(format: "%.1f", fineMin)), \(String(format: "%.1f", fineMax))], step=\(fineStep)")
                
                let fineResult = await findBestOverlap(
                    image1: normCGImage1,
                    image2: normCGImage2,
                    searchRange: (min: fineMin, max: fineMax),
                    step: fineStep
                )
                
                overlapLogger.debug("🔍 细粒度搜索结果: overlap=\(fineResult.overlap)px, score=\(String(format: "%.3f", fineResult.score))")
                
                // 选择更好的结果
                if fineResult.score > coarseResult.score {
                    finalMatch = fineResult
                } else {
                    finalMatch = coarseResult
                }
            } else {
                overlapLogger.debug("🔍 粗粒度相似度低于阈值(\(self.config.similarityThreshold))，跳过细粒度搜索")
                finalMatch = coarseResult
            }
        } else {
            // 单尺度搜索
            let step = max(Int(CGFloat(self.config.coarseStep) * scale), 1)
            finalMatch = await findBestOverlap(
                image1: normCGImage1,
                image2: normCGImage2,
                searchRange: (min: CGFloat(minOverlap), max: CGFloat(maxOverlap)),
                step: step
            )
        }
        
        // 检查相似度是否达到阈值
        guard finalMatch.score >= self.config.similarityThreshold else {
            overlapLogger.warning("⚠️ 最佳匹配相似度(\(String(format: "%.3f", finalMatch.score)))低于阈值(\(self.config.similarityThreshold))")
            return OverlapResult(
                hasOverlap: false,
                overlapRect1: .zero,
                overlapRect2: .zero,
                similarityScore: finalMatch.score,
                bestStitchPosition: OverlapResult.StitchPosition(
                    yOffset: originalHeight1,
                    quality: .poor
                ),
                confidence: 0,
                processingTime: CFAbsoluteTimeGetCurrent() - startTime,
                topCrop1: topCrop1,
                bottomCrop1: bottomCrop1,
                topCrop2: topCrop2,
                bottomCrop2: bottomCrop2
            )
        }
        
        // 将缩放后的重叠高度转换回原始尺寸（像素）
        let originalOverlapHeightPixels = finalMatch.overlap / scale
        // 转换为逻辑坐标（UIImage.size 坐标系）
        let imageScale = image1.scale
        let originalOverlapHeight = originalOverlapHeightPixels / imageScale
        
        overlapLogger.debug("📐 转换回原始尺寸: 缩放后重叠=\(finalMatch.overlap)px → 原始像素重叠=\(originalOverlapHeightPixels)px → 逻辑重叠=\(originalOverlapHeight)pt (scale=\(scale), imageScale=\(imageScale))")
        
        // 使用原始分辨率验证重叠区域
        let verifiedResult = await verifyOverlapWithOriginalResolution(
            image1: image1,
            image2: image2,
            overlapHeight: originalOverlapHeightPixels,
            scaledScore: finalMatch.score
        )
        
        overlapLogger.debug("📐 原始分辨率验证结果: 相似度=\(String(format: "%.3f", verifiedResult.score))")
        
        // 计算裁剪后图片空间的 yOffset（逻辑坐标）
        // 注意：重叠检测是在裁剪后的图片上进行的，返回的坐标应该对应裁剪后的图片空间
        let logicalHeight1 = image1.size.height
        let croppedYOffset = logicalHeight1 - originalOverlapHeight
        
        // 计算重叠比例（基于裁剪后的逻辑高度）
        let overlapRatio = originalOverlapHeight / logicalHeight1
        
        overlapLogger.info("📐 裁剪后空间: dy=\(croppedYOffset)pt, overlap=\(originalOverlapHeight)pt, overlap_ratio=\(String(format: "%.2f", overlapRatio))")
        
        let overlapRect1 = CGRect(
            x: 0,
            y: croppedYOffset,
            width: image1.size.width,
            height: originalOverlapHeight
        )
        
        let overlapRect2 = CGRect(
            x: 0,
            y: 0,
            width: image2.size.width,
            height: originalOverlapHeight
        )
        
        // 计算置信度
        let confidence = calculateConfidence(verifiedResult.score, overlapHeight: finalMatch.overlap, maxHeight: scaledHeight1)
        
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        
        return OverlapResult(
            hasOverlap: true,
            overlapRect1: overlapRect1,
            overlapRect2: overlapRect2,
            similarityScore: verifiedResult.score,
            bestStitchPosition: OverlapResult.StitchPosition(
                yOffset: croppedYOffset,
                overlapHeight: originalOverlapHeight,
                quality: OverlapResult.StitchQuality(score: verifiedResult.score)
            ),
            confidence: confidence,
            processingTime: processingTime,
            topCrop1: topCrop1,
            bottomCrop1: bottomCrop1,
            topCrop2: topCrop2,
            bottomCrop2: bottomCrop2
        )
    }
    
    // MARK: - 水平方向重叠检测
    private func detectHorizontalOverlap(
        _ image1: UIImage,
        _ image2: UIImage,
        startTime: CFAbsoluteTime,
        originalImage1: UIImage? = nil,
        originalImage2: UIImage? = nil,
        topCrop1: CGFloat = 0,
        bottomCrop1: CGFloat = 0,
        topCrop2: CGFloat = 0,
        bottomCrop2: CGFloat = 0
    ) async -> OverlapResult {
        
        // 旋转图片 90 度，复用垂直检测逻辑
        guard let rotated1 = rotateImage(image1, by: 90),
              let rotated2 = rotateImage(image2, by: 90) else {
            return .noOverlap
        }
        
        // 旋转后：原图的 topCrop 变为 leftCrop，bottomCrop 变为 rightCrop
        // 但 detectVerticalOverlap 内部只使用这些值记录到结果中，不用于裁剪
        // 为保持语义正确，这里交换标注
        let leftCrop1 = topCrop1
        let rightCrop1 = bottomCrop1
        let leftCrop2 = topCrop2
        let rightCrop2 = bottomCrop2
        
        // 调用垂直检测（使用旋转后的图片）
        var result = await detectVerticalOverlap(rotated1, rotated2, startTime: startTime, originalImage1: originalImage1, originalImage2: originalImage2, topCrop1: leftCrop1, bottomCrop1: rightCrop1, topCrop2: leftCrop2, bottomCrop2: rightCrop2)
        
        // 转换结果回原始方向
        if result.hasOverlap {
            let width1 = originalImage1?.size.width ?? image1.size.width
            let height1 = originalImage1?.size.height ?? image1.size.height
            let height2 = originalImage2?.size.height ?? image2.size.height
            
            // 原始图片中，水平重叠对应垂直方向的重叠区域
            // result.overlapRect1.height 在旋转后的坐标系中是垂直方向（即原始水平方向）
            let overlapWidth = result.overlapRect1.height
            
            let newRect1 = CGRect(
                x: width1 - overlapWidth,
                y: 0,
                width: overlapWidth,
                height: height1
            )
            
            let newRect2 = CGRect(
                x: 0,
                y: 0,
                width: overlapWidth,
                height: height2
            )
            
            result = OverlapResult(
                hasOverlap: true,
                overlapRect1: newRect1,
                overlapRect2: newRect2,
                similarityScore: result.similarityScore,
                bestStitchPosition: OverlapResult.StitchPosition(
                    xOffset: width1 - overlapWidth,
                    overlapWidth: overlapWidth,
                    quality: result.bestStitchPosition.quality
                ),
                confidence: result.confidence,
                processingTime: result.processingTime,
                topCrop1: topCrop1,
                bottomCrop1: bottomCrop1,
                topCrop2: topCrop2,
                bottomCrop2: bottomCrop2
            )
        }
        
        return result
    }
    
    // MARK: - 核心：查找最佳重叠位置
    private func findBestOverlap(
        image1: CGImage,
        image2: CGImage,
        searchRange: (min: CGFloat, max: CGFloat),
        step: Int
    ) async -> (overlap: CGFloat, score: Double, rect1: CGRect, rect2: CGRect) {
        
        let height1 = CGFloat(image1.height)
        let height2 = CGFloat(image2.height)
        let width = CGFloat(image1.width)
        
        var bestOverlap: CGFloat = 0
        var bestScore: Double = 0
        var debugScores: [(overlap: CGFloat, score: Double)] = []
        
        // 确保搜索范围有效
        let validMinOverlap = max(searchRange.min, 10)
        let validMaxOverlap = min(searchRange.max, height1, height2)
        
        guard validMinOverlap < validMaxOverlap else {
            overlapLogger.debug("🔍 搜索范围无效: min=\(validMinOverlap), max=\(validMaxOverlap)")
            return (0, 0, .zero, .zero)
        }
        
        // 从大到小搜索：大重叠区域匹配到的高分更可靠
        let startY = Int(validMaxOverlap)
        let endY = Int(validMinOverlap)
        // 最小重叠比例达到图片高度的 10% 后才允许提前退出，避免小区域误匹配
        let minOverlapForEarlyExit = max(validMinOverlap, height1 * 0.1)
        
        overlapLogger.debug("🔍 开始搜索: from \(startY) down to \(endY), step \(step), 提前退出阈值=\(minOverlapForEarlyExit)")
        
        for overlapHeight in stride(from: startY, through: endY, by: -step) {
            let overlap = CGFloat(overlapHeight)
            
            // 提取 image1 的底部区域
            let region1 = CGRect(
                x: 0,
                y: max(0, height1 - overlap),
                width: width,
                height: min(overlap, height1)
            )
            
            // 提取 image2 的顶部区域
            let region2 = CGRect(
                x: 0,
                y: 0,
                width: width,
                height: min(overlap, height2)
            )
            
            guard let cropped1 = image1.cropping(to: region1),
                  let cropped2 = image2.cropping(to: region2) else {
                let region1Str = "(x:\(region1.origin.x), y:\(region1.origin.y), w:\(region1.size.width), h:\(region1.size.height))"
                let region2Str = "(x:\(region2.origin.x), y:\(region2.origin.y), w:\(region2.size.width), h:\(region2.size.height))"
                overlapLogger.debug("🔍 裁剪失败: overlap=\(overlap), region1=\(region1Str), region2=\(region2Str)")
                continue
            }
            
            // 计算相似度
            let similarity = await calculateRegionSimilarity(cropped1, cropped2)
            let scoreItem: (overlap: CGFloat, score: Double) = (overlap, similarity)
            debugScores.append(scoreItem)
            
            // 更新最佳匹配
            if similarity > bestScore {
                bestScore = similarity
                bestOverlap = overlap
            }
            
            // 只有重叠区域足够大时才允许提前退出，避免小区域误匹配
            if bestScore >= config.highSimilarityThreshold && overlap >= minOverlapForEarlyExit {
                overlapLogger.debug("🔍 找到高相似度匹配且重叠区域足够大，提前退出: score=\(bestScore), overlap=\(overlap)")
                break
            }
        }
        
        // 稳定性检查：基于排序后的所有结果，检查最佳匹配是否可靠
        let sortedResults = debugScores.sorted { $0.score > $1.score }
        if sortedResults.count >= 2 {
            let topResult = sortedResults[0]
            let secondResult = sortedResults[1]
            let scoreGap = topResult.score - secondResult.score
            
            if topResult.score > 0.7 && scoreGap < 0.05 {
                overlapLogger.debug("🔍 稳定性警告: 最佳和第二优分数太接近 (gap=\(String(format: "%.4f", scoreGap)))")
                let overlapDiff = abs(topResult.overlap - secondResult.overlap)
                let avgOverlap = (topResult.overlap + secondResult.overlap) / 2
                // 如果重叠区域差异超过平均值的 50%，选择更大的重叠区域（大区域更可靠）
                if overlapDiff > avgOverlap * 0.5 && secondResult.overlap > topResult.overlap {
                    overlapLogger.debug("🔍 选择更大的重叠区域: \(secondResult.overlap)px (score=\(String(format: "%.3f", secondResult.score)))")
                    bestOverlap = secondResult.overlap
                    bestScore = secondResult.score
                } else {
                    // 分数接近且重叠区域也接近时，降低置信度但不改变位置
                    // 因为两个候选位置几乎相同，选择分数最高的即可
                    overlapLogger.debug("🔍 重叠区域接近，保持最佳匹配但降低置信度")
                    bestScore = topResult.score * 0.95
                    bestOverlap = topResult.overlap
                }
            }
        }
        
        // 打印前5个最佳匹配
        let top5 = sortedResults.prefix(5)
        overlapLogger.debug("🔍 前5个最佳匹配:")
        for (index, result) in top5.enumerated() {
            overlapLogger.debug("🔍   \(index + 1). overlap=\(result.overlap)px, score=\(String(format: "%.3f", result.score))")
        }
        
        overlapLogger.debug("🔍 最佳结果: overlap=\(bestOverlap)px, score=\(String(format: "%.3f", bestScore))")
        
        let rect1 = CGRect(x: 0, y: height1 - bestOverlap, width: width, height: bestOverlap)
        let rect2 = CGRect(x: 0, y: 0, width: width, height: bestOverlap)
        
        return (bestOverlap, bestScore, rect1, rect2)
    }
    
    // MARK: - 相似度计算
    private func calculateRegionSimilarity(_ image1: CGImage, _ image2: CGImage) async -> Double {
        // 并行计算像素相似度和哈希相似度
        async let pixelSimilarity = calculatePixelSimilarity(image1, image2)
        async let hashSimilarity = calculateAverageHashSimilarity(image1, image2)
        
        let pixel = await pixelSimilarity
        let hash = await hashSimilarity
        
        // 加权综合
        let combined = pixel * config.pixelMatchWeight + hash * config.hashMatchWeight
        
        overlapLogger.debug("🔍 相似度: pixel=\(String(format: "%.3f", pixel)), hash=\(String(format: "%.3f", hash)), combined=\(String(format: "%.3f", combined))")
        
        return combined
    }
    
    /// 计算像素级相似度（使用采样）
    private func calculatePixelSimilarity(_ image1: CGImage, _ image2: CGImage) async -> Double {
        let width1 = image1.width
        let height1 = image1.height
        let width2 = image2.width
        let height2 = image2.height
        
        // 确保尺寸一致
        guard width1 == width2, height1 == height2 else {
            overlapLogger.debug("🔍 尺寸不一致: \(width1)×\(height1) vs \(width2)×\(height2)")
            return 0
        }
        
        guard let pixels1 = getRGBAData(from: image1),
              let pixels2 = getRGBAData(from: image2) else {
            return 0
        }
        
        let totalPixels = width1 * height1
        let minSampleCount = max(totalPixels / 20, 500)
        let step = max(totalPixels / minSampleCount, 1)
        
        var totalDiff: Double = 0
        var sampleCount = 0
        
        for i in stride(from: 0, to: totalPixels * 4, by: step * 4) {
            let r1 = Double(pixels1[i])
            let g1 = Double(pixels1[i + 1])
            let b1 = Double(pixels1[i + 2])
            
            let r2 = Double(pixels2[i])
            let g2 = Double(pixels2[i + 1])
            let b2 = Double(pixels2[i + 2])
            
            // 使用曼哈顿距离替代欧氏距离，避免 sqrt 和 pow 计算，性能更好
            let diff = (abs(r1 - r2) + abs(g1 - g2) + abs(b1 - b2)) / (255.0 * 3.0)
            totalDiff += diff
            sampleCount += 1
        }
        
        let avgDiff = totalDiff / Double(sampleCount)
        let similarity = 1.0 - avgDiff
        
        return similarity
    }
    
    /// 计算平均哈希相似度
    private func calculateAverageHashSimilarity(_ image1: CGImage, _ image2: CGImage) async -> Double {
        let size = 8
        
        guard let resized1 = resizeCGImage(image1, to: CGSize(width: size, height: size)),
              let resized2 = resizeCGImage(image2, to: CGSize(width: size, height: size)) else {
            return 0
        }
        
        guard let gray1 = getGrayscaleData(from: resized1),
              let gray2 = getGrayscaleData(from: resized2) else {
            return 0
        }
        
        // 计算平均灰度
        let avg1 = Double(gray1.reduce(0, +)) / Double(gray1.count)
        let avg2 = Double(gray2.reduce(0, +)) / Double(gray2.count)
        
        // 生成哈希
        var hash1 = 0
        var hash2 = 0
        
        for i in 0..<gray1.count {
            if Double(gray1[i]) > avg1 {
                hash1 |= (1 << i)
            }
            if Double(gray2[i]) > avg2 {
                hash2 |= (1 << i)
            }
        }
        
        // 计算汉明距离
        let xor = hash1 ^ hash2
        let distance = xor.nonzeroBitCount
        let maxDistance = size * size
        let similarity = 1.0 - (Double(distance) / Double(maxDistance))
        
        return similarity
    }
    
    // MARK: - 原始分辨率验证
    private func verifyOverlapWithOriginalResolution(
        image1: UIImage,
        image2: UIImage,
        overlapHeight: CGFloat,
        scaledScore: Double
    ) async -> (score: Double, confidence: Double) {
        
        guard let cgImage1 = image1.cgImage,
              let cgImage2 = image2.cgImage else {
            return (0, 0)
        }
        
        let width1 = CGFloat(cgImage1.width)
        let height1 = CGFloat(cgImage1.height)
        let height2 = CGFloat(cgImage2.height)
        
        // 提取 image1 的底部区域
        // 注意：cgImage 的坐标是像素坐标，不需要再乘 scale
        let region1 = CGRect(
            x: 0,
            y: max(0, height1 - overlapHeight),
            width: width1,
            height: min(overlapHeight, height1)
        )
        
        // 提取 image2 的顶部区域
        let region2 = CGRect(
            x: 0,
            y: 0,
            width: width1,
            height: min(overlapHeight, height2)
        )
        
        guard let cropped1 = cgImage1.cropping(to: region1),
              let cropped2 = cgImage2.cropping(to: region2) else {
            overlapLogger.warning("🔍 原始分辨率验证失败：无法裁剪区域")
            return (scaledScore, 0.5)
        }
        
        // 计算原始分辨率的相似度
        let pixelSimilarity = await calculatePixelSimilarity(cropped1, cropped2)
        let hashSimilarity = await calculateAverageHashSimilarity(cropped1, cropped2)
        
        // 加权综合
        let verifiedScore = pixelSimilarity * config.pixelMatchWeight + hashSimilarity * config.hashMatchWeight
        
        // 计算置信度（基于缩放前后分数的一致性）
        let scoreDiff = abs(verifiedScore - scaledScore)
        let consistency = 1.0 - min(scoreDiff, 1.0)
        let confidence = consistency * 0.5 + verifiedScore * 0.5
        
        overlapLogger.debug("🔍 原始分辨率验证: pixel=\(String(format: "%.3f", pixelSimilarity)), hash=\(String(format: "%.3f", hashSimilarity)), final=\(String(format: "%.3f", verifiedScore))")
        
        return (verifiedScore, confidence)
    }
    
    // MARK: - 辅助方法
    
    /// 统一图片尺寸并缩放到分析尺寸
    private func normalizeImageSizes(_ image1: UIImage, _ image2: UIImage, analysisScale: CGFloat = 1.0) -> (UIImage, UIImage, CGFloat, CGFloat, CGFloat) {
        let width1 = image1.size.width
        let width2 = image2.size.width
        let height1 = image1.size.height
        let height2 = image2.size.height
        
        // 如果宽度差异小于2像素，视为相同
        if abs(width1 - width2) < 2 && analysisScale == 1.0 {
            return (image1, image2, width1, height1, height2)
        }
        
        // 统一使用较小的宽度，避免拉伸失真
        let targetWidth = min(width1, width2)
        let scale1 = targetWidth / width1
        let scale2 = targetWidth / width2
        
        // 应用分析缩放比例
        let finalScale1 = scale1 * analysisScale
        let finalScale2 = scale2 * analysisScale
        
        let newSize1 = CGSize(width: targetWidth * analysisScale, height: height1 * finalScale1)
        let newSize2 = CGSize(width: targetWidth * analysisScale, height: height2 * finalScale2)
        
        let normalized1 = resizeImage(image1, to: newSize1)
        let normalized2 = resizeImage(image2, to: newSize2)
        
        return (normalized1, normalized2, targetWidth * analysisScale, newSize1.height, newSize2.height)
    }
    
    /// 调整图片尺寸
    private func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0 // 保持原始 scale
        
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
    
    /// 调整 CGImage 尺寸
    private func resizeCGImage(_ image: CGImage, to size: CGSize) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        let bitsPerComponent = 8
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return context.makeImage()
    }
    
    /// 获取 RGBA 数据
    private func getRGBAData(from image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return pixels
    }
    
    /// 旋转图片
    private func rotateImage(_ image: UIImage, by degrees: CGFloat) -> UIImage? {
        let radians = degrees * .pi / 180
        let rotatedSize = CGSize(width: image.size.height, height: image.size.width)
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        
        let renderer = UIGraphicsImageRenderer(size: rotatedSize, format: format)
        return renderer.image { context in
            context.cgContext.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
            context.cgContext.rotate(by: radians)
            image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2, width: image.size.width, height: image.size.height))
        }
    }
    
    /// 检测滚动方向
    private func detectScrollDirection(_ image1: UIImage, _ image2: UIImage) async -> ScrollDirection {
        // 简单启发式：比较宽高比
        let ratio1 = image1.size.width / image1.size.height
        let ratio2 = image2.size.width / image2.size.height
        
        // 如果宽度明显大于高度，可能是水平滚动
        if ratio1 > 1.5 && ratio2 > 1.5 {
            return .horizontal
        }
        
        return .vertical
    }
    
    /// 计算置信度
    private func calculateConfidence(_ similarity: Double, overlapHeight: CGFloat, maxHeight: CGFloat) -> Double {
        // 基于相似度和重叠比例计算置信度
        let overlapRatio = overlapHeight / maxHeight
        let confidence = similarity * 0.7 + overlapRatio * 0.3
        return min(confidence, 1.0)
    }
    
    // MARK: - 固定区域高度估算
    
    /// 估算顶部固定区域高度（根据屏幕尺寸）
    private func estimateTopFixedAreaHeight(pixelHeight: CGFloat) -> CGFloat {
        switch pixelHeight {
        case 2556, 2532, 2796, 2778, 2688, 2340, 2436:
            // 全面屏 iPhone（Face ID 机型）
            // 状态栏 47-59px + 导航栏 88-96px ≈ 135-155px
            return 135
        case 1792:
            // iPhone 11/XR
            return 128
        case 2208, 1334:
            // 带 Home 键的 iPhone
            // 状态栏 20px + 导航栏 88px ≈ 108px
            return 108
        default:
            // 默认值
            return config.topFixedAreaHeight
        }
    }
    
    /// 估算底部固定区域高度（根据屏幕尺寸）
    private func estimateBottomFixedAreaHeight(pixelHeight: CGFloat) -> CGFloat {
        switch pixelHeight {
        case 2556, 2532, 2796, 2778, 2688, 2340, 2436:
            // 全面屏 iPhone（Face ID 机型）
            // Home 指示条 34px + 底部安全区域 ≈ 50-60px
            return 55
        case 1792:
            return 50
        case 2208, 1334:
            // 带 Home 键的 iPhone，没有 Home 指示条
            return 0
        default:
            // 默认值
            return config.bottomFixedAreaHeight
        }
    }
    
    /// 判断是否为 iPhone 截图（根据常见截图高度）
    private func isLikelyIPhoneScreenshot(height: CGFloat) -> Bool {
        // 常见 iPhone 截图高度（像素）
        let commonHeights: [CGFloat] = [
            2556, // iPhone 16/15/15 Pro/14 Pro (6.1" 1179×2556)
            2622, // iPhone 16 Pro (6.3" 1206×2622)
            2796, // iPhone 16 Plus/15 Plus/14 Pro Max/15 Pro Max (6.7" 1290×2796)
            2868, // iPhone 16 Pro Max (6.9" 1320×2868)
            2532, // iPhone 14/13 Pro/13 (6.1" 1170×2532)
            2778, // iPhone 13 Pro Max (6.7" 1284×2778)
            2688, // iPhone 12 Pro Max (6.7" 1284×2688)
            2340, // iPhone 12/12 Pro/13 mini (5.4" 1080×2340)
            1792, // iPhone 11/XR (6.1" 828×1792)
            2436, // iPhone X/XS/11 Pro/12 mini (5.8" 1125×2436)
            1334, // iPhone 8/7/6s/SE2 (4.7" 750×1334)
            2208, // iPhone 8 Plus/7 Plus (5.5" 1242×2208)
        ]
        
        // 允许 ±10 像素的误差
        return commonHeights.contains { abs($0 - height) < 10 }
    }
}
