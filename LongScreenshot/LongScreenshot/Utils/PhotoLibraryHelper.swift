import SwiftUI
import Photos
import PhotosUI

/// 相册授权状态枚举
enum PhotoLibraryAuthorizationStatus {
    case authorized
    case limited
    case denied
    case notDetermined
    case restricted
    
    var description: String {
        switch self {
        case .authorized:
            return "已授权"
        case .limited:
            return "有限访问"
        case .denied:
            return "已拒绝"
        case .notDetermined:
            return "未确定"
        case .restricted:
            return "受限制"
        }
    }
    
    var canAccess: Bool {
        switch self {
        case .authorized, .limited:
            return true
        case .denied, .notDetermined, .restricted:
            return false
        }
    }
}

/// 相册权限管理器
final class PhotoLibraryPermissionManager: ObservableObject {
    @Published var authorizationStatus: PhotoLibraryAuthorizationStatus = .notDetermined
    
    static let shared = PhotoLibraryPermissionManager()
    
    private init() {
        updateAuthorizationStatus()
    }
    
    /// 更新当前授权状态
    func updateAuthorizationStatus() {
        let status = PHPhotoLibrary.authorizationStatus()
        authorizationStatus = mapStatus(status)
    }
    
    /// 请求相册访问权限
    /// - Returns: 是否获得授权（authorized 或 limited）
    func requestAuthorization() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await MainActor.run {
            self.authorizationStatus = self.mapStatus(status)
        }
        return status == .authorized || status == .limited
    }
    
    /// 检查当前权限状态
    func checkAuthorization() -> PhotoLibraryAuthorizationStatus {
        let status = PHPhotoLibrary.authorizationStatus()
        return mapStatus(status)
    }
    
    /// 打开应用设置页面
    func openSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        if UIApplication.shared.canOpenURL(settingsURL) {
            UIApplication.shared.open(settingsURL)
        }
    }
    
    /// 映射系统权限状态到自定义枚举
    private func mapStatus(_ status: PHAuthorizationStatus) -> PhotoLibraryAuthorizationStatus {
        switch status {
        case .authorized:
            return .authorized
        case .limited:
            return .limited
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        @unknown default:
            return .denied
        }
    }
}

/// 相册帮助类
enum PhotoLibraryHelper {
    
    // MARK: - 图片保存
    
    /// 保存图片到相册
    /// - Parameters:
    ///   - image: 要保存的图片
    ///   - completion: 完成回调
    static func saveImage(_ image: UIImage, completion: @escaping (Bool, Error?) -> Void) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    completion(false, NSError(domain: "PhotoLibrary", code: 403, userInfo: [NSLocalizedDescriptionKey: "没有相册访问权限"]))
                }
                return
            }

            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, error in
                DispatchQueue.main.async {
                    completion(success, error)
                }
            }
        }
    }
    
    /// 异步保存图片到相册
    static func saveImage(_ image: UIImage) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            saveImage(image) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }
    
    // MARK: - 图片获取
    
    /// 获取所有截图（根据设备名称智能筛选）
    static func fetchScreenshots() async -> [PHAsset] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        
        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        var assets: [PHAsset] = []
        
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        
        return assets
    }
    
    /// 从相册加载图片
    /// - Parameters:
    ///   - asset: 相册资源
    ///   - targetSize: 目标尺寸
    /// - Returns: UIImage
    static func loadImage(from asset: PHAsset, targetSize: CGSize = PHImageManagerMaximumSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
    
    /// 批量加载图片
    /// - Parameters:
    ///   - assets: 相册资源数组
    ///   - targetSize: 目标尺寸
    /// - Returns: UIImage 数组
    static func loadImages(from assets: [PHAsset], targetSize: CGSize = PHImageManagerMaximumSize) async -> [UIImage] {
        var images: [UIImage] = []
        
        await withTaskGroup(of: UIImage?.self) { group in
            for asset in assets {
                group.addTask {
                    await loadImage(from: asset, targetSize: targetSize)
                }
            }
            
            for await image in group {
                if let image = image {
                    images.append(image)
                }
            }
        }
        
        return images
    }
    
    // MARK: - PHPicker 相关
    
    /// 创建 PHPicker 配置
    /// - Parameter selectionLimit: 最大选择数量
    /// - Returns: PHPickerConfiguration
    static func createPickerConfiguration(selectionLimit: Int = 20) -> PHPickerConfiguration {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = selectionLimit
        config.filter = .images
        config.preferredAssetRepresentationMode = .current
        return config
    }
}

// MARK: - SwiftUI 权限请求视图

/// 相册权限请求视图
struct PhotoLibraryPermissionView: View {
    @StateObject private var permissionManager = PhotoLibraryPermissionManager.shared
    let onAuthorized: () -> Void
    let onCancel: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // 图标
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)
            
            // 标题
            Text("需要相册访问权限")
                .font(.title2)
                .fontWeight(.bold)
            
            // 说明文本
            VStack(spacing: 8) {
                Text("为了选择图片进行拼接")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                Text("请在设置中允许访问相册")
                    .font(.subheadline)
                    .foregroundColor(.secondary.opacity(0.8))
            }
            
            Spacer()
            
            // 按钮组
            VStack(spacing: 12) {
                if permissionManager.authorizationStatus == .notDetermined {
                    Button(action: {
                        Task {
                            let authorized = await permissionManager.requestAuthorization()
                            if authorized {
                                onAuthorized()
                            }
                        }
                    }) {
                        Text("允许访问")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .cornerRadius(12)
                    }
                } else if permissionManager.authorizationStatus == .denied || permissionManager.authorizationStatus == .restricted {
                    Button(action: {
                        permissionManager.openSettings()
                    }) {
                        Text("前往设置")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .cornerRadius(12)
                    }
                } else {
                    Button(action: onAuthorized) {
                        Text("继续")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .cornerRadius(12)
                    }
                }
                
                Button(action: {
                    onCancel?()
                }) {
                    Text("取消")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal)
            
            Spacer()
                .frame(height: 30)
        }
        .padding()
        .onAppear {
            permissionManager.updateAuthorizationStatus()
        }
    }
}

#Preview {
    PhotoLibraryPermissionView(onAuthorized: {}, onCancel: nil)
}
