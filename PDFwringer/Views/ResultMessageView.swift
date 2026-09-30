import SwiftUI
import Accessibility

struct ResultMessageView: View {
    let message: String
    let isError: Bool
    var outputURL: URL?
    var onRetry: (() -> Void)?
    var isWarning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var iconName: String {
        if isError { return "xmark.circle.fill" }
        if isWarning { return "exclamationmark.triangle.fill" }
        return outputURL == nil ? "info.circle.fill" : "checkmark.circle.fill"
    }

    private var iconColor: Color {
        if isError { return Color(nsColor: .systemRed) }
        if isWarning { return Color(nsColor: .systemOrange) }
        return outputURL == nil ? Color.secondary : Color(nsColor: .systemGreen)
    }

    private var bgColor: Color {
        if isError { return .red }
        if isWarning { return .orange }
        return outputURL == nil ? .secondary : .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                    .font(.body)

                Text(message)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

            }

            if isError {
                if let onRetry {
                    Button(String(localized: "Try Again"), action: onRetry)
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                  }
              } else if let outputURL {
                Button(String(localized: "Show in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                  }
                .controlSize(.small)
                .buttonStyle(.bordered)
              }
        }
        .id("operation-result")
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(bgColor.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(bgColor.opacity(0.2), lineWidth: 0.5)
                )
        )
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        .onChange(of: message, initial: true) { _, updatedMessage in
            AccessibilityNotification.Announcement(updatedMessage).post()
        }
    }
}
