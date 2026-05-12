import SwiftUI
import Accessibility

struct ResultMessageView: View {
    let message: String
    let isError: Bool
    var isWarning: Bool = false
    var outputURL: URL?
    var onRetry: (() -> Void)?

    private var iconName: String {
        if isError { return "xmark.circle.fill" }
        if isWarning { return "exclamationmark.triangle.fill" }
        return "checkmark.circle.fill"
    }

    private var iconColor: Color {
        if isError { return Color(nsColor: .systemRed) }
        if isWarning { return Color(nsColor: .systemOrange) }
        return Color(nsColor: .systemGreen)
    }

    private var bgColor: Color {
        if isError { return .red }
        if isWarning { return .orange }
        return .green
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .font(.body)

            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(3)

            Spacer()

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
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(bgColor.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(bgColor.opacity(0.2), lineWidth: 0.5)
                )
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear {
            AccessibilityNotification.Announcement(message).post()
        }
    }
}
