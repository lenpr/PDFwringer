import SwiftUI
import PDFKit

struct DocumentView: View {
    let url: URL
    let document: PDFDocument
    let onCompress: () -> Void
    let onSplit: () -> Void
    let onRotate: () -> Void
    let onMetadata: () -> Void
    let onStartOver: () -> Void
    let onFilesDropped: ([URL]) -> Void

    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            // Left: PDF preview
            VStack(spacing: 0) {
                PDFPreviewView(document: document)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: Color(nsColor: .shadowColor).opacity(0.15), radius: 8, y: 2)
                    .padding(20)
            }
            .frame(minWidth: 280, idealWidth: 350)
            .overlay {
                DropReceiverView(isTargeted: $isDropTargeted) { urls in
                    onFilesDropped(urls)
                }
            }

            // Right: File info + action cards
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // File info header
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(url.lastPathComponent)
                                .font(.headline)
                                .lineLimit(1)
                            Text("\(document.pageCount) pages \u{2022} \(formattedFileSize)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(action: onStartOver) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Start over")
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
    }

    private var formattedFileSize: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)),
              let size = attrs[.size] as? Int64 else { return "" }
        return Formatting.fileSize(size)
    }
}

struct PDFPreviewView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displaysPageBreaks = false
        pdfView.pageShadowsEnabled = false
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }
    }
}
