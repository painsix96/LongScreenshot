import SwiftUI
import UIKit

// MARK: - 动画常量
enum AnimationConstants {
    // 时间常量
    static let quickDuration: Double = 0.15
    static let standardDuration: Double = 0.3
    static let slowDuration: Double = 0.5
    static let springDuration: Double = 0.4

    // 弹簧动画参数
    static let springResponse: Double = 0.4
    static let springDamping: Double = 0.75
    static let springStiffness: Double = 150

    // 缩放比例
    static let pressedScale: CGFloat = 0.95
    static let highlightedScale: CGFloat = 0.97
    static let minimumScale: CGFloat = 0.9
    static let maximumScale: CGFloat = 1.1

    // 透明度
    static let pressedOpacity: Double = 0.8
    static let disabledOpacity: Double = 0.5
    static let hiddenOpacity: Double = 0.0

    // 位移距离
    static let slideDistance: CGFloat = 30
    static let cardLiftDistance: CGFloat = -8
}

// MARK: - 动画曲线扩展
extension Animation {
    /// 标准弹簧动画
    static var standardSpring: Animation {
        .spring(
            response: AnimationConstants.springResponse,
            dampingFraction: AnimationConstants.springDamping
        )
    }

    /// 快速弹簧动画（用于按钮反馈）
    static var quickSpring: Animation {
        .spring(
            response: AnimationConstants.quickDuration,
            dampingFraction: 0.8
        )
    }

    /// 慢速弹簧动画（用于页面转场）
    static var slowSpring: Animation {
        .spring(
            response: AnimationConstants.slowDuration,
            dampingFraction: 0.85
        )
    }

    /// 弹性动画（用于强调效果）
    static var bouncy: Animation {
        .spring(
            response: 0.5,
            dampingFraction: 0.6
        )
    }

    /// 平滑缓动动画
    static var smoothEase: Animation {
        .easeInOut(duration: AnimationConstants.standardDuration)
    }

    /// 延迟动画
    static func delayed(_ delay: Double) -> Animation {
        .easeInOut(duration: AnimationConstants.standardDuration)
            .delay(delay)
    }
}

// MARK: - 页面转场动画
enum PageTransition {
    /// 从右侧滑入（push 效果）
    static var push: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.95)),
            removal: .move(edge: .leading)
                .combined(with: .opacity)
        )
    }

    /// 从左侧滑入（pop 效果）
    static var pop: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .leading)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.95)),
            removal: .move(edge: .trailing)
                .combined(with: .opacity)
        )
    }

    /// 从底部滑入（sheet 效果）
    static var sheet: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom)
                .combined(with: .opacity),
            removal: .move(edge: .bottom)
                .combined(with: .opacity)
        )
    }

    /// 淡入淡出
    static var fade: AnyTransition {
        .opacity
            .animation(.easeInOut(duration: AnimationConstants.standardDuration))
    }

    /// 缩放进入
    static var zoom: AnyTransition {
        .scale(scale: 0.8, anchor: .center)
            .combined(with: .opacity)
    }

    /// 翻转效果
    static var flip: AnyTransition {
        .modifier(
            active: FlipModifier(angle: .degrees(90)),
            identity: FlipModifier(angle: .degrees(0))
        )
    }

    /// 卡片堆叠效果
    static var cardStack: AnyTransition {
        .asymmetric(
            insertion: .offset(y: 50)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.9)),
            removal: .offset(y: -30)
                .combined(with: .opacity)
        )
    }
}

// MARK: - 翻转修饰器
struct FlipModifier: ViewModifier {
    let angle: Angle

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                angle,
                axis: (x: 0, y: 1, z: 0)
            )
    }
}

// MARK: - 按钮按压动画修饰器
struct PressableButtonStyle: ViewModifier {
    @State private var isPressed = false
    let scale: CGFloat
    let opacity: Double
    let hapticStyle: HapticStyle?

    init(
        scale: CGFloat = AnimationConstants.pressedScale,
        opacity: Double = AnimationConstants.pressedOpacity,
        hapticStyle: HapticStyle? = .light
    ) {
        self.scale = scale
        self.opacity = opacity
        self.hapticStyle = hapticStyle
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? scale : 1.0)
            .opacity(isPressed ? opacity : 1.0)
            .animation(.quickSpring, value: isPressed)
            .onLongPressGesture(
                minimumDuration: .infinity,
                maximumDistance: .infinity,
                pressing: { pressing in
                    isPressed = pressing
                    if pressing, let style = hapticStyle {
                        Task { @MainActor in
                            HapticManager.shared.trigger(style)
                        }
                    }
                },
                perform: {}
            )
    }
}

// MARK: - 弹性缩放修饰器
struct BouncyScaleModifier: ViewModifier {
    @State private var scale: CGFloat = 1.0
    let targetScale: CGFloat
    let trigger: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onChange(of: trigger) { newValue in
                if newValue {
                    withAnimation(.bouncy) {
                        scale = targetScale
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.bouncy) {
                            scale = 1.0
                        }
                    }
                }
            }
    }
}

// MARK: - 脉冲动画修饰器
struct PulseModifier: ViewModifier {
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: true)
                ) {
                    scale = 1.15
                    opacity = 0.7
                }
            }
    }
}

// MARK: - 摇晃动画修饰器
struct ShakeModifier: ViewModifier {
    @State private var shakeOffset: CGFloat = 0
    let trigger: Bool
    let intensity: CGFloat

    init(trigger: Bool, intensity: CGFloat = 10) {
        self.trigger = trigger
        self.intensity = intensity
    }

    func body(content: Content) -> some View {
        content
            .offset(x: shakeOffset)
            .onChange(of: trigger) { newValue in
                if newValue {
                    shake()
                }
            }
    }

    private func shake() {
        let animation = Animation.easeInOut(duration: 0.08)

        withAnimation(animation) {
            shakeOffset = -intensity
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(animation) {
                shakeOffset = intensity
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(animation) {
                shakeOffset = -intensity * 0.5
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            withAnimation(animation) {
                shakeOffset = 0
            }
        }
    }
}

// MARK: - 悬浮动画修饰器
struct HoverModifier: ViewModifier {
    @State private var offset: CGFloat = 0

    let distance: CGFloat
    let duration: Double

    init(distance: CGFloat = 5, duration: Double = 2) {
        self.distance = distance
        self.duration = duration
    }

    func body(content: Content) -> some View {
        content
            .offset(y: offset)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: duration)
                    .repeatForever(autoreverses: true)
                ) {
                    offset = -distance
                }
            }
    }
}

// MARK: - View 扩展
extension View {
    /// 按压效果
    func pressable(
        scale: CGFloat = AnimationConstants.pressedScale,
        opacity: Double = AnimationConstants.pressedOpacity,
        hapticStyle: HapticStyle? = .light
    ) -> some View {
        modifier(PressableButtonStyle(
            scale: scale,
            opacity: opacity,
            hapticStyle: hapticStyle
        ))
    }

    /// 弹性缩放效果
    func bouncyScale(targetScale: CGFloat, trigger: Bool) -> some View {
        modifier(BouncyScaleModifier(targetScale: targetScale, trigger: trigger))
    }

    /// 脉冲动画
    func pulse() -> some View {
        modifier(PulseModifier())
    }

    /// 摇晃动画
    func shake(trigger: Bool, intensity: CGFloat = 10) -> some View {
        modifier(ShakeModifier(trigger: trigger, intensity: intensity))
    }

    /// 悬浮动画
    func hover(distance: CGFloat = 5, duration: Double = 2) -> some View {
        modifier(HoverModifier(distance: distance, duration: duration))
    }

    /// 卡片抬起效果
    func cardLift(isHovered: Bool) -> some View {
        self
            .offset(y: isHovered ? AnimationConstants.cardLiftDistance : 0)
            .shadow(
                color: .black.opacity(isHovered ? 0.15 : 0.05),
                radius: isHovered ? 20 : 8,
                x: 0,
                y: isHovered ? 12 : 4
            )
            .animation(.standardSpring, value: isHovered)
    }

    /// 淡入动画
    func fadeIn(delay: Double = 0) -> some View {
        self
            .opacity(0)
            .onAppear {
                withAnimation(.delayed(delay)) {
                    // 触发淡入效果
                }
            }
    }

    /// 滑入动画
    func slideIn(from edge: Edge, delay: Double = 0) -> some View {
        self
            .transition(
                .move(edge: edge)
                    .combined(with: .opacity)
                    .animation(.delayed(delay))
            )
    }
}

// MARK: - 加载动画管理器
@MainActor
final class LoadingAnimationManager: ObservableObject {
    static let shared = LoadingAnimationManager()

    @Published var isLoading = false
    @Published var progress: Double = 0
    @Published var currentPhase: String = ""

    private var progressTimer: Timer?

    func startLoading(phase: String = "加载中...") {
        isLoading = true
        progress = 0
        currentPhase = phase
    }

    func updateProgress(_ value: Double, phase: String? = nil) {
        withAnimation(.smoothEase) {
            progress = min(max(value, 0), 1)
            if let phase = phase {
                currentPhase = phase
            }
        }
    }

    func finishLoading() {
        withAnimation(.smoothEase) {
            progress = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.smoothEase) {
                self.isLoading = false
            }
        }
    }

    func simulateProgress(duration: Double = 2.0) {
        startLoading()

        var currentProgress: Double = 0
        let increment = 0.02
        let interval = duration * increment

        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            currentProgress += increment

            Task { @MainActor in
                self.updateProgress(currentProgress)
            }

            if currentProgress >= 1.0 {
                timer.invalidate()
                Task { @MainActor in
                    self.finishLoading()
                }
            }
        }
    }
}

// MARK: - 交错动画助手
enum StaggeredAnimation {
    /// 为列表项创建交错动画
    static func staggeredDelay(
        for index: Int,
        baseDelay: Double = 0,
        staggerInterval: Double = 0.05
    ) -> Double {
        baseDelay + Double(index) * staggerInterval
    }

}
