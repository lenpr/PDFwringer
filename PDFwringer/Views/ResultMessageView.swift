import SwiftUI

struct ResultMessageView: View {
    let message: String
    let isError: Bool
    var outputURL: URL?
    var onRetry: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? Color(nsColor: .systemRed) : Color(nsColor: .systemGreen))
                .font(.body)

            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(3)

            Spacer()

            if isError {
                if let onRetry {
                    Button("Try Again", action: onRetry)
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                }
            } else if let outputURL {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isError ? Color.red.opacity(0.06) : Color.green.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isError ? Color.red.opacity(0.2) : Color.green.opacity(0.2), lineWidth: 0.5)
                )
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
