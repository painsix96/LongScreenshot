import XCTest
import UIKit
@testable import LongScreenshot

enum TestImageFactory {

    static func makeTestImage(
        width: Int = 1000,
        height: Int = 2000,
        scale: CGFloat = 1.0,
        bottomMark: Bool = false,
        topMark: Bool = false,
        bottomText: String? = nil,
        topText: String? = nil
    ) -> UIImage {
        let size = CGSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let cgContext = context.cgContext
            cgContext.setLineWidth(2.0)
            for y in stride(from: 100, to: height, by: 100) {
                let yScaled = CGFloat(y) / scale
                cgContext.move(to: CGPoint(x: 0, y: yScaled))
                cgContext.addLine(to: CGPoint(x: size.width, y: yScaled))
            }
            cgContext.strokePath()
            if bottomMark {
                let h = size.height * 0.05
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: size.height - h, width: size.width, height: h))
            }
            if topMark {
                let h = size.height * 0.05
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: 0, width: size.width, height: h))
            }
            if let txt = bottomText {
                let fs: CGFloat = 40 / scale
                let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: fs, weight: .bold), .foregroundColor: UIColor.blue]
                let th = fs * 1.5
                let y = size.height - size.height * 0.25 + (size.height * 0.25 - th) / 2
                (txt as NSString).draw(in: CGRect(x: 0, y: y, width: size.width, height: th), withAttributes: attrs)
            }
            if let txt = topText {
                let fs: CGFloat = 40 / scale
                let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: fs, weight: .bold), .foregroundColor: UIColor.blue]
                let th = fs * 1.5
                let y = (size.height * 0.25 - th) / 2
                (txt as NSString).draw(in: CGRect(x: 0, y: y, width: size.width, height: th), withAttributes: attrs)
            }
        }
    }

    /// 生成上下半区不同灰度的图片
    /// topGray: 上半区灰度值 (0=黑, 255=白)
    /// bottomGray: 下半区灰度值
    /// splitRatio: 分割位置（默认0.5，即中间）
    static func makeSplitImage(
        width: Int = 1000,
        height: Int = 2000,
        topGray: UInt8 = 255,
        bottomGray: UInt8 = 50,
        splitRatio: CGFloat = 0.5
    ) -> UIImage {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            let splitY = Int(CGFloat(height) * splitRatio)
            let topColor = UIColor(white: CGFloat(topGray) / 255.0, alpha: 1.0)
            let bottomColor = UIColor(white: CGFloat(bottomGray) / 255.0, alpha: 1.0)
            topColor.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: splitY))
            bottomColor.setFill()
            context.fill(CGRect(x: 0, y: splitY, width: width, height: height - splitY))
        }
    }

    /// 生成行号编码图：每行像素灰度值 = min(row % 256, 255)
    /// 可用于验证裁剪位置是否正确
    static func makeRowEncodedImage(width: Int = 1000, height: Int = 2000) -> UIImage {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            let cgContext = context.cgContext
            for row in 0..<height {
                let gray = min(row % 256, 255)
                let color = UIColor(white: CGFloat(gray) / 255.0, alpha: 1.0)
                color.setFill()
                cgContext.fill(CGRect(x: 0, y: row, width: width, height: 1))
            }
        }
    }

    /// 生成左右分色图：左半一种灰度，右半另一种灰度
    /// 可用于验证宽度统一时是否裁掉了右侧内容
    static func makeLeftRightSplitImage(
        width: Int = 1000,
        height: Int = 2000,
        leftGray: UInt8 = 50,
        rightGray: UInt8 = 255
    ) -> UIImage {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            let halfW = width / 2
            let leftColor = UIColor(white: CGFloat(leftGray) / 255.0, alpha: 1.0)
            let rightColor = UIColor(white: CGFloat(rightGray) / 255.0, alpha: 1.0)
            leftColor.setFill()
            context.fill(CGRect(x: 0, y: 0, width: halfW, height: height))
            rightColor.setFill()
            context.fill(CGRect(x: halfW, y: 0, width: width - halfW, height: height))
        }
    }

    /// 生成随机块结构图：将图片分成 blockSize×blockSize 的网格，
    /// 每个块随机填充不同灰度，模拟真实内容的复杂纹理
    static func makeRandomBlockImage(
        width: Int = 1000,
        height: Int = 2000,
        blockSize: Int = 50,
        seed: UInt64 = 42
    ) -> UIImage {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            var rng = seed
            let cgContext = context.cgContext
            UIColor.white.setFill()
            cgContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
            for by in stride(from: 0, to: height, by: blockSize) {
                for bx in stride(from: 0, to: width, by: blockSize) {
                    rng = rng &* 6364136223846793005 &+ 1442695040888963407
                    let gray = UInt8((rng >> 33) % 256)
                    let color = UIColor(white: CGFloat(gray) / 255.0, alpha: 1.0)
                    color.setFill()
                    let bw = min(blockSize, width - bx)
                    let bh = min(blockSize, height - by)
                    cgContext.fill(CGRect(x: bx, y: by, width: bw, height: bh))
                }
            }
        }
    }

    /// 生成带左右边缘标记的图：最左 N 列和最右 N 列用特定灰度
    /// 可用于验证边缘内容是否被保留
    static func makeEdgeMarkedImage(
        width: Int = 1000,
        height: Int = 2000,
        edgeWidth: Int = 20,
        edgeGray: UInt8 = 30,
        centerGray: UInt8 = 200
    ) -> UIImage {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            let centerColor = UIColor(white: CGFloat(centerGray) / 255.0, alpha: 1.0)
            let edgeColor = UIColor(white: CGFloat(edgeGray) / 255.0, alpha: 1.0)
            centerColor.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            edgeColor.setFill()
            context.fill(CGRect(x: 0, y: 0, width: edgeWidth, height: height))
            context.fill(CGRect(x: width - edgeWidth, y: 0, width: edgeWidth, height: height))
        }
    }

    // MARK: - 像素读取

    static func grayscaleValue(in cgImage: CGImage, at point: CGPoint) -> UInt8? {
        let x = Int(point.x), y = Int(point.y)
        guard x >= 0, x < cgImage.width, y >= 0, y < cgImage.height else { return nil }
        var pixel = [UInt8](repeating: 0, count: 1)
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 1, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: -x, y: -y, width: cgImage.width, height: cgImage.height))
        return pixel[0]
    }

    static func hasDarkRegion(of cgImage: CGImage, yRange: ClosedRange<Int>, threshold: UInt8 = 200) -> Bool {
        let step = max(1, cgImage.width / 20)
        for y in stride(from: yRange.lowerBound, through: yRange.upperBound, by: step) {
            for x in stride(from: 0, through: cgImage.width - 1, by: step) {
                if let v = grayscaleValue(in: cgImage, at: CGPoint(x: x, y: y)), v < threshold {
                    return true
                }
            }
        }
        return false
    }

    /// 计算指定区域内的平均灰度值
    static func averageGrayscale(of cgImage: CGImage, yRange: ClosedRange<Int>) -> Double? {
        var sum: Double = 0
        var count: Double = 0
        let step = max(1, cgImage.width / 10)
        for y in stride(from: yRange.lowerBound, through: yRange.upperBound, by: step) {
            for x in stride(from: 0, through: cgImage.width - 1, by: step) {
                if let v = grayscaleValue(in: cgImage, at: CGPoint(x: x, y: y)) {
                    sum += Double(v)
                    count += 1
                }
            }
        }
        return count > 0 ? sum / count : nil
    }

    /// 检测指定区域是否全部为亮色（接近白色）
    static func isBrightRegion(of cgImage: CGImage, yRange: ClosedRange<Int>, threshold: UInt8 = 240) -> Bool {
        let step = max(1, cgImage.width / 10)
        for y in stride(from: yRange.lowerBound, through: yRange.upperBound, by: step) {
            for x in stride(from: 0, through: cgImage.width - 1, by: step) {
                if let v = grayscaleValue(in: cgImage, at: CGPoint(x: x, y: y)), v < threshold {
                    return false
                }
            }
        }
        return true
    }

    /// 检测指定区域是否全部为暗色
    static func isDarkRegion(of cgImage: CGImage, yRange: ClosedRange<Int>, threshold: UInt8 = 100) -> Bool {
        let step = max(1, cgImage.width / 10)
        for y in stride(from: yRange.lowerBound, through: yRange.upperBound, by: step) {
            for x in stride(from: 0, through: cgImage.width - 1, by: step) {
                if let v = grayscaleValue(in: cgImage, at: CGPoint(x: x, y: y)), v > threshold {
                    return false
                }
            }
        }
        return true
    }

    static func createGrayscaleCGImage(width: Int, height: Int, pixels: [UInt8]) -> CGImage? {
        guard pixels.count == width * height else { return nil }
        var mutablePixels = pixels
        guard let context = CGContext(
            data: &mutablePixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        return context.makeImage()
    }

    static func makeOverlappingCandidates(
        width: Int = 100,
        height: Int = 50,
        overlap: Int = 20
    ) -> (candidateA: CGImage, candidateB: CGImage)? {
        guard overlap > 0, overlap < height else { return nil }

        var pixelsA = [UInt8](repeating: 0, count: width * height)
        var pixelsB = [UInt8](repeating: 0, count: width * height)

        for row in 0..<(height - overlap) {
            for col in 0..<width {
                pixelsA[row * width + col] = UInt8((row * 7 + col * 3) % 200 + 30)
            }
        }

        for row in overlap..<height {
            for col in 0..<width {
                pixelsB[row * width + col] = UInt8((row * 11 + col * 5 + 100) % 200 + 30)
            }
        }

        for i in 0..<overlap {
            for col in 0..<width {
                let val = UInt8((i * 13 + col * 17 + 50) % 200 + 30)
                pixelsA[(height - overlap + i) * width + col] = val
                pixelsB[i * width + col] = val
            }
        }

        guard let cgA = createGrayscaleCGImage(width: width, height: height, pixels: pixelsA),
              let cgB = createGrayscaleCGImage(width: width, height: height, pixels: pixelsB) else {
            return nil
        }

        return (cgA, cgB)
    }

    static func makeFakeMetadata(
        originalHeightA: CGFloat = 200,
        originalHeightB: CGFloat = 200,
        uniformWidth: CGFloat = 100,
        scale: CGFloat = 1.0,
        cropRatio: CGFloat = 0.25,
        downsampleScale: CGFloat = 0.5,
        scaleRatioA: CGFloat = 1.0,
        scaleRatioB: CGFloat = 1.0
    ) -> CropMetadata {
        return CropMetadata(
            originalSizeA: CGSize(width: uniformWidth / scaleRatioA, height: originalHeightA),
            originalSizeB: CGSize(width: uniformWidth / scaleRatioB, height: originalHeightB),
            uniformWidth: uniformWidth,
            scale: scale,
            cropRatio: cropRatio,
            downsampleScale: downsampleScale,
            scaleRatioA: scaleRatioA,
            scaleRatioB: scaleRatioB,
            originalHeightA: Int(originalHeightA)
        )
    }

    static func makeSlideMatchTestPair(
        width: Int = 100,
        height: Int = 50,
        overlapRatio: Double = 0.6,
        dy: Int = 0
    ) -> (candidateA: CGImage, candidateB: CGImage)? {
        let overlap = max(4, Int(Double(height) * overlapRatio))

        var pixelsA = [UInt8](repeating: 0, count: width * height)
        var pixelsB = [UInt8](repeating: 0, count: width * height)

        var rngA: UInt64 = 12345
        var rngB: UInt64 = 67890
        for row in 0..<height {
            for col in 0..<width {
                rngA = rngA &* 6364136223846793005 &+ 1442695040888963407
                pixelsA[row * width + col] = UInt8((rngA >> 40) % 200 + 30)
                rngB = rngB &* 6364136223846793005 &+ 1442695040888963407
                pixelsB[row * width + col] = UInt8((rngB >> 40) % 200 + 30)
            }
        }

        let aStart: Int, bStart: Int
        if dy >= 0 {
            aStart = height - overlap - dy
            bStart = 0
        } else {
            aStart = height - overlap
            bStart = -dy
        }

        let aEnd = aStart + overlap
        let bEnd = bStart + overlap

        guard aStart >= 0, aEnd <= height, bStart >= 0, bEnd <= height else { return nil }

        for i in 0..<overlap {
            for col in 0..<width {
                let val = UInt8((i * 37 + col * 71 + 13) % 221 + 17)
                pixelsA[(aStart + i) * width + col] = val
                pixelsB[(bStart + i) * width + col] = val
            }
        }

        guard let cgA = createGrayscaleCGImage(width: width, height: height, pixels: pixelsA),
              let cgB = createGrayscaleCGImage(width: width, height: height, pixels: pixelsB) else {
            return nil
        }

        return (cgA, cgB)
    }

    static func makeNoisySlideMatchTestPair(
        width: Int = 100,
        height: Int = 50,
        overlapRatio: Double = 0.6,
        dy: Int = 0,
        noiseLevel: Int = 5,
        seed: UInt64 = 42
    ) -> (candidateA: CGImage, candidateB: CGImage)? {
        let overlap = max(4, Int(Double(height) * overlapRatio))

        var pixelsA = [UInt8](repeating: 0, count: width * height)
        var pixelsB = [UInt8](repeating: 0, count: width * height)

        var rngA: UInt64 = 12345
        var rngB: UInt64 = 67890
        for row in 0..<height {
            for col in 0..<width {
                rngA = rngA &* 6364136223846793005 &+ 1442695040888963407
                pixelsA[row * width + col] = UInt8((rngA >> 40) % 200 + 30)
                rngB = rngB &* 6364136223846793005 &+ 1442695040888963407
                pixelsB[row * width + col] = UInt8((rngB >> 40) % 200 + 30)
            }
        }

        let aStart: Int, bStart: Int
        if dy >= 0 {
            aStart = height - overlap - dy
            bStart = 0
        } else {
            aStart = height - overlap
            bStart = -dy
        }

        let aEnd = aStart + overlap
        let bEnd = bStart + overlap

        guard aStart >= 0, aEnd <= height, bStart >= 0, bEnd <= height else { return nil }

        var rng = seed
        for i in 0..<overlap {
            for col in 0..<width {
                let baseVal = Int((i * 13 + col * 17 + 50) % 200 + 30)

                rng = rng &* 6364136223846793005 &+ 1442695040888963407
                let noiseA = Int((rng >> 33) % UInt64(2 * noiseLevel + 1)) - noiseLevel
                let valA = max(0, min(255, baseVal + noiseA))

                rng = rng &* 6364136223846793005 &+ 1442695040888963407
                let noiseB = Int((rng >> 33) % UInt64(2 * noiseLevel + 1)) - noiseLevel
                let valB = max(0, min(255, baseVal + noiseB))

                pixelsA[(aStart + i) * width + col] = UInt8(valA)
                pixelsB[(bStart + i) * width + col] = UInt8(valB)
            }
        }

        guard let cgA = createGrayscaleCGImage(width: width, height: height, pixels: pixelsA),
              let cgB = createGrayscaleCGImage(width: width, height: height, pixels: pixelsB) else {
            return nil
        }

        return (cgA, cgB)
    }

    static func makeLinearGradientCGImage(
        width: Int = 100,
        height: Int = 50,
        startGray: UInt8 = 0,
        endGray: UInt8 = 255
    ) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            let gray = Int(startGray) + (Int(endGray) - Int(startGray)) * row / max(height - 1, 1)
            for col in 0..<width {
                pixels[row * width + col] = UInt8(max(0, min(255, gray)))
            }
        }
        return createGrayscaleCGImage(width: width, height: height, pixels: pixels)
    }
}
