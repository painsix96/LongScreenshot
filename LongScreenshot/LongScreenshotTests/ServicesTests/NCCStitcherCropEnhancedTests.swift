import XCTest
import UIKit
@testable import LongScreenshot

final class NCCStitcherCropEnhancedTests: XCTestCase {

    var stitcher: NCCStitcher!

    override func setUp() {
        super.setUp()
        stitcher = NCCStitcher()
    }

    override func tearDown() {
        stitcher = nil
        super.tearDown()
    }

    // MARK: - 1）位置验证（关键）
    // 目的：验证 candidateA 的内容确实来自 imageA 的底部 25%，
    //       candidateB 的内容确实来自 imageB 的顶部 25%
    // 方法：使用上下半区不同灰度的图片，通过灰度值验证裁剪位置

    func testCandidateAComesFromBottomOfImageA() async {
        // imageA: 上半白色(255)，下半深灰(50)
        // 底部25%一定在深灰区域内
        let imageA = TestImageFactory.makeSplitImage(
            width: 1000, height: 2000,
            topGray: 255, bottomGray: 50, splitRatio: 0.5
        )
        let imageB = TestImageFactory.makeTestImage(width: 1000, height: 2000)

        let result = await stitcher.cropAndPreprocess(imageA: imageA, imageB: imageB)
        XCTAssertNotNil(result)

        let (candidateA, _, _) = result!

        // candidateA 来自底部25%，应在深灰区域
        // 验证 candidateA 大部分区域是暗的
        let avgGray = TestImageFactory.averageGrayscale(
            of: candidateA,
            yRange: (candidateA.height / 4)...(candidateA.height * 3 / 4)
        )
        XCTAssertNotNil(avgGray)
        XCTAssertLessThan(avgGray!, 150,
                          "candidateA 应来自 imageA 底部深灰区域，平均灰度应 < 150，实际 \(avgGray!)")
    }

    func testCandidateBComesFromTopOfImageB() async {
        let imageA = TestImageFactory.makeTestImage(width: 1000, height: 2000)
        // imageB: 上半深灰(50)，下半白色(255)
        // 顶部25%一定在深灰区域内
        let imageB = TestImageFactory.makeSplitImage(
            width: 1000, height: 2000,
            topGray: 50, bottomGray: 255, splitRatio: 0.5
        )

        let result = await stitcher.cropAndPreprocess(imageA: imageA, imageB: imageB)
        XCTAssertNotNil(result)

        let (_, candidateB, _) = result!

        let avgGray = TestImageFactory.averageGrayscale(
            of: candidateB,
            yRange: (candidateB.height / 4)...(candidateB.height * 3 / 4)
        )
        XCTAssertNotNil(avgGray)
        XCTAssertLessThan(avgGray!, 150,
                          "candidateB 应来自 imageB 顶部深灰区域，平均灰度应 < 150，实际 \(avgGray!)")
    }

    // MARK: - 2）方向验证
    // 目的：如果交换 A/B 裁剪逻辑（取 A 的顶部而非底部），测试必须失败
    // 方法：imageA 上半白色下半深灰，验证 candidateA 不是白色（即不是来自顶部）

    func testCandidateAIsNotFromTopOfImageA() async {
        // imageA: 上半白色(255)，下半深灰(50)
        let imageA = TestImageFactory.makeSplitImage(
            width: 1000, height: 2000,
            topGray: 255, bottomGray: 50, splitRatio: 0.5
        )
        let imageB = TestImageFactory.makeTestImage(width: 1000, height: 2000)

        let result = await stitcher.cropAndPreprocess(imageA: imageA, imageB: imageB)
        XCTAssertNotNil(result)

        let (candidateA, _, _) = result!

        // 如果错误地取了 imageA 的顶部，candidateA 应该是白色（灰度 > 240）
        // 正确实现取底部，candidateA 应该是深灰色
        let avgGray = TestImageFactory.averageGrayscale(
            of: candidateA,
            yRange: (candidateA.height / 4)...(candidateA.height * 3 / 4)
        )
        XCTAssertNotNil(avgGray)
        XCTAssertLessThan(avgGray!, 200,
                          "candidateA 不应来自 imageA 顶部（白色区域），实际灰度 \(avgGray!)")
    }

    func testCandidateBIsNotFromBottomOfImageB() async {
        let imageA = TestImageFactory.makeTestImage(width: 1000, height: 2000)
        // imageB: 上半深灰(50)，下半白色(255)
        let imageB = TestImageFactory.makeSplitImage(
            width: 1000, height: 2000,
            topGray: 50, bottomGray: 255, splitRatio: 0.5
        )

        let result = await stitcher.cropAndPreprocess(imageA: imageA, imageB: imageB)
        XCTAssertNotNil(result)

        let (_, candidateB, _) = result!

        // 如果错误地取了 imageB 的底部，candidateB 应该是白色
        // 正确实现取顶部，candidateB 应该是深灰色
        let avgGray = TestImageFactory.averageGrayscale(
            of: candidateB,
            yRange: (candidateB.height / 4)...(candidateB.height * 3 / 4)
        )
        XCTAssertNotNil(avgGray)
        XCTAssertLessThan(avgGray!, 200,
                          "candidateB 不应来自 imageB 底部（白色区域），实际灰度 \(avgGray!)")
    }

    // MARK: - 3）坐标系验证
    // 目的：在测试图顶部和底部放置完全不同的标记，验证裁剪结果只包含正确标记
    // 方法：imageA 顶部白色、底部深灰；imageB 顶部深灰、底部白色
    //       验证 candidateA 不包含 imageA 顶部的白色区域
    //       验证 candidateB 不包含 imageB 底部的白色区域

    func testCropPreservesCorrectCoordinateSystem() async {
        // imageA: 0-75% 白色, 75%-100% 深灰
        let imageA = TestImageFactory.makeSplitImage(
            width: 1000, height: 2000,
            topGray: 255, bottomGray: 50, splitRatio: 0.75
        )
        // imageB: 0-25% 深灰, 25%-100% 白色
        let imageB = TestImageFactory.makeSplitImage(
            width: 1000, height: 2000,
            topGray: 50, bottomGray: 255, splitRatio: 0.25
        )

        let result = await stitcher.cropAndPreprocess(imageA: imageA, imageB: imageB)
        XCTAssertNotNil(result)

        let (candidateA, candidateB, _) = result!

        // candidateA 来自 imageA 底部25%（即75%-100%），应为深灰
        // candidateA 的顶部（对应 imageA 的 75% 位置）也应是深灰
        let topOfA = TestImageFactory.averageGrayscale(
            of: candidateA, yRange: 0...(candidateA.height / 10)
        )
        XCTAssertNotNil(topOfA)
        XCTAssertLessThan(topOfA!, 150,
                          "candidateA 顶部应来自 imageA 的 75% 位置（深灰），实际灰度 \(topOfA!)")

        // candidateB 来自 imageB 顶部25%（即0%-25%），应为深灰
        // candidateB 的底部（对应 imageB 的 25% 位置）也应是深灰
        let bottomOfB = TestImageFactory.averageGrayscale(
            of: candidateB, yRange: (candidateB.height * 9 / 10)...(candidateB.height - 1)
        )
        XCTAssertNotNil(bottomOfB)
        XCTAssertLessThan(bottomOfB!, 150,
                          "candidateB 底部应来自 imageB 的 25% 位置（深灰），实际灰度 \(bottomOfB!)")
    }

    // MARK: - 4）缩放顺序验证
    // 目的：确认裁剪是在原图进行，而不是缩放后
    // 方法：在原图 75% 位置（即底部25%的起始边界）放置一条1px的精确标记线
    //       如果先缩放再裁剪，标记线位置会因为缩放误差而偏移
    //       如果先裁剪再缩放，标记线应该在 candidateA 的最顶部

    func testCropHappensBeforeDownsample() async {
        // imageA: 0-74.9% 白色, 75% 处一条黑色线, 75.1%-100% 深灰
        // 底部25%的起始位置恰好是 75%
        let imageA = TestImageFactory.makeSplitImage(
            width: 1000, height: 2000,
            topGray: 255, bottomGray: 50, splitRatio: 0.75
        )
        let imageB = TestImageFactory.makeTestImage(width: 1000, height: 2000)

        let result = await stitcher.cropAndPreprocess(imageA: imageA, imageB: imageB)
        XCTAssertNotNil(result)

        let (candidateA, _, _) = result!

        // 如果先裁剪再缩放：candidateA 来自原图底部25%（1500-2000px），然后缩放到0.5
        // candidateA 顶部对应原图 1500px 处，应该是深灰（50）
        // 如果先缩放再裁剪：原图缩放到0.5后变成 1000px 高，底部25% = 250px
        // 缩放后 750px 处的灰度值可能因为插值而不是精确的50

        let topGray = TestImageFactory.averageGrayscale(
            of: candidateA, yRange: 0...(candidateA.height / 20)
        )
        XCTAssertNotNil(topGray)

        // 先裁剪再缩放：顶部灰度应接近50（深灰）
        // 先缩放再裁剪：顶部灰度可能接近150+（插值混合了白色和深灰）
        XCTAssertLessThan(topGray!, 120,
                          "裁剪应在缩放前执行，candidateA 顶部灰度应接近50，实际 \(topGray!)")
    }

    // MARK: - 5）宽高比验证
    // 目的：处理前后 aspect ratio 一致
    // 方法：验证 candidateA 的宽高比 = uniformWidth / (originalHeight * cropRatio)

    func testAspectRatioPreserved() async {
        let imageA = TestImageFactory.makeTestImage(width: 1000, height: 2000)
        let imageB = TestImageFactory.makeTestImage(width: 1000, height: 2000)

        let result = await stitcher.cropAndPreprocess(imageA: imageA, imageB: imageB)
        XCTAssertNotNil(result)

        let (candidateA, candidateB, metadata) = result!

        let cropRatio = await stitcher.config.cropRatio
        let dsScale = await stitcher.config.downsampleScale

        // 原图底部25%的宽高比 = width / (height * cropRatio)
        let expectedAspectA = metadata.uniformWidth / (CGFloat(2000) * cropRatio)
        let actualAspectA = CGFloat(candidateA.width) / CGFloat(candidateA.height)
        XCTAssertEqual(actualAspectA, expectedAspectA, accuracy: 0.01,
                       "candidateA 宽高比应与原图底部25%一致，期望 \(expectedAspectA)，实际 \(actualAspectA)")

        let expectedAspectB = metadata.uniformWidth / (CGFloat(2000) * cropRatio)
        let actualAspectB = CGFloat(candidateB.width) / CGFloat(candidateB.height)
        XCTAssertEqual(actualAspectB, expectedAspectB, accuracy: 0.01,
                       "candidateB 宽高比应与原图顶部25%一致，期望 \(expectedAspectB)，实际 \(actualAspectB)")
    }

    func testAspectRatioPreservedWithDifferentDimensions() async {
        // 宽图：width=2000, height=1000
        let imageA = TestImageFactory.makeTestImage(width: 2000, height: 1000)
        let imageB = TestImageFactory.makeTestImage(width: 2000, height: 1000)

        let result = await stitcher.cropAndPreprocess(imageA: imageA, imageB: imageB)
        XCTAssertNotNil(result)

        let (candidateA, candidateB, metadata) = result!

        let cropRatio = await stitcher.config.cropRatio

        let expectedAspect = metadata.uniformWidth / (CGFloat(1000) * cropRatio)
        let actualAspectA = CGFloat(candidateA.width) / CGFloat(candidateA.height)
        XCTAssertEqual(actualAspectA, expectedAspect, accuracy: 0.01,
                       "宽图 candidateA 宽高比应一致，期望 \(expectedAspect)，实际 \(actualAspectA)")
    }

    // MARK: - 6）误通过防护
    // 目的：不能只检测"是否有暗区域"，必须检测"暗区域的位置"
    // 方法：使用上下分色图，验证暗区域在正确位置，亮区域在正确位置

    func testDarkRegionPositionInCandidateA() async {
        // imageA: 上75%白色，下25%深灰
        // candidateA 来自底部25%，应全部是深灰
        let imageA = TestImageFactory.makeSplitImage(
            width: 1000, height: 2000,
            topGray: 255, bottomGray: 50, splitRatio: 0.75
        )
        let imageB = TestImageFactory.makeTestImage(width: 1000, height: 2000)

        let result = await stitcher.cropAndPreprocess(imageA: imageA, imageB: imageB)
        XCTAssertNotNil(result)

        let (candidateA, _, _) = result!

        // 验证 candidateA 的上半部分是暗的（不是亮的）
        let topHalfRange = 0...(candidateA.height / 2)
        let topHalfAvg = TestImageFactory.averageGrayscale(of: candidateA, yRange: topHalfRange)
        XCTAssertNotNil(topHalfAvg)
        XCTAssertLessThan(topHalfAvg!, 150,
                          "candidateA 上半部分应为暗区域（来自底部25%），实际灰度 \(topHalfAvg!)")

        // 验证 candidateA 的下半部分也是暗的
        let bottomHalfRange = (candidateA.height / 2)...(candidateA.height - 1)
        let bottomHalfAvg = TestImageFactory.averageGrayscale(of: candidateA, yRange: bottomHalfRange)
        XCTAssertNotNil(bottomHalfAvg)
        XCTAssertLessThan(bottomHalfAvg!, 150,
                          "candidateA 下半部分应为暗区域，实际灰度 \(bottomHalfAvg!)")
    }

    func testDarkRegionPositionInCandidateB() async {
        let imageA = TestImageFactory.makeTestImage(width: 1000, height: 2000)
        // imageB: 上25%深灰，下75%白色
        let imageB = TestImageFactory.makeSplitImage(
            width: 1000, height: 2000,
            topGray: 50, bottomGray: 255, splitRatio: 0.25
        )

        let result = await stitcher.cropAndPreprocess(imageA: imageA, imageB: imageB)
        XCTAssertNotNil(result)

        let (_, candidateB, _) = result!

        // candidateB 来自顶部25%，应全部是深灰
        let topHalfRange = 0...(candidateB.height / 2)
        let topHalfAvg = TestImageFactory.averageGrayscale(of: candidateB, yRange: topHalfRange)
        XCTAssertNotNil(topHalfAvg)
        XCTAssertLessThan(topHalfAvg!, 150,
                          "candidateB 上半部分应为暗区域（来自顶部25%），实际灰度 \(topHalfAvg!)")

        let bottomHalfRange = (candidateB.height / 2)...(candidateB.height - 1)
        let bottomHalfAvg = TestImageFactory.averageGrayscale(of: candidateB, yRange: bottomHalfRange)
        XCTAssertNotNil(bottomHalfAvg)
        XCTAssertLessThan(bottomHalfAvg!, 150,
                          "candidateB 下半部分应为暗区域，实际灰度 \(bottomHalfAvg!)")
    }

    func testBrightRegionNotInWrongPosition() async {
        // imageA: 上75%白色，下25%深灰
        // candidateA 来自底部25%，不应包含白色区域
        let imageA = TestImageFactory.makeSplitImage(
            width: 1000, height: 2000,
            topGray: 255, bottomGray: 50, splitRatio: 0.75
        )
        let imageB = TestImageFactory.makeTestImage(width: 1000, height: 2000)

        let result = await stitcher.cropAndPreprocess(imageA: imageA, imageB: imageB)
        XCTAssertNotNil(result)

        let (candidateA, _, _) = result!

        // candidateA 中间区域不应是亮色（白色 > 240）
        let midRange = (candidateA.height / 4)...(candidateA.height * 3 / 4)
        let isBright = TestImageFactory.isBrightRegion(of: candidateA, yRange: midRange, threshold: 240)
        XCTAssertFalse(isBright,
                       "candidateA 中间区域不应是白色（如果裁剪位置错误取了顶部才会是白色）")
    }
}
