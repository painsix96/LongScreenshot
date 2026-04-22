import SwiftUI

/// 信息行组件 - 用于显示带图标、标题和值的行
public struct InfoRow: View {
    let icon: String
    let title: String
    let value: String
    var isLoading: Bool

    public init(
        icon: String,
        title: String,
        value: String,
        isLoading: Bool = false
    ) {
        self.icon = icon
        self.title = title
        self.value = value
        self.isLoading = isLoading
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()

            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

// MARK: - 预览
#Preview {
    VStack(spacing: 16) {
        InfoRow(
            icon: "doc.badge.gearshape",
            title: "格式",
            value: "JPEG"
        )

        InfoRow(
            icon: "ruler",
            title: "尺寸",
            value: "1920 × 1080 px"
        )

        InfoRow(
            icon: "memorychip",
            title: "预估大小",
            value: "2.5 MB",
            isLoading: false
        )

        InfoRow(
            icon: "arrow.clockwise",
            title: "加载中",
            value: "",
            isLoading: true
        )
    }
    .padding()
    .background(Color(.systemBackground))
}
