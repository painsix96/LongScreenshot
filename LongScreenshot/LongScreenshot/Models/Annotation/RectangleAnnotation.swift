import SwiftUI

// MARK: - 矩形标注样式
enum RectangleStyle: String, CaseIterable {
    case fill = "填充"
    case stroke = "描边"
    case dashed = "虚线"
    
    var icon: String {
        switch self {
        case .fill: return "rectangle.fill"
        case .stroke: return "rectangle"
        case .dashed: return "rectangle.dashed"
        }
    }
}

// MARK: - 矩形标注
struct RectangleAnnotation: Annotation, Equatable {
    let id: UUID
    let type: AnnotationType = .rectangle
    var color: Color
    var lineWidth: CGFloat
    var isSelected: Bool = false
    let createdAt: Date
    
    var rect: CGRect
    var style: RectangleStyle = .stroke
    var cornerRadius: CGFloat = 4.0
    var fillOpacity: CGFloat = 0.3
    
    init(
        id: UUID = UUID(),
        color: Color,
        lineWidth: CGFloat,
        rect: CGRect,
        style: RectangleStyle = .stroke,
        cornerRadius: CGFloat = 4.0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.color = color
        self.lineWidth = lineWidth
        self.rect = rect
        self.style = style
        self.cornerRadius = cornerRadius
        self.createdAt = createdAt
    }
    
    // MARK: - Annotation Protocol
    func draw(in context: GraphicsContext, size: CGSize) {
        // 确保矩形有效
        let normalizedRect = normalizeRect(rect)
        guard normalizedRect.width > 0 && normalizedRect.height > 0 else { return }
        
        let path = createRoundedRectPath(in: normalizedRect)
        
        switch style {
        case .fill:
            context.fill(
                Path(path),
                with: .color(color.opacity(fillOpacity))
            )
            context.stroke(
                Path(path),
                with: .color(color),
                style: StrokeStyle(lineWidth: lineWidth)
            )
            
        case .stroke:
            context.stroke(
                Path(path),
                with: .color(color),
                style: StrokeStyle(
                    lineWidth: lineWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            
        case .dashed:
            context.stroke(
                Path(path),
                with: .color(color),
                style: StrokeStyle(
                    lineWidth: lineWidth,
                    lineCap: .round,
                    lineJoin: .round,
                    dash: [8, 4]
                )
            )
        }
        
        // 选中状态显示控制点
        if isSelected {
            drawControlPoints(in: context, rect: normalizedRect)
        }
    }
    
    func contains(point: CGPoint) -> Bool {
        let normalizedRect = normalizeRect(rect)
        let tolerance: CGFloat = max(lineWidth, 10.0)
        
        switch style {
        case .fill:
            return normalizedRect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .stroke, .dashed:
            // 对于描边样式，检查是否在边框附近
            let innerRect = normalizedRect.insetBy(dx: lineWidth + tolerance, dy: lineWidth + tolerance)
            let outerRect = normalizedRect.insetBy(dx: -tolerance, dy: -tolerance)
            return outerRect.contains(point) && !innerRect.contains(point)
        }
    }
    
    mutating func move(by offset: CGSize) {
        rect = CGRect(
            x: rect.origin.x + offset.width,
            y: rect.origin.y + offset.height,
            width: rect.width,
            height: rect.height
        )
    }
    
    // MARK: - 控制点操作
    mutating func resize(to newRect: CGRect) {
        rect = newRect
    }
    
    func getControlPoint(at location: ControlPointLocation) -> CGPoint {
        let normalizedRect = normalizeRect(rect)
        
        switch location {
        case .topLeft:
            return CGPoint(x: normalizedRect.minX, y: normalizedRect.minY)
        case .topCenter:
            return CGPoint(x: normalizedRect.midX, y: normalizedRect.minY)
        case .topRight:
            return CGPoint(x: normalizedRect.maxX, y: normalizedRect.minY)
        case .middleLeft:
            return CGPoint(x: normalizedRect.minX, y: normalizedRect.midY)
        case .middleRight:
            return CGPoint(x: normalizedRect.maxX, y: normalizedRect.midY)
        case .bottomLeft:
            return CGPoint(x: normalizedRect.minX, y: normalizedRect.maxY)
        case .bottomCenter:
            return CGPoint(x: normalizedRect.midX, y: normalizedRect.maxY)
        case .bottomRight:
            return CGPoint(x: normalizedRect.maxX, y: normalizedRect.maxY)
        }
    }
    
    func hitTestControlPoint(_ point: CGPoint, tolerance: CGFloat = 15.0) -> ControlPointLocation? {
        for location in ControlPointLocation.allCases {
            let controlPoint = getControlPoint(at: location)
            if controlPoint.distance(to: point) <= tolerance {
                return location
            }
        }
        return nil
    }
    
    // MARK: - 私有方法
    private func createRoundedRectPath(in rect: CGRect) -> CGMutablePath {
        let path = CGMutablePath()
        
        if cornerRadius > 0 {
            path.addRoundedRect(
                in: rect,
                cornerWidth: cornerRadius,
                cornerHeight: cornerRadius
            )
        } else {
            path.addRect(rect)
        }
        
        return path
    }
    
    private func normalizeRect(_ rect: CGRect) -> CGRect {
        var normalized = rect
        
        // 确保 width 为正
        if normalized.width < 0 {
            normalized.origin.x += normalized.width
            normalized.size.width = -normalized.width
        }
        
        // 确保 height 为正
        if normalized.height < 0 {
            normalized.origin.y += normalized.height
            normalized.size.height = -normalized.height
        }
        
        return normalized
    }
    
    private func drawControlPoints(in context: GraphicsContext, rect: CGRect) {
        let controlPointRadius: CGFloat = 5.0
        let controlPointColor = Color.blue.opacity(0.8)
        
        for location in ControlPointLocation.allCases {
            let point = getControlPoint(at: location)
            let controlRect = CGRect(
                x: point.x - controlPointRadius,
                y: point.y - controlPointRadius,
                width: controlPointRadius * 2,
                height: controlPointRadius * 2
            )
            context.fill(
                Path(ellipseIn: controlRect),
                with: .color(controlPointColor)
            )
        }
    }
    
    // MARK: - 控制点位置枚举
    enum ControlPointLocation: CaseIterable {
        case topLeft
        case topCenter
        case topRight
        case middleLeft
        case middleRight
        case bottomLeft
        case bottomCenter
        case bottomRight
    }
}

// MARK: - 静态方法
extension RectangleAnnotation {
    static func == (lhs: RectangleAnnotation, rhs: RectangleAnnotation) -> Bool {
        lhs.id == rhs.id
    }
}
