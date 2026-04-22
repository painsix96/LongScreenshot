import SwiftUI

// MARK: - 标注主界面
struct AnnotationView: View {
    @StateObject private var viewModel = AnnotationViewModel()
    let image: UIImage
    
    @Environment(\.dismiss) private var dismiss
    @State private var showSaveConfirmation = false
    @State private var showClearConfirmation = false
    @State private var annotatedImage: UIImage?
    @State private var showShareSheet = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 画布区域
                DrawingCanvas(viewModel: viewModel, baseImage: image)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // 工具栏
                AnnotationToolBar(viewModel: viewModel)
                    .frame(height: 100)
            }
            .navigationTitle("图片标注")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 左侧取消按钮
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        if viewModel.hasAnnotations {
                            showClearConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                }
                
                // 右侧保存按钮
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveAnnotatedImage()
                    }
                    .disabled(!viewModel.hasAnnotations)
                }
                
                // 分享按钮
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        shareAnnotatedImage()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(!viewModel.hasAnnotations)
                }
            }
            .sheet(isPresented: $viewModel.showTextInput) {
                TextEditSheet(viewModel: viewModel)
            }
            .alert("保存成功", isPresented: $showSaveConfirmation) {
                Button("确定") {
                    dismiss()
                }
            } message: {
                Text("标注后的图片已保存到相册")
            }
            .alert("放弃更改？", isPresented: $showClearConfirmation) {
                Button("取消", role: .cancel) { }
                Button("放弃", role: .destructive) {
                    dismiss()
                }
            } message: {
                Text("您有未保存的标注，确定要放弃吗？")
            }
            .sheet(isPresented: $showShareSheet) {
                if let image = annotatedImage {
                    ShareSheet(activityItems: [image])
                }
            }
        }
    }
    
    // MARK: - 保存标注图片
    private func saveAnnotatedImage() {
        if let result = viewModel.exportAnnotatedImage(baseImage: image) {
            UIImageWriteToSavedPhotosAlbum(result, nil, nil, nil)
            annotatedImage = result
            showSaveConfirmation = true
        }
    }
    
    // MARK: - 分享标注图片
    private func shareAnnotatedImage() {
        if let result = viewModel.exportAnnotatedImage(baseImage: image) {
            annotatedImage = result
            showShareSheet = true
        }
    }
}

// MARK: - 文字编辑弹窗
struct TextEditSheet: View {
    @ObservedObject var viewModel: AnnotationViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("编辑文字")
                    .font(.headline)
                    .padding(.top)
                
                TextEditor(text: $viewModel.editingText)
                    .font(.system(size: viewModel.toolSettings.textFontSize))
                    .frame(height: 150)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .padding(.horizontal)
                
                // 字体大小调节
                VStack(alignment: .leading, spacing: 8) {
                    Text("字体大小: \(Int(viewModel.toolSettings.textFontSize))pt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Image(systemName: "textformat.size.smaller")
                        Slider(
                            value: $viewModel.toolSettings.textFontSize,
                            in: 10...60,
                            step: 2
                        )
                        Image(systemName: "textformat.size.larger")
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        viewModel.finishEditingText()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(350)])
    }
}

// MARK: - 预览
struct AnnotationView_Previews: PreviewProvider {
    static var previews: some View {
        // 创建一个示例图片
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400))
        let image = renderer.image { context in
            UIColor.systemGray6.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: 300, height: 400)))
            
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 50, y: 50, width: 200, height: 100))
            
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 50, y: 200, width: 200, height: 150))
        }
        
        return AnnotationView(image: image)
            .previewDisplayName("Annotation View")
    }
}
