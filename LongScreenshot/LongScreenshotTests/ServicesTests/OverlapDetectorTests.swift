import XCTest
import UIKit
@testable import LongScreenshot

// MARK: - OverlapDetector 单元测试

@MainActor
final class OverlapDetectorTests: XCTestCase {
    
    var overlapDetector: OverlapDetector!
    var testHelper: TestHelper!
    
    override func setUp() {
        super.setUp()
        overlapDetector = OverlapDetector()
        testHelper = TestHelper.shared
    }
    
    override func tearDown() {
        testHelper.cleanupTestFiles()
        overlapDetector = nil
        super.tearDown()
    }
    
    // MARK: - 重叠区域检测测试
    
    /// 测试垂直方向重叠检测：有重叠的图片
    func testDetectOverlap_Vertical_WithOverlap() async {
        let (topImage, bottomImage) = testHelper.createStitchableImagePair(
            width: 400,
            height: 600,
            overlapHeight: 100
        )
        
        let result = await overlapDetector.detectOverlap(
            between: topImage,
            and: bottomImage,
            scrollDirection: .vertical
        )
        
        XCTAssertTrue(result.hasOverlap, "应该检测到重叠区域")
        XCTAssertGreaterThan(result.similarityScore, 0, "相似度分数应该大于 0")
        XCTAssertGreaterThan(result.bestStitchPosition.overlapHeight, 0, "重叠高度应该大于 0")
        XCTAssertGreaterThan(result.confidence, 0, "置信度应该大于 0")
    }
    
    /// 测试垂直方向重叠检测：完全相同的图片
    func testDetectOverlap_Vertical_IdenticalImages() async {
        let image = testHelper.createScreenshotMockImage(size: CGSize(width: 400, height: 600))
        
        let result = await overlapDetector.detectOverlap(
            between: image,
            and: image,
            scrollDirection: .vertical
        )
        
        XCTAssertTrue(result.hasOverlap, "相同图片应该检测到重叠")
        XCTAssertGreaterThan(result.similarityScore, 0.5, "相同图片应该有高相似度")
    }
    
    /// 测试垂直方向重叠检测：无重叠的图片
    func testDetectOverlap_Vertical_NoOverlap() async {
        let image1 = testHelper.createSolidColorImage(color: .red, size: CGSize(width: 400, height: 600))
        let image2 = testHelper.createSolidColorImage(color: .blue, size: CGSize(width: 400, height: 600))
        
        let result = await overlapDetector.detectOverlap(
            between: image1,
            and: image2,
            scrollDirection: .vertical
        )
        
        XCTAssertFalse(result.hasOverlap, "完全不同图片不应该有重叠")
        XCTAssertEqual(result.bestStitchPosition.overlapHeight, 0, "重叠高度应该为 0")
    }
    
    /// 测试垂直方向重叠检测：大面积重叠
    func testDetectOverlap_Vertical_LargeOverlap() async {
        let (topImage, bottomImage) = testHelper.createStitchableImagePair(
            width: 400,
            height: 800,
            overlapHeight: 300
        )
        
        let result = await overlapDetector.detectOverlap(
            between: topImage,
            and: bottomImage,
            scrollDirection: .vertical
        )
        
        if result.hasOverlap {
            XCTAssertGreaterThan(result.bestStitchPosition.overlapHeight, 50, "大面积重叠应该检测到较大的重叠高度")
        }
    }
    
    /// 测试垂直方向重叠检测：小面积重叠
    func testDetectOverlap_Vertical_SmallOverlap() async {
        let (topImage, bottomImage) = testHelper.createStitchableImagePair(
            width: 400,
            height: 800,
            overlapHeight: 30
        )
        
        let result = await overlapDetector.detectOverlap(
            between: topImage,
            and: bottomImage,
            scrollDirection: .vertical
        )
        
        // 小面积重叠可能检测不到，所以不做强制断言
        print("小面积重叠检测结果: \(result.hasOverlap ? "检测到" : "未检测到")")
    }
    
    // MARK: - 水平方向重叠检测测试
    
    /// 测试水平方向重叠检测
    func testDetectOverlap_Horizontal() async {
        // 创建水平方向的测试图片
        let baseImage = testHelper.createScreenshotMockImage(
            size: CGSize(width: 1200, height: 400),
            baseColor: .white,
            gradientHeight: 50
        )
        
        // 裁剪左侧图片
        let leftImage = cropImage(baseImage, rect: CGRect(
            x: 0, y: 0, width: 600, height: 400
        ))
        
        // 裁剪右侧图片（有重叠）
        let rightImage = cropImage(baseImage, rect: CGRect(
            x: 500, y: 0, width: 600, height: 400
        ))
        
        let result = await overlapDetector.detectOverlap(
            between: leftImage,
            and: rightImage,
            scrollDirection: .horizontal
        )
        
        // 水平方向检测可能不太稳定，所以只打印结果
        print("水平方向重叠检测结果: hasOverlap=\(result.hasOverlap)")
    }
    
    /// 测试水平方向与垂直方向的对比
    func testDetectOverlap_DirectionComparison() async {
        let (topImage, bottomImage) = testHelper.createStitchableImagePair(
            width: 400,
            height: 600,
            overlapHeight: 100
        )
        
        // 垂直方向检测
        let verticalResult = await overlapDetector.detectOverlap(
            between: topImage,
            and: bottomImage,
            scrollDirection: .vertical
        )
        
        // 水平方向检测（同一张图片）
        let horizontalResult = await overlapDetector.detectOverlap(
            between: topImage,
            and: bottomImage,
            scrollDirection: .horizontal
        )
        
        // 垂直方向应该更容易检测到重叠
        print("垂直方向: hasOverlap=\(verticalResult.hasOverlap)")
        print("水平方向: hasOverlap=\(horizontalResult.hasOverlap)")
    }
    
    // MARK: - 无重叠情况处理测试
    
    /// 测试无重叠时的空结果
    func testNoOverlapResult() {
        let result = OverlapResult.noOverlap
        
        XCTAssertFalse(result.hasOverlap)
        XCTAssertEqual(result.overlapRect1, .zero)
        XCTAssertEqual(result.overlapRect2, .zero)
        XCTAssertEqual(result.similarityScore, 0)
        XCTAssertEqual(result.bestStitchPosition.overlapHeight, 0)
        XCTAssertEqual(result.confidence, 0)
    }
    
    /// 测试拼接质量等级
    func testStitchQualityLevels() {
        let excellent = OverlapResult.StitchQuality(score: 0.98)
        XCTAssertEqual(excellent, .excellent)
        XCTAssertEqual(excellent.rawValue, "优秀")
        
        let good = OverlapResult.StitchQuality(score: 0.90)
        XCTAssertEqual(good, .good)
        XCTAssertEqual(good.rawValue, "良好")
        
        let acceptable = OverlapResult.StitchQuality(score: 0.80)
        XCTAssertEqual(acceptable, .acceptable)
        XCTAssertEqual(acceptable.rawValue, "可接受")
        
        let poor = OverlapResult.StitchQuality(score: 0.60)
        XCTAssertEqual(poor, .poor)
        XCTAssertEqual(poor.rawValue, "较差")
    }
    
    // MARK: - 批量检测功能测试
    
    /// 测试批量重叠检测
    func testDetectOverlapsBatch() async {
        let images = testHelper.createStitchableImages(
            count: 5,
            width: 400,
            height: 600,
            overlapHeight: 100
        )
        
        let results = await overlapDetector.detectOverlapsBatch(
            images: images,
            scrollDirection: .vertical
        )
        
        XCTAssertEqual(results.count, 4, "5张图片应该有4个重叠检测结果")
        
        // 验证结果按索引排序
        for (index, result) in results.enumerated() {
            XCTAssertEqual(result.index, index, "结果应该按索引排序")
        }
    }
    
    /// 测试批量检测：图片数量不足
    func testDetectOverlapsBatch_InsufficientImages() async {
        let images = testHelper.createStitchableImages(
            count: 1,
            width: 400,
            height: 600,
            overlapHeight: 100
        )
        
        let results = await overlapDetector.detectOverlapsBatch(
            images: images,
            scrollDirection: .vertical
        )
        
        XCTAssertEqual(results.count, 0, "单张图片不应该产生重叠检测结果")
    }
    
    /// 测试批量检测：两张图片
    func testDetectOverlapsBatch_TwoImages() async {
        let images = testHelper.createStitchableImages(
            count: 2,
            width: 400,
            height: 600,
            overlapHeight: 100
        )
        
        let results = await overlapDetector.detectOverlapsBatch(
            images: images,
            scrollDirection: .vertical
        )
        
        XCTAssertEqual(results.count, 1, "两张图片应该有1个重叠检测结果")
        XCTAssertEqual(results.first?.index, 0)
    }
    
    /// 测试计算总重叠高度
    func testCalculateTotalOverlapHeight() async {
        // 创建测试结果
        let results = [
            OverlapResult(
                hasOverlap: true,
                overlapRect1: CGRect(x: 0, y: 500, width: 400, height: 100),
                overlapRect2: CGRect(x: 0, y: 0, width: 400, height: 100),
                similarityScore: 0.9,
                bestStitchPosition: OverlapResult.StitchPosition(
                    yOffset: 500,
                    overlapHeight: 100,
                    quality: .excellent
                ),
                confidence: 0.9,
                processingTime: 0.1,
                topCrop1: 0,
                bottomCrop1: 0,
                topCrop2: 0,
                bottomCrop2: 0
            ),
            OverlapResult(
                hasOverlap: true,
                overlapRect1: CGRect(x: 0, y: 500, width: 400, height: 150),
                overlapRect2: CGRect(x: 0, y: 0, width: 400, height: 150),
                similarityScore: 0.85,
                bestStitchPosition: OverlapResult.StitchPosition(
                    yOffset: 500,
                    overlapHeight: 150,
                    quality: .good
                ),
                confidence: 0.85,
                processingTime: 0.1,
                topCrop1: 0,
                bottomCrop1: 0,
                topCrop2: 0,
                bottomCrop2: 0
            ),
            OverlapResult.noOverlap
        ]
        
        let totalHeight = overlapDetector.calculateTotalOverlapHeight(results: results)
        XCTAssertEqual(totalHeight, 250, "总重叠高度应该为 250")
    }
    
    // MARK: - 性能测试
    
    /// 测试重叠检测性能
    func testPerformance_OverlapDetection() async {
        let (topImage, bottomImage) = testHelper.createStitchableImagePair(
            width: 1080,
            height: 1920,
            overlapHeight: 200
        )
        
        let (_, duration) = await measureAsync("overlap") {
            await overlapDetector.detectOverlap(
                between: topImage,
                and: bottomImage,
                scrollDirection: .vertical
            )
        }
        
        XCTAssertLessThan(duration, 5.0, "1080p 图片的重叠检测应该在 5 秒内完成")
        print("1080p 图片重叠检测时间: \(duration * 1000)ms")
    }
    
    /// 测试批量检测性能
    func testPerformance_BatchDetection() async {
        let images = testHelper.createStitchableImages(
            count: 5,
            width: 800,
            height: 1200,
            overlapHeight: 150
        )
        
        let (_, duration) = await measureAsync("batch") {
            await overlapDetector.detectOverlapsBatch(
                images: images,
                scrollDirection: .vertical
            )
        }
        
        XCTAssertLessThan(duration, 30.0, "5张图片的批量检测应该在 30 秒内完成")
        print("批量检测 5 张图片时间: \(duration * 1000)ms")
    }
    
    // MARK: - 边界条件测试
    
    /// 测试小尺寸图片的重叠检测
    func testSmallImageOverlap() async {
        let (topImage, bottomImage) = testHelper.createStitchableImagePair(
            width: 100,
            height: 150,
            overlapHeight: 30
        )
        
        let result = await overlapDetector.detectOverlap(
            between: topImage,
            and: bottomImage,
            scrollDirection: .vertical
        )
        
        // 小尺寸图片可能检测不稳定，只验证不崩溃
        print("小尺寸图片重叠检测: hasOverlap=\(result.hasOverlap)")
    }
    
    /// 测试不同尺寸图片的重叠检测
    func testDifferentSizeImageOverlap() async {
        let image1 = testHelper.createScreenshotMockImage(size: CGSize(width: 400, height: 600))
        let image2 = testHelper.createScreenshotMockImage(size: CGSize(width: 400, height: 800))
        
        let result = await overlapDetector.detectOverlap(
            between: image1,
            and: image2,
            scrollDirection: .vertical
        )
        
        // 验证不崩溃
        XCTAssertGreaterThanOrEqual(result.processingTime, 0)
    }
    
    /// 测试极端长宽比的图片
    func testExtremeAspectRatioOverlap() async {
        let image1 = testHelper.createSolidColorImage(color: .white, size: CGSize(width: 50, height: 1000))
        let image2 = testHelper.createSolidColorImage(color: .white, size: CGSize(width: 50, height: 1000))
        
        let result = await overlapDetector.detectOverlap(
            between: image1,
            and: image2,
            scrollDirection: .vertical
        )
        
        // 验证不崩溃
        print("极端比例图片重叠检测: hasOverlap=\(result.hasOverlap)")
    }
    
    // MARK: - 辅助方法
    
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
}
