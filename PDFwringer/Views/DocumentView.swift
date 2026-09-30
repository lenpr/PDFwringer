import SwiftUI
import PDFKit

struct DocumentView: View {
    let url: URL
    let document: PDFDocument
    let fileSize: Int64
    let onMerge: () -> Void
    let onCompress: () -> Void
    let onSplit: () -> Void
    let onRotate: () -> Void
    let onMetadata: () -> Void
    let onCrop: () -> Void
    let onAdjustColor: () -> Void
    let onExportImages: () -> Void
    let onReorderPages: () -> Void
    let onStartOver: () -> Void
    let onFilesDropped: ([URL]) -> Void
    @Binding var currentPage: Int

    @State private var isDropTargeted = false


    var body: some View {
        HSplitView {
            // Left: PDF preview + thumbnails
            VStack(spacing: 0) {
                PDFPreviewPanel(document: document, currentPage: $currentPage)

                PageThumbnailStripView(document: document, currentPage: $currentPage)
                    .padding(.horizontal, 20)
            }
            .frame(minWidth: 260, idealWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                DropReceiverView(isTargeted: $isDropTargeted) { urls in
                    onFilesDropped(urls)
                }
            }

            // Right: File info + action cards
            VStack(spacing: 0) {
                OptionsHeaderView(url: url, onBack: onStartOver,
                                  backTitle: String(localized: "Close File"),
                                  backHelp: String(localized: "Close this file and choose another"))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(String(localized: "Choose a Tool"))
                                .font(.title3.weight(.semibold))
                            Spacer()
                            Text("\(document.pageCount) pages • \(Formatting.fileSize(fileSize))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                            icon: "doc.on.doc",
                            title: String(localized: "Merge PDFs"),
                            description: String(localized: "Add more PDFs and combine them into one copy"),
                            action: onMerge
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
                            description: String(localized: "Edit document details and password protection"),
                            action: onMetadata
                        )
                    }
                    .padding(24)
                }
            }
            .frame(minWidth: 300, idealWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
