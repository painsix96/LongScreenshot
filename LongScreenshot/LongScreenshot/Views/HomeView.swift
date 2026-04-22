import SwiftUI
import Photos
import PhotosUI
import Combine
import AVFoundation

// MARK: - 照片库变更观察器
class PHPhotoLibraryObserver: NSObject, PHPhotoLibraryChangeObserver {
    private let changeHandler: () -> Void
    
    init(changeHandler: @escaping () -> Void) {
        self.changeHandler = changeHandler
    }
    
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        // 当照片库发生变化时，调用传入的处理函数
        changeHandler()
    }
}

// MARK: - 相册照片流首页
struct HomeView: View {
    @Binding var showSettings: Bool
    @StateObject private var viewModel = StitchingViewModel()
    @State private var selectedPhotos: [PHAsset] = []
    @State private var showStitchingView = false
    @State private var photoAssets: [PHAsset] = []
    @State private var isLoading = true
    @State private var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @State private var photoLibraryObserver: PHPhotoLibraryObserver?

    // 列数：一行4个照片/视频，无间距铺满
    @State private var columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 0), count: 4)

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // 顶部标题栏
                HeaderView(
                    showSettings: $showSettings,
                    selectedCount: selectedPhotos.count
                )

                // 照片网格 - 使用GeometryReader固定高度
                GeometryReader { geometry in
                    PhotoGridView(
                        photoAssets: photoAssets,
                        selectedPhotos: $selectedPhotos,
                        columns: columns,
                        isLoading: isLoading,
                        containerHeight: geometry.size.height
                    )
                }
            }

            // 底部操作栏（选择后显示）- 通过VStack覆盖在底部
            VStack {
                Spacer()
                if !selectedPhotos.isEmpty {
                    BottomActionBar(
                        selectedCount: selectedPhotos.count,
                        onClear: { selectedPhotos.removeAll() },
                        onStitch: { showStitchingView = true }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .navigationDestination(isPresented: $showStitchingView) {
            HomeStitchingProgressView(
                selectedAssets: selectedPhotos,
                viewModel: viewModel,
                onDismiss: {
                    // 当从拼接页面返回时，清除选中的照片
                    selectedPhotos.removeAll()
                }
            )
        }
        .onAppear {
            checkAuthorizationAndLoad()
            // 注册照片库变更观察器
            photoLibraryObserver = PHPhotoLibraryObserver {
                self.loadPhotos()
            }
            PHPhotoLibrary.shared().register(photoLibraryObserver!)
        }
        .onDisappear {
            // 移除照片库变更观察器
            if let observer = photoLibraryObserver {
                PHPhotoLibrary.shared().unregisterChangeObserver(observer)
            }
        }
        .alert("无法访问相册", isPresented: .constant(authorizationStatus == .denied)) {
            Button("去设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("请在设置中允许访问相册以使用长截图功能")
        }
    }

    // MARK: - 检查权限并加载照片
    private func checkAuthorizationAndLoad() {
        let status = PHPhotoLibrary.authorizationStatus()
        authorizationStatus = status

        switch status {
        case .authorized, .limited:
            loadPhotos()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { newStatus in
                DispatchQueue.main.async {
                    authorizationStatus = newStatus
                    if newStatus == .authorized || newStatus == .limited {
                        loadPhotos()
                    }
                }
            }
        case .denied, .restricted:
            isLoading = false
        @unknown default:
            isLoading = false
        }
    }

    // MARK: - 加载相册照片和视频
    private func loadPhotos() {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            // 只加载照片（截图通常是照片）
            fetchOptions.predicate = NSPredicate(
                format: "mediaType == %d",
                PHAssetMediaType.image.rawValue
            )

            let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
            var assets: [PHAsset] = []

            fetchResult.enumerateObjects { asset, _, _ in
                assets.append(asset)
            }

            DispatchQueue.main.async {
                self.photoAssets = assets
                self.isLoading = false
            }
        }
    }
}

// MARK: - 顶部标题栏
struct HeaderView: View {
    @Binding var showSettings: Bool
    let selectedCount: Int

    var body: some View {
        HStack {
            // 左侧占位，保持标题居中
            Button(action: {}) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.clear)
            }
            .frame(width: 44, height: 44)
            .disabled(true)

            Spacer()

            // 中间标题
            Text("最近项目")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            // 右侧设置按钮
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.primary)
            }
            .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(.ultraThinMaterial)
    }
}

// MARK: - 底部操作栏
struct BottomActionBar: View {
    let selectedCount: Int
    let onClear: () -> Void
    let onStitch: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // 已选择数量
            Text("已选择 \(selectedCount) 张")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)

            Spacer()

            // 清除按钮
            Button(action: onClear) {
                Text("清除")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }

            // 开始拼接按钮
            Button(action: onStitch) {
                Text("开始拼接")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .padding(.bottom, 8) // 底部安全区域额外间距
        .background(.ultraThinMaterial)
    }
}

// MARK: - 照片网格视图
struct PhotoGridView: View {
    let photoAssets: [PHAsset]
    @Binding var selectedPhotos: [PHAsset]
    let columns: [GridItem]
    let isLoading: Bool
    let containerHeight: CGFloat
    @State private var shouldScrollToBottom = false

    var body: some View {
        ScrollViewReader {
            scrollView in
            ScrollView(showsIndicators: false) {
                if isLoading {
                    LoadingPlaceholder()
                        .padding(.top, 100)
                } else if photoAssets.isEmpty {
                    EmptyPhotoView()
                        .padding(.top, 100)
                } else {
                    LazyVGrid(columns: columns, spacing: 0) {
                        ForEach(photoAssets, id: \.localIdentifier) { asset in
                            PhotoCell(
                                asset: asset,
                                selectedPhotos: $selectedPhotos
                            )
                            .id(asset.localIdentifier)
                        }
                    }
                    
                    // 底部预留空间，高度与底部操作栏一致
                    VStack(spacing: 0) {
                        Spacer()
                        Text("共 \(photoAssets.count) 张照片")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 10)
                    }
                    .frame(height: 60)
                    .id("bottom-reserved-space")
                }
            }
            .onChange(of: photoAssets) {
                newValue in
                if !newValue.isEmpty {
                    DispatchQueue.main.async {
                        scrollView.scrollTo("bottom-reserved-space", anchor: .bottom)
                    }
                }
            }
            .onAppear {
                // 每次视图出现时都滚动到底部，包括从其他页面返回
                if !photoAssets.isEmpty {
                    // 延迟一点时间，确保视图完全加载
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        scrollView.scrollTo("bottom-reserved-space", anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - 照片单元格
struct PhotoCell: View {
    let asset: PHAsset
    @Binding var selectedPhotos: [PHAsset]

    @State private var thumbnail: UIImage?

    private var isSelected: Bool {
        selectedPhotos.contains(where: { $0.localIdentifier == asset.localIdentifier })
    }

    private var selectionIndex: Int? {
        selectedPhotos.firstIndex(where: { $0.localIdentifier == asset.localIdentifier })
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // 缩略图 - 强制正方形裁剪，铺满无间距
            GeometryReader { geometry in
                Group {
                    if let thumbnail = thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.width)
                            .clipped()
                    } else {
                        Color(.systemGray5)
                            .frame(width: geometry.size.width, height: geometry.size.width)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)

            // 选中遮罩
            if isSelected {
                Color.black.opacity(0.3)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white)
                    )

                // 选中序号
                if let index = selectionIndex {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(
                            Circle()
                                .fill(.blue)
                        )
                        .padding(4)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            toggleSelection()
        }
        .onAppear {
            loadThumbnail()
        }
    }

    private func toggleSelection() {
        withAnimation(.easeInOut) {
            if let index = selectedPhotos.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) {
                selectedPhotos.remove(at: index)
            } else {
                if selectedPhotos.count < 20 {
                    selectedPhotos.append(asset)
                }
            }
        }
    }

    private func loadThumbnail() {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isSynchronous = false

        manager.requestImage(
            for: asset,
            targetSize: CGSize(width: 300, height: 300),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            if let image = image {
                self.thumbnail = image
            }
        }
    }
}

// MARK: - 加载占位符
struct LoadingPlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            Text("正在加载照片...")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 空照片视图
struct EmptyPhotoView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundStyle(.secondary.opacity(0.5))

            Text("相册中没有照片")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 拼接进度视图
struct HomeStitchingProgressView: View {
    let selectedAssets: [PHAsset]
    @ObservedObject var viewModel: StitchingViewModel
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false
    @State private var showExportOptions = false
    @State private var showSaveSuccess = false
    @State private var showDiscardAlert = false

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            if viewModel.isProcessing {
                // 处理中状态
                VStack(spacing: 20) {
                    ProgressView(value: viewModel.progress)
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)

                    Text(viewModel.statusText)
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)

                    Text("\(Int(viewModel.progress * 100))%")
                        .font(.system(size: 24, weight: .bold))
                        .monospacedDigit()
                }
            } else if let result = viewModel.stitchedImage {
                // 结果预览 - 横向铺满，保持原始比例纵向滚动
                NoBounceScrollView {
                    Image(uiImage: result)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                }
            } else if let error = viewModel.error {
                // 错误状态
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundStyle(.orange)

                    Text("拼接失败")
                        .font(.system(size: 20, weight: .semibold))

                    Text(error.localizedDescription)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // 左上方返回按钮
            ToolbarItem(placement: .topBarLeading) {
                if viewModel.isProcessing {
                    Button("取消") {
                        viewModel.cancelProcessing()
                        dismiss()
                    }
                } else if viewModel.stitchedImage != nil {
                    Button(action: { showDiscardAlert = true }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                    }
                } else if viewModel.error != nil {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
            }

            // 右上方导出按钮
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.stitchedImage != nil {
                    Button(action: { showExportOptions = true }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17))
                    }
                }
            }
        }
        .confirmationDialog("", isPresented: $showExportOptions, titleVisibility: .hidden) {
            Button("保存到相册") {
                saveToAlbum()
            }
            Button("分享") {
                showShareSheet = true
            }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = viewModel.stitchedImage {
                ShareSheet(activityItems: [image])
            }
        }
        .alert("保存成功", isPresented: $showSaveSuccess) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("图片已成功保存到相册")
        }
        .alert("确认丢弃", isPresented: $showDiscardAlert) {
            Button("取消", role: .cancel) {}
            Button("丢弃", role: .destructive) {
                // 丢弃长截图，不保存
                dismiss()
            }
        } message: {
            Text("如果不保存的话，刚才生成的长截图会丢失。")
        }
        .onAppear {
            viewModel.startStitching(assets: selectedAssets)
        }
        .onDisappear {
            // 当视图消失时调用onDismiss回调
            onDismiss()
        }
    }

    private func saveToAlbum() {
        guard let image = viewModel.stitchedImage else { return }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }) { success, error in
            DispatchQueue.main.async {
                if success {
                    self.showSaveSuccess = true
                }
            }
        }
    }
}



// MARK: - 拼接视图模型
class StitchingViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var progress: Double = 0
    @Published var statusText = "准备中..."
    @Published var stitchedImage: UIImage?
    @Published var error: Error?

    private var cancellables: Set<AnyCancellable> = []
    private var processingTask: Task<Void, Never>?

    func startStitching(assets: [PHAsset]) {
        guard assets.count >= 2 else {
            error = StitchingError.insufficientImages
            return
        }

        isProcessing = true
        progress = 0
        statusText = "加载图片..."
        stitchedImage = nil
        error = nil

        processingTask = Task {
            do {
                // 加载所有图片
                let images = try await loadImages(from: assets)

                // 更新进度
                await MainActor.run {
                    self.progress = 0.3
                    self.statusText = "检测重叠区域..."
                }

                // 执行拼接
                let result = try await performStitching(images: images)

                await MainActor.run {
                    self.stitchedImage = result
                    self.isProcessing = false
                    self.progress = 1.0
                }
                
                // 自动保存到相册
                if UserDefaults.standard.bool(forKey: "autoSaveToAlbum") {
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.creationRequestForAsset(from: result)
                    }) { _, _ in }
                }

            } catch {
                await MainActor.run {
                    self.error = error
                    self.isProcessing = false
                }
            }
        }
    }

    func cancelProcessing() {
        processingTask?.cancel()
        isProcessing = false
    }

    private func loadImages(from assets: [PHAsset]) async throws -> [UIImage] {
        var images: [UIImage] = []

        for (index, asset) in assets.enumerated() {
            try Task.checkCancellation()

            let image = try await loadImage(from: asset)
            images.append(image)

            await MainActor.run {
                self.progress = Double(index + 1) / Double(assets.count) * 0.2
            }
        }

        return images
    }

    private func loadImage(from asset: PHAsset) async throws -> UIImage {
        await withCheckedContinuation { continuation in
            let manager = PHImageManager.default()
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isSynchronous = false

            manager.requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                if let image = image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(returning: UIImage())
                }
            }
        }
    }

    private func performStitching(images: [UIImage]) async throws -> UIImage {
        guard images.count >= 2 else {
            throw StitchingError.insufficientImages
        }
        
        let builder = LongScreenshotBuilder()
        
        return try await withCheckedThrowingContinuation { continuation in
            builder.buildAsync(frames: images) { result in
                if let image = result {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: StitchingError.stitchingFailed)
                }
            }
        }
    }

}

enum StitchingError: Error {
    case insufficientImages
    case loadFailed
    case stitchingFailed
}

// MARK: - 预览
#Preview {
    HomeView(showSettings: .constant(false))
}
