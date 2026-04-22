import SwiftUI
import PhotosUI

/// 图片选择器回调协议
protocol ImagePickerDelegate: AnyObject {
    func imagePicker(didSelectImages images: [UIImage])
    func imagePickerDidCancel()
}

/// 使用 PHPickerViewController 实现的多图片选择器 (UIKit)
class ImagePickerController: NSObject {
    weak var delegate: ImagePickerDelegate?
    private let selectionLimit: Int
    
    init(selectionLimit: Int = 20) {
        self.selectionLimit = selectionLimit
        super.init()
    }
    
    /// 创建并配置 PHPickerViewController
    func makePickerViewController() -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = selectionLimit
        config.filter = .images
        config.preferredAssetRepresentationMode = .current
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        return picker
    }
}

// MARK: - PHPickerViewControllerDelegate
extension ImagePickerController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        
        guard !results.isEmpty else {
            delegate?.imagePickerDidCancel()
            return
        }
        
        // 检查最少选择数量
        guard results.count >= 2 else {
            delegate?.imagePicker(didSelectImages: [])
            return
        }
        
        // 异步加载所有选中的图片
        Task {
            let images = await loadImages(from: results)
            await MainActor.run {
                self.delegate?.imagePicker(didSelectImages: images)
            }
        }
    }
    
    /// 从 PHPickerResult 数组中加载 UIImage
    private func loadImages(from results: [PHPickerResult]) async -> [UIImage] {
        var images: [UIImage] = []
        
        await withTaskGroup(of: UIImage?.self) { group in
            for result in results {
                group.addTask {
                    await self.loadImage(from: result)
                }
            }
            
            for await image in group {
                if let image = image {
                    images.append(image)
                }
            }
        }
        
        // 保持原始选择顺序
        return images
    }
    
    /// 加载单个图片
    private func loadImage(from result: PHPickerResult) async -> UIImage? {
        await withCheckedContinuation { continuation in
            result.itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                if let image = object as? UIImage {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - SwiftUI 桥接

/// SwiftUI 用的图片选择器 Coordinator
class ImagePickerCoordinator: NSObject, ImagePickerDelegate {
    @Binding var selectedImages: [UIImage]
    @Binding var isPresented: Bool
    @Binding var errorMessage: String?
    @Binding var showError: Bool
    let minSelectionCount: Int
    let maxSelectionCount: Int
    
    init(
        selectedImages: Binding<[UIImage]>,
        isPresented: Binding<Bool>,
        errorMessage: Binding<String?>,
        showError: Binding<Bool>,
        minSelectionCount: Int = 2,
        maxSelectionCount: Int = 20
    ) {
        self._selectedImages = selectedImages
        self._isPresented = isPresented
        self._errorMessage = errorMessage
        self._showError = showError
        self.minSelectionCount = minSelectionCount
        self.maxSelectionCount = maxSelectionCount
    }
    
    func imagePicker(didSelectImages images: [UIImage]) {
        // 验证图片数量
        if images.count < minSelectionCount {
            errorMessage = "请至少选择 \(minSelectionCount) 张图片"
            showError = true
            isPresented = false
            return
        }
        
        if images.count > maxSelectionCount {
            errorMessage = "最多只能选择 \(maxSelectionCount) 张图片"
            showError = true
            // 只保留前 maxSelectionCount 张
            selectedImages = Array(images.prefix(maxSelectionCount))
        } else {
            selectedImages = images
        }
        
        isPresented = false
    }
    
    func imagePickerDidCancel() {
        isPresented = false
    }
}

/// 用于 SwiftUI 的 UIViewControllerRepresentable 包装器
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImages: [UIImage]
    @Binding var isPresented: Bool
    @Binding var errorMessage: String?
    @Binding var showError: Bool
    var minSelectionCount: Int = 2
    var maxSelectionCount: Int = 20
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        let controller = ImagePickerController(selectionLimit: maxSelectionCount)
        controller.delegate = context.coordinator
        return controller.makePickerViewController()
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> ImagePickerCoordinator {
        ImagePickerCoordinator(
            selectedImages: $selectedImages,
            isPresented: $isPresented,
            errorMessage: $errorMessage,
            showError: $showError,
            minSelectionCount: minSelectionCount,
            maxSelectionCount: maxSelectionCount
        )
    }
}
