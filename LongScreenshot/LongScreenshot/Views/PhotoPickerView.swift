import SwiftUI
import PhotosUI

/// 图片选择器完整视图（包含选择、预览、排序功能）
struct PhotoPickerView: View {
    @Binding var selectedImages: [UIImage]
    @State private var isShowingImagePicker = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var isEditing = false
    
    let minSelectionCount: Int
    let maxSelectionCount: Int
    let onComplete: (() -> Void)?
    let onCancel: (() -> Void)?
    
    init(
        selectedImages: Binding<[UIImage]>,
        minSelectionCount: Int = 2,
        maxSelectionCount: Int = 20,
        onComplete: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self._selectedImages = selectedImages
        self.minSelectionCount = minSelectionCount
        self.maxSelectionCount = maxSelectionCount
        self.onComplete = onComplete
        self.onCancel = onCancel
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            headerView
            
            // 图片预览列表
            if selectedImages.isEmpty {
                emptyStateView
            } else {
                imagePreviewList
            }
            
            // 底部操作栏
            bottomActionBar
        }
        .sheet(isPresented: $isShowingImagePicker) {
            ImagePicker(
                selectedImages: $selectedImages,
                isPresented: $isShowingImagePicker,
                errorMessage: $errorMessage,
                showError: $showError,
                minSelectionCount: minSelectionCount,
                maxSelectionCount: maxSelectionCount
            )
        }
        .alert("提示", isPresented: $showError, presenting: errorMessage) { _ in
            Button("确定") {}
        } message: { message in
            Text(message)
        }
        .onAppear {
            // 如果没有图片，自动打开选择器
            if selectedImages.isEmpty {
                isShowingImagePicker = true
            }
        }
    }
    
    // MARK: - 子视图
    
    /// 顶部工具栏
    private var headerView: some View {
        HStack {
            Button(action: {
                onCancel?()
            }) {
                Text("取消")
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(spacing: 4) {
                Text("选择图片")
                    .font(.headline)
                Text("\(selectedImages.count)/\(maxSelectionCount) 张")
                    .font(.caption)
                    .foregroundColor(selectedImages.count >= minSelectionCount ? .green : .secondary)
            }
            
            Spacer()
            
            if !selectedImages.isEmpty {
                Button(action: {
                    isEditing.toggle()
                }) {
                    Text(isEditing ? "完成" : "编辑")
                        .foregroundColor(.accentColor)
                }
            } else {
                Spacer()
                    .frame(width: 40)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
    
    /// 空状态视图
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.6))
            
            Text("还没有选择图片")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("请点击下方按钮选择 \(minSelectionCount)-\(maxSelectionCount) 张图片")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(action: {
                isShowingImagePicker = true
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("选择图片")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.accentColor)
                .cornerRadius(8)
            }
            .padding(.top, 10)
            
            Spacer()
        }
    }
    
    /// 图片预览列表（支持拖拽排序）
    private var imagePreviewList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // 图片数量提示
                HStack {
                    Image(systemName: selectedImages.count >= minSelectionCount ? "checkmark.circle.fill" : "info.circle")
                        .foregroundColor(selectedImages.count >= minSelectionCount ? .green : .orange)
                    Text("已选择 \(selectedImages.count) 张图片")
                        .font(.subheadline)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                // 图片网格
                if isEditing {
                    // 编辑模式：支持拖拽排序
                    reorderableGrid
                } else {
                    // 预览模式：普通网格
                    previewGrid
                }
            }
            .padding(.bottom, 20)
        }
    }
    
    /// 可排序的图片网格（编辑模式）
    private var reorderableGrid: some View {
        LazyVStack(spacing: 12) {
            ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                DraggableImageRow(
                    image: image,
                    index: index,
                    totalCount: selectedImages.count,
                    onMove: { source, destination in
                        moveImage(from: source, to: destination)
                    },
                    onDelete: {
                        deleteImage(at: index)
                    }
                )
            }
        }
        .padding(.horizontal)
    }
    
    /// 预览模式图片网格
    private var previewGrid: some View {
        LazyVStack(spacing: 12) {
            ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                ImagePreviewRow(
                    image: image,
                    index: index,
                    totalCount: selectedImages.count
                )
            }
        }
        .padding(.horizontal)
    }
    
    /// 底部操作栏
    private var bottomActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 16) {
                // 添加更多图片按钮
                Button(action: {
                    isShowingImagePicker = true
                }) {
                    HStack {
                        Image(systemName: "plus")
                        Text("添加")
                    }
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(8)
                }
                
                Spacer()
                
                // 完成按钮
                Button(action: {
                    if selectedImages.count >= minSelectionCount {
                        onComplete?()
                    } else {
                        errorMessage = "请至少选择 \(minSelectionCount) 张图片"
                        showError = true
                    }
                }) {
                    Text("完成 (\(selectedImages.count))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .background(selectedImages.count >= minSelectionCount ? Color.accentColor : Color.gray)
                        .cornerRadius(8)
                }
                .disabled(selectedImages.count < minSelectionCount)
            }
            .padding()
            .background(Color(.systemBackground))
        }
    }
    
    // MARK: - 操作方法
    
    /// 移动图片位置
    private func moveImage(from source: IndexSet, to destination: Int) {
        selectedImages.move(fromOffsets: source, toOffset: destination)
    }
    
    /// 删除图片
    private func deleteImage(at index: Int) {
        guard index < selectedImages.count else { return }
        selectedImages.remove(at: index)
    }
}

// MARK: - 图片预览行视图

/// 图片预览行（不可拖拽）
struct ImagePreviewRow: View {
    let image: UIImage
    let index: Int
    let totalCount: Int
    
    var body: some View {
        HStack(spacing: 12) {
            // 序号
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 28, height: 28)
                Text("\(index + 1)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
            }
            
            // 图片缩略图
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
            
            // 图片信息
            VStack(alignment: .leading, spacing: 4) {
                Text("图片 \(index + 1)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("\(Int(image.size.width)) × \(Int(image.size.height))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - 可拖拽图片行视图

/// 可拖拽排序的图片行
struct DraggableImageRow: View {
    let image: UIImage
    let index: Int
    let totalCount: Int
    let onMove: (IndexSet, Int) -> Void
    let onDelete: () -> Void
    
    @State private var isDragging = false
    
    var body: some View {
        HStack(spacing: 12) {
            // 拖拽手柄
            Image(systemName: "line.horizontal.3")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            // 序号
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 28, height: 28)
                Text("\(index + 1)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
            }
            
            // 图片缩略图
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
            
            // 图片信息
            VStack(alignment: .leading, spacing: 4) {
                Text("图片 \(index + 1)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("\(Int(image.size.width)) × \(Int(image.size.height))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 删除按钮
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.red.opacity(0.8))
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isDragging ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onDrag {
            isDragging = true
            return NSItemProvider()
        }
        .onDrop(
            of: [.text],
            delegate: ImageDropDelegate(
                item: image,
                items: [],
                currentIndex: index,
                onMove: onMove
            )
        )
    }
}

// MARK: - 拖拽代理

/// 图片拖拽代理
struct ImageDropDelegate: DropDelegate {
    let item: UIImage
    let items: [UIImage]
    let currentIndex: Int
    let onMove: (IndexSet, Int) -> Void
    
    func performDrop(info: DropInfo) -> Bool {
        return true
    }
    
    func dropEntered(info: DropInfo) {
        // 处理拖拽进入逻辑
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}

// MARK: - 预览

#Preview {
    NavigationView {
        PhotoPickerView(
            selectedImages: .constant([]),
            minSelectionCount: 2,
            maxSelectionCount: 20
        )
    }
}
