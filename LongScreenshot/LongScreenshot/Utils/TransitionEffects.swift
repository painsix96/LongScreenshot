import SwiftUI

// MARK: - 自定义转场效果命名空间
enum TransitionEffects {

    // MARK: - 淡入淡出效果

    /// 淡入淡出转场
    static var fade: AnyTransition {
        .opacity
            .animation(.easeInOut(duration: 0.3))
    }

    /// 带缩放的淡入淡出
    static var fadeScale: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.9).combined(with: .opacity),
            removal: .scale(scale: 1.1).combined(with: .opacity)
        )
    }

    // MARK: - 滑动效果

    /// 从右侧滑入
    static var slideFromRight: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    /// 从左侧滑入
    static var slideFromLeft: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
    }

    /// 从底部滑入（Sheet 效果）
    static var slideFromBottom: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        )
    }

    /// 从顶部滑入
    static var slideFromTop: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        )
    }

    // MARK: - 缩放效果

    /// 缩放进入
    static var zoom: AnyTransition {
        .scale(scale: 0.5, anchor: .center)
            .combined(with: .opacity)
    }

    /// 弹性缩放
    static var bounceScale: AnyTransition {
        .modifier(
            active: BouncyScaleEffect(scale: 0.8, opacity: 0),
            identity: BouncyScaleEffect(scale: 1.0, opacity: 1)
        )
    }

    /// 放大进入
    static var grow: AnyTransition {
        .scale(scale: 0.1, anchor: .center)
            .combined(with: .opacity)
    }

    // MARK: - 3D 翻转效果

    /// 水平翻转
    static var flipHorizontal: AnyTransition {
        .modifier(
            active: Flip3DEffect(angle: .degrees(90), axis: (0, 1, 0)),
            identity: Flip3DEffect(angle: .degrees(0), axis: (0, 1, 0))
        )
    }

    /// 垂直翻转
    static var flipVertical: AnyTransition {
        .modifier(
            active: Flip3DEffect(angle: .degrees(90), axis: (1, 0, 0)),
            identity: Flip3DEffect(angle: .degrees(0), axis: (1, 0, 0))
        )
    }

    // MARK: - 旋转效果

    /// 旋转进入
    static var rotate: AnyTransition {
        .modifier(
            active: RotateEffect(angle: .degrees(-90), opacity: 0),
            identity: RotateEffect(angle: .degrees(0), opacity: 1)
        )
    }

    /// 旋转缩放进入
    static var rotateScale: AnyTransition {
        .modifier(
            active: RotateScaleEffect(angle: .degrees(180), scale: 0.5),
            identity: RotateScaleEffect(angle: .degrees(0), scale: 1.0)
        )
    }

    // MARK: - 卡片效果

    /// 卡片堆叠效果
    static var cardStack: AnyTransition {
        .asymmetric(
            insertion: .offset(y: 100)
                .combined(with: .scale(scale: 0.8))
                .combined(with: .opacity),
            removal: .offset(y: -50)
                .combined(with: .scale(scale: 0.9))
                .combined(with: .opacity)
        )
    }

    /// 卡片翻转效果
    static var cardFlip: AnyTransition {
        .modifier(
            active: CardFlipEffect(rotation: 90),
            identity: CardFlipEffect(rotation: 0)
        )
    }

    // MARK: - 模糊效果

    /// 模糊淡入
    @available(iOS 17.0, *)
    static var blurFade: AnyTransition {
        .modifier(
            active: BlurEffect(radius: 20, opacity: 0),
            identity: BlurEffect(radius: 0, opacity: 1)
        )
    }

    // MARK: - 组合效果

    /// 弹性滑动
    static var springSlide: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing)
                .combined(with: .scale(scale: 0.9))
                .combined(with: .opacity)
                .animation(.spring(response: 0.4, dampingFraction: 0.7)),
            removal: .move(edge: .leading)
                .combined(with: .opacity)
                .animation(.easeInOut(duration: 0.2))
        )
    }

    /// 视差滑动
    static var parallaxSlide: AnyTransition {
        .modifier(
            active: ParallaxEffect(offset: 100, scale: 0.9, opacity: 0),
            identity: ParallaxEffect(offset: 0, scale: 1.0, opacity: 1)
        )
    }

    // MARK: - 列表项效果

    /// 列表项进入效果（带交错动画）
    static func listItem(index: Int, baseDelay: Double = 0) -> AnyTransition {
        let delay = baseDelay + Double(index) * 0.05
        return .asymmetric(
            insertion: .move(edge: .bottom)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.95))
                .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(delay)),
            removal: .opacity.animation(.easeInOut(duration: 0.2))
        )
    }

    // MARK: - 特殊效果

    /// 溶解效果
    static var dissolve: AnyTransition {
        .modifier(
            active: DissolveEffect(progress: 0),
            identity: DissolveEffect(progress: 1)
        )
    }

    /// 波浪效果
    static var wave: AnyTransition {
        .modifier(
            active: WaveEffect(amplitude: 20, frequency: 3, progress: 0),
            identity: WaveEffect(amplitude: 0, frequency: 3, progress: 1)
        )
    }

    /// 擦除效果
    static var wipe: AnyTransition {
        .modifier(
            active: WipeEffect(progress: 0),
            identity: WipeEffect(progress: 1)
        )
    }
}

// MARK: - 转场修饰器实现

// 弹性缩放效果
struct BouncyScaleEffect: ViewModifier {
    let scale: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(opacity)
    }
}

// 3D 翻转效果
struct Flip3DEffect: ViewModifier {
    let angle: Angle
    let axis: (x: CGFloat, y: CGFloat, z: CGFloat)

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                angle,
                axis: axis
            )
            .opacity(angle.degrees == 0 ? 1 : 0.5)
    }
}

// 旋转效果
struct RotateEffect: ViewModifier {
    let angle: Angle
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .rotationEffect(angle)
            .opacity(opacity)
    }
}

// 旋转缩放效果
struct RotateScaleEffect: ViewModifier {
    let angle: Angle
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .rotationEffect(angle)
            .scaleEffect(scale)
    }
}

// 卡片翻转效果
struct CardFlipEffect: ViewModifier {
    let rotation: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(rotation),
                axis: (x: 0, y: 1, z: 0)
            )
    }
}

// 模糊效果
@available(iOS 17.0, *)
struct BlurEffect: ViewModifier {
    let radius: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: radius)
            .opacity(opacity)
    }
}

// 视差效果
struct ParallaxEffect: ViewModifier {
    let offset: CGFloat
    let scale: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .scaleEffect(scale)
            .opacity(opacity)
    }
}

// 溶解效果
struct DissolveEffect: AnimatableModifier {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .mask(
                GeometryReader { geometry in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: .white, location: 0),
                                    .init(color: .white, location: max(0, progress - 0.1)),
                                    .init(color: .clear, location: progress),
                                    .init(color: .clear, location: 1)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            )
    }
}

// 波浪效果
struct WaveEffect: AnimatableModifier {
    let amplitude: CGFloat
    let frequency: CGFloat
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .mask(
                GeometryReader { geometry in
                    WaveShape(
                        amplitude: amplitude,
                        frequency: frequency,
                        progress: progress,
                        width: geometry.size.width
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            )
    }
}

// 波浪形状
struct WaveShape: Shape {
    let amplitude: CGFloat
    let frequency: CGFloat
    let progress: CGFloat
    let width: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let effectiveWidth = width * progress

        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: effectiveWidth, y: 0))

        // 绘制波浪底部
        for x in stride(from: effectiveWidth, through: 0, by: -1) {
            let relativeX = x / width
            let y = rect.height / 2 + amplitude * sin(relativeX * frequency * .pi * 2)
            path.addLine(to: CGPoint(x: x, y: y))
        }

        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: 0))

        return path
    }
}

// 擦除效果
struct WipeEffect: AnimatableModifier {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .clipShape(
                WipeShape(progress: progress)
            )
    }
}

// 擦除形状
struct WipeShape: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let width = rect.width * progress

        path.addRect(CGRect(x: 0, y: 0, width: width, height: rect.height))

        return path
    }
}

// MARK: - Matched Geometry Effect 助手

/// Matched Geometry Effect 动画助手
enum MatchedGeometryAnimations {

    /// 创建共享元素转场
    static func sharedElement<
        Content: View,
        Placeholder: View
    >(
        id: AnyHashable,
        in namespace: Namespace.ID,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) -> some View {
        content()
            .matchedGeometryEffect(id: id, in: namespace)
            .transition(.scale.combined(with: .opacity))
    }

    /// 卡片展开效果
    static func cardExpansion<
        Content: View
    >(
        id: AnyHashable,
        in namespace: Namespace.ID,
        isExpanded: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        content()
            .matchedGeometryEffect(
                id: id,
                in: namespace,
                properties: .frame,
                isSource: !isExpanded
            )
            .transition(.scale.combined(with: .opacity))
    }

    /// 图片放大效果（类似 Photos App）
    static func photoZoom<
        Content: View
    >(
        id: AnyHashable,
        in namespace: Namespace.ID,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        content()
            .matchedGeometryEffect(id: id, in: namespace)
            .transition(.scale(scale: 0.95).combined(with: .opacity))
    }
}

// MARK: - View 扩展

extension View {
    /// 应用自定义转场效果
    func customTransition(_ effect: AnyTransition) -> some View {
        return self.transition(effect)
    }

    /// 带条件的转场
    func customTransition(if condition: Bool, _ effect: AnyTransition) -> some View {
        return self.transition(condition ? effect : .identity)
    }
}

// MARK: - 使用示例

/*
 // MARK: - 转场效果使用示例

 struct TransitionExampleView: View {
     @State private var showDetail = false
     @Namespace private var animation

     var body: some View {
         VStack {
             if !showDetail {
                 // 缩略图
                 RoundedRectangle(cornerRadius: 12)
                     .fill(Color.blue)
                     .frame(width: 150, height: 150)
                     .matchedGeometryEffect(id: "card", in: animation)
                     .onTapGesture {
                         withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                             showDetail = true
                         }
                     }
             } else {
                 // 详情视图
                 RoundedRectangle(cornerRadius: 20)
                     .fill(Color.blue)
                     .matchedGeometryEffect(id: "card", in: animation)
                     .frame(maxWidth: .infinity, maxHeight: 400)
                     .onTapGesture {
                         withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                             showDetail = false
                         }
                     }
             }
         }
     }
 }

 // MARK: - 列表项转场示例

 struct ListTransitionExample: View {
     let items = ["Item 1", "Item 2", "Item 3"]

     var body: some View {
         List {
             ForEach(Array(items.enumerated()), id: \.element) { index, item in
                 Text(item)
                     .transition(TransitionEffects.listItem(index: index))
             }
         }
     }
 }
 */
