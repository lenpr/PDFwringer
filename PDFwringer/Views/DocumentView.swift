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
    let onAdjustColor: () -> Void
    let onPageNumbers: () -> Void
    let onExportImages: () -> Void
    let onReorderPages: () -> Void
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
                        .help(String(localized: "Start over"))
                        .accessibilityLabel(String(localized: "Start over"))
                    }

                    Divider()

                    Text(String(localized: "What would you like to do?"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ActionCardView(
                        icon: "arrow.down.doc",
                        title: String(localized: "Compress"),
                        description: String(localized: "Reduce file size with lossless or lossy compression"),
                        action: onCompress
                    )

                    ActionCardView(
                        icon: "scissors",
                        title: String(localized: "Split / Extract"),
                        description: String(localized: "Split into chunks or extract specific pages"),
                        action: onSplit
                    )

                    ActionCardView(
                        icon: "arrow.up.arrow.down",
                        title: String(localized: "Reorder Pages"),
                        description: String(localized: "Drag pages to rearrange their order"),
                        action: onReorderPages
                    )

                    ActionCardView(
                        icon: "rotate.right",
                        title: String(localized: "Rotate Pages"),
                        description: String(localized: "Rotate all or specific pages by 90°, 180°, or 270°"),
                        action: onRotate
                    )

                    ActionCardView(
                        icon: "crop",
                        title: String(localized: "Crop / Resize"),
                        description: String(localized: "Trim margins or resize pages to standard paper sizes"),
                        action: onCrop
                    )

                    ActionCardView(
                        icon: "number",
                        title: String(localized: "Add Page Numbers"),
                        description: String(localized: "Add page numbers at configurable positions"),
                        action: onPageNumbers
                    )

                    ActionCardView(
                        icon: "slider.horizontal.3",
                        title: String(localized: "Adjust Colors"),
                        description: String(localized: "Tweak brightness, contrast, and saturation"),
                        action: onAdjustColor
                    )

                    ActionCardView(
                        icon: "photo.on.rectangle",
                        title: String(localized: "Export as Images"),
                        description: String(localized: "Export pages as JPEG or PNG files"),
                        action: onExportImages
                    )

                    ActionCardView(
                        icon: "info.circle",
                        title: String(localized: "Edit Metadata"),
                        description: String(localized: "View and edit title, author, subject, and keywords"),
                        action: onMetadata
                    )
                }
                .padding(24)
            }
            .frame(minWidth: 280, idealWidth: 320)
        }
    }
}
