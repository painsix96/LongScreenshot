import SwiftUI

// MARK: - 画布状态

struct CanvasState {
    var scale: CGFloat = 1.0
    var offset: CGSize = .zero
    var lastOffset: CGSize = .zero
    var isDragging: Bool = false
    var isPinching: Bool = false
    
    // 缩放限制
    let minScale: CGFloat = 0.3
    let maxScale: CGFloat = 5.0
    
    mutating func reset() {
        scale = 1.0
        offset = .zero
        lastOffset = .zero
    }
    
    mutating func clampScale() {
        scale = min(maxScale, max(minScale, scale))
    }
}

// MARK: - 预览数据模型

struct StitchPreviewData {
    let topImage: UIImage
    let bottomImage: UIImage
    let overlapInfo: OverlapInfo
    let stitchPosition: CGFloat // 当前拼接位置 (0.0 - 1.0)
    
    struct OverlapInfo {
        let topOverlapRect: CGRect // 第一张图的重叠区域
        let bottomOverlapRect: CGRect // 第二张图的重叠区域
        let confidence: Double
    }
}

// MARK: - 预览画布

struct PreviewCanvas: View {
    // MARK: - 绑定属性
    
    let previewData: StitchPreviewData
    @Binding var canvasState: CanvasState
    @Binding var showGrid: Bool
    @Binding var showOverlapHighlight: Bool
    
    // MARK: - 回调
    
    let onTap: (CGPoint) -> Void
    let onDoubleTap: () -> Void
    
    // MARK: - 计算属性
    
    /// 总高度（包含两张图）
    private var totalHeight: CGFloat {
        let topHeight = previewData.topImage.size.height
        let bottomHeight = previewData.bottomImage.size.height
        return topHeight + bottomHeight
    }
    
    /// 第一张图的结束位置（相对）
    private var topImageEndRatio: CGFloat {
        previewData.topImage.size.height / totalHeight
    }
    
    /// 当前拼接位置（像素）
    private var stitchPixelPosition: CGFloat {
        previewData.stitchPosition * totalHeight
    }
    
    /// 重叠区域范围（相对）
    var overlapRange: ClosedRange<CGFloat> {
        let topRatio = previewData.overlapInfo.topOverlapRect.minY / previewData.topImage.size.height
        let bottomRatio = previewData.overlapInfo.bottomOverlapRect.maxY / previewData.bottomImage.size.height
        let start = topRatio * topImageEndRatio
        let end = topImageEndRatio + bottomRatio * (1 - topImageEndRatio)
        return start...end
    }
    
    // MARK: - 视图主体
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景
                backgroundLayer
                
                // 画布内容
                canvasContent
                    .scaleEffect(canvasState.scale)
                    .offset(canvasState.offset)
                    .animation(.interactiveSpring(), value: canvasState.scale)
                    .animation(.interactiveSpring(), value: canvasState.offset)
                
                // 网格覆盖层
                if showGrid {
                    GridOverlay(
                        scale: canvasState.scale,
                        offset: canvasState.offset,
                        canvasSize: geometry.size
                    )
                }
                
                // 缩放指示器
                if canvasState.isPinching {
                    ScaleIndicator(scale: canvasState.scale)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SimultaneousGesture(
                    // 双指缩放手势
                    MagnificationGesture()
                        .onChanged { value in
                            handlePinchChanged(value)
                        }
                        .onEnded { _ in
                            canvasState.isPinching = false
                        },
                    // 平移手势
                    DragGesture()
                        .onChanged { value in
                            handlePanChanged(value)
                        }
                        .onEnded { _ in
                            canvasState.isDragging = false
                            canvasState.lastOffset = canvasState.offset
                        }
                )
            )
            .onTapGesture(count: 2) {
                onDoubleTap()
                withAnimation(.easeOut(duration: 0.3)) {
                    canvasState.reset()
                }
            }
            .onTapGesture { location in
                onTap(location)
            }
        }
    }
    
    // MARK: - 背景层
    
    private var backgroundLayer: some View {
        Color.gray.opacity(0.1)
            .overlay(
                // 棋盘格背景
                CheckerboardPattern()
                    .opacity(0.3)
            )
    }
    
    // MARK: - 画布内容
    
    private var canvasContent: some View {
        Canvas { context, size in
            // 绘制第一张图片
            drawTopImage(in: &context, canvasSize: size)
            
            // 绘制第二张图片（裁剪到拼接位置）
            drawBottomImage(in: &context, canvasSize: size)
            
            // 绘制重叠区域高亮
            if showOverlapHighlight {
                drawOverlapHighlight(in: &context, canvasSize: size)
            }
            
            // 绘制拼接线
            drawStitchLine(in: &context, canvasSize: size)
        }
    }
    
    // MARK: - 绘制方法
    
    private func drawTopImage(in context: inout GraphicsContext, canvasSize: CGSize) {
        let imageSize = previewData.topImage.size
        let scale = canvasSize.width / imageSize.width
        let drawHeight = imageSize.height * scale
        
        let drawRect = CGRect(
            x: 0,
            y: 0,
            width: canvasSize.width,
            height: drawHeight
        )
        
        if let cgImage = previewData.topImage.cgImage {
            context.draw(
                Image(uiImage: previewData.topImage),
                in: drawRect
            )
        }
        
        // 添加图片标签
        drawImageLabel(
            in: &context,
            text: "图片 1",
            at: CGPoint(x: 10, y: 10),
            color: .blue
        )
    }
    
    private func drawBottomImage(in context: inout GraphicsContext, canvasSize: CGSize) {
        let imageSize = previewData.bottomImage.size
        let scale = canvasSize.width / imageSize.width
        
        // 计算第二张图应该显示的起始位置（基于拼接线位置）
        let topImageHeight = previewData.topImage.size.height * scale
        let bottomImageHeight = imageSize.height * scale
        
        // 拼接位置（像素）
        let stitchY = stitchPixelPosition / totalHeight * (topImageHeight + bottomImageHeight)
        
        // 计算第二张图可见区域
        let visibleHeight = (topImageHeight + bottomImageHeight) - stitchY
        let startYInImage = (imageSize.height * scale - visibleHeight) / scale
        
        // 创建裁剪区域
        let visibleRect = CGRect(
            x: 0,
            y: startYInImage,
            width: imageSize.width,
            height: imageSize.height - startYInImage
        )
        
        // 绘制区域
        let drawRect = CGRect(
            x: 0,
            y: stitchY,
            width: canvasSize.width,
            height: visibleHeight
        )
        
        // 使用裁剪绘制
        context.withCGContext { cgContext in
            cgContext.saveGState()
            cgContext.addRect(drawRect)
            cgContext.clip()
            
            if let cgImage = previewData.bottomImage.cgImage {
                cgContext.draw(cgImage, in: drawRect)
            }
            
            cgContext.restoreGState()
        }
        
        // 添加图片标签
        drawImageLabel(
            in: &context,
            text: "图片 2",
            at: CGPoint(x: 10, y: stitchY + 10),
            color: .green
        )
    }
    
    private func drawOverlapHighlight(in context: inout GraphicsContext, canvasSize: CGSize) {
        let topScale = canvasSize.width / previewData.topImage.size.width
        let totalPixelHeight = totalHeight * topScale
        
        // 第一张图的重叠区域
        let topOverlap = previewData.overlapInfo.topOverlapRect
        let topOverlapRect = CGRect(
            x: 0,
            y: topOverlap.minY * topScale,
            width: canvasSize.width,
            height: topOverlap.height * topScale
        )
        
        // 绘制半透明覆盖
        context.fill(
            Path(topOverlapRect),
            with: .color(Color.yellow.opacity(0.2))
        )
        
        // 边框
        context.stroke(
            Path(topOverlapRect),
            with: .color(Color.yellow.opacity(0.6)),
            lineWidth: 1
        )
        
        // 第二张图的重叠区域（需要计算位置）
        let stitchY = stitchPixelPosition / totalHeight * totalPixelHeight
        let bottomOverlap = previewData.overlapInfo.bottomOverlapRect
        let bottomScale = canvasSize.width / previewData.bottomImage.size.width
        
        let bottomOverlapRect = CGRect(
            x: 0,
            y: stitchY,
            width: canvasSize.width,
            height: bottomOverlap.height * bottomScale
        )
        
        context.fill(
            Path(bottomOverlapRect),
            with: .color(Color.orange.opacity(0.2))
        )
        
        context.stroke(
            Path(bottomOverlapRect),
            with: .color(Color.orange.opacity(0.6)),
            lineWidth: 1
        )
    }
    
    private func drawStitchLine(in context: inout GraphicsContext, canvasSize: CGSize) {
        let totalPixelHeight = totalHeight * (canvasSize.width / previewData.topImage.size.width)
        let stitchY = stitchPixelPosition / totalHeight * totalPixelHeight
        
        // 虚线路径
        var linePath = Path()
        linePath.move(to: CGPoint(x: 0, y: stitchY))
        linePath.addLine(to: CGPoint(x: canvasSize.width, y: stitchY))
        
        // 绘制虚线效果
        context.stroke(
            linePath,
            with: .color(Color.blue),
            lineWidth: 2
        )
    }
    
    private func drawImageLabel(
        in context: inout GraphicsContext,
        text: String,
        at position: CGPoint,
        color: Color
    ) {
        // 这里简化处理，实际可以使用 TextRenderer
        let labelRect = CGRect(
            x: position.x,
            y: position.y,
            width: 60,
            height: 24
        )
        
        context.fill(
            Path(labelRect),
            with: .color(color.opacity(0.8))
        )
        
        context.stroke(
            Path(labelRect),
            with: .color(color),
            lineWidth: 1
        )
    }
    
    // MARK: - 手势处理
    
    private func handlePinchChanged(_ value: CGFloat) {
        canvasState.isPinching = true
        
        // 计算新的缩放值
        let newScale = canvasState.scale * value
        canvasState.scale = min(canvasState.maxScale, max(canvasState.minScale, newScale))
    }
    
    private func handlePanChanged(_ value: DragGesture.Value) {
        canvasState.isDragging = true
        
        // 计算新的偏移量
        let newOffset = CGSize(
            width: canvasState.lastOffset.width + value.translation.width,
            height: canvasState.lastOffset.height + value.translation.height
        )
        
        canvasState.offset = newOffset
    }
}

// MARK: - 棋盘格背景

struct CheckerboardPattern: View {
    var tileSize: CGFloat = 20
    
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let rows = Int(size.height / tileSize) + 1
                let cols = Int(size.width / tileSize) + 1
                
                for row in 0..<rows {
                    for col in 0..<cols {
                        let rect = CGRect(
                            x: CGFloat(col) * tileSize,
                            y: CGFloat(row) * tileSize,
                            width: tileSize,
                            height: tileSize
                        )
                        
                        let isDark = (row + col) % 2 == 0
                        context.fill(
                            Path(rect),
                            with: .color(isDark ? Color.gray.opacity(0.1) : Color.gray.opacity(0.05))
                        )
                    }
                }
            }
        }
    }
}

// MARK: - 网格覆盖层

struct GridOverlay: View {
    let scale: CGFloat
    let offset: CGSize
    let canvasSize: CGSize
    
    var body: some View {
        Canvas { context, size in
            let gridSpacing: CGFloat = 50 * scale
            
            // 垂直线
            var x = fmod(offset.width, gridSpacing)
            while x < size.width {
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(Color.gray.opacity(0.2)), lineWidth: 0.5)
                x += gridSpacing
            }
            
            // 水平线
            var y = fmod(offset.height, gridSpacing)
            while y < size.height {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(Color.gray.opacity(0.2)), lineWidth: 0.5)
                y += gridSpacing
            }
        }
    }
}

// MARK: - 缩放指示器

struct ScaleIndicator: View {
    let scale: CGFloat
    
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Text(String(format: "%.0f%%", scale * 100))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.6))
                    )
                Spacer()
            }
            .padding(.bottom, 20)
        }
    }
}

// MARK: - 预览

struct PreviewCanvas_Previews: PreviewProvider {
    static var previews: some View {
        PreviewCanvas(
            previewData: StitchPreviewData(
                topImage: UIImage(systemName: "photo")!,
                bottomImage: UIImage(systemName: "photo.fill")!,
                overlapInfo: .init(
                    topOverlapRect: CGRect(x: 0, y: 200, width: 300, height: 100),
                    bottomOverlapRect: CGRect(x: 0, y: 0, width: 300, height: 100),
                    confidence: 0.85
                ),
                stitchPosition: 0.5
            ),
            canvasState: .constant(CanvasState()),
            showGrid: .constant(true),
            showOverlapHighlight: .constant(true),
            onTap: { _ in },
            onDoubleTap: {}
        )
    }
}
