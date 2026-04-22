import SwiftUI

/// 导出视图
struct ExportView: View {
    // MARK: - Properties

    /// 要导出的图片
    let image: UIImage

    /// 关闭回调
    let onDismiss: () -> Void

    /// 导出完成回调
    let onExportComplete: ((ExportResult) -> Void)?

    // MARK: - State

    @StateObject private var exportService = ExportService.shared
    @State private var configuration = ExportConfiguration.default
    @State private var showShareSheet = false
    @State private var showSaveSuccess = false
    @State private var shareItems: [Any] = []
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var estimatedFileSize: Int64 = 0
    @State private var isCalculatingSize = false

    // MARK: - Constants

    /// 图片预览最大高度
    private let previewMaxHeight: CGFloat = 400

    // MARK: - Initialization

    init(
        image: UIImage,
        onDismiss: @escaping () -> Void,
        onExportComplete: ((ExportResult) -> Void)? = nil
    ) {
        self.image = image
        self.onDismiss = onDismiss
        self.onExportComplete = onExportComplete
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 图片预览区域
                previewSection

                ScrollView {
                    VStack(spacing: 24) {
                        // 格式选择
                        formatSection

                        // JPG 质量滑块（仅在 JPG 格式时显示）
                        if configuration.format == .jpeg {
                            qualitySection
                        }

                        // 文件信息
                        fileInfoSection

                        // 导出进度
                        if exportService.isExporting {
                            progressSection
                        }
                    }
                    .padding()
                }

                // 底部按钮
                bottomButtons
            }
            .navigationTitle("导出设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        exportService.cancelExport()
                        onDismiss()
                    }
                    .disabled(exportService.isExporting)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(
                    activityItems: shareItems,
                    completion: { completed in
                        if completed {
                            // 分享成功，可以执行一些操作
                        }
                    }
                )
            }
            .alert("保存成功", isPresented: $showSaveSuccess) {
                Button("确定") {
                    onDismiss()
                }
            } message: {
                Text("图片已成功保存到相册")
            }
            .alert("导出失败", isPresented: $showError) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                calculateEstimatedSize()
            }
            .onChange(of: configuration.format) { _ in
                calculateEstimatedSize()
            }
            .onChange(of: configuration.jpegQuality) { _ in
                calculateEstimatedSize()
            }
        }
    }

    // MARK: - 视图组件

    /// 图片预览区域
    private var previewSection: some View {
        VStack(spacing: 12) {
            // 图片预览
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: previewMaxHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                .padding(.horizontal)

            // 尺寸信息
            HStack(spacing: 16) {
                Label(
                    "\(Int(image.size.width)) × \(Int(image.size.height))",
                    systemImage: "crop"
                )
                .font(.caption)
                .foregroundColor(.secondary)

                Text("•")
                    .foregroundColor(.secondary)

                Label(
                    String(format: "%.1f MB", Double(estimatedFileSize) / 1_048_576.0),
                    systemImage: "doc"
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical)
        .background(Color(.systemBackground))
    }

    /// 格式选择区域
    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("导出格式")
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(ExportFormat.allCases) { format in
                    FormatOptionRow(
                        format: format,
                        isSelected: configuration.format == format,
                        estimatedSize: estimatedFileSizeFor(format: format)
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            configuration.format = format
                        }
                    }
                }
            }
        }
    }

    /// 质量滑块区域
    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("图片质量")
                    .font(.headline)

                Spacer()

                Text("\(Int(configuration.jpegQuality * 100))%")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
                    .monospacedDigit()
            }

            VStack(spacing: 8) {
                Slider(
                    value: $configuration.jpegQuality,
                    in: 0.1...1.0,
                    step: 0.05
                ) {
                    Text("质量")
                } minimumValueLabel: {
                    Text("10%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } maximumValueLabel: {
                    Text("100%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // 质量标签
                HStack {
                    QualityLabel(quality: configuration.jpegQuality)
                    Spacer()
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    /// 文件信息区域
    private var fileInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("文件信息")
                .font(.headline)

            VStack(spacing: 12) {
                InfoRow(
                    icon: "doc.badge.gearshape",
                    title: "格式",
                    value: configuration.format.rawValue
                )

                Divider()

                InfoRow(
                    icon: "ruler",
                    title: "尺寸",
                    value: "\(Int(image.size.width)) × \(Int(image.size.height)) px"
                )

                Divider()

                InfoRow(
                    icon: "memorychip",
                    title: "预估大小",
                    value: ByteCountFormatter.string(
                        fromByteCount: estimatedFileSize,
                        countStyle: .file
                    ),
                    isLoading: isCalculatingSize
                )

                if configuration.format == .jpeg {
                    Divider()

                    InfoRow(
                        icon: "slider.horizontal.3",
                        title: "压缩质量",
                        value: "\(Int(configuration.jpegQuality * 100))%"
                    )
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    /// 导出进度区域
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("导出进度")
                .font(.headline)

            VStack(spacing: 16) {
                // 进度条
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor)
                            .frame(width: progressWidth(in: geometry.size.width), height: 8)
                            .animation(.linear(duration: 0.3), value: exportService.progress)
                    }
                }
                .frame(height: 8)

                // 状态文字
                HStack {
                    Label(
                        progressDescription,
                        systemImage: progressIcon
                    )
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                    Spacer()

                    if case .converting(let progress) = exportService.progress {
                        Text("\(Int(progress * 100))%")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    /// 底部按钮区域
    private var bottomButtons: some View {
        VStack(spacing: 12) {
            // 保存到相册按钮
            Button {
                Task {
                    await saveToPhotoLibrary()
                }
            } label: {
                HStack {
                    Image(systemName: "photo.on.rectangle")
                    Text("保存到相册")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(exportService.isExporting)

            // 分享按钮
            Button {
                Task {
                    await prepareAndShowShareSheet()
                }
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("分享")
                }
                .font(.headline)
                .foregroundColor(.accentColor)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(exportService.isExporting)
        }
        .padding()
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: -4)
    }

    // MARK: - 辅助计算

    /// 计算进度条宽度
    private func progressWidth(in totalWidth: CGFloat) -> CGFloat {
        switch exportService.progress {
        case .idle:
            return 0
        case .preparing:
            return totalWidth * 0.2
        case .converting(let progress):
            return totalWidth * (0.2 + progress * 0.7)
        case .saving:
            return totalWidth * 0.95
        case .completed:
            return totalWidth
        case .failed:
            return totalWidth * 0.5
        }
    }

    /// 进度描述
    private var progressDescription: String {
        switch exportService.progress {
        case .idle:
            return "等待中"
        case .preparing:
            return "准备中..."
        case .converting:
            return "转换格式..."
        case .saving:
            return "保存中..."
        case .completed:
            return "完成"
        case .failed(let error):
            return "失败：\(error)"
        }
    }

    /// 进度图标
    private var progressIcon: String {
        switch exportService.progress {
        case .idle:
            return "circle"
        case .preparing:
            return "gear"
        case .converting:
            return "arrow.triangle.2.circlepath"
        case .saving:
            return "arrow.down.doc"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    /// 计算预估文件大小
    private func calculateEstimatedSize() {
        isCalculatingSize = true

        Task {
            let size = exportService.estimateFileSize(
                image: image,
                format: configuration.format,
                jpegQuality: configuration.jpegQuality
            )

            await MainActor.run {
                self.estimatedFileSize = size
                self.isCalculatingSize = false
            }
        }
    }

    /// 获取指定格式的预估大小
    private func estimatedFileSizeFor(format: ExportFormat) -> Int64 {
        exportService.estimateFileSize(
            image: image,
            format: format,
            jpegQuality: configuration.jpegQuality
        )
    }

    // MARK: - 操作

    /// 保存到相册
    private func saveToPhotoLibrary() async {
        do {
            let result = try await exportService.exportAndSave(
                image: image,
                configuration: configuration
            )

            onExportComplete?(result)

            // 触觉反馈
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            showSaveSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true

            // 触觉反馈
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
    }

    /// 准备并显示分享面板
    private func prepareAndShowShareSheet() async {
        do {
            let shareData = try await exportService.prepareShareData(
                image: image,
                configuration: configuration
            )

            // 创建临时文件用于分享
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent(shareData.fileName)
            try shareData.data.write(to: fileURL)

            // 存储临时文件URL以便后续清理
            self.tempFileURL = fileURL

            shareItems = [fileURL, image]
            showShareSheet = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    /// 清理临时文件
    private func cleanupTempFile() {
        if let url = tempFileURL {
            try? FileManager.default.removeItem(at: url)
            tempFileURL = nil
        }
    }

    // 临时文件URL
    @State private var tempFileURL: URL?
}

// MARK: - 子视图

/// 格式选项行
private struct FormatOptionRow: View {
    let format: ExportFormat
    let isSelected: Bool
    let estimatedSize: Int64
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // 选择指示器
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 2)
                        .frame(width: 22, height: 22)

                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 14, height: 14)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(format.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(format.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // 预估大小
                Text(ByteCountFormatter.string(fromByteCount: estimatedSize, countStyle: .file))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            .padding()
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// 质量标签
private struct QualityLabel: View {
    let quality: Double

    var qualityText: String {
        switch quality {
        case 0.9...1.0:
            return "最高质量 • 文件较大"
        case 0.8..<0.9:
            return "高质量 • 推荐"
        case 0.6..<0.8:
            return "中等质量 • 平衡"
        case 0.4..<0.6:
            return "标准质量 • 文件较小"
        default:
            return "低质量 • 最小文件"
        }
    }

    var qualityColor: Color {
        switch quality {
        case 0.8...1.0:
            return .green
        case 0.6..<0.8:
            return .blue
        case 0.4..<0.6:
            return .orange
        default:
            return .red
        }
    }

    var body: some View {
        Text(qualityText)
            .font(.caption)
            .foregroundColor(qualityColor)
    }
}

// MARK: - 预览

#Preview {
    ExportView(
        image: UIImage(systemName: "photo")!,
        onDismiss: {},
        onExportComplete: nil
    )
}
