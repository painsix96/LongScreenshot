import SwiftUI

// MARK: - 标注类型枚举
enum AnnotationType: String, CaseIterable {
    case brush = "画笔"
    case arrow = "箭头"
    case rectangle = "矩形"
    case text = "文字"
    case mosaic = "马赛克"
    
    var icon: String {
        switch self {
        case .brush: return "scribble"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .text: return "textformat"
        case .mosaic: return "grid.3x3"
        }
    }
}

// MARK: - 标注基类协议
protocol Annotation: Identifiable, Equatable {
    var id: UUID { get }
    var type: AnnotationType { get }
    var color: Color { get set }
    var lineWidth: CGFloat { get set }
    var isSelected: Bool { get set }
    var createdAt: Date { get }
    
    func draw(in context: GraphicsContext, size: CGSize)
    func contains(point: CGPoint) -> Bool
    mutating func move(by offset: CGSize)
}

// MARK: - 标注工具设置
struct AnnotationToolSettings {
    var selectedTool: AnnotationType = .brush
    var selectedColor: Color = .red
    var lineWidth: CGFloat = 3.0
    var textFontSize: CGFloat = 20.0
    var mosaicBlockSize: CGFloat = 15.0
    
    // 预设颜色
    static let presetColors: [Color] = [
        .red,
        .orange,
        .yellow,
        .green,
        .blue,
        .purple,
        .pink,
        .black,
        .white,
        .gray
    ]
}

// MARK: - 标注历史记录管理
class AnnotationHistory {
    private var undoStack: [[any Annotation]] = []
    private var redoStack: [[any Annotation]] = []
    private let maxHistoryCount = 50
    
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    
    func saveState(_ annotations: [any Annotation]) {
        // 将当前状态保存到撤销栈
        let state = annotations.map { $0 }
        undoStack.append(state)
        
        // 限制历史记录数量
        if undoStack.count > maxHistoryCount {
            undoStack.removeFirst()
        }
        
        // 清空重做栈
        redoStack.removeAll()
    }
    
    func undo(currentState: [any Annotation]) -> [any Annotation]? {
        guard canUndo else { return nil }
        
        // 保存当前状态到重做栈
        redoStack.append(currentState.map { $0 })
        
        // 返回上一个状态
        return undoStack.popLast()
    }
    
    func redo(currentState: [any Annotation]) -> [any Annotation]? {
        guard canRedo else { return nil }
        
        // 保存当前状态到撤销栈
        undoStack.append(currentState.map { $0 })
        
        // 返回重做状态
        return redoStack.popLast()
    }
    
    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}

// MARK: - 辅助扩展
extension Color {
    func toUIColor() -> UIColor {
        UIColor(self)
    }
}

extension CGPoint {
    func distance(to point: CGPoint) -> CGFloat {
        sqrt(pow(x - point.x, 2) + pow(y - point.y, 2))
    }
    
    func offsetBy(dx: CGFloat, dy: CGFloat) -> CGPoint {
        CGPoint(x: x + dx, y: y + dy)
    }
}

extension CGRect {
    func contains(_ point: CGPoint, tolerance: CGFloat = 10.0) -> Bool {
        insetBy(dx: -tolerance, dy: -tolerance).contains(point)
    }
}
