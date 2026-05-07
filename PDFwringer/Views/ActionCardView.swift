import SwiftUI

struct ActionCardView: View {
    let icon: String
    let title: String
    let description: String
    let action: () -> Void

    private static let iconColor = Color.coral

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Self.iconColor)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? Self.iconColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
                    .shadow(color: Color(nsColor: .shadowColor).opacity(isHovered ? 0.12 : 0.08), radius: isHovered ? 6 : 2, y: isHovered ? 2 : 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isHovered ? Self.iconColor.opacity(0.3) : Color.primary.opacity(0.04), lineWidth: 0.5)
            }
            .offset(y: isHovered ? -1 : 0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .accessibilityLabel("\(title): \(description)")
    }
}
