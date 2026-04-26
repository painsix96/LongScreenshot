import UIKit
import AVFoundation
import Accelerate
import os.log

// MARK: - 视频帧提取器（基于位移的自适应采样）

/// 基于视觉位移的自适应关键帧提取算法
/// 核心原则：不依赖时间，只依赖视觉位移；不允许固定帧率抽样；必须适应变速滑动
/// 算法流程：
/// 1. 自适应步长提取分析帧，逐帧计算垂直位移（SAD 模板匹配）
/// 2. 累计滚动距离，基于原始位移选择关键帧
/// 3. 当累计位移达到 200~400px 时选为关键帧
/// 4. 异常处理：停顿跳过、快速滑动回溯插入中间帧、抖动平滑仅用于步长
/// 5. 输出优化：单调向下、覆盖完整、无重复
actor VideoFrameExtractor {

    private let logger = Logger(subsystem: "com.longscreenshot", category: "VideoFrameExtractor")

    // MARK: - 配置

    struct Config {
        var maxFrames: Int = 100
        var maxExtractWidth: CGFloat = 1080
        var minOffset: Int = 250
        var maxOffset: Int = 450
        var targetOffset: Int = 350
        var stallDeltaThreshold: Int = 3
        var jitterWindow: Int = 3
        var templateHeight: Int = 100
        var initialStepSeconds: Double = 0.2
        var minStepSeconds: Double = 0.05
        var maxStepSeconds: Double = 2.0
        var cropTopRatio: Double = 0.15
        var cropBottomRatio: Double = 0.15
        var backtrackMaxSteps: Int = 10
    }

    private var _config = Config()

    var config: Config {
        get { _config }
    }

    func setConfigMaxExtractWidth(_ width: CGFloat) {
        _config.maxExtractWidth = width
    }

    // MARK: - 主入口

    func extractFramesAdaptive(
        from asset: AVAsset,
        timeRange: CMTimeRange? = nil,
        progress: StitchingProgress
    ) async throws -> [UIImage] {
        let duration = try await asset.load(.duration)
        let effectiveRange = timeRange ?? CMTimeRange(start: .zero, duration: duration)
        let rangeDuration = CMTimeGetSeconds(effectiveRange.duration)
        let startTime = CMTimeGetSeconds(effectiveRange.start)

        logger.info("🎬 开始基于位移的自适应帧提取: duration=\(rangeDuration)s")

        progress.updatePhase(.loading)
        progress.updatePhaseProgress(.loading, progress: 0.05)

        // 阶段 1：自适应步长提取分析帧 + 逐帧计算垂直位移
        let (analysisFrames, rawDisplacements, frameTimes) = try await extractAndComputeDisplacements(
            from: asset,
            startTime: startTime,
            duration: rangeDuration,
            progress: progress
        )

        guard analysisFrames.count >= 2 else {
            throw VideoStitchingError.insufficientFrames
        }

        logger.info("📊 阶段1完成: 分析帧=\(analysisFrames.count), 位移数据=\(rawDisplacements.count)条")

        // 阶段 2：基于原始位移选择关键帧（不平滑，平滑仅用于步长自适应）
        let keyframeIndices = selectKeyframes(from: rawDisplacements, totalFrames: analysisFrames.count)

        logger.info("📊 阶段2完成: 选中 \(keyframeIndices.count) 个关键帧")

        // 阶段 3：对大位移区间回溯插入中间帧
        let (finalIndices, finalFrames, finalTimes) = await backtrackAndInsert(
            keyframeIndices: keyframeIndices,
            analysisFrames: analysisFrames,
            rawDisplacements: rawDisplacements,
            asset: asset,
            startTime: startTime,
            frameTimes: frameTimes
        )

        guard finalFrames.count >= 2 else {
            throw VideoStitchingError.insufficientFrames
        }

        // 输出最终选中的帧信息（索引和时间点）
        let frameInfo = zip(finalIndices, finalTimes).map { idx, time in
            "帧\(idx)@\(String(format: "%.2f", time))s"
        }.joined(separator: ", ")
        logger.info("📸 最终选中帧: \(frameInfo)")

        logger.info("✅ 基于位移的帧提取完成: 分析帧=\(analysisFrames.count), 关键帧=\(finalFrames.count)")
        return finalFrames
    }

    // MARK: - 阶段 1：自适应步长提取 + 位移计算

    private func extractAndComputeDisplacements(
        from asset: AVAsset,
        startTime: Double,
        duration: Double,
        progress: StitchingProgress
    ) async throws -> ([UIImage], [Int], [Double]) {
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero

        var frames: [UIImage] = []
        var displacements: [Int] = []
        var frameTimes: [Double] = []
        var currentTime = 0.0
        var step = _config.initialStepSeconds
        var prevFrame: UIImage? = nil
        let maxAnalysisFrames = _config.maxFrames * 5

        while currentTime < duration && frames.count < maxAnalysisFrames {
            let absoluteTime = startTime + currentTime
            let time = CMTime(seconds: absoluteTime, preferredTimescale: 600)

            do {
                let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                let frame = resizeIfNeeded(UIImage(cgImage: cgImage, scale: 1.0, orientation: .up), maxWidth: _config.maxExtractWidth)

                if let prev = prevFrame {
                    let deltaY = computeVerticalDisplacement(prev, frame)
                    displacements.append(deltaY)

                    // 平滑仅用于步长自适应决策
                    let smoothedDelta = smoothSingleValue(displacements, index: displacements.count - 1)

                    if smoothedDelta < Double(_config.stallDeltaThreshold) {
                        step = min(step * 1.5, _config.maxStepSeconds)
                    } else if smoothedDelta > Double(_config.maxOffset) {
                        step = max(step * 0.5, _config.minStepSeconds)
                    } else {
                        step = _config.initialStepSeconds
                    }
                }

                frames.append(frame)
                frameTimes.append(currentTime)
                prevFrame = frame

            } catch {
                logger.warning("⚠️ 提取分析帧失败 @ \(currentTime)s: \(error.localizedDescription)")
            }

            currentTime += step

            let progressValue = min(0.7, Double(frames.count) / Double(maxAnalysisFrames))
            progress.updatePhaseProgress(.loading, progress: 0.05 + progressValue * 0.65)
        }

        return (frames, displacements, frameTimes)
    }

    // MARK: - 阶段 1 核心：垂直位移计算（SAD 模板匹配）

    /// 使用 SAD 模板匹配计算两帧之间的垂直位移
    /// 裁剪中间区域避免状态栏/底部干扰，取前一帧底部模板在当前帧中搜索匹配
    private func computeVerticalDisplacement(_ prevFrame: UIImage, _ currFrame: UIImage) -> Int {
        guard let prevCG = prevFrame.cgImage, let currCG = currFrame.cgImage else { return 0 }

        let _ = min(prevCG.width, currCG.width)
        let height = min(prevCG.height, currCG.height)

        let cropTop = Int(Double(height) * _config.cropTopRatio)
        let cropBottom = Int(Double(height) * _config.cropBottomRatio)
        let cropHeight = height - cropTop - cropBottom

        guard cropHeight > _config.templateHeight * 2 else { return 0 }

        guard let prevGray = extractGrayscaleCrop(from: prevCG, cropY: cropTop, cropHeight: cropHeight),
              let currGray = extractGrayscaleCrop(from: currCG, cropY: cropTop, cropHeight: cropHeight) else {
            return 0
        }

        let effectiveWidth = prevGray.width
        let effectiveHeight = prevGray.height

        let tHeight = min(_config.templateHeight, effectiveHeight / 2)
        let templateStart = effectiveHeight - tHeight
        let templatePixelCount = tHeight * effectiveWidth

        var templatePixels = [UInt8](repeating: 0, count: templatePixelCount)
        for row in 0..<tHeight {
            let srcStart = (templateStart + row) * effectiveWidth
            let dstStart = row * effectiveWidth
            _ = templatePixels.withUnsafeMutableBufferPointer { dstPtr in
                prevGray.pixels.withUnsafeBufferPointer { srcPtr in
                    memcpy(dstPtr.baseAddress! + dstStart, srcPtr.baseAddress! + srcStart, effectiveWidth)
                }
            }
        }

        let searchRange = effectiveHeight - tHeight
        guard searchRange > 0 else { return 0 }

        var templateFloat = [Float](repeating: 0, count: templatePixelCount)
        vDSP_vfltu8(templatePixels, 1, &templateFloat, 1, vDSP_Length(templatePixelCount))

        var currFloat = [Float](repeating: 0, count: effectiveHeight * effectiveWidth)
        vDSP_vfltu8(currGray.pixels, 1, &currFloat, 1, vDSP_Length(effectiveHeight * effectiveWidth))

        var diff = [Float](repeating: 0, count: templatePixelCount)
        var absDiff = [Float](repeating: 0, count: templatePixelCount)

        var bestSAD: Float = Float.greatestFiniteMagnitude
        var bestY = 0
        let templatePixelCountVDSP = vDSP_Length(templatePixelCount)

        for y in 0...searchRange {
            let candidateStart = y * effectiveWidth

            vDSP_vsub(
                templateFloat.withUnsafeBufferPointer { $0.baseAddress! }, 1,
                currFloat.withUnsafeBufferPointer { $0.baseAddress! + candidateStart }, 1,
                &diff, 1,
                templatePixelCountVDSP
            )
            vDSP_vabs(diff, 1, &absDiff, 1, templatePixelCountVDSP)

            var sad: Float = 0
            vDSP_sve(absDiff, 1, &sad, templatePixelCountVDSP)

            if sad < bestSAD {
                bestSAD = sad
                bestY = y
            }
        }

        let displacement = templateStart - bestY

        logger.debug("📏 位移计算: deltaY=\(displacement)px, bestY=\(bestY), templateStart=\(templateStart), bestSAD=\(bestSAD)")

        return displacement
    }

    // MARK: - 平滑辅助（仅用于步长自适应）

    /// 对单个位置做滑动窗口平均
    private func smoothSingleValue(_ displacements: [Int], index: Int) -> Double {
        let window = _config.jitterWindow
        let halfWindow = window / 2
        let start = max(0, index - halfWindow)
        let end = min(displacements.count, index + halfWindow + 1)
        let sum = displacements[start..<end].reduce(0, +)
        return Double(sum) / Double(end - start)
    }

    // MARK: - 阶段 2：基于原始位移的关键帧选择

    /// 核心逻辑（使用原始位移，不用平滑值）：
    /// - accumulatedOffset < MIN_OFFSET → 不选帧
    /// - MIN_OFFSET <= accumulatedOffset <= MAX_OFFSET → 选当前帧
    /// - accumulatedOffset > MAX_OFFSET → 从最近几帧中选最接近 targetOffset 的帧
    /// - 0位移帧不参与累计，直接跳过
    /// - 强制保留最后一帧，并确保最后一段距离在合理范围
    private func selectKeyframes(from rawDisplacements: [Int], totalFrames: Int) -> [Int] {
        guard totalFrames >= 2 else { return [0] }

        var keyframeIndices: [Int] = [0]
        var accumulatedOffset: Int = 0
        var frameOffsets: [(index: Int, offset: Int)] = []

        let minOffset = _config.minOffset
        let maxOffset = _config.maxOffset
        let targetOffset = _config.targetOffset

        for i in 0..<rawDisplacements.count {
            let frameIndex = i + 1
            let deltaY = rawDisplacements[i]

            // 跳过0位移帧，不参与累计
            if deltaY <= 0 {
                continue
            }

            accumulatedOffset += deltaY
            frameOffsets.append((frameIndex, accumulatedOffset))

            if accumulatedOffset >= minOffset {
                if accumulatedOffset <= maxOffset {
                    keyframeIndices.append(frameIndex)
                    accumulatedOffset = 0
                    frameOffsets.removeAll()
                } else {
                    // 超过 MAX_OFFSET，从候选帧中选最接近 targetOffset 的
                    // 但候选帧的 offset 必须 ≥ minOffset，避免选中位移不足的帧
                    let validCandidates = frameOffsets.filter { $0.offset >= minOffset }
                    if let best = validCandidates.min(by: { abs($0.offset - targetOffset) < abs($1.offset - targetOffset) }) {
                        keyframeIndices.append(best.index)
                        accumulatedOffset = 0  // 重置为0，确保下一段从0开始
                    } else {
                        // 所有候选帧位移都不足 minOffset，选最后一个（位移最大的）
                        if let last = frameOffsets.last {
                            keyframeIndices.append(last.index)
                            accumulatedOffset = 0  // 重置为0，确保下一段从0开始
                        }
                    }
                    frameOffsets.removeAll()
                }
            }
        }

        // 强制保留最后一帧
        let lastFrameIndex = totalFrames - 1
        if keyframeIndices.last != lastFrameIndex {
            keyframeIndices.append(lastFrameIndex)
        }

        // 处理最后一段距离，确保在合理范围
        if keyframeIndices.count >= 2 {
            let secondLastIdx = keyframeIndices[keyframeIndices.count - 2]
            let lastIdx = keyframeIndices[keyframeIndices.count - 1]

            // 计算最后一段的实际累计位移
            var lastSegmentOffset = 0
            for i in secondLastIdx..<min(lastIdx, rawDisplacements.count) {
                let delta = rawDisplacements[i]
                if delta > 0 {
                    lastSegmentOffset += delta
                }
            }

            // 如果最后一段距离太小，去掉前一关键帧，让最后一段凑够距离
            if lastSegmentOffset < minOffset && keyframeIndices.count > 2 {
                keyframeIndices.remove(at: keyframeIndices.count - 2)
                logger.info("📊 最后一段距离不足，去掉前一关键帧以凑够距离")
            }
        }

        let unique = Array(Set(keyframeIndices)).sorted()

        logger.info("📊 关键帧选择: 候选=\(unique.map { String($0) }.joined(separator: ",")), 累计残余位移=\(accumulatedOffset)px")

        return unique
    }

    // MARK: - 阶段 3：大位移回溯插入中间帧

    /// 对相邻关键帧之间位移超过 maxOffset 的区间，回溯插入中间帧
    /// 在两个关键帧对应的时间点之间，均匀插入额外帧
    private func backtrackAndInsert(
        keyframeIndices: [Int],
        analysisFrames: [UIImage],
        rawDisplacements: [Int],
        asset: AVAsset,
        startTime: Double,
        frameTimes: [Double]
    ) async -> ([Int], [UIImage], [Double]) {
        var resultFrames: [UIImage] = [analysisFrames[0]]
        var resultIndices: [Int] = [0]
        var resultTimes: [Double] = [frameTimes[0]]

        for k in 1..<keyframeIndices.count {
            let prevIdx = keyframeIndices[k - 1]
            let currIdx = keyframeIndices[k]

            // 计算这两个关键帧之间的实际累计位移
            let segmentDisplacement = rawDisplacements[prevIdx..<currIdx].reduce(0, +)

            if segmentDisplacement > _config.maxOffset {
                // 大位移区间：在两个关键帧之间插入中间帧
                // 插入数量 = (位移 / targetOffset) - 1，确保只有位移足够大时才插帧
                let rawCount = segmentDisplacement / _config.targetOffset
                let insertCount = max(0, min(rawCount - 1, _config.backtrackMaxSteps))

                if insertCount > 0, prevIdx + 1 < currIdx {
                    // 从分析帧中均匀选取中间帧
                    let step = Double(currIdx - prevIdx) / Double(insertCount + 1)
                    for j in 1...insertCount {
                        let midIdx = prevIdx + Int(Double(j) * step)
                        if midIdx > prevIdx && midIdx < currIdx && midIdx < analysisFrames.count {
                            resultFrames.append(analysisFrames[midIdx])
                            resultIndices.append(midIdx)
                            resultTimes.append(frameTimes[midIdx])
                        }
                    }
                }
            }

            resultFrames.append(analysisFrames[currIdx])
            resultIndices.append(currIdx)
            resultTimes.append(frameTimes[currIdx])
        }

        logger.info("📊 回溯插入: 原始关键帧=\(keyframeIndices.count), 插入后=\(resultFrames.count)")

        return (resultIndices, resultFrames, resultTimes)
    }

    // MARK: - 辅助方法

    /// 裁剪 CGImage 指定区域并转为灰度像素数据
    private func extractGrayscaleCrop(from cgImage: CGImage, cropY: Int, cropHeight: Int) -> (pixels: [UInt8], width: Int, height: Int)? {
        let cropRect = CGRect(x: 0, y: cropY, width: cgImage.width, height: cropHeight)
        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }

        let width = cropped.width
        let height = cropped.height
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.interpolationQuality = .none
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))

        return (pixels, width, height)
    }

    private func resizeIfNeeded(_ image: UIImage, maxWidth: CGFloat) -> UIImage {
        let width = image.size.width * image.scale
        if width <= maxWidth {
            return image
        }

        let scale = maxWidth / width
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return resizeImage(image, to: newSize)
    }

    private func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
