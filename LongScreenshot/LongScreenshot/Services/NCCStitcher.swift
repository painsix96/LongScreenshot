import UIKit
import Accelerate
import os.log

private let nccLogger = Logger(subsystem: "com.longscreenshot", category: "NCCStitcher")

struct CropMetadata {
    let originalSizeA: CGSize
    let originalSizeB: CGSize
    let uniformWidth: CGFloat
    let scale: CGFloat
    let cropRatio: CGFloat
    let downsampleScale: CGFloat
    let scaleRatioA: CGFloat
    let scaleRatioB: CGFloat
    let originalHeightA: Int
}

actor NCCStitcher {

    struct Config {
        var cropRatio: CGFloat = 0.25
        var downsampleScale: CGFloat = 0.5
        var minOffsetRatio: Double = 0.05
        var maxOffsetRatio: Double = 0.60
        var confidenceThreshold: Double = 0.85
        var stabilityGap: Double = 0.03
        var overlapSizes: [Int] = [25, 30, 40, 50] // 调整默认 overlap 尺寸，适合测试场景
        var maxShiftRatio: Double = 0.5
        var minVariance: Float = 10.0
    }

    var config = Config()

    // MARK: - 测试辅助方法

    func setOverlapSizes(_ sizes: [Int]) {
        config.overlapSizes = sizes
    }

    // MARK: - Step 2: 裁剪候选区域 + 预处理

    func cropAndPreprocess(imageA: UIImage, imageB: UIImage) -> (candidateA: CGImage, candidateB: CGImage, metadata: CropMetadata)? {
        guard let cgA = imageA.cgImage, let cgB = imageB.cgImage else {
            nccLogger.error("❌ 无法获取 CGImage")
            return nil
        }

        // 1. 统一宽度：取较小值，等比缩放（aspect fit），禁止裁剪
        let widthA = CGFloat(cgA.width)
        let widthB = CGFloat(cgB.width)
        let uniformWidth = min(widthA, widthB)

        let scaleRatioA = uniformWidth / widthA
        let scaleRatioB = uniformWidth / widthB

        let scaledWidthA = Int(uniformWidth)
        let scaledHeightA = Int(CGFloat(cgA.height) * scaleRatioA)
        let scaledWidthB = Int(uniformWidth)
        let scaledHeightB = Int(CGFloat(cgB.height) * scaleRatioB)

        nccLogger.info("📐 等比缩放: A(\(widthA)×\(CGFloat(cgA.height))) → (\(scaledWidthA)×\(scaledHeightA)), ratio=\(String(format: "%.3f", scaleRatioA))")
        nccLogger.info("📐 等比缩放: B(\(widthB)×\(CGFloat(cgB.height))) → (\(scaledWidthB)×\(scaledHeightB)), ratio=\(String(format: "%.3f", scaleRatioB))")

        guard let scaledA = scaleCGImage(cgA, toWidth: scaledWidthA, toHeight: scaledHeightA),
              let scaledB = scaleCGImage(cgB, toWidth: scaledWidthB, toHeight: scaledHeightB) else {
            nccLogger.error("❌ 等比缩放失败")
            return nil
        }

        // 2. 裁剪候选区域（百分比，在缩放后的图片上裁剪）
        let cropRatio = config.cropRatio
        let heightA = CGFloat(scaledA.height)
        let heightB = CGFloat(scaledB.height)

        let cropHeightA = heightA * cropRatio
        let cropRectA = CGRect(
            x: 0,
            y: heightA - cropHeightA,
            width: CGFloat(scaledA.width),
            height: cropHeightA
        )

        let cropHeightB = heightB * cropRatio
        let cropRectB = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(scaledB.width),
            height: cropHeightB
        )

        nccLogger.info("✂️ 裁剪候选区域: A底部\(Int(cropHeightA))px, B顶部\(Int(cropHeightB))px (比例=\(cropRatio))")

        guard let croppedA = scaledA.cropping(to: cropRectA),
              let croppedB = scaledB.cropping(to: cropRectB) else {
            nccLogger.error("❌ 裁剪候选区域失败")
            return nil
        }

        // 3. 降采样到 0.5
        let dsScale = config.downsampleScale
        let dsWidthA = Int(CGFloat(croppedA.width) * dsScale)
        let dsHeightA = Int(CGFloat(croppedA.height) * dsScale)
        let dsWidthB = Int(CGFloat(croppedB.width) * dsScale)
        let dsHeightB = Int(CGFloat(croppedB.height) * dsScale)

        guard let dsA = downsample(cgImage: croppedA, width: dsWidthA, height: dsHeightA),
              let dsB = downsample(cgImage: croppedB, width: dsWidthB, height: dsHeightB) else {
            nccLogger.error("❌ 降采样失败")
            return nil
        }

        nccLogger.info("📐 降采样: A(\(dsA.width)×\(dsA.height)), B(\(dsB.width)×\(dsB.height)) (scale=\(dsScale))")

        // 4. 转灰度
        guard let grayA = toGrayscale(dsA),
              let grayB = toGrayscale(dsB) else {
            nccLogger.error("❌ 转灰度失败")
            return nil
        }

        nccLogger.info("🌑 灰度转换完成: A(\(grayA.width)×\(grayA.height)), B(\(grayB.width)×\(grayB.height))")

        let metadata = CropMetadata(
            originalSizeA: imageA.size,
            originalSizeB: imageB.size,
            uniformWidth: uniformWidth,
            scale: imageA.scale,
            cropRatio: cropRatio,
            downsampleScale: dsScale,
            scaleRatioA: scaleRatioA,
            scaleRatioB: scaleRatioB,
            originalHeightA: cgA.height
        )

        return (grayA, grayB, metadata)
    }

    // MARK: - Step 3: 计算结果 + 稳定性判断

    func estimateVerticalOffset(candidateA: CGImage, candidateB: CGImage, originalHeightA: Int) -> (dy: Int, score: Double)? {
        let hA = candidateA.height
        let hB = candidateB.height
        let w = min(candidateA.width, candidateB.width)

        guard hA > 2, hB > 2, w > 0 else {
            nccLogger.error("❌ 候选区域尺寸无效: A(\(candidateA.width)×\(hA)), B(\(candidateB.width)×\(hB))")
            return nil
        }

        guard let pixelsA = extractGrayscalePixels(from: candidateA),
              let pixelsB = extractGrayscalePixels(from: candidateB) else {
            nccLogger.error("❌ 提取灰度像素失败")
            return nil
        }

        let gradA = computeGradient(pixels: pixelsA, width: w, height: hA, stride: candidateA.width)
        let gradB = computeGradient(pixels: pixelsB, width: w, height: hB, stride: candidateB.width)

        // dy 范围：5% ~ 60% original imageA.height（完全基于 originalHeightA）
        let minDy = max(0, Int(Double(originalHeightA) * 0.05))
        let maxDy = Int(Double(originalHeightA) * 0.60)

        guard minDy < maxDy else {
            nccLogger.error("❌ dy 范围无效: min=\(minDy), max=\(maxDy)")
            return nil
        }

        nccLogger.info("🔍 垂直位移估计: dy∈[\(minDy), \(maxDy)], originalHeightA=\(originalHeightA)")

        // patch 高度：优化为 min(200, min(hA, hB))
        let patchHeight = min(200, min(hA, hB))

        var bestDy = 0
        var bestScore = -Double.infinity
        var secondBestDy = 0
        var secondBestScore = -1.0 // 初始化为 -1

        for dy in minDy..<maxDy {
            let aStart = hA - patchHeight
            let bStart = dy

            let aEnd = aStart + patchHeight
            let bEnd = bStart + patchHeight

            // 只检查 bStart + patchHeight 是否越界
            if bStart + patchHeight > hB {
                continue
            }

            let n = patchHeight * w
            var sliceA = [Float](repeating: 0, count: n)
            var sliceB = [Float](repeating: 0, count: n)

            for row in 0..<patchHeight {
                let srcA = (aStart + row) * w
                let srcB = (bStart + row) * w
                let dst = row * w
                for col in 0..<w {
                    sliceA[dst + col] = gradA[srcA + col]
                    sliceB[dst + col] = gradB[srcB + col]
                }
            }

            var meanA: Float = 0, meanB: Float = 0
            vDSP_meanv(sliceA, 1, &meanA, vDSP_Length(n))
            vDSP_meanv(sliceB, 1, &meanB, vDSP_Length(n))

            var negMeanA = -meanA, negMeanB = -meanB
            var shiftedA = [Float](repeating: 0, count: n)
            var shiftedB = [Float](repeating: 0, count: n)
            vDSP_vsadd(sliceA, 1, &negMeanA, &shiftedA, 1, vDSP_Length(n))
            vDSP_vsadd(sliceB, 1, &negMeanB, &shiftedB, 1, vDSP_Length(n))

            var sqA: Float = 0, sqB: Float = 0
            vDSP_dotpr(shiftedA, 1, shiftedA, 1, &sqA, vDSP_Length(n))
            vDSP_dotpr(shiftedB, 1, shiftedB, 1, &sqB, vDSP_Length(n))

            let varA = sqA / Float(n)
            let varB = sqB / Float(n)

            guard varA >= self.config.minVariance, varB >= self.config.minVariance else {
                continue
            }

            var dot: Float = 0
            vDSP_dotpr(shiftedA, 1, shiftedB, 1, &dot, vDSP_Length(n))

            let denom = sqrt(sqA * sqB)
            guard denom > 0 else {
                continue
            }

            let score = Double(dot / denom)

            if score > bestScore {
                secondBestScore = bestScore
                secondBestDy = bestDy
                bestScore = score
                bestDy = dy
            } else if score > secondBestScore {
                secondBestScore = score
                secondBestDy = dy
            }
        }

        guard bestScore > -Double.infinity else {
            nccLogger.error("❌ 无有效匹配")
            return nil
        }

        // 即使 secondBestScore 无效，也返回最佳结果
        if secondBestScore < 0 {
            nccLogger.warning("⚠️ 无有效次优匹配")
        }

        nccLogger.info("✅ 垂直位移估计完成: dy=\(bestDy), score=\(String(format: "%.4f", bestScore)), secondBest=\(String(format: "%.4f", secondBestScore))")

        return (bestDy, bestScore)
    }

    // MARK: - Step 4: 拼接逻辑实现

    func stitch(imageA: UIImage, imageB: UIImage, dy: Int) -> UIImage? {
        guard let cgA = imageA.cgImage, let cgB = imageB.cgImage else {
            nccLogger.error("❌ 无法获取 CGImage")
            return nil
        }

        let widthA = cgA.width
        let heightA = cgA.height
        let widthB = cgB.width
        let heightB = cgB.height

        // 统一宽度：取较小值
        let width = min(widthA, widthB)

        // 计算 overlap 高度（使用原图空间的 dy）
        let overlapHeight = heightA - dy
        let clampedOverlap = max(0, min(overlapHeight, heightB))

        // 计算最终高度
        let totalHeight = heightA + (heightB - clampedOverlap)

        // 打印关键日志
        nccLogger.info("FINAL overlap: \(clampedOverlap)")
        nccLogger.info("FINAL dy: \(dy)")
        nccLogger.info("USE STITCH MODE")
        nccLogger.info("Image height: \(heightA)")
        nccLogger.info("Overlap ratio: \(String(format: "%.2f", Double(clampedOverlap) / Double(heightA)))")

        // 创建拼接上下文
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: totalHeight * bytesPerRow)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: totalHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            nccLogger.error("❌ CGContext 创建失败")
            return nil
        }

        // 调整 CGContext 坐标系（Core Graphics 原点在左下角）
        context.translateBy(x: 0, y: CGFloat(totalHeight))
        context.scaleBy(x: 1.0, y: -1.0)

        // 绘制 imageA（全部）
        context.draw(cgA, in: CGRect(x: 0, y: 0, width: width, height: heightA))

        // 绘制 imageB 的新增部分（从 clampedOverlap 开始）
        let bCropRect = CGRect(
            x: 0,
            y: clampedOverlap,
            width: width,
            height: heightB - clampedOverlap
        )
        guard let bCropped = cgB.cropping(to: bCropRect) else {
            nccLogger.error("❌ 裁剪 imageB 失败")
            return nil
        }

        context.draw(bCropped, in: CGRect(x: 0, y: heightA, width: width, height: bCropped.height))

        // 创建最终图片
        guard let stitchedCGImage = context.makeImage() else {
            nccLogger.error("❌ 拼接图片创建失败")
            return nil
        }

        let stitchedImage = UIImage(cgImage: stitchedCGImage, scale: imageA.scale, orientation: imageA.imageOrientation)
        nccLogger.info("✅ 图片拼接完成: 尺寸=\(stitchedImage.size.width)×\(stitchedImage.size.height)")

        return stitchedImage
    }

    // MARK: - 提取灰度像素数据

    private func extractGrayscalePixels(from cgImage: CGImage) -> [UInt8]? {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        if cgImage.colorSpace?.model == .monochrome,
           cgImage.bitsPerPixel == 8,
           cgImage.bitsPerComponent == 8 {
            guard let dataProvider = cgImage.dataProvider,
                  let data = dataProvider.data,
                  let ptr = CFDataGetBytePtr(data) else { return nil }

            let bytesPerRow = cgImage.bytesPerRow
            let totalBytes = bytesPerRow * height
            guard CFDataGetLength(data) >= totalBytes else { return nil }

            if bytesPerRow == width {
                return Array(UnsafeBufferPointer(start: ptr, count: width * height))
            }

            var pixels = [UInt8](repeating: 0, count: width * height)
            for row in 0..<height {
                let srcOffset = row * bytesPerRow
                let dstOffset = row * width
                for col in 0..<width {
                    pixels[dstOffset + col] = ptr[srcOffset + col]
                }
            }
            return pixels
        }

        let bytesPerRow = width
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            nccLogger.error("❌ CGContext 创建失败: \(cgImage.width)×\(height), colorSpace=\(cgImage.colorSpace?.model.rawValue ?? -1)")
            return nil
        }

        context.interpolationQuality = .none
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        return pixels
    }

    // MARK: - 计算垂直梯度（梯度增强 NCC）

    private func computeGradient(pixels: [UInt8], width: Int, height: Int, stride: Int) -> [Float] {
        var gradient = [Float](repeating: 0, count: width * height)
        for y in 0..<(height - 1) {
            for x in 0..<width {
                let idx = y * stride + x
                let nextIdx = (y + 1) * stride + x
                gradient[y * width + x] = Float(Int(pixels[nextIdx]) - Int(pixels[idx]))
            }
        }
        return gradient
    }

    // MARK: - 等比缩放（aspect fit）

    private func scaleCGImage(_ cgImage: CGImage, toWidth width: Int, toHeight height: Int) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return context.makeImage()
    }

    // MARK: - 降采样

    private func downsample(cgImage: CGImage, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return context.makeImage()
    }

    // MARK: - 转灰度

    private func toGrayscale(_ cgImage: CGImage) -> CGImage? {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width

        var grayPixels = [UInt8](repeating: 0, count: width * height)

        guard let context = CGContext(
            data: &grayPixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return context.makeImage()
    }

    // MARK: - Step 5: 多图拼接流程

    func stitchImages(_ images: [UIImage]) -> UIImage? {
        guard !images.isEmpty else {
            nccLogger.error("❌ 图片数组为空")
            return nil
        }

        if images.count == 1 {
            nccLogger.info("✅ 只有一张图片，直接返回")
            return images[0]
        }

        nccLogger.info("🔍 开始多图拼接，共 \(images.count) 张图片")

        var currentResult = images[0]

        for i in 1..<images.count {
            let imageA = currentResult
            let imageB = images[i]

            nccLogger.info("🔄 拼接第 \(i) 张图片")

            // 第一步：裁剪 + 预处理
            guard let (candidateA, candidateB, metadata) = cropAndPreprocess(imageA: imageA, imageB: imageB) else {
                nccLogger.error("❌ 预处理失败，停止拼接")
                return currentResult // fallback：返回当前结果
            }

            // 第二步：NCC 滑动匹配
            guard let (dy, score) = estimateVerticalOffset(
                candidateA: candidateA,
                candidateB: candidateB,
                originalHeightA: metadata.originalHeightA
            ) else {
                nccLogger.error("❌ 垂直位移估计失败，停止拼接")
                return currentResult // fallback：返回当前结果
            }

            nccLogger.info("📐 估计垂直位移: dy=\(dy), score=\(String(format: "%.4f", score))")

            // 第三步：拼接
            guard let stitched = stitch(imageA: imageA, imageB: imageB, dy: dy) else {
                nccLogger.error("❌ 拼接失败，停止拼接")
                return currentResult // fallback：返回当前结果
            }

            currentResult = stitched
        }

        nccLogger.info("✅ 多图拼接完成: 尺寸=\(currentResult.size.width)×\(currentResult.size.height)")
        return currentResult
    }
}
