import SwiftUI

struct OptionsHeaderView: View {
    let url: URL
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Label("Back", systemImage: "chevron.left")
                    .font(.caption.weight(.medium))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
            }
            .keyboardShortcut(.escape, modifiers: [])
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())

            Spacer()

            Text(url.lastPathComponent)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
