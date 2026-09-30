import SwiftUI

struct OptionsHeaderView: View {
    var url: URL? = nil
    let onBack: () -> Void
    var allowsEscapeBack = true
    var backTitle = String(localized: "Back")
    var backHelp = String(localized: "Return to tool selection")

    var body: some View {
        HStack {
            Button(action: onBack) {
                Label(backTitle, systemImage: "chevron.left")
                    .font(.body.weight(.medium))
                    .frame(minHeight: 28)
                    .contentShape(Rectangle())
            }
            .keyboardShortcut(allowsEscapeBack ? KeyboardShortcut(.escape, modifiers: []) : nil)
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .help(backHelp)

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
