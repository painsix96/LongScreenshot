import UIKit
import AVFoundation
import Accelerate
import os.log

// MARK: - 滚动片段

/// 视频中的有效滚动片段
struct ScrollSegment {
    let startTime: CMTime
    let endTime: CMTime
    let direction: ScrollDirection
    let averageSpeed: CGFloat
}

// MARK: - 固定区域轮廓

/// 视频固定区域检测结果
struct FixedAreaProfile {
    let topFixedHeight: CGFloat
    let bottomFixedHeight: CGFloat
    let confidence: Double
    let isStable: Bool
    
    static let zero = FixedAreaProfile(topFixedHeight: 0, bottomFixedHeight: 0, confidence: 0, isStable: false)
}

// MARK: - 视频滚动检测器

/// 分析录屏视频，检测滚动片段和固定区域
actor VideoScrollDetector {
    
    private let logger = Logger(subsystem: "com.longscreenshot", category: "VideoScrollDetector")
    
    // MARK: - 配置
    
    struct Config {
        /// 采样帧数（用于固定区域检测）
        var sampleFrameCount: Int = 12
        /// 行差异阈值（基于 0~255 像素值）
        var differenceThreshold: Float = 8.0
        /// 最小状态栏高度（像素）
        var minStatusBarHeight: CGFloat = 47
        /// 稳定性检查容差（像素）
        var stabilityTolerance: CGFloat = 5
        /// 最小滚动速度（像素/秒），低于此值视为静止
        var minScrollSpeed: CGFloat = 50
        /// 最大滚动速度（像素/秒），高于此值可能是快速滑动/转场
        var maxScrollSpeed: CGFloat = 2000
        /// 内容区最小高度（像素）
        var minContentHeight: CGFloat = 200
    }
    
    private var _config = Config()
    
    var config: Config {
        get { _config }
    }
    
    func getMinContentHeight() -> CGFloat {
        return _config.minContentHeight
    }
    
    // MARK: - 主入口
    
    /// 分析视频，返回有效的滚动时间段
    func detectScrollSegments(in asset: AVAsset) async throws -> [ScrollSegment] {
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        
        guard durationSeconds > 1 else {
            throw VideoStitchingError.videoTooShort
        }
        
        logger.info("🎬 开始检测滚动片段: duration=\(durationSeconds)s")
        
        // 提取稀疏关键帧用于分析
        let sampleTimes = generateSampleTimes(duration: duration, count: _config.sampleFrameCount)
        let frames = try await extractFrames(from: asset, at: sampleTimes)
        
        guard frames.count >= 3 else {
            throw VideoStitchingError.insufficientFrames
        }
        
        // 分析每对相邻帧的滚动偏移
        var segments: [ScrollSegment] = []
        let interval = durationSeconds / Double(sampleTimes.count)
        
        for i in 1..<frames.count {
            let prevFrame = frames[i-1]
            let currFrame = frames[i]
            
            // 使用 VerticalOffsetMatcher 计算滚动偏移
            guard let matchResult = matchFrames(prevFrame, currFrame) else {
                logger.debug("🎬 第 \(i) 对帧匹配失败，可能无滚动")
                continue
            }
            
            let scrollOffset = CGFloat(matchResult.scrollOffset)
            let speed = abs(scrollOffset) / CGFloat(interval)
            
            // 判断滚动方向
            let direction: ScrollDirection
            if abs(scrollOffset) < CGFloat(_config.minScrollSpeed * interval) {
                direction = .unknown
            } else if scrollOffset > 0 {
                direction = .vertical
            } else {
                // 负偏移理论上不应该出现（除非向上滚动）
                direction = .unknown
            }
            
            let directionStr = String(describing: direction)
            logger.debug("🎬 第 \(i) 对帧: offset=\(scrollOffset)px, speed=\(speed)px/s, direction=\(directionStr)")
            
            // 过滤无效滚动
            guard direction != .unknown,
                  speed >= _config.minScrollSpeed,
                  speed <= _config.maxScrollSpeed else {
                continue
            }
            
            let startTime = sampleTimes[i-1]
            let endTime = sampleTimes[i]
            
            segments.append(ScrollSegment(
                startTime: startTime,
                endTime: endTime,
                direction: direction,
                averageSpeed: speed
            ))
        }
        
        // 合并相邻的连续滚动片段
        let mergedSegments = mergeSegments(segments)
        
        logger.info("✅ 滚动片段检测完成: 发现 \(mergedSegments.count) 个滚动片段")
        return mergedSegments
    }
    
    /// 检测视频中的固定区域（顶部和底部）
    func detectFixedAreas(in asset: AVAsset) async throws -> FixedAreaProfile {
        logger.info("🔍 开始检测视频固定区域")
        
        let duration = try await asset.load(.duration)
        let sampleTimes = generateSampleTimes(duration: duration, count: _config.sampleFrameCount)
        let frames = try await extractFrames(from: asset, at: sampleTimes)
        
        guard frames.count >= 3 else {
            logger.warning("⚠️ 帧数不足，无法检测固定区域")
            return FixedAreaProfile.zero
        }
        
        // 使用 FixedRegionDetector 检测固定区域
        let detector = FixedRegionDetector()
        var detectorConfig = detector
        detectorConfig.differenceThreshold = _config.differenceThreshold
        
        let (topHeight, bottomHeight) = detector.detect(frames: frames)
        
        // 转换为逻辑坐标（point）
        let scale = frames[0].scale
        let topFixed = CGFloat(topHeight) / scale
        let bottomFixed = CGFloat(bottomHeight) / scale
        
        logger.info("🔍 固定区域检测: 顶部=\(topFixed)pt, 底部=\(bottomFixed)pt")
        
        // 稳定性检查：在不同时间段采样，验证固定区域是否一致
        let isStable = await checkFixedAreaStability(in: asset, expectedTop: topFixed, expectedBottom: bottomFixed)
        
        // 如果检测出的顶部固定区域小于状态栏最小高度，保底使用状态栏高度
        let finalTopFixed = max(topFixed, _config.minStatusBarHeight)
        
        // 计算置信度
        let confidence = calculateFixedAreaConfidence(top: finalTopFixed, bottom: bottomFixed, frameHeight: frames[0].size.height)
        
        let profile = FixedAreaProfile(
            topFixedHeight: finalTopFixed,
            bottomFixedHeight: bottomFixed,
            confidence: confidence,
            isStable: isStable
        )
        
        logger.info("✅ 固定区域检测完成: top=\(finalTopFixed)pt, bottom=\(bottomFixed)pt, stable=\(isStable), confidence=\(confidence)")
        
        return profile
    }
    
    // MARK: - 私有方法
    
    /// 生成均匀分布的采样时间点
    private func generateSampleTimes(duration: CMTime, count: Int) -> [CMTime] {
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds > 0, count > 0 else { return [] }
        
        var times: [CMTime] = []
        let step = durationSeconds / Double(count + 1)
        
        for i in 1...count {
            let time = Double(i) * step
            times.append(CMTime(seconds: time, preferredTimescale: 600))
        }
        
        return times
    }
    
    /// 在指定时间点提取帧
    private func extractFrames(from asset: AVAsset, at times: [CMTime]) async throws -> [UIImage] {
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        var frames: [UIImage] = []
        
        for time in times {
            do {
                let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
                frames.append(image)
            } catch {
                logger.warning("⚠️ 提取采样帧失败 @ \(CMTimeGetSeconds(time))s: \(error.localizedDescription)")
            }
        }
        
        return frames
    }
    
    /// 匹配两帧，计算滚动偏移
    private func matchFrames(_ prev: UIImage, _ curr: UIImage) -> VerticalOffsetMatchResult? {
        guard let prevCG = prev.cgImage, let currCG = curr.cgImage else { return nil }
        
        let matcher = VerticalOffsetMatcher()
        return matcher.match(prevContent: prevCG, currContent: currCG)
    }
    
    /// 合并相邻的连续滚动片段
    private func mergeSegments(_ segments: [ScrollSegment]) -> [ScrollSegment] {
        guard segments.count > 1 else { return segments }
        
        var merged: [ScrollSegment] = []
        var current = segments[0]
        
        for i in 1..<segments.count {
            let next = segments[i]
            let gap = CMTimeGetSeconds(next.startTime) - CMTimeGetSeconds(current.endTime)
            
            // 如果间隔小于 0.5 秒且方向一致，合并
            if gap < 0.5 && current.direction == next.direction {
                current = ScrollSegment(
                    startTime: current.startTime,
                    endTime: next.endTime,
                    direction: current.direction,
                    averageSpeed: (current.averageSpeed + next.averageSpeed) / 2
                )
            } else {
                merged.append(current)
                current = next
            }
        }
        
        merged.append(current)
        return merged
    }
    
    /// 检查固定区域是否稳定（在不同时间段采样比较）
    private func checkFixedAreaStability(in asset: AVAsset, expectedTop: CGFloat, expectedBottom: CGFloat) async -> Bool {
        let duration = try? await asset.load(.duration)
        guard let duration = duration, CMTimeGetSeconds(duration) > 2 else { return true }
        
        // 在视频前半段和后半段分别采样
        let firstHalfTimes = [
            CMTime(seconds: CMTimeGetSeconds(duration) * 0.1, preferredTimescale: 600),
            CMTime(seconds: CMTimeGetSeconds(duration) * 0.2, preferredTimescale: 600),
            CMTime(seconds: CMTimeGetSeconds(duration) * 0.3, preferredTimescale: 600)
        ]
        
        let secondHalfTimes = [
            CMTime(seconds: CMTimeGetSeconds(duration) * 0.6, preferredTimescale: 600),
            CMTime(seconds: CMTimeGetSeconds(duration) * 0.7, preferredTimescale: 600),
            CMTime(seconds: CMTimeGetSeconds(duration) * 0.8, preferredTimescale: 600)
        ]
        
        guard let firstFrames = try? await extractFrames(from: asset, at: firstHalfTimes),
              let secondFrames = try? await extractFrames(from: asset, at: secondHalfTimes),
              firstFrames.count >= 2, secondFrames.count >= 2 else {
            return true
        }
        
        let detector = FixedRegionDetector()
        let (firstTop, firstBottom) = detector.detect(frames: firstFrames)
        let (secondTop, secondBottom) = detector.detect(frames: secondFrames)
        
        let scale = firstFrames[0].scale
        let firstTopPt = CGFloat(firstTop) / scale
        let firstBottomPt = CGFloat(firstBottom) / scale
        let secondTopPt = CGFloat(secondTop) / scale
        let secondBottomPt = CGFloat(secondBottom) / scale
        
        let topDiff = abs(firstTopPt - secondTopPt)
        let bottomDiff = abs(firstBottomPt - secondBottomPt)
        
        let isStable = topDiff <= _config.stabilityTolerance && bottomDiff <= _config.stabilityTolerance
        
        logger.info("🧪 稳定性检查: 前半段(top=\(firstTopPt), bottom=\(firstBottomPt)), 后半段(top=\(secondTopPt), bottom=\(secondBottomPt)), diff=(\(topDiff), \(bottomDiff)), stable=\(isStable)")
        
        return isStable
    }
    
    /// 计算固定区域检测置信度
    private func calculateFixedAreaConfidence(top: CGFloat, bottom: CGFloat, frameHeight: CGFloat) -> Double {
        guard frameHeight > 0 else { return 0 }
        
        let totalFixed = top + bottom
        let fixedRatio = totalFixed / frameHeight
        
        // 固定区域比例在 5%-30% 之间比较合理
        if fixedRatio < 0.05 {
            return 0.5 // 固定区域太小，可能检测失败
        } else if fixedRatio > 0.40 {
            return 0.6 // 固定区域太大，可能误检测
        } else {
            return 0.9 // 合理范围
        }
    }
}
