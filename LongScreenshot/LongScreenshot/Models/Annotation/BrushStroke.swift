import SwiftUI

// MARK: - 画笔描点
struct StrokePoint: Equatable {
    let point: CGPoint
    let pressure: CGFloat  // 模拟压感，0.0 - 1.0
    let timestamp: Date
    
    init(point: CGPoint, pressure: CGFloat = 1.0, timestamp: Date = Date()) {
        self.point = point
        self.pressure = pressure
        self.timestamp = timestamp
    }
}

// MARK: - 画笔描边
struct BrushStroke: Annotation, Equatable {
    let id: UUID
    let type: AnnotationType = .brush
    var color: Color
    var lineWidth: CGFloat
    var isSelected: Bool = false
    let createdAt: Date
    
    var points: [StrokePoint]
    var isFinished: Bool = false
    
    // 平滑处理后的点
    private var smoothedPoints: [CGPoint] {
        smoothPoints(points.map { $0.point })
    }
    
    init(
        id: UUID = UUID(),
        color: Color,
        lineWidth: CGFloat,
        points: [StrokePoint] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.color = color
        self.lineWidth = lineWidth
        self.points = points
        self.createdAt = createdAt
    }
    
    // MARK: - 添加点
    mutating func addPoint(_ point: CGPoint, pressure: CGFloat = 1.0) {
        let strokePoint = StrokePoint(point: point, pressure: pressure)
        points.append(strokePoint)
    }
    
    // MARK: - 完成绘制
    mutating func finish() {
        isFinished = true
    }
    
    // MARK: - Annotation Protocol
    func draw(in context: GraphicsContext, size: CGSize) {
        guard points.count >= 2 else { return }
        
        let path = createSmoothPath()
        
        // 根据压感调整线宽
        if points.count > 1 {
            drawVariableWidthStroke(in: context, path: path)
        } else {
            let strokeStyle = StrokeStyle(
                lineWidth: lineWidth,
                lineCap: .round,
                lineJoin: .round
            )
            context.stroke(
                Path(path),
                with: .color(color),
                style: strokeStyle
            )
        }
        
        // 选中状态显示边框
        if isSelected {
            drawSelectionIndicator(in: context, path: path)
        }
    }
    
    func contains(point: CGPoint) -> Bool {
        guard points.count >= 2 else { return false }
        
        // 检查点是否接近路径
        let tolerance: CGFloat = max(lineWidth, 20.0)
        
        for i in 0..<points.count - 1 {
            let p1 = points[i].point
            let p2 = points[i + 1].point
            if distance(from: point, toLineSegment: p1, p2) <= tolerance {
                return true
            }
        }
        
        return false
    }
    
    mutating func move(by offset: CGSize) {
        for i in 0..<points.count {
            let newPoint = CGPoint(
                x: points[i].point.x + offset.width,
                y: points[i].point.y + offset.height
            )
            points[i] = StrokePoint(
                point: newPoint,
                pressure: points[i].pressure,
                timestamp: points[i].timestamp
            )
        }
    }
    
    // MARK: - 私有方法
    private func createSmoothPath() -> CGMutablePath {
        let path = CGMutablePath()
        let smoothed = smoothedPoints
        
        guard smoothed.count >= 2 else { return path }
        
        path.move(to: smoothed[0])
        
        // 使用二次贝塞尔曲线平滑连接
        for i in 1..<smoothed.count {
            if i == 1 {
                path.addLine(to: smoothed[i])
            } else {
                let prevPoint = smoothed[i - 1]
                let currPoint = smoothed[i]
                let midPoint = CGPoint(
                    x: (prevPoint.x + currPoint.x) / 2,
                    y: (prevPoint.y + currPoint.y) / 2
                )
                path.addQuadCurve(to: midPoint, control: prevPoint)
                if i == smoothed.count - 1 {
                    path.addLine(to: currPoint)
                }
            }
        }
        
        return path
    }
    
    private func smoothPoints(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 3 else { return points }
        
        var smoothed: [CGPoint] = [points[0]]
        
        for i in 1..<points.count - 1 {
            let prev = points[i - 1]
            let curr = points[i]
            let next = points[i + 1]
            
            // 简单的移动平均平滑
            let smoothedPoint = CGPoint(
                x: (prev.x + curr.x * 2 + next.x) / 4,
                y: (prev.y + curr.y * 2 + next.y) / 4
            )
            smoothed.append(smoothedPoint)
        }
        
        smoothed.append(points[points.count - 1])
        return smoothed
    }
    
    private func drawVariableWidthStroke(in context: GraphicsContext, path: CGMutablePath) {
        // 根据压感绘制变宽描边
        guard points.count >= 2 else { return }
        
        for i in 0..<points.count - 1 {
            let segmentPath = CGMutablePath()
            let p1 = points[i].point
            let p2 = points[i + 1].point
            
            segmentPath.move(to: p1)
            segmentPath.addLine(to: p2)
            
            let avgPressure = (points[i].pressure + points[i + 1].pressure) / 2
            let adjustedWidth = lineWidth * (0.5 + avgPressure * 0.5)
            
            context.stroke(
                Path(segmentPath),
                with: .color(color),
                style: StrokeStyle(
                    lineWidth: adjustedWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
    }
    
    private func drawSelectionIndicator(in context: GraphicsContext, path: CGMutablePath) {
        context.stroke(
            Path(path),
            with: .color(.blue.opacity(0.5)),
            style: StrokeStyle(
                lineWidth: lineWidth + 4,
                lineCap: .round,
                lineJoin: .round,
                dash: [5, 5]
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
extension BrushStroke {
    static func == (lhs: BrushStroke, rhs: BrushStroke) -> Bool {
        lhs.id == rhs.id
    }
}
