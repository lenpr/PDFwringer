import SwiftUI

struct LandingView: View {
    let onFilesSelected: ([URL]) -> Void

    @State private var isDropTargeted = false
    @State private var dashPhase: CGFloat = 0

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

                Text("\u{2318}O to open")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)

                Button(action: selectFiles) {
                    Label("Select Files...", systemImage: "folder")
                        .font(.body.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                appIconBackdrop
            }
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .opacity(isDropTargeted ? 1 : 0.6)
                    .overlay {
                        if isDropTargeted {
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(
                                    style: StrokeStyle(lineWidth: 2, dash: [8, 4], dashPhase: dashPhase)
                                )
                                .foregroundStyle(Color.accentColor)
                        }
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(24)
            .overlay {
                DropReceiverView(isTargeted: $isDropTargeted) { urls in
                    onFilesSelected(urls)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isDropTargeted)
            .onChange(of: isDropTargeted) {
                if isDropTargeted {
                    withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                        dashPhase = 12
                    }
                } else {
                    dashPhase = 0
                }
            }

            Spacer()
        }
    }

    private var appIconBackdrop: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 500, height: 500)
            .blur(radius: 4)
            .opacity(0.15)
    }

    private func selectFiles() {
        guard let urls = FileDialogHelper.showOpenPanel(allowsMultiple: true) else { return }
        onFilesSelected(urls)
    }
}
