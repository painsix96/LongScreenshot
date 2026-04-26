import SwiftUI

struct SettingsView: View {
    @AppStorage("autoSaveToAlbum") private var autoSaveToAlbum = false
    @AppStorage("imageQuality") private var imageQuality = 0.9

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                List {
                    // 应用信息头部
                    SettingsHeader()
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)

                    // 拼接设置
                    Section {
                        Toggle(isOn: $autoSaveToAlbum) {
                            SettingsRow(
                                icon: "square.and.arrow.down",
                                iconColor: .blue,
                                title: "自动保存到相册",
                                subtitle: "拼接完成后自动保存"
                            )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                SettingsRow(
                                    icon: "photo",
                                    iconColor: .green,
                                    title: "图片质量",
                                    subtitle: "调整导出图片的压缩质量"
                                )
                                Spacer()
                                Text("\(Int(imageQuality * 100))%")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }

                            Slider(value: $imageQuality, in: 0.5...1.0, step: 0.1)
                                .tint(.green)
                        }
                    } header: {
                        Text("拼接设置")
                            .font(.system(size: 13, weight: .semibold))
                            .textCase(.uppercase)
                    }

                    // 帮助
                    Section {
                        NavigationLink {
                            TutorialView()
                        } label: {
                            SettingsRow(
                                icon: "graduationcap.fill",
                                iconColor: .indigo,
                                title: "使用教程",
                                subtitle: "了解如何使用长截图功能"
                            )
                        }
                    } header: {
                        Text("帮助")
                            .font(.system(size: 13, weight: .semibold))
                            .textCase(.uppercase)
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("设置")
        }
    }
}

// MARK: - 设置头部
struct SettingsHeader: View {
    var body: some View {
        VStack(spacing: 16) {
            // 应用图标
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 90, height: 90)
                    .shadow(color: .blue.opacity(0.3), radius: 15, x: 0, y: 8)

                Image(systemName: "photo.stack.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
            }

            // 应用名称和版本
            VStack(spacing: 4) {
                Text("长截图")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.primary)

                Text("版本 1.0.0")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - 设置行
struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            // 图标背景
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            // 文字
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 使用教程页面
struct TutorialView: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: 20) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)
                            .shadow(color: .blue.opacity(0.3), radius: 15, x: 0, y: 8)

                        Image(systemName: "photo.stack.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 20)

                    Text("长截图")
                        .font(.system(size: 28, weight: .bold))

                    Text("一款简洁高效的长截图拼接工具，帮助你将多张截图无缝拼接成一张完整的长图。")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .listRowBackground(Color.clear)
            }

            Section("录屏拼接") {
                VideoTutorialCard(
                    stepNumber: 1,
                    icon: "video.fill",
                    title: "选择视频",
                    description: "在首页点击选择一个视频（视频会显示时长标识）"
                )
                VideoTutorialCard(
                    stepNumber: 2,
                    icon: "squares.below.rectangle",
                    title: "开始拼接",
                    description: "点击底部「开始拼接」按钮"
                )
                VideoTutorialCard(
                    stepNumber: 3,
                    icon: "film",
                    title: "自动分析",
                    description: "系统自动分析视频并提取画面帧"
                )
                VideoTutorialCard(
                    stepNumber: 4,
                    icon: "wand.and.stars",
                    title: "生成长图",
                    description: "系统自动将视频帧拼接成一张全景长图"
                )
                VideoTutorialCard(
                    stepNumber: 5,
                    icon: "square.and.arrow.up",
                    title: "保存分享",
                    description: "拼接完成后，可保存到相册或直接分享"
                )
            }

            Section("多图拼接") {
                PhotoTutorialCard(
                    stepNumber: 1,
                    icon: "photo.stack.fill",
                    title: "选择图片",
                    description: "在首页点击选择2-20张截图，选中的图片会显示序号"
                )
                PhotoTutorialCard(
                    stepNumber: 2,
                    icon: "squares.below.rectangle",
                    title: "开始拼接",
                    description: "点击底部「开始拼接」按钮"
                )
                PhotoTutorialCard(
                    stepNumber: 3,
                    icon: "magnifyingglass",
                    title: "检测重叠",
                    description: "系统自动检测图片间的重叠区域"
                )
                PhotoTutorialCard(
                    stepNumber: 4,
                    icon: "wand.and.stars",
                    title: "自动拼接",
                    description: "系统根据重叠区域自动拼接图片"
                )
                PhotoTutorialCard(
                    stepNumber: 5,
                    icon: "square.and.arrow.up",
                    title: "保存分享",
                    description: "拼接完成后，可保存到相册或直接分享"
                )
            }

            Section("常见问题") {
                VStack(alignment: .leading, spacing: 12) {
                    FAQItem(question: "最多可以拼接多少张图片？", answer: "最多支持20张图片拼接。")
                    FAQItem(question: "拼接失败怎么办？", answer: "请确保图片有重叠区域，且图片顺序正确。")
                    FAQItem(question: "如何获得更好的拼接效果？", answer: "截图时保持内容有适当的重叠区域（约50-100像素）。")
                }
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("使用教程")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 视频教程卡片
struct VideoTutorialCard: View {
    let stepNumber: Int
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.indigo.opacity(0.12))
                    .frame(width: 50, height: 50)

                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.indigo)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("步骤 \(stepNumber)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.indigo))

                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - 照片教程卡片
struct PhotoTutorialCard: View {
    let stepNumber: Int
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.green.opacity(0.12))
                    .frame(width: 50, height: 50)

                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("步骤 \(stepNumber)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.green))

                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
    }
}


// MARK: - 常见问题项
struct FAQItem: View {
    let question: String
    let answer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(question)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            Text(answer)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    SettingsView()
}
