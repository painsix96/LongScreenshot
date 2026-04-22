import UIKit
import XCTest
import CoreData

// MARK: - 测试辅助工具类

/// 测试辅助工具类，提供创建测试图片、清理测试数据等功能
class TestHelper {
    
    static let shared = TestHelper()
    
    private let fileManager = FileManager.default
    private var testFiles: [URL] = []
    
    private init() {}
    
    // MARK: - 创建测试图片
    
    /// 创建纯色测试图片
    /// - Parameters:
    ///   - color: 图片颜色
    ///   - size: 图片尺寸
    ///   - scale: 缩放比例
    /// - Returns: 生成的 UIImage
    func createSolidColorImage(
        color: UIColor,
        size: CGSize,
        scale: CGFloat = 1.0
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        
        return image
    }
    
    /// 创建带有底部渐变的测试图片（模拟真实截图）
    /// - Parameters:
    ///   - size: 图片尺寸
    ///   - baseColor: 基础颜色
    ///   - gradientHeight: 渐变区域高度
    /// - Returns: 生成的 UIImage
    func createScreenshotMockImage(
        size: CGSize,
        baseColor: UIColor = .white,
        gradientHeight: CGFloat = 200
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            // 绘制基础背景
            baseColor.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            
            // 绘制渐变区域（模拟截图重叠部分）
            let gradientRect = CGRect(
                x: 0,
                y: size.height - gradientHeight,
                width: size.width,
                height: gradientHeight
            )
            
            let gradientColors = [baseColor.cgColor, UIColor.lightGray.cgColor]
            let gradientLocations: [CGFloat] = [0.0, 1.0]
            
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: gradientColors as CFArray,
                locations: gradientLocations
            ) {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: gradientRect.minY),
                    end: CGPoint(x: 0, y: gradientRect.maxY),
                    options: []
                )
            }
            
            // 添加一些随机线条模拟内容
            for _ in 0..<20 {
                let lineY = CGFloat.random(in: 0..<size.height)
                let lineRect = CGRect(x: 0, y: lineY, width: size.width, height: 2)
                UIColor.darkGray.withAlphaComponent(0.3).setFill()
                context.fill(lineRect)
            }
        }
        
        return image
    }
    
    /// 创建可拼接的测试图片对
    /// - Parameters:
    ///   - width: 图片宽度
    ///   - height: 单张图片高度
    ///   - overlapHeight: 重叠区域高度
    /// - Returns: 两张有重叠的图片
    func createStitchableImagePair(
        width: CGFloat = 1080,
        height: CGFloat = 1920,
        overlapHeight: CGFloat = 200
    ) -> (top: UIImage, bottom: UIImage) {
        // 创建基础图案
        let baseImage = createScreenshotMockImage(
            size: CGSize(width: width, height: height * 2 - overlapHeight),
            baseColor: .white,
            gradientHeight: overlapHeight
        )
        
        // 裁剪顶部图片
        let topImage = cropImage(baseImage, rect: CGRect(
            x: 0,
            y: 0,
            width: width,
            height: height
        ))
        
        // 裁剪底部图片
        let bottomImage = cropImage(baseImage, rect: CGRect(
            x: 0,
            y: height - overlapHeight,
            width: width,
            height: height
        ))
        
        return (topImage, bottomImage)
    }
    
    /// 创建多张可拼接的测试图片
    /// - Parameters:
    ///   - count: 图片数量
    ///   - width: 图片宽度
    ///   - height: 单张图片高度
    ///   - overlapHeight: 重叠区域高度
    /// - Returns: 图片数组
    func createStitchableImages(
        count: Int,
        width: CGFloat = 1080,
        height: CGFloat = 1920,
        overlapHeight: CGFloat = 200
    ) -> [UIImage] {
        guard count >= 2 else {
            return [createScreenshotMockImage(size: CGSize(width: width, height: height))]
        }
        
        let totalHeight = height + CGFloat(count - 1) * (height - overlapHeight)
        let baseImage = createScreenshotMockImage(
            size: CGSize(width: width, height: totalHeight),
            baseColor: .white,
            gradientHeight: overlapHeight
        )
        
        var images: [UIImage] = []
        for i in 0..<count {
            let yOffset = CGFloat(i) * (height - overlapHeight)
            let image = cropImage(baseImage, rect: CGRect(
                x: 0,
                y: yOffset,
                width: width,
                height: height
            ))
            images.append(image)
        }
        
        return images
    }
    
    /// 裁剪图片
    private func cropImage(_ image: UIImage, rect: CGRect) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = image.isOpaque
        
        let renderer = UIGraphicsImageRenderer(size: rect.size, format: format)
        return renderer.image { context in
            image.draw(at: CGPoint(x: -rect.origin.x, y: -rect.origin.y))
        }
    }
    
    /// 创建 1080p 测试图片
    func create1080pImage(color: UIColor = .blue) -> UIImage {
        return createSolidColorImage(color: color, size: CGSize(width: 1080, height: 1920))
    }
    
    /// 创建 4K 测试图片
    func create4KImage(color: UIColor = .red) -> UIImage {
        return createSolidColorImage(color: color, size: CGSize(width: 3840, height: 2160))
    }
    
    // MARK: - 图片比较
    
    /// 比较两张图片是否相同
    func areImagesEqual(_ image1: UIImage, _ image2: UIImage, tolerance: CGFloat = 0.01) -> Bool {
        guard let cgImage1 = image1.cgImage,
              let cgImage2 = image2.cgImage else {
            return false
        }
        
        let width1 = cgImage1.width
        let height1 = cgImage1.height
        let width2 = cgImage2.width
        let height2 = cgImage2.height
        
        guard width1 == width2 && height1 == height2 else {
            return false
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var rawData1 = [UInt8](repeating: 0, count: width1 * height1 * 4)
        var rawData2 = [UInt8](repeating: 0, count: width1 * height1 * 4)
        
        guard let context1 = CGContext(
            data: &rawData1,
            width: width1,
            height: height1,
            bitsPerComponent: 8,
            bytesPerRow: 4 * width1,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let context2 = CGContext(
            data: &rawData2,
            width: width1,
            height: height1,
            bitsPerComponent: 8,
            bytesPerRow: 4 * width1,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }
        
        context1.draw(cgImage1, in: CGRect(x: 0, y: 0, width: width1, height: height1))
        context2.draw(cgImage2, in: CGRect(x: 0, y: 0, width: width1, height: height1))
        
        var diffCount = 0
        let pixelCount = width1 * height1
        let maxDiffPixels = Int(CGFloat(pixelCount) * tolerance)
        
        for i in 0..<pixelCount * 4 {
            if abs(Int(rawData1[i]) - Int(rawData2[i])) > 10 {
                diffCount += 1
                if diffCount > maxDiffPixels {
                    return false
                }
            }
        }
        
        return true
    }
    
    // MARK: - 测试数据清理
    
    /// 注册测试文件路径用于后续清理
    func registerTestFile(_ url: URL) {
        testFiles.append(url)
    }
    
    /// 清理所有测试文件
    func cleanupTestFiles() {
        for url in testFiles {
            try? fileManager.removeItem(at: url)
        }
        testFiles.removeAll()
    }
    
    /// 清理 Core Data 内存存储
    func cleanupCoreData(container: NSPersistentContainer) {
        let context = container.viewContext
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "StitchHistory")
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        
        do {
            try container.persistentStoreCoordinator.execute(deleteRequest, with: context)
        } catch {
            print("清理 Core Data 失败: \(error)")
        }
    }
    
    /// 创建临时目录
    func createTempDirectory() -> URL? {
        let tempDir = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        
        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            testFiles.append(tempDir)
            return tempDir
        } catch {
            print("创建临时目录失败: \(error)")
            return nil
        }
    }
    
    /// 保存图片到临时文件
    func saveImageToTemp(_ image: UIImage, filename: String? = nil) -> URL? {
        let name = filename ?? "\(UUID().uuidString).jpg"
        guard let tempDir = createTempDirectory() else { return nil }
        let fileURL = tempDir.appendingPathComponent(name)
        
        guard let data = image.jpegData(compressionQuality: 0.9) else { return nil }
        
        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("保存图片失败: \(error)")
            return nil
        }
    }
    
    /// 从 Bundle 加载测试图片
    func loadTestImageFromBundle(named name: String, withExtension ext: String = "jpg") -> UIImage? {
        let bundle = Bundle(for: TestHelper.self)
        guard let url = bundle.url(forResource: name, withExtension: ext) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

// MARK: - XCTest 扩展

extension XCTestCase {
    
    /// 异步等待一段时间
    func waitAsync(timeout: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
    }
    
    /// 测量异步操作的执行时间
    func measureAsync<T>(
        _ name: String,
        operation: () async throws -> T
    ) async rethrows -> (result: T, duration: TimeInterval) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try await operation()
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        return (result, duration)
    }
}

// MARK: - 性能测试断言

extension XCTestCase {
    
    /// 断言操作在指定时间内完成
    func assertPerformance(
        operation: () async throws -> Void,
        maxDuration: TimeInterval,
        message: String = "操作耗时超过预期"
    ) async rethrows {
        let (_, duration) = try await measureAsync("", operation: operation)
        XCTAssertLessThan(duration, maxDuration, message)
    }
}

// MARK: - 图片断言

extension XCTestCase {
    
    /// 断言两张图片相等
    func XCTAssertImagesEqual(
        _ image1: UIImage,
        _ image2: UIImage,
        tolerance: CGFloat = 0.01,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let areEqual = TestHelper.shared.areImagesEqual(image1, image2, tolerance: tolerance)
        XCTAssertTrue(areEqual, "图片不相等", file: file, line: line)
    }
    
    /// 断言图片尺寸符合预期
    func XCTAssertImageSize(
        _ image: UIImage,
        width: CGFloat,
        height: CGFloat,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertEqual(image.size.width, width, accuracy: 0.5, "图片宽度不匹配", file: file, line: line)
        XCTAssertEqual(image.size.height, height, accuracy: 0.5, "图片高度不匹配", file: file, line: line)
    }
}
