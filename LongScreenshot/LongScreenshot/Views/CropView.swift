import SwiftUI

/// 图片裁剪主视图
struct CropView: View {
    @StateObject private var viewModel: CropViewModel
    @Environment(\.dismiss) private var dismiss
    
    /// 裁剪完成回调
    var onCropComplete: ((UIImage) -> Void)?
    
    /// 初始化
    init(image: UIImage, onCropComplete: ((UIImage) -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: CropViewModel(image: image))
        self.onCropComplete = onCropComplete
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 顶部工具栏
                topToolbar
                
                // 裁剪区域
                cropArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                
                // 底部工具栏
                bottomToolbar
            }
            .navigationTitle("裁剪图片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                    .foregroundColor(.primary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        performCrop()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
                }
            }
        }
    }
    
    // MARK: - Top Toolbar
    
    private var topToolbar: some View {
        HStack(spacing: 20) {
            // 撤销按钮
            Button(action: { viewModel.undo() }) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.title3)
                    .foregroundColor(viewModel.canUndo ? .primary : .gray)
            }
            .disabled(!viewModel.canUndo)
            
            // 重做按钮
            Button(action: { viewModel.redo() }) {
                Image(systemName: "arrow.uturn.forward")
                    .font(.title3)
                    .foregroundColor(viewModel.canRedo ? .primary : .gray)
            }
            .disabled(!viewModel.canRedo)
            
            Spacer()
            
            // 重置按钮
            Button(action: { viewModel.resetToDefault() }) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.title3)
                    .foregroundColor(.primary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(UIColor.systemBackground))
    }
    
    // MARK: - Crop Area
    
    private var cropArea: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景图片
                imageLayer
                
                // 裁剪遮罩层
                CropOverlayView(viewModel: viewModel)
                
                // 手势层（双指缩放、单指平移）
                gestureLayer
            }
        }
    }
    
    // MARK: - Image Layer
    
    private var imageLayer: some View {
        GeometryReader { geometry in
            let displayRect = viewModel.displayImageRect
            
            Image(uiImage: viewModel.originalImage)
                .resizable()
                .scaledToFit()
                .frame(width: displayRect.width, height: displayRect.height)
                .position(x: displayRect.midX, y: displayRect.midY)
                .scaleEffect(viewModel.scale)
                .offset(viewModel.offset)
                .rotationEffect(.degrees(viewModel.rotation))
                .scaleEffect(x: viewModel.isFlippedHorizontally ? -1 : 1, 
                            y: viewModel.isFlippedVertically ? -1 : 1)
        }
    }
    
    // MARK: - Gesture Layer
    
    private var gestureLayer: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    // 双指缩放
                    MagnificationGesture()
                        .onChanged { value in
                            let delta = value - 1.0
                            let newScale = max(1.0, min(3.0, viewModel.scale + delta * 0.5))
                            viewModel.scale = newScale
                        }
                        .onEnded { _ in }
                )
                .simultaneousGesture(
                    // 单指平移
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            viewModel.offset = CGSize(
                                width: viewModel.offset.width + value.translation.width * 0.5,
                                height: viewModel.offset.height + value.translation.height * 0.5
                            )
                        }
                        .onEnded { _ in
                            withAnimation(.spring()) {
                                viewModel.offset = .zero
                            }
                        }
                )
        }
    }
    
    // MARK: - Bottom Toolbar
    
    private var bottomToolbar: some View {
        VStack(spacing: 16) {
            // 比例选择
            ratioSelector
            
            // 操作按钮
            actionButtons
        }
        .padding(.horizontal)
        .padding(.vertical, 16)
        .background(Color(UIColor.systemBackground))
    }
    
    // MARK: - Ratio Selector
    
    private var ratioSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(CropRatio.allCases, id: \.self) { ratio in
                    RatioButton(
                        title: ratio.title,
                        isSelected: viewModel.selectedRatio == ratio,
                        action: { viewModel.setRatio(ratio) }
                    )
                }
            }
            .padding(.horizontal, 4)
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: 30) {
            // 左旋
            CropActionButton(
                icon: "rotate.left",
                title: "左旋",
                action: { viewModel.rotate(clockwise: false) }
            )
            
            // 右旋
            CropActionButton(
                icon: "rotate.right",
                title: "右旋",
                action: { viewModel.rotate(clockwise: true) }
            )
            
            // 水平翻转
            CropActionButton(
                icon: "arrow.left.and.right",
                title: "水平翻转",
                action: { viewModel.flipHorizontally() }
            )
            
            // 垂直翻转
            CropActionButton(
                icon: "arrow.up.and.down",
                title: "垂直翻转",
                action: { viewModel.flipVertically() }
            )
        }
    }
    
    // MARK: - Helper Methods
    
    private func performCrop() {
        Task {
            do {
                let croppedImage = try await viewModel.crop()
                await MainActor.run {
                    onCropComplete?(croppedImage)
                    dismiss()
                }
            } catch {
                print("裁剪失败: \(error)")
            }
        }
    }
}

// MARK: - Ratio Button

private struct RatioButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor : Color.gray.opacity(0.2))
                )
        }
    }
}

// MARK: - Crop Action Button

private struct CropActionButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption2)
            }
            .foregroundColor(.primary)
            .frame(minWidth: 60)
        }
    }
}

// MARK: - Preview

struct CropView_Previews: PreviewProvider {
    static var previews: some View {
        if let image = UIImage(systemName: "photo") {
            CropView(image: image)
        }
    }
}
