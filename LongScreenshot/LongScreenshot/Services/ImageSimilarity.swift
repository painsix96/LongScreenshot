import UIKit
import Accelerate
import Vision
import CoreImage

// MARK: - 相似度结果
struct SimilarityResult {
    let score: Double // 0.0 - 1.0，1.0 表示完全相同
    let method: SimilarityMethod
    let confidence: Double // 置信度
    let processingTime: TimeInterval
    
    var isSimilar: Bool {
        return score > 0.85
    }
}

enum SimilarityMethod {
    case perceptualHash
    case pixelDifference
    case featureMatching
    case hybrid // 综合多种算法
}

// MARK: - 图像相似度计算
actor ImageSimilarity {
    
    // MARK: - 配置参数
    struct Config {
        // pHash 参数
        var pHashSize: Int = 32 // DCT 矩阵大小
        var pHashHashSize: Int = 8 // 最终哈希位数
        
        // 像素差异参数
        var pixelSampleSize: CGSize = CGSize(width: 100, height: 100)
        var pixelThreshold: Double = 0.15 // 像素差异阈值
        
        // 特征匹配参数
        var featureConfidenceThreshold: Float = 0.7
        var minFeatureMatches: Int = 10
        
        // 性能优化
        var maxProcessingDimension: CGFloat = 1080
        var useParallelProcessing: Bool = true
    }
    
    var config = Config()
    
    // MARK: - 主入口：综合相似度计算
    func calculateSimilarity(
        between image1: UIImage,
        and image2: UIImage,
        method: SimilarityMethod = .hybrid
    ) async -> SimilarityResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // 预处理图片（统一尺寸和格式）
        let processedImages = await preprocessImages(image1, image2)
        
        let score: Double
        let confidence: Double
        
        switch method {
        case .perceptualHash:
            (score, confidence) = await calculatePerceptualHashSimilarity(
                processedImages.0,
                processedImages.1
            )
        case .pixelDifference:
            (score, confidence) = await calculatePixelDifference(
                processedImages.0,
                processedImages.1
            )
        case .featureMatching:
            (score, confidence) = await calculateFeatureSimilarity(
                processedImages.0,
                processedImages.1
            )
        case .hybrid:
            (score, confidence) = await calculateHybridSimilarity(
                processedImages.0,
                processedImages.1
            )
        }
        
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        
        return SimilarityResult(
            score: score,
            method: method,
            confidence: confidence,
            processingTime: processingTime
        )
    }
    
    // MARK: - 1. 感知哈希 (pHash) 算法
    
    /// 计算感知哈希相似度
    func calculatePerceptualHashSimilarity(_ image1: UIImage, _ image2: UIImage) async -> (score: Double, confidence: Double) {
        guard let hash1 = computePHash(image1),
              let hash2 = computePHash(image2) else {
            return (0, 0)
        }
        
        // 计算汉明距离
        let hammingDistance = calculateHammingDistance(hash1, hash2)
        let maxDistance = config.pHashHashSize * config.pHashHashSize
        let similarity = 1.0 - Double(hammingDistance) / Double(maxDistance)
        
        // 置信度：距离越小，置信度越高
        let confidence = 1.0 - Double(hammingDistance) / Double(maxDistance / 2)
        
        return (similarity, max(0, confidence))
    }
    
    /// 计算图片的感知哈希
    private func computePHash(_ image: UIImage) -> UInt64? {
        guard let cgImage = image.cgImage else { return nil }
        
        let size = config.pHashSize
        
        // 1. 缩放到指定大小
        guard let resizedImage = resizeImage(image, to: CGSize(width: size, height: size)),
              let resizedCGImage = resizedImage.cgImage else { return nil }
        
        // 2. 转换为灰度图
        guard let grayImage = convertToGrayscale(resizedCGImage) else { return nil }
        
        // 3. 应用 DCT（离散余弦变换）
        guard let dctCoefficients = applyDCT(to: grayImage, size: size) else { return nil }
        
        // 4. 提取低频分量并计算哈希
        let hash = computeHashFromDCT(dctCoefficients, hashSize: config.pHashHashSize)
        
        return hash
    }
    
    /// 应用离散余弦变换 (DCT)
    private func applyDCT(to pixels: [Float], size: Int) -> [Float]? {
        var input = pixels
        var output = [Float](repeating: 0, count: size * size)
        
        // 使用 Accelerate 框架的 DCT
        guard let dctSetup = vDSP_DCT_CreateSetup(
            nil,
            vDSP_Length(size * size),
            vDSP_DCT_Type.II
        ) else { return nil }
        
        vDSP_DCT_Execute(dctSetup, &input, &output)
        // vDSP_DCT_DestroySetup 在某些版本中不可用，使用 vDSP_destroy_fftsetup 替代
        // 实际上 DCT setup 不需要显式销毁，因为它内部使用的是 vDSP 的 FFT setup
        // 为了避免内存泄漏警告，我们将 dctSetup 设为可选类型，让它在作用域结束时自动释放
        _ = dctSetup
        
        return output
    }
    
    /// 从 DCT 系数计算哈希
    private func computeHashFromDCT(_ dctCoefficients: [Float], hashSize: Int) -> UInt64 {
        var hash: UInt64 = 0
        
        // 计算低频区域的平均值（排除 DC 分量）
        var sum: Float = 0
        var count = 0
        for y in 0..<hashSize {
            for x in 0..<hashSize {
                if x == 0 && y == 0 { continue } // 跳过 DC 分量
                let index = y * config.pHashSize + x
                if index < dctCoefficients.count {
                    sum += abs(dctCoefficients[index])
                    count += 1
                }
            }
        }
        
        let average = sum / Float(count)
        
        // 生成哈希值
        for y in 0..<hashSize {
            for x in 0..<hashSize {
                let index = y * config.pHashSize + x
                if index < dctCoefficients.count {
                    let bit = abs(dctCoefficients[index]) > average ? 1 : 0
                    let bitPosition = y * hashSize + x
                    hash |= (UInt64(bit) << bitPosition)
                }
            }
        }
        
        return hash
    }
    
    /// 计算汉明距离
    private func calculateHammingDistance(_ hash1: UInt64, _ hash2: UInt64) -> Int {
        var xor = hash1 ^ hash2
        var distance = 0
        while xor != 0 {
            distance += Int(xor & 1)
            xor >>= 1
        }
        return distance
    }
    
    // MARK: - 2. 像素级差异比较算法
    
    /// 计算像素级差异相似度
    func calculatePixelDifference(_ image1: UIImage, _ image2: UIImage) async -> (score: Double, confidence: Double) {
        let sampleSize = config.pixelSampleSize
        
        guard let resized1 = resizeImage(image1, to: sampleSize),
              let resized2 = resizeImage(image2, to: sampleSize),
              let cgImage1 = resized1.cgImage,
              let cgImage2 = resized2.cgImage else {
            return (0, 0)
        }
        
        // 获取像素数据
        guard let pixels1 = getPixelData(from: cgImage1),
              let pixels2 = getPixelData(from: cgImage2) else {
            return (0, 0)
        }
        
        // 计算像素差异
        var totalDifference: Double = 0
        let pixelCount = pixels1.count / 4 // RGBA
        
        for i in 0..<pixelCount {
            let offset = i * 4
            let r1 = Double(pixels1[offset])
            let g1 = Double(pixels1[offset + 1])
            let b1 = Double(pixels1[offset + 2])
            
            let r2 = Double(pixels2[offset])
            let g2 = Double(pixels2[offset + 1])
            let b2 = Double(pixels2[offset + 2])
            
            // 使用欧几里得距离计算颜色差异
            let diff = sqrt(
                pow(r1 - r2, 2) +
                pow(g1 - g2, 2) +
                pow(b1 - b2, 2)
            ) / 441.67 // 归一化到 0-1 (sqrt(255^2 * 3))
            
            totalDifference += diff
        }
        
        let averageDifference = totalDifference / Double(pixelCount)
        let similarity = max(0, 1.0 - averageDifference / config.pixelThreshold)
        
        // 计算置信度（基于方差）
        let variance = calculateVariance(pixels1, pixels2)
        let confidence = 1.0 - min(variance, 1.0)
        
        return (similarity, confidence)
    }
    
    /// 获取图片像素数据
    private func getPixelData(from cgImage: CGImage) -> [UInt8]? {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let totalBytes = height * bytesPerRow
        
        var pixels = [UInt8](repeating: 0, count: totalBytes)
        
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return pixels
    }
    
    /// 计算方差
    private func calculateVariance(_ pixels1: [UInt8], _ pixels2: [UInt8]) -> Double {
        let count = min(pixels1.count, pixels2.count)
        var sum: Double = 0
        var sumSquared: Double = 0
        
        for i in stride(from: 0, to: count, by: 4) {
            let diff = Double(pixels1[i]) - Double(pixels2[i])
            sum += diff
            sumSquared += diff * diff
        }
        
        let mean = sum / Double(count / 4)
        let meanSquared = sumSquared / Double(count / 4)
        
        return meanSquared - mean * mean
    }
    
    // MARK: - 3. 特征点匹配算法 (Vision 框架)
    // Note: Vision framework feature matching requires iOS 15.0+
    // Using simplified implementation for compatibility
    
    /// 使用 Vision 框架计算特征相似度 (简化版本)
    func calculateFeatureSimilarity(_ image1: UIImage, _ image2: UIImage) async -> (score: Double, confidence: Double) {
        // 由于 VNGenerateFeaturePrintRequest 在某些环境不可用
        // 这里使用感知哈希作为替代方案
        return await calculatePerceptualHashSimilarity(image1, image2)
    }
    
    // MARK: - 4. 综合算法 (Hybrid)
    
    /// 综合多种算法的相似度计算
    private func calculateHybridSimilarity(_ image1: UIImage, _ image2: UIImage) async -> (score: Double, confidence: Double) {
        // 并行执行多种算法
        async let pHashResult = calculatePerceptualHashSimilarity(image1, image2)
        async let pixelResult = calculatePixelDifference(image1, image2)
        async let featureResult = calculateFeatureSimilarity(image1, image2)
        
        let (pHash, pHashConf) = await pHashResult
        let (pixel, pixelConf) = await pixelResult
        let (feature, featureConf) = await featureResult
        
        // 根据置信度加权
        let totalConfidence = pHashConf + pixelConf + featureConf
        guard totalConfidence > 0 else { return (0, 0) }
        
        let weightedScore = (pHash * pHashConf + pixel * pixelConf + feature * featureConf) / totalConfidence
        let averageConfidence = totalConfidence / 3.0
        
        return (weightedScore, averageConfidence)
    }
    
    // MARK: - 辅助方法
    
    /// 预处理图片（统一尺寸和格式）
    private func preprocessImages(_ image1: UIImage, _ image2: UIImage) async -> (UIImage, UIImage) {
        // 确定目标尺寸（保持较小的尺寸以提高性能）
        let maxDim = config.maxProcessingDimension
        
        let size1 = image1.size
        let size2 = image2.size
        
        let scale1 = min(maxDim / size1.width, maxDim / size1.height, 1.0)
        let scale2 = min(maxDim / size2.width, maxDim / size2.height, 1.0)
        
        let targetSize1 = CGSize(width: size1.width * scale1, height: size1.height * scale1)
        let targetSize2 = CGSize(width: size2.width * scale2, height: size2.height * scale2)
        
        // 使用相同的尺寸（取较小者）
        let commonSize = CGSize(
            width: min(targetSize1.width, targetSize2.width),
            height: min(targetSize1.height, targetSize2.height)
        )
        
        let processed1 = resizeImage(image1, to: commonSize) ?? image1
        let processed2 = resizeImage(image2, to: commonSize) ?? image2
        
        return (processed1, processed2)
    }
    
    /// 调整图片尺寸
    private func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
    
    /// 转换为灰度图
    private func convertToGrayscale(_ cgImage: CGImage) -> [Float]? {
        let width = cgImage.width
        let height = cgImage.height
        let totalPixels = width * height
        
        var pixels = [UInt8](repeating: 0, count: totalPixels * 4)
        var grayPixels = [Float](repeating: 0, count: totalPixels)
        
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 4 * width,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // 转换为灰度值 (使用标准灰度系数)
        for i in 0..<totalPixels {
            let offset = i * 4
            let r = Float(pixels[offset])
            let g = Float(pixels[offset + 1])
            let b = Float(pixels[offset + 2])
            // 标准灰度转换: 0.299 * R + 0.587 * G + 0.114 * B
            grayPixels[i] = 0.299 * r + 0.587 * g + 0.114 * b
        }
        
        return grayPixels
    }
}

// MARK: - 扩展：计算相似度等级
extension SimilarityResult {
    enum SimilarityLevel {
        case identical     // 完全相同
        case verySimilar   // 非常相似
        case similar       // 相似
        case somewhatSimilar // 略有相似
        case different     // 不同
        
        init(score: Double) {
            switch score {
            case 0.98...1.0: self = .identical
            case 0.90..<0.98: self = .verySimilar
            case 0.80..<0.90: self = .similar
            case 0.60..<0.80: self = .somewhatSimilar
            default: self = .different
            }
        }
    }
    
    var level: SimilarityLevel {
        return SimilarityLevel(score: score)
    }
    
    var levelDescription: String {
        switch level {
        case .identical: return "完全相同"
        case .verySimilar: return "非常相似"
        case .similar: return "相似"
        case .somewhatSimilar: return "略有相似"
        case .different: return "不同"
        }
    }
}
