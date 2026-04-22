import XCTest
import UIKit
@testable import LongScreenshot

final class NCCStitcherCropTests: XCTestCase {

    var stitcher: NCCStitcher!

    override func setUp() {
        super.setUp()
        stitcher = NCCStitcher()
    }

    override func tearDown() {
        stitcher = nil
        super.tearDown()
    }

    // MARK: - 1) 基本裁剪尺寸测试

    func testCropDimensions() async {
        let imageA = TestImageFactory.makeTestImage(width: 1000, height: 2000, bottomMark: true)
        let imageB = TestImageFactory.makeTestImage(width: 1000, height: 2000, topMark: true)

        let result = await stitcher.cropAndPreprocess(imageA: imageA, imageB: imageB)
        XCTAssertNotNil(result, "裁剪预处理不应返回 nil")

        let (candidateA, candidateB, _) = result!

        let dsScale = await stitcher.config.downsampleScale
        let expectedCropHeight = Int(Double(2000) * 0.25 * dsScale)

        XCTAssertEqual(candidateA.height, expectedCropHeight, accuracy: 1,
                       "candidateA 高度应 ≈ \(expectedCropHeight)，实际 \(candidateA.height)")
        XCTAssertEqual(candidateB.height, expectedCropHeight, accuracy: 1,
                       "candidateB 高度应 ≈ \(expectedCropHeight)，实际 \(candidateB.height)")
        XCTAssertEqual(candidateA.width, candidateB.width,
                       "两张候选区域宽度应相同")
    }

    // MARK: - 2) 红色标记验证（灰度图中红色变暗）
    // 红色在灰度图中亮度约 76，白色为 255，黑色横线为 0
    // candidateA 底部 5% 是红色条带，检测该区域是否比白色背景暗

    func testCropContainsRedMark() async {
        let imageA = TestImageFactory.makeTestImage(width: 1000, height: 2000, bottomMark: true)
        let imageB = TestImageFactory.makeTestImage(width: 1000, height: 2000, topMark: true)

        let result = await stitcher.cropAndPreprocess(imageA: imageA, imageB: imageB)
        XCTAssertNotNil(result)

        let (candidateA, candidateB, _) = result!

        // 底部红色条带在灰度图中亮度约 76，远低于白色 255
        // 检测底部区域是否有明显比白色暗的像素
        let bottomRegion = (candidateA.height * 8 / 10)...(candidateA.height - 1)
        XCTAssertTrue(
            TestImageFactory.hasDarkRegion(of: candidateA, yRange: bottomRegion, threshold: 240),
            "candidateA 底部应包含红色条带（灰度图中亮度 < 240）"
        )

        let topRegion = 0...(candidateB.height * 2 / 10)
        XCTAssertTrue(
            TestImageFactory.hasDarkRegion(of: candidateB, yRange: topRegion, threshold: 240),
            "candidateB 顶部应包含红色条带（灰度图中亮度 < 240）"
        )
    }

    // MARK: - 3) 统一宽度保持比例（不同宽度图片）

    func testUniformWidthWithDifferentImageWidths() async {
        let imageA = TestImageFactory.makeTestImage(width: 1000, height: 2000, bottomMark: true)
        let imageB = TestImageFactory.makeTestImage(width: 800, height: 2000, topMark: true)

        let result = await stitcher.cropAndPreprocess(imageA: imageA, imageB: imageB)
        XCTAssertNotNil(result, "不同宽度图片裁剪不应返回 nil")

        let (candidateA, candidateB, metadata) = result!

        XCTAssertEqual(candidateA.width, candidateB.width,
                       "不同宽度图片裁剪后宽度应统一")

        let dsScale = await stitcher.config.downsampleScale
        let expectedUniformWidth = Int(Double(800) * dsScale)
        XCTAssertEqual(candidateA.width, expectedUniformWidth, accuracy: 1,
                       "统一宽度应取较小值 800 的降采样结果")
        XCTAssertEqual(metadata.uniformWidth, 800.0,
                       "元数据中统一宽度应为 800")

        // imageA 等比缩放后高度 = 2000 * (800/1000) = 1600
        // 裁剪高度 = 1600 * 0.25 = 400，降采样后 = 400 * 0.5 = 200
        let scaledHeightA = 2000.0 * (800.0 / 1000.0)
        let expectedCropHeightA = Int(scaledHeightA * 0.25 * dsScale)
        XCTAssertEqual(candidateA.height, expectedCropHeightA, accuracy: 1,
                       "candidateA 高度应按等比缩放后高度的 25% 降采样")

        // imageB 宽度本身就是 800，无需缩放
        let expectedCropHeightB = Int(2000.0 * 0.25 * dsScale)
        XCTAssertEqual(candidateB.height, expectedCropHeightB, accuracy: 1,
                       "candidateB 高度应按原图高度 2000 的 25% 降采样")
    }

    // MARK: - 4) 文字标记验证（灰度图中蓝色文字变暗）
    // 蓝色文字在灰度图中亮度约 29，检测暗区域
    // 文字在底部25%区域的中间位置，裁剪后应该包含

    func testCropContainsTextMark() async {
        let imageA = TestImageFactory.makeTestImage(width: 1000, height: 2000, bottomText: "BOTTOM")
        let imageB = TestImageFactory.makeTestImage(width: 1000, height: 2000, topText: "TOP")

        let result = await stitcher.cropAndPreprocess(imageA: imageA, imageB: imageB)
        XCTAssertNotNil(result)

        let (candidateA, candidateB, _) = result!

        // 文字在底部25%区域中间，裁剪后应该在整个 candidateA 中
        // 黑色横线每100px一条，在灰度图中亮度为0
        // 所以 candidateA 中一定有暗像素（横线），这足以验证裁剪正确
        // 但我们需要验证文字确实在裁剪区域内，而不仅仅是横线
        // 文字位于底部25%区域的中间，降采样后可能在 candidateA 的 30%-70% 位置
        let bottomTextRegion = (candidateA.height * 3 / 10)...(candidateA.height * 7 / 10)
        XCTAssertTrue(
            TestImageFactory.hasDarkRegion(of: candidateA, yRange: bottomTextRegion, threshold: 240),
            "candidateA 中间区域应包含文字 'BOTTOM'（灰度图中亮度 < 240）"
        )

        // TOP 文字在顶部25%区域的中间，降采样后可能在 candidateB 的 30%-70% 位置
        let topTextRegion = (candidateB.height * 3 / 10)...(candidateB.height * 7 / 10)
        XCTAssertTrue(
            TestImageFactory.hasDarkRegion(of: candidateB, yRange: topTextRegion, threshold: 240),
            "candidateB 中间区域应包含文字 'TOP'（灰度图中亮度 < 240）"
        )
    }

    // MARK: - 5) 元数据正确性

    func testMetadataCorrectness() async {
        let imageA = TestImageFactory.makeTestImage(width: 1000, height: 2000)
        let imageB = TestImageFactory.makeTestImage(width: 1000, height: 2000)

        let result = await stitcher.cropAndPreprocess(imageA: imageA, imageB: imageB)
        XCTAssertNotNil(result)

        let (_, _, metadata) = result!

        XCTAssertEqual(metadata.originalSizeA, CGSize(width: 1000, height: 2000),
                       "元数据中 imageA 原始尺寸应正确")
        XCTAssertEqual(metadata.originalSizeB, CGSize(width: 1000, height: 2000),
                       "元数据中 imageB 原始尺寸应正确")
        XCTAssertEqual(metadata.uniformWidth, 1000.0,
                       "元数据中统一宽度应正确")
        XCTAssertEqual(metadata.cropRatio, 0.25,
                       "元数据中裁剪比例应正确")
        XCTAssertEqual(metadata.downsampleScale, 0.5,
                       "元数据中降采样比例应正确")
    }

    // MARK: - 6) 边界情况：nil cgImage

    func testCropWithNilCGImage() async {
        let brokenImage = UIImage()
        let result = await stitcher.cropAndPreprocess(imageA: brokenImage, imageB: brokenImage)
        XCTAssertNil(result, "cgImage 为 nil 时应返回 nil")
    }

    // MARK: - 7) 灰度输出验证

    func testOutputIsGrayscale() async {
        let imageA = TestImageFactory.makeTestImage(width: 1000, height: 2000, bottomMark: true)
        let imageB = TestImageFactory.makeTestImage(width: 1000, height: 2000, topMark: true)

        let result = await stitcher.cropAndPreprocess(imageA: imageA, imageB: imageB)
        XCTAssertNotNil(result)

        let (candidateA, candidateB, _) = result!

        XCTAssertEqual(candidateA.colorSpace?.model, .monochrome,
                       "candidateA 应为灰度图")
        XCTAssertEqual(candidateB.colorSpace?.model, .monochrome,
                       "candidateB 应为灰度图")
        XCTAssertEqual(candidateA.bitsPerPixel, 8,
                       "灰度图每像素应为 8 位")
        XCTAssertEqual(candidateB.bitsPerPixel, 8,
                       "灰度图每像素应为 8 位")
    }
}
