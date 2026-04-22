import SwiftUI
import Combine

/// 裁剪状态历史记录
struct CropState: Equatable {
    var cropRect: CGRect
    var rotation: CGFloat
    var isFlippedHorizontally: Bool
    var isFlippedVertically: Bool
    var scale: CGFloat
    var offset: CGSize
    
    static let `default` = CropState(
        cropRect: .zero,
        rotation: 0,
        isFlippedHorizontally: false,
        isFlippedVertically: false,
        scale: 1.0,
        offset: .zero
    )
}

/// 裁剪比例
enum CropRatio: Equatable, CaseIterable {
    case free
    case square    // 1:1
    case ratio4_3  // 4:3
    case ratio3_4  // 3:4
    case ratio16_9 // 16:9
    case ratio9_16 // 9:16
    
    var title: String {
        switch self {
        case .free: return "自由"
        case .square: return "1:1"
        case .ratio4_3: return "4:3"
        case .ratio3_4: return "3:4"
        case .ratio16_9: return "16:9"
        case .ratio9_16: return "9:16"
        }
    }
    
    var value: CGFloat? {
        switch self {
        case .free: return nil
        case .square: return 1.0
        case .ratio4_3: return 4.0 / 3.0
        case .ratio3_4: return 3.0 / 4.0
        case .ratio16_9: return 16.0 / 9.0
        case .ratio9_16: return 9.0 / 16.0
        }
    }
}

/// 裁剪视图模型
@MainActor
final class CropViewModel: ObservableObject {
    // MARK: - Published Properties
    
    /// 原始图片
    @Published var originalImage: UIImage
    
    /// 当前裁剪框
    @Published var cropRect: CGRect = .zero
    
    /// 当前旋转角度（度数）
    @Published var rotation: CGFloat = 0
    
    /// 是否水平翻转
    @Published var isFlippedHorizontally: Bool = false
    
    /// 是否垂直翻转
    @Published var isFlippedVertically: Bool = false
    
    /// 缩放比例
    @Published var scale: CGFloat = 1.0
    
    /// 平移偏移
    @Published var offset: CGSize = .zero
    
    /// 当前裁剪比例
    @Published var selectedRatio: CropRatio = .free
    
    /// 是否正在拖拽
    @Published var isDragging: Bool = false
    
    /// 预览裁剪结果
    @Published var previewImage: UIImage?
    
    /// 裁剪区域最大尺寸
    @Published var maxCropSize: CGSize = .zero
    
    // MARK: - Undo/Redo
    
    private var undoStack: [CropState] = []
    private var redoStack: [CropState] = []
    private let maxUndoSteps = 20
    
    // MARK: - Constants
    
    /// 最小裁剪尺寸
    let minCropSize: CGFloat = 100
    
    /// 拖拽手柄大小
    let handleSize: CGFloat = 44
    
    /// 边缘拖拽检测宽度
    let edgeDetectionWidth: CGFloat = 30
    
    // MARK: - Computed Properties
    
    /// 是否可以撤销
    var canUndo: Bool { !undoStack.isEmpty }
    
    /// 是否可以重做
    var canRedo: Bool { !redoStack.isEmpty }
    
    /// 当前有效的裁剪框（限制在图片范围内）
    var validCropRect: CGRect {
        let maxRect = CGRect(origin: .zero, size: maxCropSize)
        return cropRect.intersection(maxRect)
    }
    
    /// 图片在视图中的显示尺寸
    var displayImageSize: CGSize {
        guard maxCropSize != .zero else { return .zero }
        let imageRatio = originalImage.size.width / originalImage.size.height
        let containerRatio = maxCropSize.width / maxCropSize.height
        
        if imageRatio > containerRatio {
            // 图片较宽，以宽度为准
            let width = maxCropSize.width
            let height = width / imageRatio
            return CGSize(width: width, height: height)
        } else {
            // 图片较高，以高度为准
            let height = maxCropSize.height
            let width = height * imageRatio
            return CGSize(width: width, height: height)
        }
    }
    
    /// 图片在视图中的显示位置
    var displayImageRect: CGRect {
        let size = displayImageSize
        let x = (maxCropSize.width - size.width) / 2
        let y = (maxCropSize.height - size.height) / 2
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
    
    // MARK: - Initialization
    
    init(image: UIImage) {
        self.originalImage = image
        resetToDefault()
    }
    
    // MARK: - Public Methods
    
    /// 重置为默认状态
    func resetToDefault() {
        saveCurrentState()
        
        // 默认裁剪框为整个图片显示区域
        cropRect = displayImageRect
        rotation = 0
        isFlippedHorizontally = false
        isFlippedVertically = false
        scale = 1.0
        offset = .zero
        selectedRatio = .free
        
        updatePreview()
    }
    
    /// 设置裁剪比例
    func setRatio(_ ratio: CropRatio) {
        guard selectedRatio != ratio else { return }
        
        saveCurrentState()
        selectedRatio = ratio
        
        if let ratioValue = ratio.value {
            // 应用固定比例
            applyFixedRatio(ratioValue)
        }
        
        updatePreview()
    }
    
    /// 旋转图片（90度增量）
    func rotate(clockwise: Bool = true) {
        saveCurrentState()
        
        let rotationStep: CGFloat = clockwise ? 90 : -90
        rotation += rotationStep
        
        // 归一化到 0-360
        rotation = ((rotation.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
        
        // 旋转时交换裁剪框的宽高
        let center = CGPoint(x: cropRect.midX, y: cropRect.midY)
        let newWidth = cropRect.height
        let newHeight = cropRect.width
        
        var newRect = CGRect(
            x: center.x - newWidth / 2,
            y: center.y - newHeight / 2,
            width: newWidth,
            height: newHeight
        )
        
        // 确保不超出边界
        newRect = constrainCropRect(newRect)
        cropRect = newRect
        
        updatePreview()
    }
    
    /// 水平翻转
    func flipHorizontally() {
        saveCurrentState()
        isFlippedHorizontally.toggle()
        updatePreview()
    }
    
    /// 垂直翻转
    func flipVertically() {
        saveCurrentState()
        isFlippedVertically.toggle()
        updatePreview()
    }
    
    /// 更新裁剪框（拖拽时）
    func updateCropRect(_ newRect: CGRect) {
        cropRect = constrainCropRect(newRect)
        updatePreview()
    }
    
    /// 更新裁剪框（带比例约束）
    func updateCropRectWithRatio(_ newRect: CGRect, anchor: CropResizeAnchor) {
        var constrainedRect = newRect
        
        if let ratio = selectedRatio.value {
            constrainedRect = applyRatioConstraint(newRect, ratio: ratio, anchor: anchor)
        }
        
        cropRect = constrainCropRect(constrainedRect)
        updatePreview()
    }
    
    /// 撤销
    func undo() {
        guard canUndo else { return }
        
        // 保存当前状态到重做栈
        let currentState = createCurrentState()
        redoStack.append(currentState)
        if redoStack.count > maxUndoSteps {
            redoStack.removeFirst()
        }
        
        // 恢复到上一状态
        let previousState = undoStack.removeLast()
        restoreState(previousState)
    }
    
    /// 重做
    func redo() {
        guard canRedo else { return }
        
        // 保存当前状态到撤销栈
        let currentState = createCurrentState()
        undoStack.append(currentState)
        if undoStack.count > maxUndoSteps {
            undoStack.removeFirst()
        }
        
        // 恢复到下一状态
        let nextState = redoStack.removeLast()
        restoreState(nextState)
    }
    
    /// 执行裁剪
    func crop() async throws -> UIImage {
        let imageSize = originalImage.size
        let displayRect = displayImageRect
        
        // 将裁剪框坐标转换为图片坐标系
        let scaleX = imageSize.width / displayRect.width
        let scaleY = imageSize.height / displayRect.height
        
        var imageCropRect = CGRect(
            x: (cropRect.origin.x - displayRect.origin.x) * scaleX,
            y: (cropRect.origin.y - displayRect.origin.y) * scaleY,
            width: cropRect.width * scaleX,
            height: cropRect.height * scaleY
        )
        
        // 处理翻转 - 调整裁剪坐标
        if isFlippedHorizontally {
            imageCropRect.origin.x = imageSize.width - imageCropRect.maxX
        }
        if isFlippedVertically {
            imageCropRect.origin.y = imageSize.height - imageCropRect.maxY
        }
        
        // 执行裁剪
        guard let cgImage = originalImage.cgImage?.cropping(to: imageCropRect) else {
            throw CropError.cropFailed
        }
        
        var croppedImage = UIImage(cgImage: cgImage, scale: originalImage.scale, orientation: originalImage.imageOrientation)
        
        // 应用旋转
        if rotation != 0 {
            croppedImage = Self.rotateImageStatic(croppedImage, by: rotation)
        }
        
        return croppedImage
    }
    
    /// 更新预览图
    func updatePreview() {
        Task {
            do {
                let preview = try await generatePreview()
                await MainActor.run {
                    self.previewImage = preview
                }
            } catch {
                print("预览生成失败: \(error)")
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func saveCurrentState() {
        let state = createCurrentState()
        undoStack.append(state)
        if undoStack.count > maxUndoSteps {
            undoStack.removeFirst()
        }
        // 清空重做栈
        redoStack.removeAll()
    }
    
    private func createCurrentState() -> CropState {
        return CropState(
            cropRect: cropRect,
            rotation: rotation,
            isFlippedHorizontally: isFlippedHorizontally,
            isFlippedVertically: isFlippedVertically,
            scale: scale,
            offset: offset
        )
    }
    
    private func restoreState(_ state: CropState) {
        cropRect = state.cropRect
        rotation = state.rotation
        isFlippedHorizontally = state.isFlippedHorizontally
        isFlippedVertically = state.isFlippedVertically
        scale = state.scale
        offset = state.offset
        updatePreview()
    }
    
    private func applyFixedRatio(_ ratio: CGFloat) {
        let currentCenter = CGPoint(x: cropRect.midX, y: cropRect.midY)
        let maxRect = displayImageRect
        
        var newWidth: CGFloat
        var newHeight: CGFloat
        
        // 尝试以当前高度计算宽度
        newHeight = cropRect.height
        newWidth = newHeight * ratio
        
        // 如果超出边界，以宽度为准
        if newWidth > maxRect.width {
            newWidth = maxRect.width
            newHeight = newWidth / ratio
        }
        
        // 如果还是超出，以高度为准
        if newHeight > maxRect.height {
            newHeight = maxRect.height
            newWidth = newHeight * ratio
        }
        
        var newRect = CGRect(
            x: currentCenter.x - newWidth / 2,
            y: currentCenter.y - newHeight / 2,
            width: newWidth,
            height: newHeight
        )
        
        // 确保在边界内
        newRect = constrainCropRect(newRect)
        cropRect = newRect
    }
    
    private func applyRatioConstraint(_ rect: CGRect, ratio: CGFloat, anchor: CropResizeAnchor) -> CGRect {
        var newRect = rect
        let currentRatio = rect.width / rect.height
        
        // 根据拖拽锚点调整
        switch anchor {
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            // 角点拖拽 - 保持比例
            if currentRatio > ratio {
                newRect.size.height = newRect.width / ratio
            } else {
                newRect.size.width = newRect.height * ratio
            }
        case .top, .bottom:
            // 上下边缘 - 调整宽度
            newRect.size.width = newRect.height * ratio
        case .left, .right:
            // 左右边缘 - 调整高度
            newRect.size.height = newRect.width / ratio
        case .center:
            // 中心点不改变尺寸
            break
        }
        
        return newRect
    }
    
    private func constrainCropRect(_ rect: CGRect) -> CGRect {
        let imageRect = displayImageRect
        var constrained = rect
        
        // 最小尺寸限制
        constrained.size.width = max(constrained.size.width, minCropSize)
        constrained.size.height = max(constrained.size.height, minCropSize)
        
        // 最大尺寸限制（不超出图片显示区域）
        constrained.size.width = min(constrained.size.width, imageRect.width)
        constrained.size.height = min(constrained.size.height, imageRect.height)
        
        // 位置限制
        constrained.origin.x = max(constrained.origin.x, imageRect.minX)
        constrained.origin.y = max(constrained.origin.y, imageRect.minY)
        constrained.origin.x = min(constrained.origin.x, imageRect.maxX - constrained.width)
        constrained.origin.y = min(constrained.origin.y, imageRect.maxY - constrained.height)
        
        return constrained
    }
    
    private func generatePreview() async throws -> UIImage {
        // 在闭包外捕获需要的值
        let originalImage = self.originalImage
        let displayImageRect = self.displayImageRect
        let cropRect = self.cropRect
        let isFlippedHorizontally = self.isFlippedHorizontally
        let isFlippedVertically = self.isFlippedVertically
        let rotation = self.rotation
        
        return try await Task.detached(priority: .userInitiated) {
            let imageSize = originalImage.size
            let displayRect = displayImageRect
            
            // 计算裁剪比例
            let scaleX = imageSize.width / displayRect.width
            let scaleY = imageSize.height / displayRect.height
            
            var imageCropRect = CGRect(
                x: (cropRect.origin.x - displayRect.origin.x) * scaleX,
                y: (cropRect.origin.y - displayRect.origin.y) * scaleY,
                width: cropRect.width * scaleX,
                height: cropRect.height * scaleY
            )
            
            // 处理翻转
            if isFlippedHorizontally {
                imageCropRect.origin.x = imageSize.width - imageCropRect.maxX
            }
            if isFlippedVertically {
                imageCropRect.origin.y = imageSize.height - imageCropRect.maxY
            }
            
            // 限制在图片范围内
            imageCropRect = imageCropRect.intersection(CGRect(origin: .zero, size: imageSize))
            
            guard imageCropRect.width > 0, imageCropRect.height > 0 else {
                throw CropError.invalidCropRect
            }
            
            guard let cgImage = originalImage.cgImage?.cropping(to: imageCropRect) else {
                throw CropError.cropFailed
            }
            
            var previewImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: originalImage.imageOrientation)
            
            // 应用旋转
            if rotation != 0 {
                previewImage = await Self.rotateImageStatic(previewImage, by: rotation)
            }
            
            // 压缩预览图以提高性能
            return await Self.compressForPreviewStatic(previewImage)
        }.value
    }
    
    private static func compressForPreviewStatic(_ image: UIImage) -> UIImage {
        let maxPreviewSize: CGFloat = 400
        let scale = min(1.0, maxPreviewSize / max(image.size.width, image.size.height))
        
        if scale >= 1.0 { return image }
        
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    private static func rotateImageStatic(_ image: UIImage, by degrees: CGFloat) -> UIImage {
        let radians = degrees * .pi / 180
        let rotatedSize = CGSize(
            width: abs(image.size.width * cos(radians)) + abs(image.size.height * sin(radians)),
            height: abs(image.size.width * sin(radians)) + abs(image.size.height * cos(radians))
        )
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        
        let renderer = UIGraphicsImageRenderer(size: rotatedSize, format: format)
        return renderer.image { context in
            let cgContext = context.cgContext
            cgContext.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
            cgContext.rotate(by: radians)
            image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2, width: image.size.width, height: image.size.height))
        }
    }
}

/// 裁剪调整锚点
enum CropResizeAnchor {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
    case center
}

/// 裁剪错误
enum CropError: Error {
    case cropFailed
    case invalidCropRect
    case imageNotFound
}
