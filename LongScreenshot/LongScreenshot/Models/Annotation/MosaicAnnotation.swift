import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - 马赛克类型
enum MosaicType: String, CaseIterable {
    case pixelate = "像素化"
    case blur = "模糊"
    case hexagonal = "六边形"
    
    var icon: String {
        switch self {
        case .pixelate: return "grid.3x3"
        case .blur: return "circle.dotted"
        case .hexagonal: return "hexagon.fill"
        }
    }
}

// MARK: - 马赛克标注
struct MosaicAnnotation: Annotation, Equatable {
    let id: UUID
    let type: AnnotationType = .mosaic
    var color: Color = .clear  // 马赛克不使用颜色
    var lineWidth: CGFloat  // 用于块大小
    var isSelected: Bool = false
    let createdAt: Date
    
    var rect: CGRect
    var mosaicType: MosaicType = .pixelate
    var intensity: CGFloat = 0.5  // 马赛克强度 0.0 - 1.0
    
    // 缓存处理后的图像
    private var processedImage: UIImage?
    
    init(
        id: UUID = UUID(),
        blockSize: CGFloat,
        rect: CGRect,
        mosaicType: MosaicType = .pixelate,
        intensity: CGFloat = 0.5,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.lineWidth = blockSize
        self.rect = rect
        self.mosaicType = mosaicType
        self.intensity = intensity
        self.createdAt = createdAt
    }
    
    // MARK: - Annotation Protocol
    func draw(in context: GraphicsContext, size: CGSize) {
        let normalizedRect = normalizeRect(rect)
        guard normalizedRect.width > 0 && normalizedRect.height > 0 else { return }
        
        // 绘制马赛克效果
        switch mosaicType {
        case .pixelate:
            drawPixelateEffect(in: context, rect: normalizedRect)
        case .blur:
            drawBlurEffect(in: context, rect: normalizedRect)
        case .hexagonal:
            drawHexagonalEffect(in: context, rect: normalizedRect)
        }
        
        // 选中状态显示边框
        if isSelected {
            drawSelectionIndicator(in: context, rect: normalizedRect)
        }
    }
    
    func contains(point: CGPoint) -> Bool {
        let normalizedRect = normalizeRect(rect)
        return normalizedRect.contains(point, tolerance: 10.0)
    }
    
    mutating func move(by offset: CGSize) {
        rect = CGRect(
            x: rect.origin.x + offset.width,
            y: rect.origin.y + offset.height,
            width: rect.width,
            height: rect.height
        )
    }
    
    // MARK: - 编辑操作
    mutating func resize(to newRect: CGRect) {
        rect = newRect
        processedImage = nil  // 清除缓存
    }
    
    mutating func updateBlockSize(_ size: CGFloat) {
        lineWidth = max(5, min(50, size))
        processedImage = nil
    }
    
    // MARK: - 私有方法
    private func drawPixelateEffect(in context: GraphicsContext, rect: CGRect) {
        // 绘制像素化效果
        let blockSize = lineWidth
        let cols = Int(ceil(rect.width / blockSize))
        let rows = Int(ceil(rect.height / blockSize))
        
        // 创建马赛克图案
        for row in 0..<rows {
            for col in 0..<cols {
                let blockRect = CGRect(
                    x: rect.minX + CGFloat(col) * blockSize,
                    y: rect.minY + CGFloat(row) * blockSize,
                    width: min(blockSize, rect.maxX - (rect.minX + CGFloat(col) * blockSize)),
                    height: min(blockSize, rect.maxY - (rect.minY + CGFloat(row) * blockSize))
                )
                
                // 绘制方块
                context.fill(
                    Path(CGRect(origin: blockRect.origin, size: blockRect.size)),
                    with: .color(.gray.opacity(0.3 + CGFloat.random(in: 0...0.2)))
                )
                
                // 绘制网格线
                context.stroke(
                    Path(CGRect(origin: blockRect.origin, size: blockRect.size)),
                    with: .color(.gray.opacity(0.4)),
                    style: StrokeStyle(lineWidth: 0.5)
                )
            }
        }
        
        // 绘制叠加层
        context.fill(
            Path(rect),
            with: .color(.black.opacity(intensity * 0.3))
        )
    }
    
    private func drawBlurEffect(in context: GraphicsContext, rect: CGRect) {
        // 绘制模糊效果表示
        // 使用渐变模拟模糊效果
        let gradient = Gradient(
            colors: [
                .gray.opacity(0.4),
                .gray.opacity(0.6),
                .gray.opacity(0.4)
            ]
        )
        
        context.fill(
            Path(rect),
            with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: rect.minX, y: rect.minY),
                endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
            )
        )
        
        // 绘制圆点图案表示模糊
        let dotSize: CGFloat = lineWidth / 2
        let spacing = lineWidth * 1.5
        
        for y in stride(from: rect.minY + spacing/2, to: rect.maxY, by: spacing) {
            for x in stride(from: rect.minX + spacing/2, to: rect.maxX, by: spacing) {
                let dotRect = CGRect(
                    x: x - dotSize/2,
                    y: y - dotSize/2,
                    width: dotSize,
                    height: dotSize
                )
                context.fill(
                    Path(ellipseIn: dotRect),
                    with: .color(.gray.opacity(0.5 + CGFloat.random(in: 0...0.3)))
                )
            }
        }
    }
    
    private func drawHexagonalEffect(in context: GraphicsContext, rect: CGRect) {
        // 绘制六边形马赛克效果
        let hexSize = lineWidth
        let hexWidth = hexSize * sqrt(3)
        let hexHeight = hexSize * 2
        
        let cols = Int(ceil(rect.width / (hexWidth * 0.75)))
        let rows = Int(ceil(rect.height / hexHeight)) + 1
        
        for row in 0..<rows {
            for col in 0..<cols {
                let xOffset = (row % 2 == 0) ? 0 : hexWidth * 0.375
                let center = CGPoint(
                    x: rect.minX + CGFloat(col) * hexWidth * 0.75 + xOffset,
                    y: rect.minY + CGFloat(row) * hexHeight * 0.75 + hexHeight/2
                )
                
                let hexPath = createHexagonPath(center: center, size: hexSize/2)
                
                context.fill(
                    Path(hexPath),
                    with: .color(.gray.opacity(0.3 + CGFloat.random(in: 0...0.3)))
                )
                
                context.stroke(
                    Path(hexPath),
                    with: .color(.gray.opacity(0.5)),
                    style: StrokeStyle(lineWidth: 0.5)
                )
            }
        }
        
        // 叠加层
        context.fill(
            Path(rect),
            with: .color(.black.opacity(intensity * 0.2))
        )
    }
    
    private func createHexagonPath(center: CGPoint, size: CGFloat) -> CGMutablePath {
        let path = CGMutablePath()
        
        for i in 0..<6 {
            let angle = Double(i) * .pi / 3
            let x = center.x + size * CGFloat(cos(angle))
            let y = center.y + size * CGFloat(sin(angle))
            
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        path.closeSubpath()
        return path
    }
    
    private func drawSelectionIndicator(in context: GraphicsContext, rect: CGRect) {
        context.stroke(
            Path(rect),
            with: .color(.blue.opacity(0.6)),
            style: StrokeStyle(
                lineWidth: 2,
                dash: [5, 5]
            )
        )
        
        // 绘制控制点
        let controlPoints = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ]
        
        for point in controlPoints {
            let controlRect = CGRect(
                x: point.x - 4,
                y: point.y - 4,
                width: 8,
                height: 8
            )
            context.fill(
                Path(ellipseIn: controlRect),
                with: .color(.blue)
            )
        }
    }
    
    private func normalizeRect(_ rect: CGRect) -> CGRect {
        var normalized = rect
        
        if normalized.width < 0 {
            normalized.origin.x += normalized.width
            normalized.size.width = -normalized.width
        }
        
        if normalized.height < 0 {
            normalized.origin.y += normalized.height
            normalized.size.height = -normalized.height
        }
        
        return normalized
    }
    
    // MARK: - 图像处理（用于实际应用马赛克）
    func applyMosaic(to image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        let ciImage = CIImage(cgImage: cgImage)
        let context = CIContext()
        
        switch mosaicType {
        case .pixelate:
            return applyPixelate(to: ciImage, in: rect, context: context)
        case .blur:
            return applyBlur(to: ciImage, in: rect, context: context)
        case .hexagonal:
            return applyPixelate(to: ciImage, in: rect, context: context)  // 回退到像素化
        }
    }
    
    private func applyPixelate(to ciImage: CIImage, in rect: CGRect, context: CIContext) -> UIImage? {
        let filter = CIFilter.pixellate()
        filter.inputImage = ciImage
        filter.scale = Float(lineWidth)
        
        guard let outputImage = filter.outputImage,
              let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    private func applyBlur(to ciImage: CIImage, in rect: CGRect, context: CIContext) -> UIImage? {
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = ciImage
        filter.radius = Float(lineWidth)
        
        guard let outputImage = filter.outputImage,
              let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - 静态方法
extension MosaicAnnotation {
    static func == (lhs: MosaicAnnotation, rhs: MosaicAnnotation) -> Bool {
        lhs.id == rhs.id
    }
}
