import SwiftUI

// MARK: - 调整结果

struct ManualAdjustmentResult {
    let confirmed: Bool
    let stitchPosition: CGFloat
    let topCropHeight: CGFloat // 第一张图保留的高度
    let bottomCropOffset: CGFloat // 第二张图起始偏移
}

// MARK: - 视图模型

@MainActor
class ManualAdjustmentViewModel: ObservableObject {
    // MARK: - 输入数据
    let topImage: UIImage
    let bottomImage: UIImage
    let overlapResult: OverlapResult
    
    // MARK: - 发布属性
    @Published var stitchingLine: StitchingLine
    @Published var canvasState: CanvasState
    @Published var showGrid: Bool = true
    @Published var showOverlapHighlight: Bool = true
    @Published var isProcessing: Bool = false
    @Published var showConfirmation: Bool = false
    @Published var errorMessage: String?
    
    // MARK: - 计算属性
    
    /// 拼接线位置（相对0-1）
    var stitchPosition: CGFloat {
        stitchingLine.position
    }
    
    /// 重叠区域范围（相对）
    var overlapRange: ClosedRange<CGFloat> {
        let topHeight = topImage.size.height
        let bottomHeight = bottomImage.size.height
        let totalHeight = topHeight + bottomHeight
        
        let overlapHeight = CGFloat(overlapResult.bestStitchPosition.overlapHeight)
        let topOverlapStart = (topHeight - overlapHeight) / totalHeight
        let topOverlapEnd = topHeight / totalHeight
        
        return topOverlapStart...topOverlapEnd
    }
    
    /// 预览数据
    var previewData: StitchPreviewData {
        StitchPreviewData(
            topImage: topImage,
            bottomImage: bottomImage,
            overlapInfo: .init(
                topOverlapRect: overlapResult.overlapRect1,
                bottomOverlapRect: overlapResult.overlapRect2,
                confidence: overlapResult.confidence
            ),
            stitchPosition: stitchPosition
        )
    }
    
    /// 吸附配置
    var snapConfig: SnapConfiguration {
        SnapConfiguration(
            enabled: true,
            snapThreshold: 20,
            snapToEdges: false,
            snapToOverlapCenter: true,
            edgeSnapPoints: [
                overlapRange.lowerBound,
                overlapRange.upperBound
            ]
        )
    }
    
    /// 容器尺寸（用于拼接线）
    var containerSize: CGSize {
        let width: CGFloat = min(UIScreen.main.bounds.width - 32, 400)
        let topHeight = topImage.size.height
        let bottomHeight = bottomImage.size.height
        let totalHeight = topHeight + bottomHeight
        let scale = width / topImage.size.width
        return CGSize(width: width, height: totalHeight * scale)
    }
    
    // MARK: - 初始化
    
    init(
        topImage: UIImage,
        bottomImage: UIImage,
        overlapResult: OverlapResult,
        initialPosition: CGFloat? = nil
    ) {
        self.topImage = topImage
        self.bottomImage = bottomImage
        self.overlapResult = overlapResult
        
        // 设置初始位置（默认在重叠区域中心）
        let initialPos = initialPosition ?? {
            let topHeight = topImage.size.height
            let totalHeight = topHeight + bottomImage.size.height
            let overlapHeight = CGFloat(overlapResult.bestStitchPosition.overlapHeight)
            let centerY = (topHeight - overlapHeight / 2) / totalHeight
            return centerY
        }()
        
        self.stitchingLine = StitchingLine(position: initialPos)
        self.canvasState = CanvasState()
    }
    
    // MARK: - 方法
    
    /// 确认调整
    func confirmAdjustment() -> ManualAdjustmentResult {
        let topHeight = topImage.size.height
        let totalHeight = topHeight + bottomImage.size.height
        let stitchY = stitchPosition * totalHeight
        
        // 计算第一张图的裁剪高度
        let topCropHeight = min(stitchY, topHeight)
        
        // 计算第二张图的起始偏移
        let bottomCropOffset = max(0, stitchY - topHeight)
        
        return ManualAdjustmentResult(
            confirmed: true,
            stitchPosition: stitchPosition,
            topCropHeight: topCropHeight,
            bottomCropOffset: bottomCropOffset
        )
    }
    
    /// 重置位置
    func resetPosition() {
        withAnimation(.easeOut(duration: 0.3)) {
            let topHeight = topImage.size.height
            let totalHeight = topHeight + bottomImage.size.height
            let overlapHeight = CGFloat(overlapResult.bestStitchPosition.overlapHeight)
            let centerY = (topHeight - overlapHeight / 2) / totalHeight
            stitchingLine.position = centerY
        }
    }
    
    /// 重置画布
    func resetCanvas() {
        withAnimation(.easeOut(duration: 0.3)) {
            canvasState.reset()
        }
    }
    
    /// 微调位置
    func adjustPosition(by offset: CGFloat) {
        withAnimation(.easeOut(duration: 0.2)) {
            let newPosition = stitchingLine.position + offset
            stitchingLine.position = max(overlapRange.lowerBound, min(overlapRange.upperBound, newPosition))
        }
    }
    
    /// 生成预览图
    func generatePreviewImage() async -> UIImage? {
        isProcessing = true
        defer { isProcessing = false }
        
        let result = confirmAdjustment()
        
        return await Task.detached(priority: .userInitiated) {
            let format = UIGraphicsImageRendererFormat()
            format.scale = self.topImage.scale
            
            let size = CGSize(
                width: self.topImage.size.width,
                height: result.topCropHeight + (self.bottomImage.size.height - result.bottomCropOffset)
            )
            
            let renderer = UIGraphicsImageRenderer(size: size, format: format)
            return renderer.image { context in
                // 绘制第一张图（裁剪）
                let topDrawRect = CGRect(
                    x: 0,
                    y: 0,
                    width: self.topImage.size.width,
                    height: result.topCropHeight
                )
                self.topImage.draw(in: topDrawRect)
                
                // 绘制第二张图（从偏移位置开始）
                let bottomDrawRect = CGRect(
                    x: 0,
                    y: result.topCropHeight,
                    width: self.bottomImage.size.width,
                    height: self.bottomImage.size.height - result.bottomCropOffset
                )
                
                // 计算第二张图需要绘制的部分
                let bottomSourceRect = CGRect(
                    x: 0,
                    y: result.bottomCropOffset,
                    width: self.bottomImage.size.width,
                    height: self.bottomImage.size.height - result.bottomCropOffset
                )
                
                if let cgImage = self.bottomImage.cgImage?.cropping(to: bottomSourceRect) {
                    UIImage(cgImage: cgImage).draw(in: bottomDrawRect)
                }
            }
        }.value
    }
}

// MARK: - 手动调整视图

struct ManualAdjustmentView: View {
    @StateObject private var viewModel: ManualAdjustmentViewModel
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - 回调
    let onConfirm: (ManualAdjustmentResult) -> Void
    let onCancel: () -> Void
    
    // MARK: - 初始化
    
    init(
        topImage: UIImage,
        bottomImage: UIImage,
        overlapResult: OverlapResult,
        initialPosition: CGFloat? = nil,
        onConfirm: @escaping (ManualAdjustmentResult) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._viewModel = StateObject(wrappedValue: ManualAdjustmentViewModel(
            topImage: topImage,
            bottomImage: bottomImage,
            overlapResult: overlapResult,
            initialPosition: initialPosition
        ))
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }
    
    // MARK: - 视图主体
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 主内容
                VStack(spacing: 0) {
                    // 预览区域
                    previewSection
                    
                    // 控制面板
                    controlPanel
                }
                
                // 加载遮罩
                if viewModel.isProcessing {
                    loadingOverlay
                }
            }
            .navigationTitle("手动调整拼接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        onCancel()
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认") {
                        let result = viewModel.confirmAdjustment()
                        onConfirm(result)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("错误", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("确定") {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
    
    // MARK: - 预览区域
    
    private var previewSection: some View {
        GeometryReader { geometry in
            ZStack {
                // Canvas 预览
                PreviewCanvas(
                    previewData: viewModel.previewData,
                    canvasState: $viewModel.canvasState,
                    showGrid: $viewModel.showGrid,
                    showOverlapHighlight: $viewModel.showOverlapHighlight,
                    onTap: { location in
                        handleCanvasTap(at: location)
                    },
                    onDoubleTap: {
                        viewModel.resetCanvas()
                    }
                )
                
                // 拼接线覆盖层
                StitchingLineView(
                    line: $viewModel.stitchingLine,
                    canvasScale: $viewModel.canvasState.scale,
                    canvasOffset: $viewModel.canvasState.offset,
                    containerSize: viewModel.containerSize,
                    overlapRange: viewModel.overlapRange,
                    snapConfig: viewModel.snapConfig,
                    onPositionChanged: { position in
                        // 位置变化时更新
                    },
                    onDragEnded: { position in
                        // 拖动结束时
                    }
                )
                .frame(width: viewModel.containerSize.width, height: viewModel.containerSize.height)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        }
        .background(Color(UIColor.systemBackground))
    }
    
    // MARK: - 控制面板
    
    private var controlPanel: some View {
        VStack(spacing: 16) {
            // 信息显示
            infoSection
            
            Divider()
            
            // 微调控件
            fineAdjustmentSection
            
            Divider()
            
            // 显示选项
            displayOptionsSection
        }
        .padding()
        .background(
            Color(UIColor.secondarySystemBackground)
                .ignoresSafeArea(edges: .bottom)
        )
    }
    
    // MARK: - 信息显示
    
    private var infoSection: some View {
        HStack(spacing: 20) {
            InfoItem(
                title: "重叠区域",
                value: String(format: "%.0f px", viewModel.overlapResult.bestStitchPosition.overlapHeight)
            )
            
            InfoItem(
                title: "置信度",
                value: String(format: "%.0f%%", viewModel.overlapResult.confidence * 100)
            )
            
            InfoItem(
                title: "当前位置",
                value: String(format: "%.1f%%", viewModel.stitchPosition * 100)
            )
            
            Spacer()
        }
    }
    
    // MARK: - 微调控件
    
    private var fineAdjustmentSection: some View {
        VStack(spacing: 12) {
            Text("微调位置")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 20) {
                // 向上微调
                Button {
                    viewModel.adjustPosition(by: -0.01)
                } label: {
                    AdjustmentButtonLabel(
                        icon: "arrow.up",
                        text: "上移"
                    )
                }
                
                // 重置
                Button {
                    viewModel.resetPosition()
                } label: {
                    AdjustmentButtonLabel(
                        icon: "arrow.counterclockwise",
                        text: "重置"
                    )
                }
                
                // 向下微调
                Button {
                    viewModel.adjustPosition(by: 0.01)
                } label: {
                    AdjustmentButtonLabel(
                        icon: "arrow.down",
                        text: "下移"
                    )
                }
            }
        }
    }
    
    // MARK: - 显示选项
    
    private var displayOptionsSection: some View {
        HStack(spacing: 20) {
            Toggle(isOn: $viewModel.showGrid) {
                Label("网格", systemImage: "grid")
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            
            Toggle(isOn: $viewModel.showOverlapHighlight) {
                Label("重叠区域", systemImage: "rectangle.dashed")
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            
            Spacer()
            
            // 重置画布
            Button {
                viewModel.resetCanvas()
            } label: {
                Label("重置视图", systemImage: "arrow.2.circlepath")
            }
            .buttonStyle(.bordered)
        }
    }
    
    // MARK: - 加载遮罩
    
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                
                Text("处理中...")
                    .foregroundColor(.white)
                    .font(.headline)
            }
        }
    }
    
    // MARK: - 处理
    
    private func handleCanvasTap(at location: CGPoint) {
        // 可以添加点击调整位置的功能
    }
}

// MARK: - 辅助视图

struct InfoItem: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
        }
    }
}

struct AdjustmentButtonLabel: View {
    let icon: String
    let text: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 20))
            Text(text)
                .font(.caption)
        }
        .frame(width: 60, height: 60)
        .background(Color(UIColor.tertiarySystemBackground))
        .cornerRadius(8)
    }
}

// MARK: - 预览

struct ManualAdjustmentView_Previews: PreviewProvider {
    static var previews: some View {
        let topImage = UIImage(systemName: "photo")!
        let bottomImage = UIImage(systemName: "photo.fill")!
        let overlapResult = OverlapResult(
            hasOverlap: true,
            overlapRect1: CGRect(x: 0, y: 200, width: 300, height: 100),
            overlapRect2: CGRect(x: 0, y: 0, width: 300, height: 100),
            similarityScore: 0.85,
            bestStitchPosition: .init(
                yOffset: 200,
                overlapHeight: 100,
                quality: .good
            ),
            confidence: 0.85,
            processingTime: 0.1,
            topCrop1: 0,
            bottomCrop1: 0,
            topCrop2: 0,
            bottomCrop2: 0
        )
        
        ManualAdjustmentView(
            topImage: topImage,
            bottomImage: bottomImage,
            overlapResult: overlapResult,
            onConfirm: { _ in },
            onCancel: {}
        )
    }
}
