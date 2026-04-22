import SwiftUI

// MARK: - 拼接线数据模型

struct StitchingLine: Identifiable {
    let id = UUID()
    var position: CGFloat // 相对于容器的位置 (0.0 - 1.0)
    var isDragging: Bool = false
    var showInfo: Bool = true
}

// MARK: - 吸附配置

struct SnapConfiguration {
    var enabled: Bool = true
    var snapThreshold: CGFloat = 15.0 // 吸附距离阈值（像素）
    var snapToEdges: Bool = true // 是否吸附到边缘
    var snapToOverlapCenter: Bool = true // 是否吸附到重叠区域中心
    var edgeSnapPoints: [CGFloat] = [] // 自定义边缘吸附点 (0.0 - 1.0)
}

// MARK: - 可拖动拼接线视图

struct StitchingLineView: View {
    // MARK: - 绑定属性
    
    @Binding var line: StitchingLine
    @Binding var canvasScale: CGFloat
    @Binding var canvasOffset: CGSize
    
    // MARK: - 配置属性
    
    let containerSize: CGSize
    let overlapRange: ClosedRange<CGFloat>? // 重叠区域范围 (0.0 - 1.0)
    let snapConfig: SnapConfiguration
    let onPositionChanged: ((CGFloat) -> Void)?
    let onDragEnded: ((CGFloat) -> Void)?
    
    // MARK: - 状态
    
    @State private var dragStartPosition: CGFloat = 0
    @State private var showSnapIndicator: Bool = false
    @State private var snapTargetPosition: CGFloat? = nil
    
    // MARK: - 计算属性
    
    /// 像素位置转相对位置
    private func pixelToRelative(_ pixel: CGFloat) -> CGFloat {
        return pixel / containerSize.height
    }
    
    /// 相对位置转像素位置
    private func relativeToPixel(_ relative: CGFloat) -> CGFloat {
        return relative * containerSize.height
    }
    
    /// 当前像素位置
    private var currentPixelPosition: CGFloat {
        relativeToPixel(line.position)
    }
    
    /// 限制位置在重叠区域内
    private func clampToOverlapRange(_ position: CGFloat) -> CGFloat {
        guard let range = overlapRange else { return position }
        return max(range.lowerBound, min(range.upperBound, position))
    }
    
    /// 计算吸附点
    private func calculateSnapPoint(_ position: CGFloat) -> CGFloat? {
        guard snapConfig.enabled else { return nil }
        
        let pixelPos = relativeToPixel(position)
        var closestSnap: CGFloat?
        var minDistance: CGFloat = snapConfig.snapThreshold
        
        // 检查边缘吸附点
        if snapConfig.snapToEdges {
            let edgePoints: [CGFloat] = [0.0, 1.0]
            for point in edgePoints {
                let distance = abs(relativeToPixel(point) - pixelPos)
                if distance < minDistance {
                    minDistance = distance
                    closestSnap = point
                }
            }
        }
        
        // 检查自定义吸附点
        for point in snapConfig.edgeSnapPoints {
            let distance = abs(relativeToPixel(point) - pixelPos)
            if distance < minDistance {
                minDistance = distance
                closestSnap = point
            }
        }
        
        // 检查重叠区域中心
        if snapConfig.snapToOverlapCenter, let range = overlapRange {
            let center = (range.lowerBound + range.upperBound) / 2
            let distance = abs(relativeToPixel(center) - pixelPos)
            if distance < minDistance {
                minDistance = distance
                closestSnap = center
            }
        }
        
        return closestSnap
    }
    
    // MARK: - 视图主体
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 吸附指示器
                if showSnapIndicator, let snapTarget = snapTargetPosition {
                    SnapIndicatorView(
                        position: relativeToPixel(snapTarget),
                        lineWidth: geometry.size.width
                    )
                }
                
                // 虚线
                DashedLine(
                    position: currentPixelPosition,
                    isDragging: line.isDragging,
                    lineWidth: geometry.size.width
                )
                
                // 拖动控制点
                DragHandle(
                    position: currentPixelPosition,
                    isDragging: line.isDragging,
                    lineWidth: geometry.size.width
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            handleDragChanged(value, in: geometry)
                        }
                        .onEnded { value in
                            handleDragEnded(value, in: geometry)
                        }
                )
                
                // 位置信息标签
                if line.showInfo {
                    PositionInfoLabel(
                        position: currentPixelPosition,
                        containerHeight: containerSize.height,
                        isDragging: line.isDragging,
                        lineWidth: geometry.size.width
                    )
                }
            }
        }
        .frame(height: containerSize.height)
    }
    
    // MARK: - 拖动处理
    
    private func handleDragChanged(_ value: DragGesture.Value, in geometry: GeometryProxy) {
        // 标记为正在拖动
        if !line.isDragging {
            line.isDragging = true
            dragStartPosition = line.position
        }
        
        // 计算新位置（考虑画布缩放和平移）
        let translationY = value.translation.height / canvasScale
        let newPixelPosition = relativeToPixel(dragStartPosition) + translationY
        var newRelativePosition = pixelToRelative(newPixelPosition)
        
        // 限制在重叠区域内
        newRelativePosition = clampToOverlapRange(newRelativePosition)
        
        // 检查吸附
        if let snapPoint = calculateSnapPoint(newRelativePosition) {
            snapTargetPosition = snapPoint
            showSnapIndicator = true
            
            // 如果接近吸附点，应用吸附
            let distance = abs(relativeToPixel(snapPoint) - relativeToPixel(newRelativePosition))
            if distance < snapConfig.snapThreshold / 2 {
                newRelativePosition = snapPoint
            }
        } else {
            showSnapIndicator = false
            snapTargetPosition = nil
        }
        
        // 更新位置
        line.position = newRelativePosition
        
        // 通知回调
        onPositionChanged?(newRelativePosition)
    }
    
    private func handleDragEnded(_ value: DragGesture.Value, in geometry: GeometryProxy) {
        line.isDragging = false
        showSnapIndicator = false
        
        // 最终吸附检查
        if let snapPoint = snapTargetPosition {
            withAnimation(.easeOut(duration: 0.2)) {
                line.position = snapPoint
            }
        }
        
        snapTargetPosition = nil
        onDragEnded?(line.position)
    }
}

// MARK: - 虚线视图

struct DashedLine: View {
    let position: CGFloat
    let isDragging: Bool
    let lineWidth: CGFloat
    
    var body: some View {
        HStack(spacing: 0) {
            // 左侧
            Rectangle()
                .fill(isDragging ? Color.blue.opacity(0.8) : Color.blue.opacity(0.6))
                .frame(width: (lineWidth - 40) / 2, height: isDragging ? 3 : 2)
            
            // 中心高亮区域
            Circle()
                .fill(isDragging ? Color.blue : Color.blue.opacity(0.8))
                .frame(width: 8, height: 8)
            
            // 右侧
            Rectangle()
                .fill(isDragging ? Color.blue.opacity(0.8) : Color.blue.opacity(0.6))
                .frame(width: (lineWidth - 40) / 2, height: isDragging ? 3 : 2)
        }
        .position(x: lineWidth / 2, y: position)
        .shadow(color: isDragging ? Color.blue.opacity(0.5) : Color.clear, radius: isDragging ? 4 : 0)
    }
}

// MARK: - 拖动控制点

struct DragHandle: View {
    let position: CGFloat
    let isDragging: Bool
    let lineWidth: CGFloat
    
    var body: some View {
        HStack(spacing: 12) {
            // 左控制点
            HandleButton(isDragging: isDragging)
            
            Spacer()
            
            // 右控制点
            HandleButton(isDragging: isDragging)
        }
        .padding(.horizontal, 16)
        .position(x: lineWidth / 2, y: position)
    }
}

// MARK: - 控制点按钮

struct HandleButton: View {
    let isDragging: Bool
    
    var body: some View {
        ZStack {
            // 外圈
            Circle()
                .fill(Color.white)
                .frame(width: 24, height: 24)
                .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
            
            // 内圈
            Circle()
                .fill(isDragging ? Color.blue : Color.blue.opacity(0.8))
                .frame(width: 12, height: 12)
        }
        .scaleEffect(isDragging ? 1.2 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isDragging)
    }
}

// MARK: - 位置信息标签

struct PositionInfoLabel: View {
    let position: CGFloat
    let containerHeight: CGFloat
    let isDragging: Bool
    let lineWidth: CGFloat
    
    private var percentage: Int {
        Int((position / containerHeight) * 100)
    }
    
    private var pixels: Int {
        Int(position)
    }
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(percentage)%")
                .font(.system(size: 12, weight: .semibold))
            Text("\(pixels) px")
                .font(.system(size: 10))
                .opacity(0.8)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(isDragging ? Color.blue : Color.black.opacity(0.7))
        )
        .position(
            x: lineWidth / 2,
            y: position > containerHeight / 2 ? position - 45 : position + 45
        )
        .opacity(isDragging ? 1.0 : 0.7)
        .animation(.easeInOut(duration: 0.15), value: isDragging)
    }
}

// MARK: - 吸附指示器

struct SnapIndicatorView: View {
    let position: CGFloat
    let lineWidth: CGFloat
    
    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.green.opacity(0.5))
                .frame(width: (lineWidth - 60) / 2, height: 2)
            
            Image(systemName: "arrow.down.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 20))
            
            Rectangle()
                .fill(Color.green.opacity(0.5))
                .frame(width: (lineWidth - 60) / 2, height: 2)
        }
        .position(x: lineWidth / 2, y: position)
        .opacity(0.8)
    }
}

// MARK: - 预览

struct StitchingLineView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            // 基础示例
            StitchingLineView(
                line: .constant(StitchingLine(position: 0.5)),
                canvasScale: .constant(1.0),
                canvasOffset: .constant(.zero),
                containerSize: CGSize(width: 300, height: 400),
                overlapRange: 0.3...0.7,
                snapConfig: SnapConfiguration(),
                onPositionChanged: nil,
                onDragEnded: nil
            )
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .padding()
        }
    }
}
