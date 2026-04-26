import SwiftUI

// MARK: - 绘制画布
struct DrawingCanvas: View {
    @ObservedObject var viewModel: AnnotationViewModel
    let baseImage: UIImage
    
    @State private var canvasSize: CGSize = .zero
    @State private var imageDisplaySize: CGSize = .zero
    @State private var imageOffset: CGPoint = .zero
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景图片
                Image(uiImage: baseImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .background(
                        GeometryReader { imageGeometry in
                            Color.clear
                                .onAppear {
                                    calculateImageFrame(in: geometry.size, imageSize: baseImage.size)
                                }
                                .onChange(of: geometry.size) { newSize in
                                    calculateImageFrame(in: newSize, imageSize: baseImage.size)
                                }
                        }
                    )
                
                // 标注绘制层
                Canvas { context, size in
                    drawAnnotations(in: &context, size: size)
                }
                .allowsHitTesting(false)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color.black.opacity(0.05))
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        handleDragChanged(value)
                    }
                    .onEnded { value in
                        handleDragEnded(value)
                    }
            )
            .onTapGesture { location in
                handleTap(at: location)
            }
        }
    }
    
    // MARK: - 绘制标注
    private func drawAnnotations(in context: inout GraphicsContext, size: CGSize) {
        for anyAnnotation in viewModel.annotations {
            anyAnnotation.annotation.draw(in: context, size: size)
        }
    }
    
    // MARK: - 手势处理
    private func handleDragChanged(_ value: DragGesture.Value) {
        let location = value.location
        let translation = value.translation
        
        // 检查是否正在绘制
        if viewModel.isDrawing {
            // 继续绘制
            viewModel.continueDrawing(to: location)
        } else if viewModel.selectedAnnotationId != nil {
            // 移动选中的标注
            let offset = CGSize(width: translation.width, height: translation.height)
            viewModel.moveSelectedAnnotation(by: offset)
        }
    }
    
    private func handleDragEnded(_ value: DragGesture.Value) {
        if viewModel.isDrawing {
            viewModel.endDrawing()
        }
    }
    
    private func handleTap(at location: CGPoint) {
        // 如果正在编辑文字，先完成编辑
        if viewModel.showTextInput {
            viewModel.finishEditingText()
            return
        }
        
        // 尝试选择标注
        let wasSelected = viewModel.selectAnnotation(at: location)
        
        // 如果没有选中任何标注，根据当前工具开始绘制
        if !wasSelected {
            viewModel.startDrawing(at: location)
        }
    }
    
    // MARK: - 计算图片显示尺寸
    private func calculateImageFrame(in containerSize: CGSize, imageSize: CGSize) {
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height
        
        if imageAspect > containerAspect {
            // 图片较宽，以容器宽度为准
            let width = containerSize.width
            let height = width / imageAspect
            imageDisplaySize = CGSize(width: width, height: height)
            imageOffset = CGPoint(
                x: 0,
                y: (containerSize.height - height) / 2
            )
        } else {
            // 图片较高，以容器高度为准
            let height = containerSize.height
            let width = height * imageAspect
            imageDisplaySize = CGSize(width: width, height: height)
            imageOffset = CGPoint(
                x: (containerSize.width - width) / 2,
                y: 0
            )
        }
        
        canvasSize = containerSize
    }
}

// MARK: - 带缩放支持的画布
struct ScalableDrawingCanvas: View {
    @ObservedObject var viewModel: AnnotationViewModel
    let baseImage: UIImage
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    private let minScale: CGFloat = 0.5
    private let maxScale: CGFloat = 5.0
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                DrawingCanvas(viewModel: viewModel, baseImage: baseImage)
                    .frame(
                        width: geometry.size.width * scale,
                        height: geometry.size.height * scale
                    )
                    .scaleEffect(scale)
            }
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let delta = value / lastScale
                        lastScale = value
                        scale = min(max(scale * delta, minScale), maxScale)
                    }
                    .onEnded { _ in
                        lastScale = 1.0
                    }
            )
            .onTapGesture(count: 2) {
                // 双击重置缩放
                withAnimation(.spring()) {
                    scale = 1.0
                    offset = .zero
                }
            }
        }
    }
}

// MARK: - 画布预览
struct DrawingCanvas_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = AnnotationViewModel()
        
        // 创建一个示例图片
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400))
        let image = renderer.image { context in
            UIColor.systemGray6.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: 300, height: 400)))
            
            // 绘制一些示例内容
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 50, y: 50, width: 200, height: 100))
            
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 50, y: 200, width: 200, height: 150))
        }
        
        return DrawingCanvas(viewModel: viewModel, baseImage: image)
            .previewDisplayName("Drawing Canvas")
    }
}
