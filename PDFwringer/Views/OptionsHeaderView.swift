import SwiftUI

struct OptionsHeaderView: View {
    var url: URL? = nil
    let onBack: () -> Void
    var allowsEscapeBack = true

    var body: some View {
        HStack {
            Button(action: onBack) {
                Label(String(localized: "Back"), systemImage: "chevron.left")
                    .font(.caption.weight(.medium))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
            }
            .keyboardShortcut(allowsEscapeBack ? KeyboardShortcut(.escape, modifiers: []) : nil)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())

            Spacer()

            if let url {
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(url.path(percentEncoded: false))
            }
        }
    }
}
