import Foundation
import AVFoundation
import Accelerate
import CoreGraphics
import UIKit

/// 滚动方向枚举
enum ScrollDirection {
    case vertical
    case horizontal
}

/// 视频转长截图的核心类
class ScreenRecordingStitcher {
    
    /// 回调类型定义
    typealias ProgressCallback = (Float) -> Void
    typealias CompletionCallback = (UIImage?) -> Void
    
    // 配置参数
    private let frameSkipInterval: Int = 1  // 每隔1帧取1帧，可配置
    private let accumulationThreshold: CGFloat = 0.65  // 累积位移阈值，屏幕高度的65%
    private let stillnessThreshold: TimeInterval = 2.0  // 静止帧检测阈值
    private let jumpThresholdMultiplier: CGFloat = 1.5  // 跳跃位移阈值倍数
    
    // 内部状态
    private var keyFrames: [CGImage] = []
    private var accumulatedDistance: CGFloat = 0.0
    private var baseFrame: CVPixelBuffer?
    private var lastFrameTime: CMTime = .zero
    private var isProcessing: Bool = false
    
    // 后台队列
    private let processingQueue = DispatchQueue(label: "com.stills.stitch", qos: .userInitiated)
    
    /// 主入口方法
    /// - Parameters:
    ///   - videoURL: 视频文件URL
    ///   - direction: 滚动方向
    ///   - progress: 进度回调
    ///   - completion: 完成回调
    func processVideo(videoURL: URL, direction: ScrollDirection, progress: @escaping ProgressCallback, completion: @escaping CompletionCallback) {
        guard !isProcessing else {
            completion(nil)
            return
        }
        
        isProcessing = true
        keyFrames.removeAll()
        accumulatedDistance = 0.0
        baseFrame = nil
        lastFrameTime = .zero
        
        processingQueue.async {
            self.performProcessing(videoURL: videoURL, direction: direction, progress: progress, completion: completion)
        }
    }
    
    /// 执行处理逻辑
    private func performProcessing(videoURL: URL, direction: ScrollDirection, progress: @escaping ProgressCallback, completion: @escaping CompletionCallback) {
        // 步骤1: 视频解码和关键帧提取
        let asset = AVAsset(url: videoURL)
        guard let reader = try? AVAssetReader(asset: asset),
              let videoTrack = asset.tracks(withMediaType: .video).first else {
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }
        
        let totalDuration = asset.duration.seconds
        var currentTime: TimeInterval = 0.0
        
        // 配置输出
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
        reader.add(readerOutput)
        
        // 开始读取
        reader.startReading()
        var frameCount = 0
        
        while reader.status == .reading {
            guard let sampleBuffer = readerOutput.copyNextSampleBuffer(),
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                break
            }
            
            // 每隔 frameSkipInterval 帧处理一次
            if frameCount % (frameSkipInterval + 1) == 0 {
                if self.processFrame(pixelBuffer: pixelBuffer, direction: direction) {
                    // 更新进度
                    let currentSampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    currentTime = currentSampleTime.seconds
                    let progressValue = Float(currentTime / totalDuration)
                    DispatchQueue.main.async {
                        progress(progressValue)
                    }
                }
            }
            
            frameCount += 1
        }
        
        // 处理完成，添加最后一帧
        if let lastFrame = baseFrame, keyFrames.isEmpty || keyFrames.count > 0 {
            if let cgImage = pixelBufferToCGImage(pixelBuffer: lastFrame) {
                keyFrames.append(cgImage)
            }
        }
        
        // 步骤2: 图像拼接
        if keyFrames.count > 1 {
            let stitchedImage = stitchImages(images: keyFrames, direction: direction)
            DispatchQueue.main.async {
                completion(stitchedImage)
                self.isProcessing = false
            }
        } else if let firstImage = keyFrames.first {
            let singleImage = UIImage(cgImage: firstImage)
            DispatchQueue.main.async {
                completion(singleImage)
                self.isProcessing = false
            }
        } else {
            DispatchQueue.main.async {
                completion(nil)
                self.isProcessing = false
            }
        }
    }
    
    /// 处理单帧
    private func processFrame(pixelBuffer: CVPixelBuffer, direction: ScrollDirection) -> Bool {
        guard let baseFrame = baseFrame else {
            // 第一帧作为基准帧
            self.baseFrame = pixelBuffer
            if let cgImage = pixelBufferToCGImage(pixelBuffer: pixelBuffer) {
                keyFrames.append(cgImage)
            }
            lastFrameTime = CMTime.now()
            return true
        }
        
        // 计算位移
        let translation = estimateTranslation(previous: baseFrame, current: pixelBuffer)
        
        // 根据滚动方向获取位移分量
        let displacement: CGFloat
        switch direction {
        case .vertical:
            displacement = abs(translation.y)
        case .horizontal:
            displacement = abs(translation.x)
        }
        
        accumulatedDistance += displacement
        
        // 检查静止状态
        let currentTime = CMTime.now()
        let timeElapsed = currentTime.seconds - lastFrameTime.seconds
        
        // 检查是否需要添加关键帧
        let screenHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let threshold = screenHeight * accumulationThreshold
        
        var shouldAddKeyFrame = false
        
        // 累积位移达到阈值
        if accumulatedDistance >= threshold {
            shouldAddKeyFrame = true
        }
        // 静止超过阈值时间
        else if timeElapsed >= stillnessThreshold && displacement < 1.0 {
            shouldAddKeyFrame = true
        }
        // 位移跳跃极大
        else if displacement > threshold * jumpThresholdMultiplier {
            shouldAddKeyFrame = true
        }
        
        if shouldAddKeyFrame {
            if let cgImage = pixelBufferToCGImage(pixelBuffer: pixelBuffer) {
                keyFrames.append(cgImage)
            }
            self.baseFrame = pixelBuffer
            accumulatedDistance = 0.0
            lastFrameTime = currentTime
            return true
        }
        
        return false
    }
    
    /// 基于相位相关的帧间位移计算
    private func estimateTranslation(previous: CVPixelBuffer, current: CVPixelBuffer, scaleFactor: CGFloat = 0.25) -> CGPoint {
        // 1. 转换为灰度浮点纹理并降采样
        guard let previousGray = convertToGrayAndDownsample(pixelBuffer: previous, scaleFactor: scaleFactor),
              let currentGray = convertToGrayAndDownsample(pixelBuffer: current, scaleFactor: scaleFactor) else {
            return .zero
        }
        
        let width = previousGray.width
        let height = previousGray.height
        let count = width * height
        
        // 2. 应用Hann窗
        applyHannWindow(buffer: &previousGray.data, width: width, height: height)
        applyHannWindow(buffer: &currentGray.data, width: width, height: height)
        
        // 3. 计算FFT
        guard let fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Float(width))), FFTRadix(kFFTRadix2)) else {
            return .zero
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }
        
        // 准备FFT缓冲区
        let fftSize = vDSP_Length(width * height * 2)
        var fftBuffer1 = [Float](repeating: 0, count: Int(fftSize))
        var fftBuffer2 = [Float](repeating: 0, count: Int(fftSize))
        
        // 复制数据到FFT缓冲区
        memcpy(&fftBuffer1, previousGray.data, MemoryLayout<Float>.size * count)
        memcpy(&fftBuffer2, currentGray.data, MemoryLayout<Float>.size * count)
        
        // 执行FFT
        var fft1 = DSPSplitComplex(realp: &fftBuffer1, imagp: &fftBuffer1 + count)
        var fft2 = DSPSplitComplex(realp: &fftBuffer2, imagp: &fftBuffer2 + count)
        
        vDSP_fft2d_zrip(fftSetup, &fft1, 1, 0, vDSP_Length(height), vDSP_Length(width), FFTDirection(kFFTDirection_Forward))
        vDSP_fft2d_zrip(fftSetup, &fft2, 1, 0, vDSP_Length(height), vDSP_Length(width), FFTDirection(kFFTDirection_Forward))
        
        // 4. 计算互功率谱
        var crossPowerSpectrum = [Float](repeating: 0, count: Int(fftSize))
        var crossPowerSpectrumSplit = DSPSplitComplex(realp: &crossPowerSpectrum, imagp: &crossPowerSpectrum + count)
        
        for i in 0..<count {
            // F1 * conj(F2)
            let real1 = fft1.realp[i]
            let imag1 = fft1.imagp[i]
            let real2 = fft2.realp[i]
            let imag2 = fft2.imagp[i]
            
            let real = real1 * real2 + imag1 * imag2
            let imag = imag1 * real2 - real1 * imag2
            
            // 计算幅值
            let magnitude = sqrt(real * real + imag * imag) + 1e-6
            
            // 归一化
            crossPowerSpectrumSplit.realp[i] = real / magnitude
            crossPowerSpectrumSplit.imagp[i] = imag / magnitude
        }
        
        // 5. 逆FFT
        vDSP_fft2d_zrip(fftSetup, &crossPowerSpectrumSplit, 1, 0, vDSP_Length(height), vDSP_Length(width), FFTDirection(kFFTDirection_Inverse))
        
        // 6. 寻找峰值（亚像素精度）
        var maxValue: Float = -Float.greatestFiniteMagnitude
        var maxX: Int = 0
        var maxY: Int = 0
        
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let value = crossPowerSpectrum[index]
                if value > maxValue {
                    maxValue = value
                    maxX = x
                    maxY = y
                }
            }
        }
        
        // 亚像素精度拟合
        let subPixel = fitSubPixelPeak(buffer: crossPowerSpectrum, width: width, height: height, peakX: maxX, peakY: maxY)
        
        // 7. 坐标中心化并恢复到原图尺度
        let centerX = CGFloat(width) / 2.0
        let centerY = CGFloat(height) / 2.0
        
        var dx = (CGFloat(maxX) + subPixel.x) - centerX
        var dy = (CGFloat(maxY) + subPixel.y) - centerY
        
        // 处理循环位移
        if dx > centerX {
            dx -= CGFloat(width)
        } else if dx < -centerX {
            dx += CGFloat(width)
        }
        
        if dy > centerY {
            dy -= CGFloat(height)
        } else if dy < -centerY {
            dy += CGFloat(height)
        }
        
        // 恢复到原图尺度
        dx /= scaleFactor
        dy /= scaleFactor
        
        return CGPoint(x: dx, y: dy)
    }
    
    /// 转换为灰度并降采样
    private func convertToGrayAndDownsample(pixelBuffer: CVPixelBuffer, scaleFactor: CGFloat) -> (data: UnsafeMutablePointer<Float>, width: Int, height: Int)? {
        let originalWidth = CVPixelBufferGetWidth(pixelBuffer)
        let originalHeight = CVPixelBufferGetHeight(pixelBuffer)
        
        let newWidth = Int(CGFloat(originalWidth) * scaleFactor)
        let newHeight = Int(CGFloat(originalHeight) * scaleFactor)
        
        guard newWidth > 0 && newHeight > 0 else {
            return nil
        }
        
        // 锁定像素缓冲区
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }
        
        // 创建输出缓冲区
        let dataSize = newWidth * newHeight * MemoryLayout<Float>.size
        guard let outputData = UnsafeMutablePointer<Float>.allocate(capacity: newWidth * newHeight) else {
            return nil
        }
        
        // 计算步长
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytesPerPixel = 4 // BGRA
        
        // 降采样并转换为灰度
        for y in 0..<newHeight {
            for x in 0..<newWidth {
                let originalX = Int(CGFloat(x) / scaleFactor)
                let originalY = Int(CGFloat(y) / scaleFactor)
                
                let pixelAddress = baseAddress + originalY * bytesPerRow + originalX * bytesPerPixel
                let pixel = pixelAddress.assumingMemoryBound(to: UInt8.self)
                
                // BGRA转灰度
                let b = Float(pixel[0]) / 255.0
                let g = Float(pixel[1]) / 255.0
                let r = Float(pixel[2]) / 255.0
                let gray = 0.299 * r + 0.587 * g + 0.114 * b
                
                outputData[y * newWidth + x] = gray
            }
        }
        
        return (outputData, newWidth, newHeight)
    }
    
    /// 应用Hann窗
    private func applyHannWindow(buffer: inout UnsafeMutablePointer<Float>, width: Int, height: Int) {
        let count = width * height
        
        // 创建Hann窗
        var window = [Float](repeating: 0, count: width)
        for i in 0..<width {
            window[i] = 0.5 * (1.0 - cos(2.0 * .pi * Float(i) / Float(width - 1)))
        }
        
        // 应用窗函数
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                buffer[index] *= window[x] * window[y]
            }
        }
    }
    
    /// 亚像素峰值拟合
    private func fitSubPixelPeak(buffer: [Float], width: Int, height: Int, peakX: Int, peakY: Int) -> CGPoint {
        // 检查边界
        guard peakX > 0 && peakX < width - 1 && peakY > 0 && peakY < height - 1 else {
            return .zero
        }
        
        // 提取3x3邻域
        var values = [Float](repeating: 0, count: 9)
        var index = 0
        
        for y in peakY-1...peakY+1 {
            for x in peakX-1...peakX+1 {
                values[index] = buffer[y * width + x]
                index += 1
            }
        }
        
        // 二次曲面拟合
        // 假设峰值附近的表面可以用二次函数表示：f(x,y) = a + bx + cy + dxy + ex² + fy²
        // 这里使用简化的2D高斯拟合
        
        let centerValue = values[4] // 中心值
        let dx = (values[5] - values[3]) / (2.0 * centerValue)
        let dy = (values[7] - values[1]) / (2.0 * centerValue)
        
        return CGPoint(x: dx, y: dy)
    }
    
    /// 将CVPixelBuffer转换为CGImage
    private func pixelBufferToCGImage(pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        return context.createCGImage(ciImage, from: ciImage.extent)
    }
    
    /// 图像拼接
    private func stitchImages(images: [CGImage], direction: ScrollDirection) -> UIImage? {
        guard images.count > 1 else {
            return images.first.map { UIImage(cgImage: $0) }
        }
        
        // 计算最终图像尺寸
        var totalWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxWidth: CGFloat = 0
        var maxHeight: CGFloat = 0
        
        for image in images {
            let width = CGFloat(image.width)
            let height = CGFloat(image.height)
            maxWidth = max(maxWidth, width)
            maxHeight = max(maxHeight, height)
            
            if direction == .horizontal {
                totalWidth += width
                totalHeight = max(totalHeight, height)
            } else {
                totalHeight += height
                totalWidth = max(totalWidth, width)
            }
        }
        
        // 创建上下文
        UIGraphicsBeginImageContext(CGSize(width: totalWidth, height: totalHeight))
        defer { UIGraphicsEndImageContext() }
        
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        
        for (index, image) in images.enumerated() {
            if index == 0 {
                // 第一帧直接绘制
                let rect = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
                UIImage(cgImage: image).draw(in: rect)
                
                if direction == .horizontal {
                    currentX = CGFloat(image.width)
                } else {
                    currentY = CGFloat(image.height)
                }
            } else {
                // 计算与前一帧的重叠区域
                let previousImage = images[index - 1]
                let overlap = direction == .horizontal ? CGFloat(previousImage.width) * 0.35 : CGFloat(previousImage.height) * 0.35
                
                // 计算偏移量
                let offset = calculateOffsetBetween(previous: previousImage, current: image, direction: direction, overlap: overlap)
                
                // 绘制当前帧
                let rect:
                if direction == .horizontal {
                    rect = CGRect(x: currentX - offset.x, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
                    currentX += CGFloat(image.width) - offset.x
                } else {
                    rect = CGRect(x: 0, y: currentY - offset.y, width: CGFloat(image.width), height: CGFloat(image.height))
                    currentY += CGFloat(image.height) - offset.y
                }
                
                // 混合绘制
                blendImages(previous: previousImage, current: image, in: rect, direction: direction, overlap: overlap)
            }
        }
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    /// 计算两帧之间的偏移量
    private func calculateOffsetBetween(previous: CGImage, current: CGImage, direction: ScrollDirection, overlap: CGFloat) -> CGPoint {
        // 这里使用简化的模板匹配，实际项目中可以使用更复杂的算法
        return .zero
    }
    
    /// 混合两张图像
    private func blendImages(previous: CGImage, current: CGImage, in rect: CGRect, direction: ScrollDirection, overlap: CGFloat) {
        let context = UIGraphicsGetCurrentContext()
        guard let context = context else { return }
        
        // 绘制当前帧
        let currentImage = UIImage(cgImage: current)
        currentImage.draw(in: rect)
        
        // 绘制前一帧的重叠部分，使用渐变混合
        context.saveGState()
        
        var blendRect: CGRect
        var gradient: CGGradient
        
        if direction == .horizontal {
            blendRect = CGRect(x: rect.minX, y: rect.minY, width: overlap, height: rect.height)
            let colors = [UIColor.white.withAlphaComponent(1.0).cgColor, UIColor.white.withAlphaComponent(0.0).cgColor]
            gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            context.drawLinearGradient(gradient, start: CGPoint(x: blendRect.minX, y: blendRect.midY), end: CGPoint(x: blendRect.maxX, y: blendRect.midY), options: [])
        } else {
            blendRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: overlap)
            let colors = [UIColor.white.withAlphaComponent(1.0).cgColor, UIColor.white.withAlphaComponent(0.0).cgColor]
            gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            context.drawLinearGradient(gradient, start: CGPoint(x: blendRect.midX, y: blendRect.minY), end: CGPoint(x: blendRect.midX, y: blendRect.maxY), options: [])
        }
        
        context.setBlendMode(.destinationIn)
        let previousImage = UIImage(cgImage: previous)
        previousImage.draw(in: blendRect, blendMode: .normal, alpha: 1.0)
        
        context.restoreGState()
    }
}

/// 扩展：便捷方法
extension ScreenRecordingStitcher {
    /// 保存图像到相册
    func saveToPhotosAlbum(_ image: UIImage, completion: @escaping (Bool, Error?) -> Void) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        // 注意：实际项目中应该使用 Photos 框架并处理权限
        completion(true, nil)
    }
}

/// 使用示例
/*
let stitcher = ScreenRecordingStitcher()
let videoURL = URL(fileURLWithPath: "path/to/video.mp4")

stitcher.processVideo(videoURL: videoURL, direction: .vertical, progress: { progress in
    print("Progress: \(progress * 100)%")
}) { image in
    if let image = image {
        stitcher.saveToPhotosAlbum(image) { success, error in
            if success {
                print("Saved to photos album")
            } else {
                print("Error saving: \(error?.localizedDescription ?? "Unknown error")")
            }
        }
    } else {
        print("Failed to generate stitched image")
    }
}
*/