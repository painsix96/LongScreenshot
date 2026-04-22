import SwiftUI

// MARK: - 文字对齐方式
enum TextAlignment: String, CaseIterable {
    case left = "左对齐"
    case center = "居中"
    case right = "右对齐"
    
    var swiftUIAlignment: SwiftUI.Alignment {
        switch self {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }
    
    var icon: String {
        switch self {
        case .left: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .right: return "text.alignright"
        }
    }
}

// MARK: - 文字背景样式
enum TextBackgroundStyle: String, CaseIterable {
    case none = "无"
    case solid = "纯色"
    case semiTransparent = "半透明"
    case rounded = "圆角"
    
    var icon: String {
        switch self {
        case .none: return "textformat"
        case .solid: return "square.fill"
        case .semiTransparent: return "square.fill.on.square.fill"
        case .rounded: return "rectangle.roundedtop.fill"
        }
    }
}

// MARK: - 文字标注
struct TextAnnotation: Annotation, Equatable {
    let id: UUID
    let type: AnnotationType = .text
    var color: Color
    var lineWidth: CGFloat  // 用于字体大小
    var isSelected: Bool = false
    let createdAt: Date
    
    var text: String
    var position: CGPoint
    var fontName: String = ".AppleSystemUIFont"
    var alignment: TextAlignment = .center
    var backgroundStyle: TextBackgroundStyle = .semiTransparent
    var backgroundColor: Color = .black
    var rotation: Double = 0.0  // 旋转角度
    
    // 计算尺寸
    var computedSize: CGSize {
        let font = UIFont.systemFont(ofSize: lineWidth)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let size = (text as NSString).size(withAttributes: attributes)
        return CGSize(
            width: size.width + 20,  // 添加内边距
            height: size.height + 12
        )
    }
    
    init(
        id: UUID = UUID(),
        color: Color,
        fontSize: CGFloat,
        text: String,
        position: CGPoint,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.color = color
        self.lineWidth = fontSize
        self.text = text
        self.position = position
        self.createdAt = createdAt
    }
    
    // MARK: - Annotation Protocol
    func draw(in context: GraphicsContext, size: CGSize) {
        let textSize = computedSize
        let rect = CGRect(
            x: position.x - textSize.width / 2,
            y: position.y - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        
        // 保存当前状态以应用旋转
        var context = context
        
        // 绘制背景
        drawBackground(in: &context, rect: rect)
        
        // 绘制文字
        drawText(in: &context, rect: rect)
        
        // 选中状态
        if isSelected {
            drawSelectionIndicator(in: &context, rect: rect)
        }
    }
    
    func contains(point: CGPoint) -> Bool {
        let textSize = computedSize
        let rect = CGRect(
            x: position.x - textSize.width / 2,
            y: position.y - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        return rect.contains(point, tolerance: 10.0)
    }
    
    mutating func move(by offset: CGSize) {
        position = CGPoint(
            x: position.x + offset.width,
            y: position.y + offset.height
        )
    }
    
    // MARK: - 编辑操作
    mutating func updateText(_ newText: String) {
        text = newText
    }
    
    mutating func updateFontSize(_ size: CGFloat) {
        lineWidth = max(10, min(100, size))
    }
    
    mutating func updateRotation(_ angle: Double) {
        rotation = angle
    }
    
    // MARK: - 私有方法
    private func drawBackground(in context: inout GraphicsContext, rect: CGRect) {
        switch backgroundStyle {
        case .none:
            break
            
        case .solid:
            context.fill(
                Path(rect),
                with: .color(backgroundColor)
            )
            
        case .semiTransparent:
            context.fill(
                Path(rect),
                with: .color(backgroundColor.opacity(0.6))
            )
            
        case .rounded:
            let roundedRect = rect.insetBy(dx: -4, dy: -2)
            let path = CGMutablePath()
            path.addRoundedRect(
                in: roundedRect,
                cornerWidth: 8,
                cornerHeight: 8
            )
            context.fill(
                Path(path),
                with: .color(backgroundColor.opacity(0.7))
            )
        }
    }
    
    private func drawText(in context: inout GraphicsContext, rect: CGRect) {
        // 使用 SwiftUI 的 resolvedText 方法
        let font = Font.system(size: lineWidth, weight: .medium)
        
        let textContent = Text(text)
            .font(font)
            .foregroundColor(color)
        
        // 根据对齐方式调整位置
        var xOffset: CGFloat = 0
        switch alignment {
        case .left:
            xOffset = -rect.width / 2 + 10
        case .center:
            xOffset = 0
        case .right:
            xOffset = rect.width / 2 - 10
        }
        
        // 在 GraphicsContext 中绘制文字
        let textPoint = CGPoint(
            x: position.x + xOffset,
            y: position.y - lineWidth / 2
        )
        
        // 使用 Text 绘制到当前 context
        context.draw(
            textContent,
            at: textPoint,
            anchor: alignment == .left ? .leading : (alignment == .right ? .trailing : .center)
        )
    }
    
    private func drawSelectionIndicator(in context: inout GraphicsContext, rect: CGRect) {
        let borderRect = rect.insetBy(dx: -4, dy: -4)
        let path = CGMutablePath()
        path.addRect(borderRect)
        
        context.stroke(
            Path(path),
            with: .color(.blue.opacity(0.6)),
            style: StrokeStyle(
                lineWidth: 2,
                dash: [4, 4]
            )
        )
        
        // 绘制旋转控制点
        let handleRadius: CGFloat = 5.0
        let handleRect = CGRect(
            x: position.x - handleRadius,
            y: rect.minY - 20,
            width: handleRadius * 2,
            height: handleRadius * 2
        )
        context.fill(
            Path(ellipseIn: handleRect),
            with: .color(.blue)
        )
        
        // 连接旋转手柄的线
        let linePath = CGMutablePath()
        linePath.move(to: CGPoint(x: position.x, y: rect.minY))
        linePath.addLine(to: CGPoint(x: position.x, y: rect.minY - 15))
        context.stroke(
            Path(linePath),
            with: .color(.blue.opacity(0.5)),
            style: StrokeStyle(lineWidth: 1)
        )
    }
}

// MARK: - 静态方法
extension TextAnnotation {
    static func == (lhs: TextAnnotation, rhs: TextAnnotation) -> Bool {
        lhs.id == rhs.id
    }
}
