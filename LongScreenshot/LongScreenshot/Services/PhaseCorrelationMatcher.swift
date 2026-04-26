import UIKit
import Accelerate
import os.log

/// 基于相位相关法的帧间位移计算
/// 使用频域分析来计算两帧之间的平移量，具有更好的抗亮度变化和模糊能力
struct PhaseCorrelationMatcher {
    
    private let logger = Logger(subsystem: "com.longscreenshot", category: "PhaseCorrelationMatcher")
    
    /// 降采样因子，默认 1/4 分辨率
    var scaleFactor: CGFloat = 0.25
    
    /// 用于 FFT 计划复用的缓存
    private var fftPlans: [Int: FFTSetup] = [:]
    
    /// 计算两帧之间的位移
    /// - Parameters:
    ///   - buffer1: 第一帧的 CVPixelBuffer
    ///   - buffer2: 第二帧的 CVPixelBuffer
    /// - Returns: 位移 (dx, dy)，单位是像素
    func calculateDisplacement(from buffer1: CVPixelBuffer, to buffer2: CVPixelBuffer) -> (dx: CGFloat, dy: CGFloat) {
        // 转换为 CGImage
        guard let image1 = bufferToCGImage(buffer1),
              let image2 = bufferToCGImage(buffer2) else {
            logger.error("❌ 无法将 CVPixelBuffer 转换为 CGImage")
            return (0, 0)
        }
        
        return calculateDisplacement(from: image1, to: image2)
    }
    
    /// 计算两帧之间的位移
    /// - Parameters:
    ///   - image1: 第一帧的 CGImage
    ///   - image2: 第二帧的 CGImage
    /// - Returns: 位移 (dx, dy)，单位是像素
    func calculateDisplacement(from image1: CGImage, to image2: CGImage) -> (dx: CGFloat, dy: CGFloat) {
        // 降采样
        let scaledWidth = max(1, Int(CGFloat(min(image1.width, image2.width)) * scaleFactor))
        let scaledHeight = max(1, Int(CGFloat(min(image1.height, image2.height)) * scaleFactor))
        
        guard let scaledImage1 = resizeImage(image1, to: CGSize(width: scaledWidth, height: scaledHeight)),
              let scaledImage2 = resizeImage(image2, to: CGSize(width: scaledWidth, height: scaledHeight)) else {
            logger.error("❌ 无法调整图像大小")
            return (0, 0)
        }
        
        // 转换为灰度浮点数据
        guard let gray1 = convertToGrayscaleFloat(image: scaledImage1),
              let gray2 = convertToGrayscaleFloat(image: scaledImage2) else {
            logger.error("❌ 无法转换为灰度浮点数据")
            return (0, 0)
        }
        
        // 应用 Hann 窗
        let windowed1 = applyHannWindow(to: gray1, width: scaledWidth, height: scaledHeight)
        let windowed2 = applyHannWindow(to: gray2, width: scaledWidth, height: scaledHeight)
        
        // 计算位移
        let (scaledDx, scaledDy) = computePhaseCorrelation(image1: windowed1, image2: windowed2, width: scaledWidth, height: scaledHeight)
        
        // 缩放回原始分辨率
        let dx = scaledDx / CGFloat(scaleFactor)
        let dy = scaledDy / CGFloat(scaleFactor)
        
        // 容错处理：当位移非常小时，返回 (0, 0)
        if abs(dx) < 0.5 && abs(dy) < 0.5 {
            return (0, 0)
        }
        
        return (dx, dy)
    }
    
    // MARK: - 私有辅助方法
    
    /// 将 CVPixelBuffer 转换为 CGImage
    private func bufferToCGImage(_ buffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let context = CIContext(options: nil)
        return context.createCGImage(ciImage, from: ciImage.extent)
    }
    
    /// 调整图像大小
    private func resizeImage(_ image: CGImage, to size: CGSize) -> CGImage? {
        let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: image.bitmapInfo.rawValue
        )
        
        guard let context = context else { return nil }
        
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }
    
    /// 将 CGImage 转换为灰度浮点数据（0~1）
    private func convertToGrayscaleFloat(image: CGImage) -> [Float]? {
        let width = image.width
        let height = image.height
        let pixelCount = width * height
        
        // 创建灰度上下文
        let bytesPerRow = width * MemoryLayout<Float>.stride
        var pixels = [Float](repeating: 0, count: pixelCount)
        
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // 归一化到 0~1
        var maxValue: Float = 0
        vDSP_maxv(pixels, 1, &maxValue, vDSP_Length(pixelCount))
        
        if maxValue > 0 {
            let scale: Float = 1.0 / maxValue
            vDSP_vsmul(pixels, 1, &scale, &pixels, 1, vDSP_Length(pixelCount))
        }
        
        return pixels
    }
    
    /// 应用 Hann 窗
    private func applyHannWindow(to pixels: [Float], width: Int, height: Int) -> [Float] {
        let pixelCount = width * height
        var result = [Float](repeating: 0, count: pixelCount)
        
        // 创建 1D Hann 窗
        var rowWindow = [Float](repeating: 0, count: width)
        var colWindow = [Float](repeating: 0, count: height)
        
        for i in 0..<width {
            rowWindow[i] = 0.5 * (1 - cos(2 * .pi * Float(i) / Float(width - 1)))
        }
        
        for i in 0..<height {
            colWindow[i] = 0.5 * (1 - cos(2 * .pi * Float(i) / Float(height - 1)))
        }
        
        // 应用 2D 窗
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                result[index] = pixels[index] * rowWindow[x] * colWindow[y]
            }
        }
        
        return result
    }
    
    /// 计算相位相关
    private func computePhaseCorrelation(image1: [Float], image2: [Float], width: Int, height: Int) -> (dx: CGFloat, dy: CGFloat) {
        let pixelCount = width * height
        
        // 确保宽度和高度是 2 的幂次（FFT 要求）
        let fftWidth = nextPowerOf2(width)
        let fftHeight = nextPowerOf2(height)
        let fftSize = fftWidth * fftHeight
        
        // 准备 FFT 输入数据（复数形式）
        var complex1 = [DSPComplex](repeating: DSPComplex(real: 0, imag: 0), count: fftSize)
        var complex2 = [DSPComplex](repeating: DSPComplex(real: 0, imag: 0), count: fftSize)
        
        // 填充数据
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                complex1[y * fftWidth + x] = DSPComplex(real: image1[index], imag: 0)
                complex2[y * fftWidth + x] = DSPComplex(real: image2[index], imag: 0)
            }
        }
        
        // 获取或创建 FFT 计划
        let fftPlanKey = fftWidth * 10000 + fftHeight
        var fftPlan: FFTSetup
        
        if let existingPlan = fftPlans[fftPlanKey] {
            fftPlan = existingPlan
        } else {
            fftPlan = vDSP_create_fftsetup(vDSP_Length(log2(Float(fftWidth))), FFTRadix(kFFTRadix2))
            fftPlans[fftPlanKey] = fftPlan
        }
        
        // 执行 FFT
        var fft1 = complex1
        var fft2 = complex2
        
        vDSP_fft2d_zip(fftPlan, &fft1, vDSP_Stride(1), &fft1, vDSP_Stride(fftWidth), vDSP_Length(fftHeight), vDSP_Length(fftWidth), FFTDirection(kFFTDirection_Forward))
        vDSP_fft2d_zip(fftPlan, &fft2, vDSP_Stride(1), &fft2, vDSP_Stride(fftWidth), vDSP_Length(fftHeight), vDSP_Length(fftWidth), FFTDirection(kFFTDirection_Forward))
        
        // 计算互功率谱
        var crossPowerSpectrum = [DSPComplex](repeating: DSPComplex(real: 0, imag: 0), count: fftSize)
        let epsilon: Float = 1e-10
        
        for i in 0..<fftSize {
            // 计算共轭
            let conj2 = DSPComplex(real: fft2[i].real, imag: -fft2[i].imag)
            
            // 复数乘法：F1 * conj(F2)
            let product = DSPComplex(
                real: fft1[i].real * conj2.real - fft1[i].imag * conj2.imag,
                imag: fft1[i].real * conj2.imag + fft1[i].imag * conj2.real
            )
            
            // 计算幅度
            let magnitude = sqrt(product.real * product.real + product.imag * product.imag)
            
            // 归一化
            if magnitude > epsilon {
                crossPowerSpectrum[i] = DSPComplex(
                    real: product.real / magnitude,
                    imag: product.imag / magnitude
                )
            } else {
                crossPowerSpectrum[i] = DSPComplex(real: 0, imag: 0)
            }
        }
        
        // 执行逆 FFT
        vDSP_fft2d_zip(fftPlan, &crossPowerSpectrum, vDSP_Stride(1), &crossPowerSpectrum, vDSP_Stride(fftWidth), vDSP_Length(fftHeight), vDSP_Length(fftWidth), FFTDirection(kFFTDirection_Inverse))
        
        // 提取实部并找到峰值
        var correlation = [Float](repeating: 0, count: fftSize)
        for i in 0..<fftSize {
            correlation[i] = crossPowerSpectrum[i].real
        }
        
        // 找到峰值位置
        let (peakX, peakY) = findPeakPosition(correlation: correlation, width: fftWidth, height: fftHeight)
        
        // 亚像素精度精炼
        let (refinedX, refinedY) = refinePeakPosition(correlation: correlation, width: fftWidth, height: fftHeight, peakX: peakX, peakY: peakY)
        
        // 转换为相对于图像中心的位移
        let dx = CGFloat(refinedX) - CGFloat(fftWidth / 2)
        let dy = CGFloat(refinedY) - CGFloat(fftHeight / 2)
        
        return (dx, dy)
    }
    
    /// 找到相关面中的峰值位置
    private func findPeakPosition(correlation: [Float], width: Int, height: Int) -> (x: Int, y: Int) {
        var maxValue: Float = -Float.greatestFiniteMagnitude
        var maxX = 0
        var maxY = 0
        
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                if correlation[index] > maxValue {
                    maxValue = correlation[index]
                    maxX = x
                    maxY = y
                }
            }
        }
        
        return (maxX, maxY)
    }
    
    /// 使用 3x3 邻域进行亚像素精度精炼
    private func refinePeakPosition(correlation: [Float], width: Int, height: Int, peakX: Int, peakY: Int) -> (x: CGFloat, y: CGFloat) {
        // 确保峰值周围有足够的像素
        guard peakX > 0, peakX < width - 1, peakY > 0, peakY < height - 1 else {
            return (CGFloat(peakX), CGFloat(peakY))
        }
        
        // 提取 3x3 邻域
        let center = correlation[peakY * width + peakX]
        let left = correlation[peakY * width + (peakX - 1)]
        let right = correlation[peakY * width + (peakX + 1)]
        let top = correlation[(peakY - 1) * width + peakX]
        let bottom = correlation[(peakY + 1) * width + peakX]
        
        // 抛物线插值
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        
        if right - left != 0 {
            dx = CGFloat(right - left) / (2 * (2 * center - left - right))
        }
        
        if bottom - top != 0 {
            dy = CGFloat(bottom - top) / (2 * (2 * center - top - bottom))
        }
        
        return (CGFloat(peakX) + dx, CGFloat(peakY) + dy)
    }
    
    /// 计算下一个 2 的幂次
    private func nextPowerOf2(_ n: Int) -> Int {
        var power = 1
        while power < n {
            power <<= 1
        }
        return power
    }
    
    /// 清理 FFT 计划
    func cleanup() {
        for plan in fftPlans.values {
            vDSP_destroy_fftsetup(plan)
        }
        fftPlans.removeAll()
    }
}
