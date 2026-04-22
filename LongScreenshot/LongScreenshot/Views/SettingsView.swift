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
                            HStack {
                                SettingsRow(
                                    icon: "book.open",
                                    iconColor: .indigo,
                                    title: "使用教程",
                                    subtitle: "了解如何使用长截图功能"
                                )
                                Spacer()
                            }
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
                            .frame(width: 100, height: 100)
                            .shadow(color: .blue.opacity(0.3), radius: 15, x: 0, y: 8)

                        Image(systemName: "photo.stack.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 20)

                    // 应用名称
                    Text("长截图")
                        .font(.system(size: 28, weight: .bold))

                    // 简介
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

            Section("使用步骤") {
                VStack(alignment: .leading, spacing: 16) {
                    InstructionStep(number: 1, text: "进入首页，浏览系统相册的照片")
                    InstructionStep(number: 2, text: "点击选择需要拼接的截图（2-20张）")
                    InstructionStep(number: 3, text: "点击「开始拼接」按钮")
                    InstructionStep(number: 4, text: "等待自动拼接完成")
                    InstructionStep(number: 5, text: "保存到相册或分享")
                }
                .padding(.vertical, 8)
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

// MARK: - 使用步骤
struct InstructionStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 序号
            Text("\(number)")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(.blue)
                )

            // 文字
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
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
