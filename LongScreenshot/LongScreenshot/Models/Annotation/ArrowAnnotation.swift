import SwiftUI

// MARK: - 箭头标注
struct ArrowAnnotation: Annotation, Equatable {
    let id: UUID
    let type: AnnotationType = .arrow
    var color: Color
    var lineWidth: CGFloat
    var isSelected: Bool = false
    let createdAt: Date
    
    var startPoint: CGPoint
    var endPoint: CGPoint
    
    // 箭头样式
    var arrowHeadLength: CGFloat = 15.0
    var arrowHeadAngle: CGFloat = .pi / 6  // 30度
    
    init(
        id: UUID = UUID(),
        color: Color,
        lineWidth: CGFloat,
        startPoint: CGPoint,
        endPoint: CGPoint,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.color = color
        self.lineWidth = lineWidth
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.createdAt = createdAt
    }
    
    // MARK: - Annotation Protocol
    func draw(in context: GraphicsContext, size: CGSize) {
        let arrowPath = createArrowPath()
        
        // 绘制箭头主体
        context.stroke(
            Path(arrowPath),
            with: .color(color),
            style: StrokeStyle(
                lineWidth: lineWidth,
                lineCap: .round,
                lineJoin: .round
            )
        )
        
        // 填充箭头头部
        context.fill(
            Path(createArrowHeadPath()),
            with: .color(color)
        )
        
        // 选中状态显示控制点
        if isSelected {
            drawControlPoints(in: context)
        }
    }
    
    func contains(point: CGPoint) -> Bool {
        let tolerance: CGFloat = max(lineWidth, 15.0)
        
        // 检查是否在箭头线上
        if distance(from: point, toLineSegment: startPoint, endPoint) <= tolerance {
            return true
        }
        
        // 检查是否在箭头头部
        let headPath = createArrowHeadPath()
        let boundingBox = headPath.boundingBox
        return boundingBox.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
    }
    
    mutating func move(by offset: CGSize) {
        startPoint = CGPoint(
            x: startPoint.x + offset.width,
            y: startPoint.y + offset.height
        )
        endPoint = CGPoint(
            x: endPoint.x + offset.width,
            y: endPoint.y + offset.height
        )
    }
    
    // MARK: - 控制点操作
    mutating func moveStartPoint(to point: CGPoint) {
        startPoint = point
    }
    
    mutating func moveEndPoint(to point: CGPoint) {
        endPoint = point
    }
    
    func isNearStartPoint(_ point: CGPoint, tolerance: CGFloat = 20.0) -> Bool {
        startPoint.distance(to: point) <= tolerance
    }
    
    func isNearEndPoint(_ point: CGPoint, tolerance: CGFloat = 20.0) -> Bool {
        endPoint.distance(to: point) <= tolerance
    }
    
    // MARK: - 私有方法
    private func createArrowPath() -> CGMutablePath {
        let path = CGMutablePath()
        path.move(to: startPoint)
        path.addLine(to: endPoint)
        return path
    }
    
    private func createArrowHeadPath() -> CGMutablePath {
        let path = CGMutablePath()
        
        let angle = atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x)
        
        // 计算箭头头部的三个点
        let headPoint1 = CGPoint(
            x: endPoint.x - arrowHeadLength * cos(angle - arrowHeadAngle),
            y: endPoint.y - arrowHeadLength * sin(angle - arrowHeadAngle)
        )
        
        let headPoint2 = CGPoint(
            x: endPoint.x - arrowHeadLength * cos(angle + arrowHeadAngle),
            y: endPoint.y - arrowHeadLength * sin(angle + arrowHeadAngle)
        )
        
        path.move(to: headPoint1)
        path.addLine(to: endPoint)
        path.addLine(to: headPoint2)
        path.closeSubpath()
        
        return path
    }
    
    private func drawControlPoints(in context: GraphicsContext) {
        let controlPointRadius: CGFloat = 6.0
        let controlPointColor = Color.blue.opacity(0.8)
        
        // 起点控制点
        let startRect = CGRect(
            x: startPoint.x - controlPointRadius,
            y: startPoint.y - controlPointRadius,
            width: controlPointRadius * 2,
            height: controlPointRadius * 2
        )
        context.fill(
            Path(ellipseIn: startRect),
            with: .color(controlPointColor)
        )
        
        // 终点控制点
        let endRect = CGRect(
            x: endPoint.x - controlPointRadius,
            y: endPoint.y - controlPointRadius,
            width: controlPointRadius * 2,
            height: controlPointRadius * 2
        )
        context.fill(
            Path(ellipseIn: endRect),
            with: .color(controlPointColor)
        )
        
        // 连接线
        let guidePath = CGMutablePath()
        guidePath.move(to: startPoint)
        guidePath.addLine(to: endPoint)
        context.stroke(
            Path(guidePath),
            with: .color(.blue.opacity(0.3)),
            style: StrokeStyle(
                lineWidth: 1,
                dash: [4, 4]
            )
        )
    }
    
    private func distance(from point: CGPoint, toLineSegment p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        
        if dx == 0 && dy == 0 {
            return point.distance(to: p1)
        }
        
        let t = max(0, min(1, ((point.x - p1.x) * dx + (point.y - p1.y) * dy) / (dx * dx + dy * dy)))
        let projection = CGPoint(x: p1.x + t * dx, y: p1.y + t * dy)
        return point.distance(to: projection)
    }
}

// MARK: - 静态方法
extension ArrowAnnotation {
    static func == (lhs: ArrowAnnotation, rhs: ArrowAnnotation) -> Bool {
        lhs.id == rhs.id
    }
}
