import SwiftUI
import Photos
import PhotosUI

@MainActor
class ContentViewModel: ObservableObject {
    // MARK: - Published Properties
    
    /// 选中的图片数组
    @Published var selectedImages: [UIImage] = []
    
    /// 拼接结果图片
    @Published var stitchedImage: UIImage?
    
    /// 是否正在加载
    @Published var isLoading = false
    
    /// 错误消息
    @Published var errorMessage: String?
    
    /// 是否显示错误
    @Published var showError = false
    
    /// 是否显示图片选择器
    @Published var showImagePicker = false
    
    /// 是否显示图片预览/排序界面
    @Published var showPhotoPickerView = false
    
    /// 是否显示权限请求界面
    @Published var showPermissionView = false
    
    /// 是否显示拼接结果
    @Published var showStitchedResult = false

    /// 是否显示导出界面
    @Published var showExportView = false

    /// 是否显示分享面板
    @Published var showShareSheet = false

    /// 分享项目
    @Published var shareItems: [Any] = []

    // MARK: - Constants
    
    /// 最小选择图片数量
    let minSelectionCount = 2
    
    /// 最大选择图片数量
    let maxSelectionCount = 20
    
    // MARK: - 图片选择
    
    /// 开始选择图片流程
    func startImageSelection() {
        let status = PhotoLibraryPermissionManager.shared.checkAuthorization()
        
        switch status {
        case .authorized, .limited:
            // 已有权限，直接显示图片选择界面
            showPhotoPickerView = true
        case .notDetermined:
            // 未请求权限，显示权限请求界面
            showPermissionView = true
        case .denied, .restricted:
            // 权限被拒绝，显示权限请求界面（引导去设置）
            showPermissionView = true
        }
    }
    
    /// 请求相册访问权限（从相册导入按钮调用）
    func requestPhotoLibraryAccess() {
        let status = PhotoLibraryPermissionManager.shared.checkAuthorization()
        
        switch status {
        case .authorized, .limited:
            // 已有权限，打开系统相册选择器
            showImagePicker = true
        case .notDetermined:
            // 请求权限
            Task {
                let authorized = await PhotoLibraryPermissionManager.shared.requestAuthorization()
                await MainActor.run {
                    if authorized {
                        self.showImagePicker = true
                    } else {
                        self.errorMessage = "需要相册访问权限才能选择图片"
                        self.showError = true
                    }
                }
            }
        case .denied, .restricted:
            // 权限被拒绝
            errorMessage = "请在设置中允许访问相册"
            showError = true
        }
    }
    
    /// 打开图片选择器（直接打开 PHPicker）
    func openImagePicker() {
        showImagePicker = true
    }
    
    /// 选择图片按钮点击
    func selectImages() {
        startImageSelection()
    }
    
    /// 添加更多图片
    func addMoreImages() {
        showImagePicker = true
    }
    
    /// 移除单张图片
    func removeImage(at index: Int) {
        guard index < selectedImages.count else { return }
        selectedImages.remove(at: index)
    }
    
    /// 清空所有选中图片
    func clearSelectedImages() {
        selectedImages.removeAll()
        stitchedImage = nil
    }
    
    /// 重新排序图片
    func reorderImages(from source: IndexSet, to destination: Int) {
        selectedImages.move(fromOffsets: source, toOffset: destination)
    }
    
    // MARK: - 图片拼接
    
    /// 执行图片拼接
    func stitchImages() async {
        guard selectedImages.count >= minSelectionCount else {
            errorMessage = "至少需要 \(minSelectionCount) 张图片进行拼接"
            showError = true
            return
        }
        
        guard selectedImages.count <= maxSelectionCount else {
            errorMessage = "最多只能拼接 \(maxSelectionCount) 张图片"
            showError = true
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // 使用新的 LongScreenshotBuilder 进行拼接
        let builder = LongScreenshotBuilder()
        
        if let result = builder.build(frames: selectedImages) {
            stitchedImage = result
            showStitchedResult = true
        } else {
            errorMessage = "图片拼接失败，请重试"
            showError = true
        }
    }
    
    /// 保存拼接结果到相册
    func saveStitchedImage() async {
        guard let image = stitchedImage else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let success = try await PhotoLibraryHelper.saveImage(image)
            if success {
                errorMessage = "保存成功"
                showError = true
            } else {
                errorMessage = "保存失败"
                showError = true
            }
        } catch {
            errorMessage = "保存出错：\(error.localizedDescription)"
            showError = true
        }
    }
    
    /// 分享拼接结果
    func shareStitchedImage() -> UIImage? {
        return stitchedImage
    }

    // MARK: - 导出功能

    /// 显示导出界面
    func showExport() {
        guard stitchedImage != nil else {
            errorMessage = "没有可导出的图片"
            showError = true
            return
        }
        showExportView = true
    }

    /// 导出并保存到相册
    func exportAndSave(configuration: ExportConfiguration = .default) async {
        guard let image = stitchedImage else {
            errorMessage = "没有可导出的图片"
            showError = true
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await ExportService.shared.exportAndSave(
                image: image,
                configuration: configuration
            )
            errorMessage = "保存成功（\(result.fileSizeDescription)）"
            showError = true
        } catch {
            errorMessage = "导出失败：\(error.localizedDescription)"
            showError = true
        }
    }

    /// 准备分享
    func prepareShare(configuration: ExportConfiguration = .default) async {
        guard let image = stitchedImage else {
            errorMessage = "没有可分享的图片"
            showError = true
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let shareData = try await ExportService.shared.prepareShareData(
                image: image,
                configuration: configuration
            )

            // 创建临时文件
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent(shareData.fileName)
            try shareData.data.write(to: fileURL)

            shareItems = [fileURL, image]
            showShareSheet = true
        } catch {
            errorMessage = "准备分享失败：\(error.localizedDescription)"
            showError = true
        }
    }

    /// 批量导出历史记录
    func batchExportHistory(images: [UIImage]) async -> BatchExportResult {
        return await ExportService.shared.batchExport(images: images)
    }

    // MARK: - 验证
    
    /// 验证当前选中的图片是否可以进行拼接
    func validateImagesForStitching() -> Bool {
        guard selectedImages.count >= minSelectionCount else {
            errorMessage = "请至少选择 \(minSelectionCount) 张图片"
            showError = true
            return false
        }
        
        guard selectedImages.count <= maxSelectionCount else {
            errorMessage = "最多只能选择 \(maxSelectionCount) 张图片"
            showError = true
            return false
        }
        
        return true
    }
    
    /// 检查是否可以选择更多图片
    func canAddMoreImages() -> Bool {
        return selectedImages.count < maxSelectionCount
    }
    
    /// 获取剩余可选图片数量
    func remainingSelectionCount() -> Int {
        return maxSelectionCount - selectedImages.count
    }
}
