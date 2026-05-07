import SwiftUI
import PDFKit

struct DocumentView: View {
    let url: URL
    let document: PDFDocument
    let fileSize: Int64
    let onCompress: () -> Void
    let onSplit: () -> Void
    let onRotate: () -> Void
    let onMetadata: () -> Void
    let onCrop: () -> Void
    let onStartOver: () -> Void
    let onFilesDropped: ([URL]) -> Void
    @Binding var currentPage: Int

    @State private var isDropTargeted = false
    @State private var pageCountScale: CGFloat = 1.0

    var body: some View {
        HStack(spacing: 0) {
            // Left: PDF preview + thumbnails
            VStack(spacing: 0) {
                PDFPreviewPanel(document: document, currentPage: $currentPage)

                PageThumbnailStripView(document: document, currentPage: $currentPage)
                    .padding(.horizontal, 20)
            }
            .frame(minWidth: 280, idealWidth: 350)
            .overlay {
                DropReceiverView(isTargeted: $isDropTargeted) { urls in
                    onFilesDropped(urls)
                }
            }

            Divider()

            // Right: File info + action cards
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // File info header
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(url.lastPathComponent)
                                .font(.headline)
                                .lineLimit(1)
                            Text("\(document.pageCount) pages \u{2022} \(Formatting.fileSize(fileSize))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .contentTransition(.numericText())
                                .scaleEffect(pageCountScale)
                                .onAppear {
                                    withAnimation(.spring(duration: 0.3, bounce: 0.5).delay(0.15)) {
                                        pageCountScale = 1.15
                                    }
                                    withAnimation(.spring(duration: 0.3, bounce: 0.3).delay(0.4)) {
                                        pageCountScale = 1.0
                                    }
                                }
                        }
                        Spacer()
                        Button(action: onStartOver) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Start over")
                        .accessibilityLabel("Start over")
                    }

                    Divider()

                    Text("What would you like to do?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ActionCardView(
                        icon: "arrow.down.doc",
                        title: "Compress",
                        description: "Reduce file size with lossless or lossy compression",
                        action: onCompress
                    )

                    ActionCardView(
                        icon: "scissors",
                        title: "Split / Extract",
                        description: "Split into chunks or extract specific pages",
                        action: onSplit
                    )

                    ActionCardView(
                        icon: "rotate.right",
                        title: "Rotate Pages",
                        description: "Rotate all or specific pages by 90°, 180°, or 270°",
                        action: onRotate
                    )

                    ActionCardView(
                        icon: "crop",
                        title: "Crop / Resize",
                        description: "Trim margins or resize pages to standard paper sizes",
                        action: onCrop
                    )

                    ActionCardView(
                        icon: "info.circle",
                        title: "Edit Metadata",
                        description: "View and edit title, author, subject, and keywords",
                        action: onMetadata
                    )
                }
                .padding(24)
            }
            .frame(minWidth: 280, idealWidth: 320)
        }
        .background {
            Group {
                Button("") { onCompress() }
                    .keyboardShortcut("1")
                Button("") { onSplit() }
                    .keyboardShortcut("2")
                Button("") { onRotate() }
                    .keyboardShortcut("3")
                Button("") { onCrop() }
                    .keyboardShortcut("4")
                Button("") { onMetadata() }
                    .keyboardShortcut("5")
            }
            .hidden()
        }
    }
}
