import SwiftUI

/// 裁剪遮罩层视图
struct CropOverlayView: View {
    @ObservedObject var viewModel: CropViewModel
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 半透明遮罩层
                maskLayer
                
                // 裁剪区域高亮
                cropAreaHighlight
                
                // 网格线
                gridLines
                
                // 四角和边缘拖拽手柄
                resizeHandles
            }
            .onAppear {
                viewModel.maxCropSize = geometry.size
                viewModel.resetToDefault()
            }
            .onChange(of: geometry.size) { newSize in
                viewModel.maxCropSize = newSize
            }
        }
    }
    
    // MARK: - Mask Layer
    
    private var maskLayer: some View {
        GeometryReader { geometry in
            let cropRect = viewModel.cropRect
            let containerSize = geometry.size
            
            ZStack {
                // 上部分遮罩
                Rectangle()
                    .fill(Color.black.opacity(0.6))
                    .frame(height: cropRect.minY)
                    .position(x: containerSize.width / 2, y: cropRect.minY / 2)
                
                // 下部分遮罩
                Rectangle()
                    .fill(Color.black.opacity(0.6))
                    .frame(height: containerSize.height - cropRect.maxY)
                    .position(x: containerSize.width / 2, y: cropRect.maxY + (containerSize.height - cropRect.maxY) / 2)
                
                // 左部分遮罩
                Rectangle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: cropRect.minX, height: cropRect.height)
                    .position(x: cropRect.minX / 2, y: cropRect.midY)
                
                // 右部分遮罩
                Rectangle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: containerSize.width - cropRect.maxX, height: cropRect.height)
                    .position(x: cropRect.maxX + (containerSize.width - cropRect.maxX) / 2, y: cropRect.midY)
            }
        }
    }
    
    // MARK: - Crop Area Highlight
    
    private var cropAreaHighlight: some View {
        Rectangle()
            .strokeBorder(Color.white, lineWidth: 2)
            .frame(width: viewModel.cropRect.width, height: viewModel.cropRect.height)
            .position(x: viewModel.cropRect.midX, y: viewModel.cropRect.midY)
    }
    
    // MARK: - Grid Lines
    
    private var gridLines: some View {
        Canvas { context, size in
            let cropRect = viewModel.cropRect
            let lineWidth: CGFloat = 1
            let lineColor = Color.white.opacity(0.5)
            
            // 垂直线 - 三等分
            let thirdWidth = cropRect.width / 3
            for i in 1..<3 {
                let x = cropRect.minX + CGFloat(i) * thirdWidth
                var path = Path()
                path.move(to: CGPoint(x: x, y: cropRect.minY))
                path.addLine(to: CGPoint(x: x, y: cropRect.maxY))
                context.stroke(path, with: .color(lineColor), lineWidth: lineWidth)
            }
            
            // 水平线 - 三等分
            let thirdHeight = cropRect.height / 3
            for i in 1..<3 {
                let y = cropRect.minY + CGFloat(i) * thirdHeight
                var path = Path()
                path.move(to: CGPoint(x: cropRect.minX, y: y))
                path.addLine(to: CGPoint(x: cropRect.maxX, y: y))
                context.stroke(path, with: .color(lineColor), lineWidth: lineWidth)
            }
            
            // 中心十字线（可选，用于更精确的对齐）
            if viewModel.isDragging {
                let centerX = cropRect.midX
                let centerY = cropRect.midY
                
                var verticalPath = Path()
                verticalPath.move(to: CGPoint(x: centerX, y: cropRect.minY))
                verticalPath.addLine(to: CGPoint(x: centerX, y: cropRect.maxY))
                context.stroke(verticalPath, with: .color(Color.white.opacity(0.3)), lineWidth: lineWidth)
                
                var horizontalPath = Path()
                horizontalPath.move(to: CGPoint(x: cropRect.minX, y: centerY))
                horizontalPath.addLine(to: CGPoint(x: cropRect.maxX, y: centerY))
                context.stroke(horizontalPath, with: .color(Color.white.opacity(0.3)), lineWidth: lineWidth)
            }
        }
    }
    
    // MARK: - Resize Handles
    
    private var resizeHandles: some View {
        let handleSize = viewModel.handleSize
        let cornerSize: CGFloat = 20
        let edgeHeight: CGFloat = 30
        let edgeWidth: CGFloat = 30
        
        return ZStack {
            // 四角手柄
            // 左上
            cornerHandle(
                position: CGPoint(x: viewModel.cropRect.minX, y: viewModel.cropRect.minY),
                size: cornerSize,
                anchor: .topLeft
            )
            
            // 右上
            cornerHandle(
                position: CGPoint(x: viewModel.cropRect.maxX, y: viewModel.cropRect.minY),
                size: cornerSize,
                anchor: .topRight
            )
            
            // 左下
            cornerHandle(
                position: CGPoint(x: viewModel.cropRect.minX, y: viewModel.cropRect.maxY),
                size: cornerSize,
                anchor: .bottomLeft
            )
            
            // 右下
            cornerHandle(
                position: CGPoint(x: viewModel.cropRect.maxX, y: viewModel.cropRect.maxY),
                size: cornerSize,
                anchor: .bottomRight
            )
            
            // 边缘手柄
            // 上
            edgeHandle(
                position: CGPoint(x: viewModel.cropRect.midX, y: viewModel.cropRect.minY),
                size: CGSize(width: viewModel.cropRect.width - cornerSize * 2, height: edgeHeight),
                anchor: .top
            )
            
            // 下
            edgeHandle(
                position: CGPoint(x: viewModel.cropRect.midX, y: viewModel.cropRect.maxY),
                size: CGSize(width: viewModel.cropRect.width - cornerSize * 2, height: edgeHeight),
                anchor: .bottom
            )
            
            // 左
            edgeHandle(
                position: CGPoint(x: viewModel.cropRect.minX, y: viewModel.cropRect.midY),
                size: CGSize(width: edgeWidth, height: viewModel.cropRect.height - cornerSize * 2),
                anchor: .left
            )
            
            // 右
            edgeHandle(
                position: CGPoint(x: viewModel.cropRect.maxX, y: viewModel.cropRect.midY),
                size: CGSize(width: edgeWidth, height: viewModel.cropRect.height - cornerSize * 2),
                anchor: .right
            )
            
            // 中心拖拽区域（整个裁剪框）
            centerDragArea
        }
    }
    
    // MARK: - Corner Handle
    
    private func cornerHandle(position: CGPoint, size: CGFloat, anchor: CropResizeAnchor) -> some View {
        let lineLength = size / 2
        let lineWidth: CGFloat = 3
        
        return Canvas { context, _ in
            let halfSize = size / 2
            var path = Path()
            
            switch anchor {
            case .topLeft:
                // L形 - 向右下延伸
                path.move(to: CGPoint(x: position.x + halfSize, y: position.y))
                path.addLine(to: CGPoint(x: position.x, y: position.y))
                path.addLine(to: CGPoint(x: position.x, y: position.y + halfSize))
            case .topRight:
                // L形 - 向左下延伸
                path.move(to: CGPoint(x: position.x - halfSize, y: position.y))
                path.addLine(to: CGPoint(x: position.x, y: position.y))
                path.addLine(to: CGPoint(x: position.x, y: position.y + halfSize))
            case .bottomLeft:
                // L形 - 向右上延伸
                path.move(to: CGPoint(x: position.x + halfSize, y: position.y))
                path.addLine(to: CGPoint(x: position.x, y: position.y))
                path.addLine(to: CGPoint(x: position.x, y: position.y - halfSize))
            case .bottomRight:
                // L形 - 向左上延伸
                path.move(to: CGPoint(x: position.x - halfSize, y: position.y))
                path.addLine(to: CGPoint(x: position.x, y: position.y))
                path.addLine(to: CGPoint(x: position.x, y: position.y - halfSize))
            default:
                break
            }
            
            context.stroke(path, with: .color(.white), lineWidth: lineWidth)
        }
        .frame(width: size * 2, height: size * 2)
        .position(position)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    viewModel.isDragging = true
                    let newRect = calculateNewRect(from: value, anchor: anchor)
                    viewModel.updateCropRectWithRatio(newRect, anchor: anchor)
                }
                .onEnded { _ in
                    viewModel.isDragging = false
                }
        )
    }
    
    // MARK: - Edge Handle
    
    private func edgeHandle(position: CGPoint, size: CGSize, anchor: CropResizeAnchor) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.01)) // 几乎透明但可交互
            .frame(width: max(size.width, 20), height: max(size.height, 20))
            .position(position)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        viewModel.isDragging = true
                        let newRect = calculateNewRect(from: value, anchor: anchor)
                        viewModel.updateCropRectWithRatio(newRect, anchor: anchor)
                    }
                    .onEnded { _ in
                        viewModel.isDragging = false
                    }
            )
    }
    
    // MARK: - Center Drag Area
    
    private var centerDragArea: some View {
        Rectangle()
            .fill(Color.white.opacity(0.001)) // 几乎透明但可交互
            .frame(width: max(viewModel.cropRect.width - 60, 20), 
                   height: max(viewModel.cropRect.height - 60, 20))
            .position(x: viewModel.cropRect.midX, y: viewModel.cropRect.midY)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        viewModel.isDragging = true
                        let translation = value.translation
                        let newRect = CGRect(
                            x: viewModel.cropRect.origin.x + translation.width,
                            y: viewModel.cropRect.origin.y + translation.height,
                            width: viewModel.cropRect.width,
                            height: viewModel.cropRect.height
                        )
                        viewModel.updateCropRect(newRect)
                    }
                    .onEnded { _ in
                        viewModel.isDragging = false
                    }
            )
    }
    
    // MARK: - Helper Methods
    
    private func calculateNewRect(from value: DragGesture.Value, anchor: CropResizeAnchor) -> CGRect {
        let translation = value.translation
        var newRect = viewModel.cropRect
        
        switch anchor {
        case .topLeft:
            newRect.origin.x += translation.width
            newRect.origin.y += translation.height
            newRect.size.width -= translation.width
            newRect.size.height -= translation.height
            
        case .top:
            newRect.origin.y += translation.height
            newRect.size.height -= translation.height
            
        case .topRight:
            newRect.origin.y += translation.height
            newRect.size.width += translation.width
            newRect.size.height -= translation.height
            
        case .right:
            newRect.size.width += translation.width
            
        case .bottomRight:
            newRect.size.width += translation.width
            newRect.size.height += translation.height
            
        case .bottom:
            newRect.size.height += translation.height
            
        case .bottomLeft:
            newRect.origin.x += translation.width
            newRect.size.width -= translation.width
            newRect.size.height += translation.height
            
        case .left:
            newRect.origin.x += translation.width
            newRect.size.width -= translation.width
            
        case .center:
            break
        }
        
        return newRect
    }
}

// MARK: - Preview

struct CropOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = CropViewModel(image: UIImage(systemName: "photo")!)
        viewModel.maxCropSize = CGSize(width: 400, height: 600)
        viewModel.cropRect = CGRect(x: 50, y: 100, width: 300, height: 400)
        
        return ZStack {
            Color.gray
            CropOverlayView(viewModel: viewModel)
        }
        .frame(width: 400, height: 600)
    }
}
