import SwiftUI

struct LandingView: View {
    let onFilesSelected: ([URL]) -> Void

    @State private var isDropTargeted = false
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 56, weight: .thin))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.pulse, options: .repeating.speed(0.3), value: isDropTargeted)

                VStack(spacing: 6) {
                    Text("Drop PDF files here")
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.primary)

                    Text("or click to select")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }

                Button(action: selectFiles) {
                    Label("Select Files...", systemImage: "folder")
                        .font(.body.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .opacity(isDropTargeted ? 1 : 0.6)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                isDropTargeted ? Color.accentColor : Color.clear,
                                lineWidth: 2
                            )
                    }
            }
            .padding(24)
            .overlay {
                DropReceiverView(isTargeted: $isDropTargeted) { urls in
                    onFilesSelected(urls)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isDropTargeted)

            Spacer()
        }
    }

    private func selectFiles() {
        guard let urls = FileDialogHelper.showOpenPanel(allowsMultiple: true) else { return }
        onFilesSelected(urls)
    }
}
