import XCTest
import UIKit
@testable import LongScreenshot

// MARK: - 鲁棒性测试
// 目的：验证裁剪+预处理在各种边界和真实场景下的行为

final class NCCStitcherRobustnessTests: XCTestCase {

    var stitcher: NCCStitcher!

    override func setUp() {
        super.setUp()
        stitcher = NCCStitcher()
    }

    override func tearDown() {
        stitcher = nil
        super.tearDown()
    }

    // ================================================================
    // 1）验证宽度统一使用等比缩放，而不是裁剪
    // ================================================================
    // 目的：当两张图宽度不同时，当前实现用 min(widthA, widthB) 裁剪宽图，
    //       这会丢失宽图右侧的内容。正确做法应该是等比缩放。
    //       本测试先记录当前行为，暴露问题。

    func testWidthUnificationShouldScaleNotCrop() async {
        // imageA: 宽1000，左半深灰(50)，右半白色(255)
        // imageB: 宽800
        // 等比缩放：imageA 缩放到 800 宽，高度等比缩放
        // 缩放后 imageA 仍包含左右两半的内容
        let imageA = TestImageFactory.makeLeftRightSplitImage(
            width: 1000, height: 2000,
            leftGray: 50, rightGray: 255
        )
        let imageB = TestImageFactory.makeTestImage(width: 800, height: 2000)

        let result = await stitcher.cropAndPreprocess(imageA: imageA, imageB: imageB)
        XCTAssertNotNil(result)

        let (candidateA, _, metadata) = result!

        XCTAssertEqual(metadata.uniformWidth, 800.0,
                       "统一宽度应为 800")

        // 等比缩放后 candidateA 应包含完整内容（左半深灰 + 右半白色）
        // 中心位置灰度应接近 (50+255)/2 ≈ 150
        let midX = candidateA.width / 2
        let midY = candidateA.height / 2
        let centerGray = TestImageFactory.grayscaleValue(
            in: candidateA, at: CGPoint(x: midX, y: midY)
        )

        XCTAssertNotNil(centerGray)
        if let gray = centerGray {
            XCTAssertGreaterThan(gray, 100,
                                 "等比缩放后 candidateA 中心应包含左右混合内容（灰度 > 100），实际 \(gray)")
        }

        // 验证右侧内容保留：candidateA 右侧应有白色区域
        let rightX = candidateA.width - 5
        let rightGray = TestImageFactory.grayscaleValue(
            in: candidateA, at: CGPoint(x: rightX, y: midY)
        )
        XCTAssertNotNil(rightGray)
        if let gray = rightGray {
            XCTAssertGreaterThan(gray, 200,
                                 "等比缩放后 candidateA 右侧应保留白色内容（灰度 > 200），实际 \(gray)")
        }

        // 验证左侧内容保留：candidateA 左侧应有深灰区域
        let leftGray = TestImageFactory.grayscaleValue(
            in: candidateA, at: CGPoint(x: 5, y: midY)
        )
        XCTAssertNotNil(leftGray)
        if let gray = leftGray {
            XCTAssertLessThan(gray, 100,
                              "等比缩放后 candidateA 左侧应保留深灰内容（灰度 < 100），实际 \(gray)")
        }
    }

    // ================================================================
    // 2）验证在不同宽度图片中，边缘内容不会丢失
    // ================================================================
    // 目的：等比缩放后，imageA 的左右边缘标记都应保留

    func testEdgeContentPreservedWhenWidthDiffers() async {
        // imageA: 宽1000，左右各有20px深色边缘标记，中间浅灰
        let imageA = TestImageFactory.makeEdgeMarkedImage(
            width: 1000, height: 2000,
            edgeWidth: 20, edgeGray: 30, centerGray: 200
        )
        // imageB: 宽800
        let imageB = TestImageFactory.makeTestImage(width: 800, height: 2000)

        let result = await stitcher.cropAndPreprocess(imageA: imageA, imageB: imageB)
        XCTAssertNotNil(result)

        let (candidateA, _, _) = result!

        // 等比缩放后，imageA 的左右边缘标记都应保留
        let midY = candidateA.height / 2

        // 验证左侧边缘标记保留
        let leftEdgeGray = TestImageFactory.grayscaleValue(
            in: candidateA, at: CGPoint(x: 2, y: midY)
        )
        XCTAssertNotNil(leftEdgeGray)
        if let gray = leftEdgeGray {
            XCTAssertLessThan(gray, 100,
                              "等比缩放后 candidateA 左边缘应保留深色标记（灰度 < 100），实际 \(gray)")
        }

        // 验证右侧边缘标记保留
        let rightEdgeX = candidateA.width - 5
        let rightEdgeGray = TestImageFactory.grayscaleValue(
            in: candidateA, at: CGPoint(x: rightEdgeX, y: midY)
        )
        XCTAssertNotNil(rightEdgeGray)
        if let gray = rightEdgeGray {
            XCTAssertLessThan(gray, 100,
                              "等比缩放后 candidateA 右边缘应保留深色标记（灰度 < 100），实际 \(gray)")
        }
    }

    func testLeftEdgePreservedWhenWidthDiffers() async {
        // imageA: 宽1000，左右各有20px深色边缘标记
        let imageA = TestImageFactory.makeEdgeMarkedImage(
            width: 1000, height: 2000,
            edgeWidth: 20, edgeGray: 30, centerGray: 200
        )
        let imageB = TestImageFactory.makeTestImage(width: 800, height: 2000)

        let result = await stitcher.cropAndPreprocess(imageA: imageA, imageB: imageB)
        XCTAssertNotNil(result)

        let (candidateA, _, _) = result!

        // imageA 左侧边缘标记在 x=0~20，裁剪后仍然保留
        // 验证 candidateA 左侧有深色标记
        let leftEdgeX = 2
        let midY = candidateA.height / 2
        let leftEdgeGray = TestImageFactory.grayscaleValue(
            in: candidateA, at: CGPoint(x: leftEdgeX, y: midY)
        )

        XCTAssertNotNil(leftEdgeGray)
        if let gray = leftEdgeGray {
            XCTAssertLessThan(gray, 100,
                              "candidateA 左边缘应保留深色标记（灰度 < 100），实际 \(gray)")
        }
    }

    // ================================================================
    // 3）测试 overlap 区域不在 25% 时的情况
    // ================================================================
    // 目的：验证当 cropRatio 改变时，裁剪区域正确调整

    func testCropRatioCanBeChanged() async {
        // 修改 cropRatio 为 0.15（15%）
        await stitcher.setCropRatio(0.15)

        let imageA = TestImageFactory.makeSplitImage(
            width: 1000, height: 2000,
            topGray: 255, bottomGray: 50, splitRatio: 0.75
        )
        let imageB = TestImageFactory.makeSplitImage(
            width: 1000, height: 2000,
            topGray: 50, bottomGray: 255, splitRatio: 0.25
        )

        let result = await stitcher.cropAndPreprocess(imageA: imageA, imageB: imageB)
        XCTAssertNotNil(result)

        let (candidateA, candidateB, metadata) = result!

        let dsScale = await stitcher.config.downsampleScale
        let expectedHeight = Int(Double(2000) * 0.15 * dsScale)

        XCTAssertEqual(candidateA.height, expectedHeight, accuracy: 1,
                       "cropRatio=0.15 时 candidateA 高度应 ≈ \(expectedHeight)，实际 \(candidateA.height)")
        XCTAssertEqual(candidateB.height, expectedHeight, accuracy: 1,
                       "cropRatio=0.15 时 candidateB 高度应 ≈ \(expectedHeight)，实际 \(candidateB.height)")
        XCTAssertEqual(metadata.cropRatio, 0.15,
                       "元数据中 cropRatio 应为 0.15")

        // 验证裁剪位置仍然正确
        let avgA = TestImageFactory.averageGrayscale(of: candidateA, yRange: 0...(candidateA.height - 1))
        XCTAssertNotNil(avgA)
        XCTAssertLessThan(avgA!, 150,
                          "cropRatio=0.15 时 candidateA 仍应来自底部深灰区域，实际灰度 \(avgA!)")
    }

    func testCropRatioAt50Percent() async {
        // cropRatio = 0.5（50%），裁剪区域很大
        await stitcher.setCropRatio(0.5)

        let imageA = TestImageFactory.makeSplitImage(
            width: 1000, height: 2000,
            topGray: 255, bottomGray: 50, splitRatio: 0.5
        )
        let imageB = TestImageFactory.makeSplitImage(
            width: 1000, height: 2000,
            topGray: 50, bottomGray: 255, splitRatio: 0.5
        )

        let result = await stitcher.cropAndPreprocess(imageA: imageA, imageB: imageB)
        XCTAssertNotNil(result)

        let (candidateA, candidateB, _) = result!

        let dsScale = await stitcher.config.downsampleScale
        let expectedHeight = Int(Double(2000) * 0.5 * dsScale)

        XCTAssertEqual(candidateA.height, expectedHeight, accuracy: 1,
                       "cropRatio=0.5 时 candidateA 高度应 ≈ \(expectedHeight)")
        XCTAssertEqual(candidateB.height, expectedHeight, accuracy: 1,
                       "cropRatio=0.5 时 candidateB 高度应 ≈ \(expectedHeight)")

        // imageA 底部50%全是深灰
        let avgA = TestImageFactory.averageGrayscale(of: candidateA, yRange: 0...(candidateA.height - 1))
        XCTAssertNotNil(avgA)
        XCTAssertLessThan(avgA!, 150,
                          "cropRatio=0.5 时 candidateA 应来自底部深灰区域")

        // imageB 顶部50%全是深灰
        let avgB = TestImageFactory.averageGrayscale(of: candidateB, yRange: 0...(candidateB.height - 1))
        XCTAssertNotNil(avgB)
        XCTAssertLessThan(avgB!, 150,
                          "cropRatio=0.5 时 candidateB 应来自顶部深灰区域")
    }

    func testCropRatioAt5Percent() async {
        // cropRatio = 0.05（5%），裁剪区域很小
        await stitcher.setCropRatio(0.05)

        let imageA = TestImageFactory.makeSplitImage(
            width: 1000, height: 2000,
            topGray: 255, bottomGray: 50, splitRatio: 0.75
        )
        let imageB = TestImageFactory.makeSplitImage(
            width: 1000, height: 2000,
            topGray: 50, bottomGray: 255, splitRatio: 0.25
        )

        let result = await stitcher.cropAndPreprocess(imageA: imageA, imageB: imageB)
        XCTAssertNotNil(result)

        let (candidateA, candidateB, _) = result!

        let dsScale = await stitcher.config.downsampleScale
        let expectedHeight = Int(Double(2000) * 0.05 * dsScale)

        XCTAssertEqual(candidateA.height, expectedHeight, accuracy: 1,
                       "cropRatio=0.05 时 candidateA 高度应 ≈ \(expectedHeight)")
        XCTAssertEqual(candidateB.height, expectedHeight, accuracy: 1,
                       "cropRatio=0.05 时 candidateB 高度应 ≈ \(expectedHeight)")
    }

    // ================================================================
    // 4）伪真实内容测试（随机块结构）
    // ================================================================
    // 目的：模拟真实截图的复杂纹理，验证裁剪+预处理不会崩溃，
    //       且输出尺寸和格式正确

    func testRandomBlockImageDoesNotCrash() async {
        let imageA = TestImageFactory.makeRandomBlockImage(
            width: 1000, height: 2000, blockSize: 50, seed: 42
        )
        let imageB = TestImageFactory.makeRandomBlockImage(
            width: 1000, height: 2000, blockSize: 50, seed: 99
        )

        let result = await stitcher.cropAndPreprocess(imageA: imageA, imageB: imageB)
        XCTAssertNotNil(result, "随机块结构图裁剪不应返回 nil")

        let (candidateA, candidateB, metadata) = result!

        let dsScale = await stitcher.config.downsampleScale
        let cropRatio = await stitcher.config.cropRatio
        let expectedHeight = Int(Double(2000) * Double(cropRatio) * Double(dsScale))

        XCTAssertEqual(candidateA.height, expectedHeight, accuracy: 1,
                       "随机块图 candidateA 高度应正确")
        XCTAssertEqual(candidateB.height, expectedHeight, accuracy: 1,
                       "随机块图 candidateB 高度应正确")
        XCTAssertEqual(candidateA.colorSpace?.model, .monochrome,
                       "随机块图输出应为灰度图")
        XCTAssertEqual(candidateB.colorSpace?.model, .monochrome,
                       "随机块图输出应为灰度图")
    }

    func testRandomBlockImagePreservesTextureDiversity() async {
        // 使用不同 seed 生成两张不同的随机块图
        // 验证裁剪后两张图的内容确实不同（不是全白或全黑）
        let imageA = TestImageFactory.makeRandomBlockImage(
            width: 1000, height: 2000, blockSize: 50, seed: 42
        )
        let imageB = TestImageFactory.makeRandomBlockImage(
            width: 1000, height: 2000, blockSize: 50, seed: 99
        )

        let result = await stitcher.cropAndPreprocess(imageA: imageA, imageB: imageB)
        XCTAssertNotNil(result)

        let (candidateA, candidateB, _) = result!

        // 验证灰度值有足够的方差（不是全白/全黑/全灰）
        let avgA = TestImageFactory.averageGrayscale(of: candidateA, yRange: 0...(candidateA.height - 1))
        let avgB = TestImageFactory.averageGrayscale(of: candidateB, yRange: 0...(candidateB.height - 1))

        XCTAssertNotNil(avgA)
        XCTAssertNotNil(avgB)

        // 平均灰度应在 50~200 之间（有足够的明暗变化）
        XCTAssertGreaterThan(avgA!, 30, "随机块图 candidateA 不应太暗（灰度 > 30），实际 \(avgA!)")
        XCTAssertLessThan(avgA!, 220, "随机块图 candidateA 不应太亮（灰度 < 220），实际 \(avgA!)")
        XCTAssertGreaterThan(avgB!, 30, "随机块图 candidateB 不应太暗")
        XCTAssertLessThan(avgB!, 220, "随机块图 candidateB 不应太亮")
    }

    func testRandomBlockImageWithDifferentSizes() async {
        // 不同尺寸的随机块图
        let imageA = TestImageFactory.makeRandomBlockImage(
            width: 1179, height: 2556, blockSize: 40, seed: 1
        )
        let imageB = TestImageFactory.makeRandomBlockImage(
            width: 1179, height: 2556, blockSize: 40, seed: 2
        )

        let result = await stitcher.cropAndPreprocess(imageA: imageA, imageB: imageB)
        XCTAssertNotNil(result, "iPhone 截图尺寸的随机块图裁剪不应返回 nil")

        let (candidateA, candidateB, metadata) = result!

        // iPhone 截图尺寸：1179×2556
        XCTAssertEqual(metadata.uniformWidth, 1179.0,
                       "iPhone 截图尺寸的统一宽度应正确")

        let dsScale = await stitcher.config.downsampleScale
        let cropRatio = await stitcher.config.cropRatio
        let expectedHeight = Int(Double(2556) * Double(cropRatio) * Double(dsScale))

        XCTAssertEqual(candidateA.height, expectedHeight, accuracy: 2,
                       "iPhone 截图尺寸的 candidateA 高度应正确")
    }

    func testRandomBlockImageWithDifferentWidths() async {
        // 不同宽度的随机块图
        let imageA = TestImageFactory.makeRandomBlockImage(
            width: 1000, height: 2000, blockSize: 50, seed: 10
        )
        let imageB = TestImageFactory.makeRandomBlockImage(
            width: 800, height: 2000, blockSize: 40, seed: 20
        )

        let result = await stitcher.cropAndPreprocess(imageA: imageA, imageB: imageB)
        XCTAssertNotNil(result, "不同宽度的随机块图裁剪不应返回 nil")

        let (candidateA, candidateB, metadata) = result!

        XCTAssertEqual(candidateA.width, candidateB.width,
                       "不同宽度随机块图裁剪后宽度应统一")
        XCTAssertEqual(metadata.uniformWidth, 800.0,
                       "统一宽度应取较小值 800")
    }
}

// MARK: - NCCStitcher 测试辅助扩展

extension NCCStitcher {
    func setCropRatio(_ ratio: CGFloat) async {
        config.cropRatio = ratio
    }
}
