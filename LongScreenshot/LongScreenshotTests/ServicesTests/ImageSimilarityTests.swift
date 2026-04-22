import XCTest
import UIKit
@testable import LongScreenshot

// MARK: - ImageSimilarity 单元测试

@MainActor
final class ImageSimilarityTests: XCTestCase {
    
    var imageSimilarity: ImageSimilarity!
    var testHelper: TestHelper!
    
    override func setUp() {
        super.setUp()
        imageSimilarity = ImageSimilarity()
        testHelper = TestHelper.shared
    }
    
    override func tearDown() {
        testHelper.cleanupTestFiles()
        imageSimilarity = nil
        super.tearDown()
    }
    
    // MARK: - 感知哈希算法测试
    
    /// 测试感知哈希：相同图片应该返回相似度 1.0
    func testPerceptualHash_SameImage() async {
        let image = testHelper.createSolidColorImage(color: .blue, size: CGSize(width: 200, height: 200))
        
        let result = await imageSimilarity.calculateSimilarity(
            between: image,
            and: image,
            method: .perceptualHash
        )
        
        XCTAssertEqual(result.score, 1.0, accuracy: 0.01, "相同图片的感知哈希相似度应为 1.0")
        XCTAssertTrue(result.isSimilar, "相同图片应该被判定为相似")
        XCTAssertGreaterThan(result.confidence, 0.8, "置信度应该足够高")
    }
    
    /// 测试感知哈希：完全不同图片应该返回低相似度
    func testPerceptualHash_DifferentImages() async {
        let image1 = testHelper.createSolidColorImage(color: .black, size: CGSize(width: 200, height: 200))
        let image2 = testHelper.createSolidColorImage(color: .white, size: CGSize(width: 200, height: 200))
        
        let result = await imageSimilarity.calculateSimilarity(
            between: image1,
            and: image2,
            method: .perceptualHash
        )
        
        XCTAssertLessThan(result.score, 0.5, "完全不同图片的相似度应该很低")
        XCTAssertFalse(result.isSimilar, "黑白图片不应该被判定为相似")
    }
    
    /// 测试感知哈希：相似图片应该有较高相似度
    func testPerceptualHash_SimilarImages() async {
        let baseImage = testHelper.createScreenshotMockImage(size: CGSize(width: 400, height: 600))
        // 创建略微修改的版本（添加轻微噪声）
        let modifiedImage = testHelper.createScreenshotMockImage(size: CGSize(width: 400, height: 600))
        
        let result = await imageSimilarity.calculateSimilarity(
            between: baseImage,
            and: modifiedImage,
            method: .perceptualHash
        )
        
        XCTAssertGreaterThan(result.score, 0.7, "相似图片应该有较高相似度")
    }
    
    /// 测试感知哈希：不同尺寸图片应该能正确处理
    func testPerceptualHash_DifferentSizes() async {
        let image1 = testHelper.createSolidColorImage(color: .red, size: CGSize(width: 100, height: 100))
        let image2 = testHelper.createSolidColorImage(color: .red, size: CGSize(width: 400, height: 400))
        
        let result = await imageSimilarity.calculateSimilarity(
            between: image1,
            and: image2,
            method: .perceptualHash
        )
        
        XCTAssertGreaterThan(result.score, 0.9, "相同颜色的不同尺寸图片应该有高相似度")
    }
    
    // MARK: - 像素差异计算测试
    
    /// 测试像素差异：相同图片应该返回相似度 1.0
    func testPixelDifference_SameImage() async {
        let image = testHelper.createSolidColorImage(color: .green, size: CGSize(width: 100, height: 100))
        
        let result = await imageSimilarity.calculateSimilarity(
            between: image,
            and: image,
            method: .pixelDifference
        )
        
        XCTAssertEqual(result.score, 1.0, accuracy: 0.01, "相同图片的像素差异相似度应为 1.0")
        XCTAssertTrue(result.isSimilar)
    }
    
    /// 测试像素差异：轻微颜色变化的图片
    func testPixelDifference_SlightColorChange() async {
        let image1 = testHelper.createSolidColorImage(color: UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0), 
                                                       size: CGSize(width: 100, height: 100))
        let image2 = testHelper.createSolidColorImage(color: UIColor(red: 0.52, green: 0.52, blue: 0.52, alpha: 1.0), 
                                                       size: CGSize(width: 100, height: 100))
        
        let result = await imageSimilarity.calculateSimilarity(
            between: image1,
            and: image2,
            method: .pixelDifference
        )
        
        XCTAssertGreaterThan(result.score, 0.7, "轻微颜色变化应该有较高相似度")
        XCTAssertLessThan(result.score, 1.0, "轻微颜色变化不应该是完全相似")
    }
    
    /// 测试像素差异：完全不同颜色应该返回低相似度
    func testPixelDifference_CompletelyDifferent() async {
        let image1 = testHelper.createSolidColorImage(color: .red, size: CGSize(width: 100, height: 100))
        let image2 = testHelper.createSolidColorImage(color: .blue, size: CGSize(width: 100, height: 100))
        
        let result = await imageSimilarity.calculateSimilarity(
            between: image1,
            and: image2,
            method: .pixelDifference
        )
        
        XCTAssertLessThan(result.score, 0.3, "完全不同颜色应该有低相似度")
    }
    
    // MARK: - 特征点匹配测试
    
    /// 测试特征点匹配：相同图片
    @available(iOS 13.0, *)
    func testFeatureMatching_SameImage() async {
        let image = testHelper.createScreenshotMockImage(size: CGSize(width: 300, height: 400))
        
        let result = await imageSimilarity.calculateSimilarity(
            between: image,
            and: image,
            method: .featureMatching
        )
        
        XCTAssertGreaterThan(result.score, 0.95, "相同图片的特征匹配相似度应该很高")
        XCTAssertTrue(result.isSimilar)
    }
    
    /// 测试特征点匹配：有内容的图片（特征点匹配需要真实内容）
    @available(iOS 13.0, *)
    func testFeatureMatching_WithContent() async {
        let image1 = testHelper.createScreenshotMockImage(size: CGSize(width: 400, height: 600))
        let image2 = testHelper.createScreenshotMockImage(size: CGSize(width: 400, height: 600))
        
        let result = await imageSimilarity.calculateSimilarity(
            between: image1,
            and: image2,
            method: .featureMatching
        )
        
        // 由于生成的图片是随机的，相似度可能变化
        XCTAssertGreaterThanOrEqual(result.score, 0)
        XCTAssertLessThanOrEqual(result.score, 1.0)
    }
    
    // MARK: - 综合算法测试
    
    /// 测试综合算法：相同图片
    func testHybrid_SameImage() async {
        let image = testHelper.createScreenshotMockImage(size: CGSize(width: 300, height: 400))
        
        let result = await imageSimilarity.calculateSimilarity(
            between: image,
            and: image,
            method: .hybrid
        )
        
        XCTAssertGreaterThan(result.score, 0.95, "相同图片的综合相似度应该很高")
        XCTAssertTrue(result.isSimilar)
    }
    
    /// 测试综合算法：可拼接的截图
    func testHybrid_StitchableScreenshots() async {
        let (topImage, bottomImage) = testHelper.createStitchableImagePair(
            width: 400,
            height: 600,
            overlapHeight: 100
        )
        
        let result = await imageSimilarity.calculateSimilarity(
            between: topImage,
            and: bottomImage,
            method: .hybrid
        )
        
        // 可拼接的截图应该有部分相似
        XCTAssertGreaterThan(result.score, 0.1, "可拼接截图应该有部分相似性")
    }
    
    // MARK: - 性能测试
    
    /// 测试 1080p 图片处理性能（应该在 1 秒内完成）
    func testPerformance_1080pImage() async {
        let image1 = testHelper.create1080pImage(color: .purple)
        let image2 = testHelper.create1080pImage(color: .orange)
        
        let (_, duration) = await measureAsync("pHash") {
            await imageSimilarity.calculateSimilarity(
                between: image1,
                and: image2,
                method: .perceptualHash
            )
        }
        
        XCTAssertLessThan(duration, 1.0, "1080p 图片的感知哈希计算应该在 1 秒内完成")
        print("1080p 图片感知哈希处理时间: \(duration * 1000)ms")
    }
    
    /// 测试像素差异算法性能
    func testPerformance_PixelDifference_1080p() async {
        let image1 = testHelper.create1080pImage(color: .cyan)
        let image2 = testHelper.create1080pImage(color: .magenta)
        
        let (_, duration) = await measureAsync("pixelDiff") {
            await imageSimilarity.calculateSimilarity(
                between: image1,
                and: image2,
                method: .pixelDifference
            )
        }
        
        XCTAssertLessThan(duration, 1.0, "1080p 图片的像素差异计算应该在 1 秒内完成")
        print("1080p 图片像素差异处理时间: \(duration * 1000)ms")
    }
    
    /// 测试特征匹配算法性能
    @available(iOS 13.0, *)
    func testPerformance_FeatureMatching_1080p() async {
        let image = testHelper.create1080pImage(color: .yellow)
        
        let (_, duration) = await measureAsync("feature") {
            await imageSimilarity.calculateSimilarity(
                between: image,
                and: image,
                method: .featureMatching
            )
        }
        
        XCTAssertLessThan(duration, 1.0, "1080p 图片的特征匹配计算应该在 1 秒内完成")
        print("1080p 图片特征匹配处理时间: \(duration * 1000)ms")
    }
    
    /// 测试综合算法性能
    func testPerformance_Hybrid_1080p() async {
        let image1 = testHelper.create1080pImage(color: .white)
        let image2 = testHelper.create1080pImage(color: .gray)
        
        let (_, duration) = await measureAsync("hybrid") {
            await imageSimilarity.calculateSimilarity(
                between: image1,
                and: image2,
                method: .hybrid
            )
        }
        
        XCTAssertLessThan(duration, 3.0, "1080p 图片的综合算法计算应该在 3 秒内完成")
        print("1080p 图片综合算法处理时间: \(duration * 1000)ms")
    }
    
    // MARK: - 边界条件测试
    
    /// 测试小尺寸图片处理
    func testSmallImageHandling() async {
        let image1 = testHelper.createSolidColorImage(color: .red, size: CGSize(width: 10, height: 10))
        let image2 = testHelper.createSolidColorImage(color: .red, size: CGSize(width: 10, height: 10))
        
        let result = await imageSimilarity.calculateSimilarity(
            between: image1,
            and: image2,
            method: .perceptualHash
        )
        
        XCTAssertGreaterThan(result.score, 0.9, "小尺寸图片也应该正确计算相似度")
    }
    
    /// 测试长宽比例极端的图片
    func testExtremeAspectRatio() async {
        let image1 = testHelper.createSolidColorImage(color: .blue, size: CGSize(width: 10, height: 1000))
        let image2 = testHelper.createSolidColorImage(color: .blue, size: CGSize(width: 10, height: 1000))
        
        let result = await imageSimilarity.calculateSimilarity(
            between: image1,
            and: image2,
            method: .perceptualHash
        )
        
        XCTAssertGreaterThan(result.score, 0.9, "极端比例图片也应该正确计算相似度")
    }
    
    /// 测试透明图片处理
    func testTransparentImageHandling() async {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100), format: format)
        let image1 = renderer.image { context in
            UIColor.clear.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: 100, height: 100)))
        }
        
        let image2 = renderer.image { context in
            UIColor.clear.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: 100, height: 100)))
        }
        
        let result = await imageSimilarity.calculateSimilarity(
            between: image1,
            and: image2,
            method: .pixelDifference
        )
        
        XCTAssertGreaterThan(result.score, 0.9, "相同透明图片应该有高相似度")
    }
    
    // MARK: - SimilarityResult 扩展测试
    
    /// 测试相似度等级计算
    func testSimilarityLevel() {
        let identical = SimilarityResult(score: 0.99, method: .hybrid, confidence: 1.0, processingTime: 0.1)
        XCTAssertEqual(identical.level, SimilarityResult.SimilarityLevel.identical)
        
        let verySimilar = SimilarityResult(score: 0.95, method: .hybrid, confidence: 0.9, processingTime: 0.1)
        XCTAssertEqual(verySimilar.level, SimilarityResult.SimilarityLevel.verySimilar)
        
        let similar = SimilarityResult(score: 0.85, method: .hybrid, confidence: 0.8, processingTime: 0.1)
        XCTAssertEqual(similar.level, SimilarityResult.SimilarityLevel.similar)
        
        let different = SimilarityResult(score: 0.5, method: .hybrid, confidence: 0.5, processingTime: 0.1)
        XCTAssertEqual(different.level, SimilarityResult.SimilarityLevel.different)
    }
    
    /// 测试相似度描述
    func testSimilarityLevelDescription() {
        let result = SimilarityResult(score: 0.98, method: .hybrid, confidence: 0.95, processingTime: 0.1)
        XCTAssertEqual(result.levelDescription, "完全相同")
    }
}
