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
    @Binding var currentPage: Int

    @State private var isDropTargeted = false
    @State private var pageCountScale: CGFloat = 1.0

    var body: some View {
        HStack(spacing: 0) {
            // Left: PDF preview + thumbnails
            VStack(spacing: 0) {
                PDFPreviewView(document: document, currentPage: $currentPage)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: Color(nsColor: .shadowColor).opacity(0.15), radius: 8, y: 2)
                    .padding(20)

                PageThumbnailStripView(document: document, currentPage: $currentPage)
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
        .background {
            Group {
                Button("") { onCompress() }
                    .keyboardShortcut("1")
                Button("") { onSplit() }
                    .keyboardShortcut("2")
                Button("") { onRotate() }
                    .keyboardShortcut("3")
                Button("") { onMetadata() }
                    .keyboardShortcut("4")
            }
            .hidden()
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
    @Binding var currentPage: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displaysPageBreaks = false
        pdfView.pageShadowsEnabled = false

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }

        if let page = document.page(at: currentPage),
           pdfView.currentPage != page {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                pdfView.animator().alphaValue = 0.4
            } completionHandler: {
                pdfView.go(to: page)
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.15
                    pdfView.animator().alphaValue = 1.0
                }
            }
        }
    }

    class Coordinator: NSObject {
        var parent: PDFPreviewView

        init(parent: PDFPreviewView) {
            self.parent = parent
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let page = pdfView.currentPage,
                  let index = pdfView.document?.index(for: page) else { return }
            DispatchQueue.main.async {
                if self.parent.currentPage != index {
                    self.parent.currentPage = index
                }
            }
        }
    }
}
