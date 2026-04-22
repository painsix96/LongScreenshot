import SwiftUI

// MARK: - 自定义加载视图

/// 主加载视图，包含进度环、状态文字和毛玻璃背景
struct LoadingView: View {
    let progress: Double
    let phase: String
    let showCancelButton: Bool
    let onCancel: (() -> Void)?

    init(
        progress: Double = 0,
        phase: String = "加载中...",
        showCancelButton: Bool = false,
        onCancel: (() -> Void)? = nil
    ) {
        self.progress = progress
        self.phase = phase
        self.showCancelButton = showCancelButton
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack {
            // 背景遮罩
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .transition(.opacity)

            // 主内容
            VStack(spacing: 24) {
                // 进度环
                ProgressRingView(progress: progress)
                    .frame(width: 100, height: 100)

                // 状态文字
                VStack(spacing: 8) {
                    Text(phase)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)

                    // 进度百分比
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                        .contentTransition(.numericText())
                }

                // 取消按钮
                if showCancelButton, let onCancel = onCancel {
                    Button(action: onCancel) {
                        Text("取消")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color(.tertiarySystemFill))
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
            }
            .padding(32)
            .background(
                GlassmorphicBackground()
            )
            .transition(.scale.combined(with: .opacity))
        }
    }
}

// MARK: - 进度环视图

struct ProgressRingView: View {
    let progress: Double

    @State private var animatedProgress: Double = 0
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            // 背景圆环
            Circle()
                .stroke(
                    Color(.systemGray5),
                    style: StrokeStyle(
                        lineWidth: 8,
                        lineCap: .round
                    )
                )

            // 进度圆环
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(
                        colors: [.blue, .purple, .pink, .blue],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(
                        lineWidth: 8,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .rotationEffect(.degrees(rotation))

            // 中心内容
            ZStack {
                // 脉冲效果
                PulseCircle()
                    .opacity(0.3)

                // 图标
                Image(systemName: "photo.stack.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    #if canImport(SwiftUI, _version: 5.9)
                    .symbolEffect(.bounce, options: .repeat(1))
                    #endif
            }
        }
        .onAppear {
            // 旋转动画
            withAnimation(
                .linear(duration: 2)
                .repeatForever(autoreverses: false)
            ) {
                rotation = 360
            }
        }
        .onChange(of: progress) { newValue in
            withAnimation(.smoothEase) {
                animatedProgress = newValue
            }
        }
    }
}

// MARK: - 脉冲圆圈

struct PulseCircle: View {
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.5

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        .blue.opacity(0.4),
                        .blue.opacity(0.1),
                        .clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 40
                )
            )
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.5)
                    .repeatForever(autoreverses: true)
                ) {
                    scale = 1.3
                    opacity = 0.2
                }
            }
    }
}

// MARK: - 毛玻璃背景

struct GlassmorphicBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.5),
                                .white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: .black.opacity(0.15),
                radius: 30,
                x: 0,
                y: 15
            )
    }
}

// MARK: - 进度条加载视图

struct ProgressBarLoadingView: View {
    let progress: Double
    let phase: String

    @State private var animatedProgress: Double = 0

    var body: some View {
        VStack(spacing: 16) {
            // 进度条
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // 背景
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)

                    // 进度
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * animatedProgress, height: 8)
                        .animation(.smoothEase, value: animatedProgress)

                    // 光效
                    if animatedProgress > 0 && animatedProgress < 1 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0),
                                        .white.opacity(0.8),
                                        .white.opacity(0)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 40, height: 8)
                            .offset(x: geometry.size.width * animatedProgress - 20)
                            .animation(
                                .linear(duration: 1)
                                .repeatForever(autoreverses: false),
                                value: animatedProgress
                            )
                    }
                }
            }
            .frame(height: 8)

            // 状态
            HStack {
                Text(phase)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(Int(animatedProgress * 100))%")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.blue)
                    .contentTransition(.numericText())
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .onChange(of: progress) { newValue in
            withAnimation(.smoothEase) {
                animatedProgress = newValue
            }
        }
    }
}

// MARK: - 骨架屏加载视图

struct SkeletonLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            // 图片占位
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray5))
                .frame(height: 200)
                .overlay(
                    ShimmerEffect()
                )

            // 文字占位
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(height: 16)
                    .overlay(ShimmerEffect())

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(height: 12)
                    .frame(width: 200)
                    .overlay(ShimmerEffect())
            }
        }
        .padding()
    }
}

// MARK: - 闪烁效果

struct ShimmerEffect: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            LinearGradient(
                colors: [
                    .clear,
                    .white.opacity(0.5),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geometry.size.width * 2)
            .offset(x: -geometry.size.width + phase * geometry.size.width * 2)
            .onAppear {
                withAnimation(
                    .linear(duration: 1.5)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 1
                }
            }
        }
    }
}

// MARK: - 点状加载指示器

struct DotsLoadingView: View {
    @State private var animations: [Bool] = [false, false, false]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 12, height: 12)
                    .scaleEffect(animations[index] ? 1.5 : 1.0)
                    .opacity(animations[index] ? 1.0 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.4)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.15),
                        value: animations[index]
                    )
            }
        }
        .onAppear {
            for index in animations.indices {
                animations[index] = true
            }
        }
    }
}

// MARK: - 无限循环加载指示器

struct InfiniteLoadingView: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            // 外圈
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(
                    AngularGradient(
                        colors: [.blue, .purple, .pink, .blue],
                        center: .center
                    ),
                    style: StrokeStyle(
                        lineWidth: 4,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .frame(width: 50, height: 50)

            // 内圈
            Circle()
                .trim(from: 0.3, to: 1)
                .stroke(
                    AngularGradient(
                        colors: [.purple, .blue, .cyan, .purple],
                        center: .center
                    ),
                    style: StrokeStyle(
                        lineWidth: 3,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(isAnimating ? -360 : 0))
                .frame(width: 30, height: 30)
        }
        .onAppear {
            withAnimation(
                .linear(duration: 1.5)
                .repeatForever(autoreverses: false)
            ) {
                isAnimating = true
            }
        }
    }
}

// MARK: - 拼接进度视图

struct StitchingProgressView: View {
    @ObservedObject var progress: StitchingProgress

    var body: some View {
        LoadingView(
            progress: progress.currentProgress,
            phase: progress.progressDescription,
            showCancelButton: true,
            onCancel: {
                progress.cancel()
            }
        )
    }
}

// MARK: - 全屏加载遮罩

struct FullScreenLoadingOverlay: View {
    let message: String
    let showProgress: Bool
    let progress: Double

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .transition(.opacity)

            VStack(spacing: 20) {
                if showProgress {
                    ProgressRingView(progress: progress)
                        .frame(width: 80, height: 80)
                } else {
                    InfiniteLoadingView()
                }

                Text(message)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            )
            .transition(.scale.combined(with: .opacity))
        }
    }
}

// MARK: - 加载视图修饰器

struct LoadingOverlayModifier: ViewModifier {
    let isLoading: Bool
    let message: String
    let progress: Double
    let showProgress: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                if isLoading {
                    FullScreenLoadingOverlay(
                        message: message,
                        showProgress: showProgress,
                        progress: progress
                    )
                }
            }
    }
}

// MARK: - View 扩展

extension View {
    /// 添加加载遮罩
    func loadingOverlay(
        isLoading: Bool,
        message: String = "加载中...",
        showProgress: Bool = false,
        progress: Double = 0
    ) -> some View {
        modifier(LoadingOverlayModifier(
            isLoading: isLoading,
            message: message,
            progress: progress,
            showProgress: showProgress
        ))
    }

    /// 添加骨架屏加载效果
    func skeletonLoading(isLoading: Bool) -> some View {
        self
            .redacted(reason: isLoading ? .placeholder : [])
            .shimmering(active: isLoading)
    }

    /// 闪烁效果修饰器
    func shimmering(active: Bool) -> some View {
        overlay(
            active ? ShimmerEffect() : nil
        )
    }
}

// MARK: - 预览

#Preview {
    ZStack {
        Color(.systemBackground)
            .ignoresSafeArea()

        VStack(spacing: 30) {
            // 主加载视图
            LoadingView(
                progress: 0.65,
                phase: "正在分析重叠区域...",
                showCancelButton: true
            ) {
                print("取消")
            }
            .frame(height: 200)

            // 进度条加载
            ProgressBarLoadingView(
                progress: 0.45,
                phase: "处理图像融合"
            )

            // 点状加载
            DotsLoadingView()

            // 无限循环加载
            InfiniteLoadingView()
        }
        .padding()
    }
}

#Preview("Skeleton") {
    ZStack {
        Color(.systemBackground)
            .ignoresSafeArea()

        SkeletonLoadingView()
            .padding()
    }
}
