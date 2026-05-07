import SwiftUI

struct OptionsHeaderView: View {
    let url: URL
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Label("Back", systemImage: "chevron.left")
                    .font(.caption.weight(.medium))
            }
            .keyboardShortcut(.escape, modifiers: [])
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .padding(.vertical, 4)
            .padding(.horizontal, 2)

            Spacer()

            Text(url.lastPathComponent)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
