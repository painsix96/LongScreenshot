import SwiftUI

// MARK: - 标注工具栏
struct AnnotationToolBar: View {
    @ObservedObject var viewModel: AnnotationViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    // 工具选择
                    toolSelectionSection
                    
                    Divider()
                        .frame(height: 40)
                    
                    // 颜色选择
                    colorSelectionSection
                    
                    Divider()
                        .frame(height: 40)
                    
                    // 粗细调节
                    lineWidthSection
                    
                    Divider()
                        .frame(height: 40)
                    
                    // 撤销/重做
                    historySection
                    
                    Divider()
                        .frame(height: 40)
                    
                    // 操作按钮
                    actionSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(.ultraThinMaterial)
        }
    }
    
    // MARK: - 工具选择区域
    private var toolSelectionSection: some View {
        HStack(spacing: 12) {
            ForEach(AnnotationType.allCases, id: \.self) { tool in
                ToolButton(
                    icon: tool.icon,
                    title: tool.rawValue,
                    isSelected: viewModel.toolSettings.selectedTool == tool
                ) {
                    viewModel.selectTool(tool)
                    provideHapticFeedback()
                }
            }
        }
    }
    
    // MARK: - 颜色选择区域
    private var colorSelectionSection: some View {
        HStack(spacing: 8) {
            ForEach(AnnotationToolSettings.presetColors.indices, id: \.self) { index in
                let color = AnnotationToolSettings.presetColors[index]
                ColorButton(
                    color: color,
                    isSelected: viewModel.toolSettings.selectedColor == color
                ) {
                    viewModel.selectColor(color)
                    provideHapticFeedback()
                }
            }
        }
    }
    
    // MARK: - 粗细调节区域
    private var lineWidthSection: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "line.horizontal.decrease")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Slider(
                    value: $viewModel.toolSettings.lineWidth,
                    in: 1...20,
                    step: 0.5
                )
                .frame(width: 100)
                .onChange(of: viewModel.toolSettings.lineWidth) { newValue in
                    viewModel.updateLineWidth(newValue)
                }
                
                Image(systemName: "line.horizontal.increase")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text("\(String(format: "%.1f", viewModel.toolSettings.lineWidth))pt")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - 撤销/重做区域
    private var historySection: some View {
        HStack(spacing: 12) {
            // 撤销按钮
            HistoryButton(
                icon: "arrow.uturn.backward",
                isEnabled: viewModel.canUndo
            ) {
                viewModel.undo()
                provideHapticFeedback()
            }
            
            // 重做按钮
            HistoryButton(
                icon: "arrow.uturn.forward",
                isEnabled: viewModel.canRedo
            ) {
                viewModel.redo()
                provideHapticFeedback()
            }
        }
    }
    
    // MARK: - 操作区域
    private var actionSection: some View {
        HStack(spacing: 12) {
            // 删除按钮
            ToolbarActionButton(
                icon: "trash",
                color: .red,
                isEnabled: viewModel.selectedAnnotationId != nil
            ) {
                viewModel.deleteSelectedAnnotation()
                provideHapticFeedback()
            }
            
            // 清空按钮
            ToolbarActionButton(
                icon: "xmark.circle",
                color: .orange,
                isEnabled: viewModel.hasAnnotations
            ) {
                viewModel.clearAllAnnotations()
                provideHapticFeedback()
            }
        }
    }
    
    // MARK: - 触觉反馈
    private func provideHapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}

// MARK: - 工具按钮
struct ToolButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 32, height: 32)
                    .background(isSelected ? Color.blue.opacity(0.2) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? .blue : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 颜色按钮
struct ColorButton: View {
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 28, height: 28)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .shadow(radius: 1)
                )
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 历史按钮
struct HistoryButton: View {
    let icon: String
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 36, height: 36)
                .background(isEnabled ? Color.gray.opacity(0.2) : Color.clear)
                .clipShape(Circle())
                .foregroundStyle(isEnabled ? .primary : Color.gray.opacity(0.5))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

// MARK: - 工具栏操作按钮
struct ToolbarActionButton: View {
    let icon: String
    let color: Color
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 36, height: 36)
                .background(isEnabled ? color.opacity(0.15) : Color.clear)
                .clipShape(Circle())
                .foregroundStyle(isEnabled ? color : color.opacity(0.3))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

// MARK: - 工具栏预览
struct AnnotationToolBar_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Spacer()
            AnnotationToolBar(viewModel: AnnotationViewModel())
        }
        .previewDisplayName("Annotation Tool Bar")
    }
}


