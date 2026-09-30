import SwiftUI

struct LandingView: View {
    let onFilesSelected: ([URL]) -> Void

    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 56, weight: .thin))
                    .foregroundStyle(Color.coral)

                VStack(spacing: 6) {
                    Text(String(localized: "Drop PDF files here"))
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.primary)

                    Text(String(localized: "Choose files or press \u{2318}O"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Button(action: selectFiles) {
                    Label(String(localized: "Select Files..."), systemImage: "folder")
                        .font(.body.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(.coral)
                .controlSize(.large)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "Drop zone for PDF files"))
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
                                    style: StrokeStyle(lineWidth: 2, dash: [8, 4], dashPhase: 0)
                                )
                                .foregroundStyle(Color.coral)
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


            Spacer()
        }
    }

    private var appIconBackdrop: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 360, height: 360)
            .blur(radius: 4)
            .opacity(0.06)
    }

    private func selectFiles() {
        guard let urls = FileDialogHelper.showOpenPanel(allowsMultiple: true) else { return }
        onFilesSelected(urls)
    }
}
