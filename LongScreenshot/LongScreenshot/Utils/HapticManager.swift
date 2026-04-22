import SwiftUI
import UIKit
import CoreHaptics

// MARK: - 触觉反馈样式
enum HapticStyle {
    /// 轻触反馈 - 用于轻微交互
    case light
    /// 中等反馈 - 用于标准按钮点击
    case medium
    /// 重触反馈 - 用于重要操作
    case heavy
    /// 成功反馈 - 操作成功
    case success
    /// 错误反馈 - 操作失败
    case error
    /// 警告反馈 - 需要注意
    case warning
    /// 选择反馈 - 用于选择器
    case selection
    /// 自定义强度 (0.0 - 1.0)
    case custom(CGFloat)
}

// MARK: - 触觉反馈管理器
@MainActor
final class HapticManager {
    static let shared = HapticManager()

    // UIImpactFeedbackGenerator 缓存
    private var lightImpact: UIImpactFeedbackGenerator?
    private var mediumImpact: UIImpactFeedbackGenerator?
    private var heavyImpact: UIImpactFeedbackGenerator?

    // UINotificationFeedbackGenerator
    private var notificationGenerator: UINotificationFeedbackGenerator?

    // UISelectionFeedbackGenerator
    private var selectionGenerator: UISelectionFeedbackGenerator?

    // Core Haptics 引擎
    private var hapticEngine: CHHapticEngine?

    // 设备支持状态
    private(set) var supportsHaptics: Bool = false
    private(set) var supportsCoreHaptics: Bool = false

    private init() {
        checkDeviceSupport()
        prepareGenerators()
    }

    // MARK: - 设备支持检测

    private func checkDeviceSupport() {
        // 检测是否支持触感反馈
        supportsHaptics = UIDevice.current.model.contains("iPhone")

        // 检测 Core Haptics 支持 (iOS 13+)
        if #available(iOS 13.0, *) {
            supportsCoreHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

            if supportsCoreHaptics {
                setupCoreHaptics()
            }
        }
    }

    /// 检查设备是否支持触感反馈
    func checkSupport() -> (haptics: Bool, coreHaptics: Bool) {
        return (supportsHaptics, supportsCoreHaptics)
    }

    // MARK: - 准备反馈生成器

    private func prepareGenerators() {
        guard supportsHaptics else { return }

        lightImpact = UIImpactFeedbackGenerator(style: .light)
        mediumImpact = UIImpactFeedbackGenerator(style: .medium)
        heavyImpact = UIImpactFeedbackGenerator(style: .heavy)

        notificationGenerator = UINotificationFeedbackGenerator()
        selectionGenerator = UISelectionFeedbackGenerator()

        // 预准备生成器以减少延迟
        lightImpact?.prepare()
        mediumImpact?.prepare()
        heavyImpact?.prepare()
        notificationGenerator?.prepare()
        selectionGenerator?.prepare()
    }

    // MARK: - Core Haptics 设置

    @available(iOS 13.0, *)
    private func setupCoreHaptics() {
        do {
            hapticEngine = try CHHapticEngine()

            // 处理引擎停止
            hapticEngine?.stoppedHandler = { reason in
                print("Haptic Engine Stopped: \(reason)")
            }

            // 处理引擎重置
            hapticEngine?.resetHandler = { [weak self] in
                try? self?.hapticEngine?.start()
            }

            try hapticEngine?.start()
        } catch {
            print("Failed to create haptic engine: \(error)")
            supportsCoreHaptics = false
        }
    }

    // MARK: - 触发触觉反馈

    /// 触发触觉反馈
    func trigger(_ style: HapticStyle) {
        guard supportsHaptics else { return }

        switch style {
        case .light:
            lightImpact?.impactOccurred()
            lightImpact?.prepare()

        case .medium:
            mediumImpact?.impactOccurred()
            mediumImpact?.prepare()

        case .heavy:
            heavyImpact?.impactOccurred()
            heavyImpact?.prepare()

        case .success:
            notificationGenerator?.notificationOccurred(.success)
            notificationGenerator?.prepare()

        case .error:
            notificationGenerator?.notificationOccurred(.error)
            notificationGenerator?.prepare()

        case .warning:
            notificationGenerator?.notificationOccurred(.warning)
            notificationGenerator?.prepare()

        case .selection:
            selectionGenerator?.selectionChanged()
            selectionGenerator?.prepare()

        case .custom(let intensity):
            if #available(iOS 13.0, *), supportsCoreHaptics {
                playCustomHaptic(intensity: intensity)
            } else {
                // 回退到标准触感
                if intensity < 0.33 {
                    lightImpact?.impactOccurred()
                } else if intensity < 0.66 {
                    mediumImpact?.impactOccurred()
                } else {
                    heavyImpact?.impactOccurred()
                }
            }
        }
    }

    /// 触发轻触反馈（快捷方法）
    func light() {
        trigger(.light)
    }

    /// 触发中等反馈（快捷方法）
    func medium() {
        trigger(.medium)
    }

    /// 触发成功反馈（快捷方法）
    func success() {
        trigger(.success)
    }

    /// 触发错误反馈（快捷方法）
    func error() {
        trigger(.error)
    }

    // MARK: - Core Haptics 自定义反馈

    @available(iOS 13.0, *)
    private func playCustomHaptic(intensity: CGFloat) {
        guard let engine = hapticEngine else { return }

        let intensityParameter = CHHapticEventParameter(
            parameterID: .hapticIntensity,
            value: Float(intensity)
        )
        let sharpnessParameter = CHHapticEventParameter(
            parameterID: .hapticSharpness,
            value: Float(intensity)
        )

        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [intensityParameter, sharpnessParameter],
            relativeTime: 0
        )

        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("Failed to play custom haptic: \(error)")
        }
    }

    /// 播放复杂触感模式
    @available(iOS 13.0, *)
    func playPattern(_ pattern: HapticPattern) {
        guard supportsCoreHaptics, let engine = hapticEngine else {
            // 回退到简单触感
            fallbackToSimpleHaptic(pattern)
            return
        }

        do {
            let events = pattern.toCHHapticEvents()
            let hapticPattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: hapticPattern)
            try player.start(atTime: 0)
        } catch {
            print("Failed to play haptic pattern: \(error)")
            fallbackToSimpleHaptic(pattern)
        }
    }

    private func fallbackToSimpleHaptic(_ pattern: HapticPattern) {
        switch pattern {
        case .success:
            trigger(.success)
        case .error:
            trigger(.error)
        case .warning:
            trigger(.warning)
        default:
            trigger(.medium)
        }
    }
}

// MARK: - 触感模式
enum HapticPattern {
    /// 成功模式 - 轻快的双脉冲
    case success
    /// 错误模式 - 重脉冲
    case error
    /// 警告模式 - 中等脉冲
    case warning
    /// 心跳模式
    case heartbeat
    /// 节奏模式 - 自定义节奏
    case rhythm([Double])
    /// 渐变模式 - 强度渐变
    case ramp(start: Double, end: Double, duration: Double)

    @available(iOS 13.0, *)
    func toCHHapticEvents() -> [CHHapticEvent] {
        switch self {
        case .success:
            return [
                createEvent(intensity: 0.8, sharpness: 0.7, time: 0),
                createEvent(intensity: 0.5, sharpness: 0.5, time: 0.1)
            ]

        case .error:
            return [
                createEvent(intensity: 1.0, sharpness: 0.9, time: 0),
                createEvent(intensity: 0.6, sharpness: 0.7, time: 0.15)
            ]

        case .warning:
            return [
                createEvent(intensity: 0.7, sharpness: 0.6, time: 0),
                createEvent(intensity: 0.4, sharpness: 0.4, time: 0.1)
            ]

        case .heartbeat:
            return [
                createEvent(intensity: 0.8, sharpness: 0.6, time: 0),
                createEvent(intensity: 0.4, sharpness: 0.4, time: 0.15),
                createEvent(intensity: 0.8, sharpness: 0.6, time: 0.4),
                createEvent(intensity: 0.4, sharpness: 0.4, time: 0.55)
            ]

        case .rhythm(let intervals):
            var events: [CHHapticEvent] = []
            var currentTime: Double = 0
            for (index, interval) in intervals.enumerated() {
                let intensity = 0.5 + 0.3 * sin(Double(index) * 0.5)
                events.append(createEvent(
                    intensity: intensity,
                    sharpness: 0.5,
                    time: currentTime
                ))
                currentTime += interval
            }
            return events

        case .ramp(let start, let end, let duration):
            var events: [CHHapticEvent] = []
            let steps = 10
            for i in 0..<steps {
                let t = Double(i) / Double(steps - 1)
                let intensity = start + (end - start) * t
                events.append(createEvent(
                    intensity: intensity,
                    sharpness: 0.5,
                    time: duration * t
                ))
            }
            return events
        }
    }

    @available(iOS 13.0, *)
    private func createEvent(intensity: Double, sharpness: Double, time: Double) -> CHHapticEvent {
        let intensityParam = CHHapticEventParameter(
            parameterID: .hapticIntensity,
            value: Float(intensity)
        )
        let sharpnessParam = CHHapticEventParameter(
            parameterID: .hapticSharpness,
            value: Float(sharpness)
        )
        return CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [intensityParam, sharpnessParam],
            relativeTime: time
        )
    }
}

// MARK: - SwiftUI View 扩展

extension View {
    /// 添加触觉反馈
    func hapticFeedback(_ style: HapticStyle) -> some View {
        self.onTapGesture {
            Task { @MainActor in
                HapticManager.shared.trigger(style)
            }
        }
    }

    /// 添加触觉反馈（条件触发）
    func hapticFeedback(_ style: HapticStyle, trigger: Bool) -> some View {
        self.onChange(of: trigger) { newValue in
            if newValue {
                Task { @MainActor in
                    HapticManager.shared.trigger(style)
                }
            }
        }
    }
}

// MARK: - Button 扩展

extension Button {
    /// 带触觉反馈的按钮
    func withHaptic(_ style: HapticStyle = .medium) -> some View {
        self.simultaneousGesture(
            TapGesture().onEnded {
                Task { @MainActor in
                    HapticManager.shared.trigger(style)
                }
            }
        )
    }
}
