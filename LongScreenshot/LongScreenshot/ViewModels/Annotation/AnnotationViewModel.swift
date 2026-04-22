import SwiftUI
import Combine

// MARK: - 标注视图模型
@MainActor
class AnnotationViewModel: ObservableObject {
    // MARK: - Published 属性
    @Published var annotations: [AnyAnnotation] = []
    @Published var selectedAnnotationId: UUID?
    @Published var toolSettings = AnnotationToolSettings()
    @Published var isDrawing = false
    @Published var canUndo = false
    @Published var canRedo = false
    @Published var showTextInput = false
    @Published var editingText = ""
    @Published var editingTextAnnotationId: UUID?
    
    // MARK: - 私有属性
    private var history = AnnotationHistory()
    private var currentStroke: BrushStroke?
    private var currentArrow: ArrowAnnotation?
    private var currentRectangle: RectangleAnnotation?
    private var currentMosaic: MosaicAnnotation?
    
    // MARK: - 计算属性
    var selectedAnnotation: (any Annotation)? {
        guard let id = selectedAnnotationId else { return nil }
        return annotations.first { $0.id == id }?.annotation
    }
    
    var hasAnnotations: Bool { !annotations.isEmpty }
    
    // MARK: - 初始化
    init() {
        updateHistoryState()
    }
    
    // MARK: - 工具切换
    func selectTool(_ tool: AnnotationType) {
        toolSettings.selectedTool = tool
        deselectAll()
    }
    
    func selectColor(_ color: Color) {
        toolSettings.selectedColor = color
        updateSelectedAnnotationColor(color)
    }
    
    func updateLineWidth(_ width: CGFloat) {
        toolSettings.lineWidth = width
        updateSelectedAnnotationLineWidth(width)
    }
    
    // MARK: - 绘制操作
    func startDrawing(at point: CGPoint) {
        isDrawing = true
        saveStateToHistory()
        
        switch toolSettings.selectedTool {
        case .brush:
            startBrushStroke(at: point)
        case .arrow:
            startArrow(at: point)
        case .rectangle:
            startRectangle(at: point)
        case .text:
            addText(at: point)
        case .mosaic:
            startMosaic(at: point)
        }
    }
    
    func continueDrawing(to point: CGPoint) {
        guard isDrawing else { return }
        
        switch toolSettings.selectedTool {
        case .brush:
            continueBrushStroke(to: point)
        case .arrow:
            continueArrow(to: point)
        case .rectangle:
            continueRectangle(to: point)
        case .text:
            break
        case .mosaic:
            continueMosaic(to: point)
        }
    }
    
    func endDrawing() {
        isDrawing = false
        
        switch toolSettings.selectedTool {
        case .brush:
            finishBrushStroke()
        case .arrow:
            finishArrow()
        case .rectangle:
            finishRectangle()
        case .text:
            break
        case .mosaic:
            finishMosaic()
        }
        
        updateHistoryState()
    }
    
    // MARK: - 选择操作
    func selectAnnotation(at point: CGPoint) -> Bool {
        // 从后向前查找（上面的优先）
        for anyAnnotation in annotations.reversed() {
            if anyAnnotation.annotation.contains(point: point) {
                selectAnnotation(withId: anyAnnotation.id)
                return true
            }
        }
        
        deselectAll()
        return false
    }
    
    func selectAnnotation(withId id: UUID) {
        // 取消之前的选择
        deselectAll()
        
        // 选择新的
        selectedAnnotationId = id
        if let index = annotations.firstIndex(where: { $0.id == id }) {
            var annotation = annotations[index].annotation
            annotation.isSelected = true
            annotations[index] = AnyAnnotation(annotation)
            
            // 更新工具设置为选中标注的设置
            toolSettings.selectedColor = annotation.color
            toolSettings.lineWidth = annotation.lineWidth
        }
    }
    
    func deselectAll() {
        selectedAnnotationId = nil
        
        for index in annotations.indices {
            var annotation = annotations[index].annotation
            annotation.isSelected = false
            annotations[index] = AnyAnnotation(annotation)
        }
    }
    
    // MARK: - 移动操作
    func moveSelectedAnnotation(by offset: CGSize) {
        guard let id = selectedAnnotationId,
              let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        
        var annotation = annotations[index].annotation
        annotation.move(by: offset)
        annotations[index] = AnyAnnotation(annotation)
    }
    
    func moveAnnotation(withId id: UUID, by offset: CGSize) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        
        var annotation = annotations[index].annotation
        annotation.move(by: offset)
        annotations[index] = AnyAnnotation(annotation)
    }
    
    // MARK: - 删除操作
    func deleteSelectedAnnotation() {
        guard let id = selectedAnnotationId else { return }
        deleteAnnotation(withId: id)
    }
    
    func deleteAnnotation(withId id: UUID) {
        saveStateToHistory()
        annotations.removeAll { $0.id == id }
        if selectedAnnotationId == id {
            selectedAnnotationId = nil
        }
        updateHistoryState()
    }
    
    func clearAllAnnotations() {
        guard !annotations.isEmpty else { return }
        saveStateToHistory()
        annotations.removeAll()
        selectedAnnotationId = nil
        updateHistoryState()
    }
    
    // MARK: - 撤销/重做
    func undo() {
        guard let previousState = history.undo(currentState: annotations.map { $0.annotation }) else { return }
        restoreState(from: previousState)
        updateHistoryState()
    }
    
    func redo() {
        guard let nextState = history.redo(currentState: annotations.map { $0.annotation }) else { return }
        restoreState(from: nextState)
        updateHistoryState()
    }
    
    // MARK: - 文字编辑
    func startEditingText(_ annotation: TextAnnotation) {
        editingText = annotation.text
        editingTextAnnotationId = annotation.id
        showTextInput = true
    }
    
    func finishEditingText() {
        guard let id = editingTextAnnotationId,
              let index = annotations.firstIndex(where: { $0.id == id }),
              var textAnnotation = annotations[index].annotation as? TextAnnotation else {
            showTextInput = false
            editingTextAnnotationId = nil
            return
        }
        
        saveStateToHistory()
        textAnnotation.updateText(editingText)
        annotations[index] = AnyAnnotation(textAnnotation)
        
        showTextInput = false
        editingTextAnnotationId = nil
        updateHistoryState()
    }
    
    // MARK: - 导出
    func exportAnnotatedImage(baseImage: UIImage) -> UIImage? {
        let imageRenderer = UIGraphicsImageRenderer(size: baseImage.size)
        
        return imageRenderer.image { ctx in
            // 绘制原图
            baseImage.draw(in: CGRect(origin: .zero, size: baseImage.size))
            
            // 绘制所有标注 - 使用各自的绘制逻辑
            for anyAnnotation in annotations {
                let annotation = anyAnnotation.annotation
                drawAnnotation(annotation, in: ctx, scale: baseImage.size)
            }
        }
    }
    
    /// 在 CGContext 中绘制标注
    private func drawAnnotation(_ annotation: any Annotation, in ctx: UIGraphicsImageRendererContext, scale: CGSize) {
        let cgContext = ctx.cgContext
        cgContext.saveGState()
        
        // 根据标注类型使用不同的绘制逻辑
        if let arrow = annotation as? ArrowAnnotation {
            drawArrow(arrow, in: cgContext)
        } else if let brush = annotation as? BrushStroke {
            drawBrush(brush, in: cgContext)
        } else if let rect = annotation as? RectangleAnnotation {
            drawRectangle(rect, in: cgContext)
        } else if let text = annotation as? TextAnnotation {
            drawText(text, in: ctx, scale: scale)
        } else if let mosaic = annotation as? MosaicAnnotation {
            drawMosaic(mosaic, in: cgContext)
        }
        
        cgContext.restoreGState()
    }
    
    private func drawArrow(_ arrow: ArrowAnnotation, in context: CGContext) {
        context.setStrokeColor(arrow.color.toUIColor().cgColor)
        context.setLineWidth(arrow.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        
        // 绘制箭头主体
        context.move(to: arrow.startPoint)
        context.addLine(to: arrow.endPoint)
        context.strokePath()
        
        // 绘制箭头头部
        let angle = atan2(arrow.endPoint.y - arrow.startPoint.y, arrow.endPoint.x - arrow.startPoint.x)
        let headLength: CGFloat = 15.0
        let headAngle: CGFloat = .pi / 6
        
        let headPoint1 = CGPoint(
            x: arrow.endPoint.x - headLength * cos(angle - headAngle),
            y: arrow.endPoint.y - headLength * sin(angle - headAngle)
        )
        let headPoint2 = CGPoint(
            x: arrow.endPoint.x - headLength * cos(angle + headAngle),
            y: arrow.endPoint.y - headLength * sin(angle + headAngle)
        )
        
        context.move(to: headPoint1)
        context.addLine(to: arrow.endPoint)
        context.addLine(to: headPoint2)
        context.addLine(to: headPoint1)
        context.fillPath()
    }
    
    private func drawBrush(_ brush: BrushStroke, in context: CGContext) {
        context.setStrokeColor(brush.color.toUIColor().cgColor)
        context.setLineWidth(brush.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        
        let points = brush.points
        guard points.count >= 2 else { return }
        
        context.move(to: points[0].point)
        for i in 1..<points.count {
            context.addLine(to: points[i].point)
        }
        context.strokePath()
    }
    
    private func drawRectangle(_ rectAnnotation: RectangleAnnotation, in context: CGContext) {
        let rect = rectAnnotation.rect
        
        switch rectAnnotation.style {
        case .fill:
            context.setFillColor(rectAnnotation.color.toUIColor().withAlphaComponent(rectAnnotation.fillOpacity).cgColor)
            context.fill(rect)
            context.setStrokeColor(rectAnnotation.color.toUIColor().cgColor)
            context.setLineWidth(rectAnnotation.lineWidth)
            context.stroke(rect)
        case .stroke:
            context.setStrokeColor(rectAnnotation.color.toUIColor().cgColor)
            context.setLineWidth(rectAnnotation.lineWidth)
            context.stroke(rect)
        case .dashed:
            context.setStrokeColor(rectAnnotation.color.toUIColor().cgColor)
            context.setLineWidth(rectAnnotation.lineWidth)
            context.setLineDash(phase: 0, lengths: [8, 4])
            context.stroke(rect)
        }
    }
    
    private func drawText(_ textAnnotation: TextAnnotation, in ctx: UIGraphicsImageRendererContext, scale: CGSize) {
        let font = UIFont.systemFont(ofSize: textAnnotation.lineWidth)
        let textColor = textAnnotation.color.toUIColor()
        
        let paragraphStyle = NSMutableParagraphStyle()
        switch textAnnotation.alignment {
        case .left:
            paragraphStyle.alignment = .left
        case .center:
            paragraphStyle.alignment = .center
        case .right:
            paragraphStyle.alignment = .right
        }
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]
        
        let textSize = (textAnnotation.text as NSString).size(withAttributes: attributes)
        let textRect = CGRect(
            x: textAnnotation.position.x - textSize.width / 2,
            y: textAnnotation.position.y - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        
        // 绘制背景
        switch textAnnotation.backgroundStyle {
        case .solid:
            textAnnotation.backgroundColor.toUIColor().setFill()
            UIRectFill(textRect)
        case .semiTransparent:
            textAnnotation.backgroundColor.toUIColor().withAlphaComponent(0.6).setFill()
            UIRectFill(textRect)
        case .rounded:
            let path = UIBezierPath(roundedRect: textRect.insetBy(dx: -4, dy: -2), cornerRadius: 8)
            textAnnotation.backgroundColor.toUIColor().withAlphaComponent(0.7).setFill()
            path.fill()
        case .none:
            break
        }
        
        (textAnnotation.text as NSString).draw(in: textRect, withAttributes: attributes)
    }
    
    private func drawMosaic(_ mosaic: MosaicAnnotation, in context: CGContext) {
        let rect = mosaic.rect
        let blockSize = mosaic.lineWidth
        
        context.setFillColor(UIColor.gray.withAlphaComponent(0.3).cgColor)
        
        let cols = Int(ceil(rect.width / blockSize))
        let rows = Int(ceil(rect.height / blockSize))
        
        for row in 0..<rows {
            for col in 0..<cols {
                let blockRect = CGRect(
                    x: rect.minX + CGFloat(col) * blockSize,
                    y: rect.minY + CGFloat(row) * blockSize,
                    width: min(blockSize, rect.maxX - (rect.minX + CGFloat(col) * blockSize)),
                    height: min(blockSize, rect.maxY - (rect.minY + CGFloat(row) * blockSize))
                )
                context.fill(blockRect)
            }
        }
    }
    
    // MARK: - 私有方法 - 画笔
    private func startBrushStroke(at point: CGPoint) {
        let pressure = simulatePressure()
        var stroke = BrushStroke(
            color: toolSettings.selectedColor,
            lineWidth: toolSettings.lineWidth
        )
        stroke.addPoint(point, pressure: pressure)
        currentStroke = stroke
        
        annotations.append(AnyAnnotation(stroke))
    }
    
    private func continueBrushStroke(to point: CGPoint) {
        guard var stroke = currentStroke else { return }
        
        let pressure = simulatePressure()
        stroke.addPoint(point, pressure: pressure)
        
        // 更新数组中的描边
        if let index = annotations.firstIndex(where: { $0.id == stroke.id }) {
            annotations[index] = AnyAnnotation(stroke)
            currentStroke = stroke
        }
    }
    
    private func finishBrushStroke() {
        currentStroke?.finish()
        if let stroke = currentStroke,
           let index = annotations.firstIndex(where: { $0.id == stroke.id }) {
            var finishedStroke = stroke
            finishedStroke.finish()
            annotations[index] = AnyAnnotation(finishedStroke)
        }
        currentStroke = nil
    }
    
    // MARK: - 私有方法 - 箭头
    private func startArrow(at point: CGPoint) {
        let arrow = ArrowAnnotation(
            color: toolSettings.selectedColor,
            lineWidth: toolSettings.lineWidth,
            startPoint: point,
            endPoint: point
        )
        currentArrow = arrow
        annotations.append(AnyAnnotation(arrow))
    }
    
    private func continueArrow(to point: CGPoint) {
        guard var arrow = currentArrow else { return }
        arrow.endPoint = point
        
        if let index = annotations.firstIndex(where: { $0.id == arrow.id }) {
            annotations[index] = AnyAnnotation(arrow)
            currentArrow = arrow
        }
    }
    
    private func finishArrow() {
        currentArrow = nil
    }
    
    // MARK: - 私有方法 - 矩形
    private func startRectangle(at point: CGPoint) {
        let rect = RectangleAnnotation(
            color: toolSettings.selectedColor,
            lineWidth: toolSettings.lineWidth,
            rect: CGRect(origin: point, size: .zero)
        )
        currentRectangle = rect
        annotations.append(AnyAnnotation(rect))
    }
    
    private func continueRectangle(to point: CGPoint) {
        guard var rect = currentRectangle else { return }
        
        let origin = CGPoint(
            x: min(rect.rect.origin.x, point.x),
            y: min(rect.rect.origin.y, point.y)
        )
        let size = CGSize(
            width: abs(point.x - rect.rect.origin.x),
            height: abs(point.y - rect.rect.origin.y)
        )
        
        rect.rect = CGRect(origin: origin, size: size)
        
        if let index = annotations.firstIndex(where: { $0.id == rect.id }) {
            annotations[index] = AnyAnnotation(rect)
            currentRectangle = rect
        }
    }
    
    private func finishRectangle() {
        currentRectangle = nil
    }
    
    // MARK: - 私有方法 - 文字
    private func addText(at point: CGPoint) {
        let textAnnotation = TextAnnotation(
            color: toolSettings.selectedColor,
            fontSize: toolSettings.textFontSize,
            text: "点击编辑文字",
            position: point
        )
        
        saveStateToHistory()
        annotations.append(AnyAnnotation(textAnnotation))
        selectAnnotation(withId: textAnnotation.id)
        startEditingText(textAnnotation)
        updateHistoryState()
    }
    
    // MARK: - 私有方法 - 马赛克
    private func startMosaic(at point: CGPoint) {
        let mosaic = MosaicAnnotation(
            blockSize: toolSettings.mosaicBlockSize,
            rect: CGRect(origin: point, size: .zero)
        )
        currentMosaic = mosaic
        annotations.append(AnyAnnotation(mosaic))
    }
    
    private func continueMosaic(to point: CGPoint) {
        guard var mosaic = currentMosaic else { return }
        
        let origin = CGPoint(
            x: min(mosaic.rect.origin.x, point.x),
            y: min(mosaic.rect.origin.y, point.y)
        )
        let size = CGSize(
            width: abs(point.x - mosaic.rect.origin.x),
            height: abs(point.y - mosaic.rect.origin.y)
        )
        
        mosaic.rect = CGRect(origin: origin, size: size)
        
        if let index = annotations.firstIndex(where: { $0.id == mosaic.id }) {
            annotations[index] = AnyAnnotation(mosaic)
            currentMosaic = mosaic
        }
    }
    
    private func finishMosaic() {
        currentMosaic = nil
    }
    
    // MARK: - 私有方法 - 辅助
    private func simulatePressure() -> CGFloat {
        // 模拟压感：随机生成 0.5 - 1.0 的压力值
        // 实际应用中可以从 Apple Pencil 获取真实压感
        return CGFloat.random(in: 0.5...1.0)
    }
    
    private func saveStateToHistory() {
        history.saveState(annotations.map { $0.annotation })
    }
    
    private func updateHistoryState() {
        canUndo = history.canUndo
        canRedo = history.canRedo
    }
    
    private func restoreState(from state: [any Annotation]) {
        annotations = state.map { AnyAnnotation($0) }
        selectedAnnotationId = nil
    }
    
    private func updateSelectedAnnotationColor(_ color: Color) {
        guard let id = selectedAnnotationId,
              let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        
        var annotation = annotations[index].annotation
        annotation.color = color
        annotations[index] = AnyAnnotation(annotation)
    }
    
    private func updateSelectedAnnotationLineWidth(_ width: CGFloat) {
        guard let id = selectedAnnotationId,
              let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        
        var annotation = annotations[index].annotation
        annotation.lineWidth = width
        annotations[index] = AnyAnnotation(annotation)
    }
}

// MARK: - 类型擦除包装器
struct AnyAnnotation: Identifiable, Equatable {
    let id: UUID
    let annotation: any Annotation
    
    init(_ annotation: any Annotation) {
        self.id = annotation.id
        self.annotation = annotation
    }
    
    static func == (lhs: AnyAnnotation, rhs: AnyAnnotation) -> Bool {
        lhs.id == rhs.id
    }
}
