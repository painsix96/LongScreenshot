import UIKit
import Photos

/// 导出格式枚举
enum ExportFormat: String, CaseIterable, Identifiable {
    case png = "PNG"
    case jpeg = "JPEG"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .png:
            return "PNG - 无损格式"
        case .jpeg:
            return "JPEG - 压缩格式"
        }
    }

    var fileExtension: String {
        switch self {
        case .png:
            return "png"
        case .jpeg:
            return "jpg"
        }
    }

    var mimeType: String {
        switch self {
        case .png:
            return "image/png"
        case .jpeg:
            return "image/jpeg"
        }
    }
}

/// 导出进度
enum ExportProgress: Equatable {
    case idle
    case preparing
    case converting(progress: Double)
    case saving
    case completed
    case failed(error: String)
}

/// 导出配置
struct ExportConfiguration {
    var format: ExportFormat = .png
    var jpegQuality: Double = 0.85
    var includeMetadata: Bool = true

    /// 默认配置
    static let `default` = ExportConfiguration()

    /// 高质量 JPEG 配置
    static let highQualityJPEG = ExportConfiguration(format: .jpeg, jpegQuality: 0.95)

    /// 小文件配置
    static let smallFile = ExportConfiguration(format: .jpeg, jpegQuality: 0.70)
}

/// 导出结果
struct ExportResult {
    let image: UIImage
    let format: ExportFormat
    let fileSize: Int64
    let fileURL: URL?
    let dimensions: CGSize

    var fileSizeDescription: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

/// 批量导出结果
struct BatchExportResult {
    let results: [ExportResult]
    let totalFileSize: Int64
    let successCount: Int
    let failedCount: Int

    var fileSizeDescription: String {
        ByteCountFormatter.string(fromByteCount: totalFileSize, countStyle: .file)
    }
}

/// 导出服务错误
enum ExportError: LocalizedError {
    case invalidImage
    case conversionFailed
    case saveFailed(Error)
    case permissionDenied
    case fileCreationFailed
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "无效的图片数据"
        case .conversionFailed:
            return "图片格式转换失败"
        case .saveFailed(let error):
            return "保存失败：\(error.localizedDescription)"
        case .permissionDenied:
            return "没有相册访问权限"
        case .fileCreationFailed:
            return "无法创建临时文件"
        case .unknown:
            return "未知错误"
        }
    }
}

/// 导出服务
@MainActor
final class ExportService: ObservableObject {
    // MARK: - Published Properties

    /// 当前导出进度
    @Published var progress: ExportProgress = .idle

    /// 是否正在导出
    @Published var isExporting = false

    /// 导出队列
    @Published private(set) var exportQueue: [ExportTask] = []

    // MARK: - Singleton

    static let shared = ExportService()

    private init() {}

    // MARK: - Types

    /// 导出任务
    struct ExportTask: Identifiable {
        let id = UUID()
        let image: UIImage
        let configuration: ExportConfiguration
        var status: TaskStatus = .pending

        enum TaskStatus {
            case pending
            case processing
            case completed(ExportResult)
            case failed(String)
        }
    }

    // MARK: - 导出方法

    /// 导出单张图片
    /// - Parameters:
    ///   - image: 要导出的图片
    ///   - configuration: 导出配置
    /// - Returns: 导出结果
    func export(
        image: UIImage,
        configuration: ExportConfiguration = .default
    ) async throws -> ExportResult {
        guard !isExporting else {
            throw ExportError.unknown
        }

        isExporting = true
        progress = .preparing

        defer {
            isExporting = false
            progress = .idle
        }

        // 模拟进度更新
        try await updateProgress(.converting(progress: 0.3))
        try await Task.sleep(nanoseconds: 100_000_000)

        try await updateProgress(.converting(progress: 0.6))

        // 执行格式转换
        let result = try await convertImage(image, configuration: configuration)

        try await updateProgress(.converting(progress: 1.0))
        try await Task.sleep(nanoseconds: 100_000_000)

        return result
    }

    /// 导出并保存到相册
    /// - Parameters:
    ///   - image: 要导出的图片
    ///   - configuration: 导出配置
    /// - Returns: 导出结果
    func exportAndSave(
        image: UIImage,
        configuration: ExportConfiguration = .default
    ) async throws -> ExportResult {
        let result = try await export(image: image, configuration: configuration)

        progress = .saving

        // 保存到相册
        try await saveToPhotoLibrary(result.image)

        progress = .completed

        return result
    }

    /// 批量导出图片
    /// - Parameters:
    ///   - images: 要导出的图片数组
    ///   - configuration: 导出配置
    ///   - progressHandler: 进度回调
    /// - Returns: 批量导出结果
    func batchExport(
        images: [UIImage],
        configuration: ExportConfiguration = .default,
        progressHandler: ((Int, Int) -> Void)? = nil
    ) async -> BatchExportResult {
        isExporting = true
        progress = .preparing

        var results: [ExportResult] = []
        var successCount = 0
        var failedCount = 0
        var totalFileSize: Int64 = 0

        for (index, image) in images.enumerated() {
            let progressValue = Double(index) / Double(images.count)
            progress = .converting(progress: progressValue)

            progressHandler?(index + 1, images.count)

            do {
                let result = try await convertImage(image, configuration: configuration)
                results.append(result)
                totalFileSize += result.fileSize
                successCount += 1
            } catch {
                failedCount += 1
            }
        }

        progress = .completed
        isExporting = false

        return BatchExportResult(
            results: results,
            totalFileSize: totalFileSize,
            successCount: successCount,
            failedCount: failedCount
        )
    }

    /// 批量导出并保存到相册
    /// - Parameters:
    ///   - images: 要导出的图片数组
    ///   - configuration: 导出配置
    ///   - progressHandler: 进度回调
    /// - Returns: 批量导出结果
    func batchExportAndSave(
        images: [UIImage],
        configuration: ExportConfiguration = .default,
        progressHandler: ((Int, Int) -> Void)? = nil
    ) async -> BatchExportResult {
        let result = await batchExport(
            images: images,
            configuration: configuration,
            progressHandler: progressHandler
        )

        // 保存所有图片到相册
        progress = .saving

        for exportResult in result.results {
            try? await saveToPhotoLibrary(exportResult.image)
        }

        progress = .completed

        return result
    }

    // MARK: - 格式转换

    /// 转换图片格式
    /// - Parameters:
    ///   - image: 原始图片
    ///   - configuration: 导出配置
    /// - Returns: 导出结果
    private func convertImage(
        _ image: UIImage,
        configuration: ExportConfiguration
    ) async throws -> ExportResult {
        guard let cgImage = image.cgImage else {
            throw ExportError.invalidImage
        }

        let data: Data?
        let format = configuration.format

        switch format {
        case .png:
            data = image.pngData()
        case .jpeg:
            data = image.jpegData(compressionQuality: configuration.jpegQuality)
        }

        guard let imageData = data else {
            throw ExportError.conversionFailed
        }

        // 创建临时文件
        let tempURL = try createTempFile(
            data: imageData,
            extension: format.fileExtension
        )

        // 计算文件大小
        let fileSize = Int64(imageData.count)

        // 创建导出结果（使用原始图片用于分享和预览）
        return ExportResult(
            image: image,
            format: format,
            fileSize: fileSize,
            fileURL: tempURL,
            dimensions: CGSize(
                width: cgImage.width,
                height: cgImage.height
            )
        )
    }

    /// 预估文件大小
    /// - Parameters:
    ///   - image: 图片
    ///   - format: 导出格式
    ///   - jpegQuality: JPEG 质量（仅 JPEG 格式有效）
    /// - Returns: 预估文件大小（字节）
    func estimateFileSize(
        image: UIImage,
        format: ExportFormat,
        jpegQuality: Double = 0.85
    ) -> Int64 {
        guard let cgImage = image.cgImage else { return 0 }

        let width = cgImage.width
        let height = cgImage.height
        let bitsPerPixel = cgImage.bitsPerPixel

        let uncompressedSize = Int64(width * height * (bitsPerPixel / 8))

        switch format {
        case .png:
            // PNG 通常压缩率约为 30-50%
            return Int64(Double(uncompressedSize) * 0.4)
        case .jpeg:
            // JPEG 大小与质量相关
            let qualityFactor = 0.3 + (jpegQuality * 0.7)
            return Int64(Double(uncompressedSize) * qualityFactor * 0.15)
        }
    }

    // MARK: - 保存到相册

    /// 保存图片到相册
    /// - Parameter image: 要保存的图片
    private func saveToPhotoLibrary(_ image: UIImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)

        guard status == .authorized || status == .limited else {
            throw ExportError.permissionDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, error in
                if let error = error {
                    continuation.resume(throwing: ExportError.saveFailed(error))
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ExportError.unknown)
                }
            }
        }
    }

    // MARK: - 临时文件管理

    /// 创建临时文件
    /// - Parameters:
    ///   - data: 文件数据
    ///   - extension: 文件扩展名
    /// - Returns: 临时文件 URL
    private func createTempFile(data: Data, extension: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "\(UUID().uuidString).\(`extension`)"
        let fileURL = tempDir.appendingPathComponent(fileName)

        try data.write(to: fileURL)

        return fileURL
    }

    /// 清理临时文件
    func cleanTempFiles() {
        let tempDir = FileManager.default.temporaryDirectory

        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: tempDir,
                includingPropertiesForKeys: nil
            )

            for file in files {
                if file.pathExtension == "png" || file.pathExtension == "jpg" {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        } catch {
            print("清理临时文件失败：\(error)")
        }
    }

    // MARK: - 分享相关

    /// 准备分享数据
    /// - Parameters:
    ///   - image: 要分享的图片
    ///   - configuration: 导出配置
    /// - Returns: 分享用的数据
    func prepareShareData(
        image: UIImage,
        configuration: ExportConfiguration = .default
    ) async throws -> ShareData {
        let data: Data?

        switch configuration.format {
        case .png:
            data = image.pngData()
        case .jpeg:
            data = image.jpegData(compressionQuality: configuration.jpegQuality)
        }

        guard let imageData = data else {
            throw ExportError.conversionFailed
        }

        return ShareData(
            image: image,
            data: imageData,
            format: configuration.format
        )
    }

    // MARK: - 辅助方法

    /// 更新进度
    private func updateProgress(_ newProgress: ExportProgress) async throws {
        try await Task.sleep(nanoseconds: 10_000_000) // 短暂延迟确保 UI 更新
        await MainActor.run {
            self.progress = newProgress
        }
    }

    /// 取消导出
    func cancelExport() {
        progress = .idle
        isExporting = false
        exportQueue.removeAll()
    }
}

// MARK: - 分享数据

/// 分享数据
struct ShareData {
    let image: UIImage
    let data: Data
    let format: ExportFormat

    var fileName: String {
        "LongScreenshot_\(Date().timeIntervalSince1970).\(format.fileExtension)"
    }
}

// MARK: - UIActivityViewController 包装

import SwiftUI

/// 分享 Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]?
    let completion: (Bool) -> Void

    init(
        activityItems: [Any],
        applicationActivities: [UIActivity]? = nil,
        completion: @escaping (Bool) -> Void = { _ in }
    ) {
        self.activityItems = activityItems
        self.applicationActivities = applicationActivities
        self.completion = completion
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )

        controller.completionWithItemsHandler = { _, completed, _, _ in
            completion(completed)
        }

        // 排除某些不需要的分享选项
        controller.excludedActivityTypes = [
            .assignToContact,
            .addToReadingList,
            .postToFacebook
        ]

        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - ShareLink 扩展

extension View {
    /// 添加分享功能
    func shareSheet(
        isPresented: Binding<Bool>,
        items: [Any],
        onComplete: ((Bool) -> Void)? = nil
    ) -> some View {
        self.sheet(isPresented: isPresented) {
            ShareSheet(
                activityItems: items,
                completion: { completed in
                    isPresented.wrappedValue = false
                    onComplete?(completed)
                }
            )
        }
    }
}

// MARK: - 预览用扩展

extension ExportService {
    /// 创建预览用的导出服务
    static var preview: ExportService {
        let service = ExportService()
        return service
    }
}
