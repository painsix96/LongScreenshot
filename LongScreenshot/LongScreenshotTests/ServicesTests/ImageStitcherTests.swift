import XCTest
import UIKit
@testable import LongScreenshot

// MARK: - ImageStitcher 单元测试

@MainActor
final class ImageStitcherTests: XCTestCase {
    
    var imageStitcher: ImageStitcher!
    var testHelper: TestHelper!
    
    override func setUp() {
        super.setUp()
        imageStitcher = ImageStitcher(config: .default)
        testHelper = TestHelper.shared
    }
    
    override func tearDown() {
        testHelper.cleanupTestFiles()
        imageStitcher = nil
        super.tearDown()
    }
    
    // MARK: - 基本拼接功能测试
    
    /// 测试基本拼接功能：两张有重叠的图片
    func testBasicStitch_TwoImages() async throws {
        let (topImage, bottomImage) = testHelper.createStitchableImagePair(
            width: 400,
            height: 600,
            overlapHeight: 100
        )
        
        let result = try await imageStitcher.stitch(images: [topImage, bottomImage])
        
        XCTAssertNotNil(result.image, "拼接结果不应该为 nil")
        XCTAssertEqual(result.processedCount, 2, "应该处理 2 张图片")
        XCTAssertGreaterThan(result.totalHeight, topImage.size.height, "拼接后高度应该大于单张图片")
        XCTAssertLessThan(result.totalHeight, topImage.size.height + bottomImage.size.height, "重叠区域应该被消除")
    }
    
    /// 测试基本拼接功能：相同图片
    func testBasicStitch_IdenticalImages() async throws {
        let image = testHelper.createScreenshotMockImage(size: CGSize(width: 400, height: 600))
        
        let result = try await imageStitcher.stitch(images: [image, image])
        
        XCTAssertNotNil(result.image)
        XCTAssertGreaterThan(result.totalHeight, 0)
    }
    
    /// 测试拼接结果的尺寸
    func testStitch_ResultDimensions() async throws {
        let (topImage, bottomImage) = testHelper.createStitchableImagePair(
            width: 400,
            height: 600,
            overlapHeight: 100
        )
        
        let result = try await imageStitcher.stitch(images: [topImage, bottomImage])
        
        XCTAssertEqual(result.image.size.width, 400, accuracy: 1.0, "拼接后宽度应该保持一致")
        XCTAssertGreaterThan(result.image.size.height, 500, "拼接后高度应该合理")
    }
    
    // MARK: - 多张图片拼接测试
    
    /// 测试多张图片拼接：3张图片
    func testStitch_MultipleImages_3() async throws {
        let images = testHelper.createStitchableImages(
            count: 3,
            width: 400,
            height: 600,
            overlapHeight: 100
        )
        
        let result = try await imageStitcher.stitch(images: images)
        
        XCTAssertNotNil(result.image)
        XCTAssertEqual(result.processedCount, 3)
        XCTAssertEqual(result.overlaps.count, 2, "3 张图片应该有 2 个重叠信息")
    }
    
    /// 测试多张图片拼接：5张图片
    func testStitch_MultipleImages_5() async throws {
        let images = testHelper.createStitchableImages(
            count: 5,
            width: 400,
            height: 600,
            overlapHeight: 100
        )
        
        let result = try await imageStitcher.stitch(images: images)
        
        XCTAssertNotNil(result.image)
        XCTAssertEqual(result.processedCount, 5)
        XCTAssertEqual(result.overlaps.count, 4, "5 张图片应该有 4 个重叠信息")
    }
    
    /// 测试多张图片拼接：10张图片
    func testStitch_MultipleImages_10() async throws {
        let images = testHelper.createStitchableImages(
            count: 10,
            width: 400,
            height: 400,
            overlapHeight: 50
        )
        
        let result = try await imageStitcher.stitch(images: images)
        
        XCTAssertNotNil(result.image)
        XCTAssertEqual(result.processedCount, 10)
    }
    
    /// 测试快速拼接模式
    func testStitchQuickly() async throws {
        let (topImage, bottomImage) = testHelper.createStitchableImagePair(
            width: 400,
            height: 600,
            overlapHeight: 100
        )
        
        let stitchedImage = try await imageStitcher.stitchQuickly(images: [topImage, bottomImage])
        
        XCTAssertNotNil(stitchedImage, "快速拼接应该返回图片")
    }
    
    // MARK: - 错误处理测试
    
    /// 测试图片数量不足错误
    func testError_InsufficientImages() async {
        let singleImage = testHelper.createScreenshotMockImage(size: CGSize(width: 400, height: 600))
        
        do {
            _ = try await imageStitcher.stitch(images: [singleImage])
            XCTFail("应该抛出 insufficientImages 错误")
        } catch let error as StitchError {
            XCTAssertEqual(error, StitchError.insufficientImages)
        } catch {
            XCTFail("错误类型不匹配")
        }
    }
    
    /// 测试空数组错误
    func testError_EmptyArray() async {
        do {
            _ = try await imageStitcher.stitch(images: [])
            XCTFail("应该抛出 insufficientImages 错误")
        } catch let error as StitchError {
            XCTAssertEqual(error, StitchError.insufficientImages)
        } catch {
            XCTFail("错误类型不匹配")
        }
    }
    
    /// 测试超出最大图片数限制
    func testError_MaxImagesExceeded() async {
        // 创建 25 张图片（超过默认 20 张限制）
        let images = testHelper.createStitchableImages(
            count: 25,
            width: 200,
            height: 200,
            overlapHeight: 20
        )
        
        do {
            _ = try await imageStitcher.stitch(images: images)
            XCTFail("应该抛出超出最大图片数错误")
        } catch let error as StitchError {
            if case .custom(let message) = error {
                XCTAssertTrue(message.contains("20"), "错误信息应该包含最大图片数")
            } else {
                // 可能抛出其他类型的错误
                print("捕获到错误: \(error)")
            }
        } catch {
            print("捕获到未知错误: \(error)")
        }
    }
    
    /// 测试无效图片数据
    func testError_InvalidImageData() async {
        // 创建一个空的 UIImage（没有 CGImage）
        let emptyImage = UIImage()
        
        do {
            _ = try await imageStitcher.stitch(images: [emptyImage, emptyImage])
            XCTFail("应该抛出无效图片数据错误")
        } catch {
            // 应该捕获到某种错误
            print("捕获到错误: \(error)")
        }
    }
    
    // MARK: - 不同配置测试
    
    /// 测试高性能配置
    func testConfig_HighPerformance() async throws {
        let highPerformanceStitcher = ImageStitcher(config: .highPerformance)
        let (topImage, bottomImage) = testHelper.createStitchableImagePair(
            width: 400,
            height: 600,
            overlapHeight: 100
        )
        
        let result = try await highPerformanceStitcher.stitch(images: [topImage, bottomImage])
        
        XCTAssertNotNil(result.image)
    }
    
    /// 测试高质量配置
    func testConfig_HighQuality() async throws {
        let highQualityStitcher = ImageStitcher(config: .highQuality)
        let (topImage, bottomImage) = testHelper.createStitchableImagePair(
            width: 400,
            height: 600,
            overlapHeight: 100
        )
        
        let result = try await highQualityStitcher.stitch(images: [topImage, bottomImage])
        
        XCTAssertNotNil(result.image)
    }
    
    /// 测试自定义配置
    func testConfig_Custom() async throws {
        let customConfig = StitchingConfig(
            maxImages: 5,
            enableOverlapDetection: false,
            enableBlending: false,
            outputQuality: 0.8,
            fastMode: true,
            memoryLimitMB: 128
        )
        let customStitcher = ImageStitcher(config: customConfig)
        
        let (topImage, bottomImage) = testHelper.createStitchableImagePair(
            width: 400,
            height: 600,
            overlapHeight: 100
        )
        
        let result = try await customStitcher.stitch(images: [topImage, bottomImage])
        
        XCTAssertNotNil(result.image)
    }
    
    // MARK: - 内存管理测试
    
    /// 测试大图片拼接时的内存使用
    func testMemory_LargeImages() async throws {
        let (topImage, bottomImage) = testHelper.createStitchableImagePair(
            width: 1080,
            height: 1920,
            overlapHeight: 200
        )
        
        let result = try await imageStitcher.stitch(images: [topImage, bottomImage])
        
        XCTAssertNotNil(result.image)
        XCTAssertGreaterThan(result.memoryPeakUsage, 0, "应该有内存使用记录")
        print("内存峰值使用: \(result.memoryPeakUsage) MB")
    }
    
    /// 测试多张 1080p 图片拼接
    func testMemory_Multiple1080pImages() async throws {
        let images = testHelper.createStitchableImages(
            count: 3,
            width: 1080,
            height: 1920,
            overlapHeight: 200
        )
        
        let result = try await imageStitcher.stitch(images: images)
        
        XCTAssertNotNil(result.image)
        XCTAssertGreaterThan(result.memoryPeakUsage, 0)
        print("3 张 1080p 图片拼接内存峰值: \(result.memoryPeakUsage) MB")
    }
    
    /// 测试拼接结果的信息完整性
    func testStitchResult_Information() async throws {
        let (topImage, bottomImage) = testHelper.createStitchableImagePair(
            width: 400,
            height: 600,
            overlapHeight: 100
        )
        
        let result = try await imageStitcher.stitch(images: [topImage, bottomImage])
        
        XCTAssertGreaterThan(result.processingTime, 0, "应该有处理时间")
        XCTAssertEqual(result.processedCount, 2)
        XCTAssertGreaterThan(result.totalHeight, 0)
    }
    
    // MARK: - 静态方法测试
    
    /// 测试静态快速拼接方法
    func testStatic_Stitch() async {
        let (topImage, bottomImage) = testHelper.createStitchableImagePair(
            width: 400,
            height: 600,
            overlapHeight: 100
        )
        
        let stitchedImage = await ImageStitcher.stitch(images: [topImage, bottomImage])
        
        XCTAssertNotNil(stitchedImage)
    }
    
    /// 测试静态高质量拼接方法
    func testStatic_StitchHighQuality() async {
        let (topImage, bottomImage) = testHelper.createStitchableImagePair(
            width: 400,
            height: 600,
            overlapHeight: 100
        )
        
        let stitchedImage = await ImageStitcher.stitchHighQuality(images: [topImage, bottomImage])
        
        XCTAssertNotNil(stitchedImage)
    }
    
    /// 测试静态方法：图片数量不足
    func testStatic_InsufficientImages() async {
        let singleImage = testHelper.createScreenshotMockImage(size: CGSize(width: 400, height: 600))
        
        let result = await ImageStitcher.stitch(images: [singleImage])
        
        XCTAssertNil(result, "单张图片应该返回 nil")
    }
    
    // MARK: - 性能测试
    
    /// 测试两张 1080p 图片拼接性能
    func testPerformance_Two1080p() async throws {
        let (topImage, bottomImage) = testHelper.createStitchableImagePair(
            width: 1080,
            height: 1920,
            overlapHeight: 200
        )
        
        let (_, duration) = await measureAsync("stitch") {
            try await imageStitcher.stitch(images: [topImage, bottomImage])
        }
        
        XCTAssertLessThan(duration, 30.0, "两张 1080p 图片拼接应该在 30 秒内完成")
        print("两张 1080p 图片拼接时间: \(duration * 1000)ms")
    }
    
    /// 测试多张图片拼接性能
    func testPerformance_MultipleImages() async throws {
        let images = testHelper.createStitchableImages(
            count: 5,
            width: 800,
            height: 1200,
            overlapHeight: 150
        )
        
        let (_, duration) = await measureAsync("stitch") {
            try await imageStitcher.stitch(images: images)
        }
        
        XCTAssertLessThan(duration, 60.0, "5 张图片拼接应该在 60 秒内完成")
        print("5 张图片拼接时间: \(duration * 1000)ms")
    }
    
    // MARK: - 边界条件测试
    
    /// 测试小尺寸图片拼接
    func testSmallImages() async throws {
        let image1 = testHelper.createSolidColorImage(color: .red, size: CGSize(width: 50, height: 50))
        let image2 = testHelper.createSolidColorImage(color: .blue, size: CGSize(width: 50, height: 50))
        
        let result = try await imageStitcher.stitch(images: [image1, image2])
        
        XCTAssertNotNil(result.image)
    }
    
    /// 测试极端长宽比图片拼接
    func testExtremeAspectRatio() async throws {
        let image1 = testHelper.createSolidColorImage(color: .green, size: CGSize(width: 100, height: 2000))
        let image2 = testHelper.createSolidColorImage(color: .yellow, size: CGSize(width: 100, height: 2000))
        
        let result = try await imageStitcher.stitch(images: [image1, image2])
        
        XCTAssertNotNil(result.image)
    }
    
    /// 测试不同宽度图片拼接
    func testDifferentWidths() async throws {
        let image1 = testHelper.createScreenshotMockImage(size: CGSize(width: 400, height: 600))
        let image2 = testHelper.createScreenshotMockImage(size: CGSize(width: 500, height: 600))
        
        let result = try await imageStitcher.stitch(images: [image1, image2])
        
        XCTAssertNotNil(result.image)
    }
    
    /// 测试不同高度图片拼接
    func testDifferentHeights() async throws {
        let image1 = testHelper.createScreenshotMockImage(size: CGSize(width: 400, height: 600))
        let image2 = testHelper.createScreenshotMockImage(size: CGSize(width: 400, height: 800))
        
        let result = try await imageStitcher.stitch(images: [image1, image2])
        
        XCTAssertNotNil(result.image)
    }
}

// MARK: - StitchingResult OverlapInfo 测试

extension ImageStitcherTests {
    
    /// 测试 OverlapInfo 结构
    func testOverlapInfo() {
        let overlapInfo = StitchingResult.OverlapInfo(
            index: 0,
            height: 100,
            confidence: 0.9
        )
        
        XCTAssertEqual(overlapInfo.index, 0)
        XCTAssertEqual(overlapInfo.height, 100)
        XCTAssertEqual(overlapInfo.confidence, 0.9)
    }
}
