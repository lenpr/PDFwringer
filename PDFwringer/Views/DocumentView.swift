import SwiftUI
import PDFKit
import QuartzCore

struct DocumentView: View {
    let url: URL
    let document: PDFDocument
    let fileSize: Int64
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
}

struct PDFPreviewView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var currentPage: Int
    var generation: Int = 0
    var proxy: PDFViewProxy?

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
        pdfView.displayDirection = .vertical

        proxy?.pdfView = pdfView

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document || context.coordinator.lastGeneration != generation {
            pdfView.document = document
            context.coordinator.lastGeneration = generation
            pdfView.autoScales = true
            pdfView.layoutDocumentView()
        }

        proxy?.pdfView = pdfView

        let currentIndex: Int? = {
            guard let page = pdfView.currentPage else { return nil }
            return pdfView.document?.index(for: page)
        }()

        if currentIndex != currentPage,
           let page = document.page(at: currentPage) {
            context.coordinator.pendingNavigation?.cancel()
            let item = DispatchWorkItem {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                pdfView.go(to: page)
                pdfView.autoScales = true
                CATransaction.commit()
            }
            context.coordinator.pendingNavigation = item
            DispatchQueue.main.async(execute: item)
        }
    }

    class Coordinator: NSObject {
        var parent: PDFPreviewView
        var lastGeneration = 0
        var pendingNavigation: DispatchWorkItem?

        init(parent: PDFPreviewView) {
            self.parent = parent
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let page = pdfView.currentPage,
                  let index = pdfView.document?.index(for: page) else { return }
            Task { @MainActor in
                if self.parent.currentPage != index {
                    self.parent.currentPage = index
                }
            }
        }
    }
}

@MainActor @Observable
class PDFViewProxy {
    weak var pdfView: PDFView?

    func zoomIn() { pdfView?.zoomIn(nil) }
    func zoomOut() { pdfView?.zoomOut(nil) }
    func fitToView() { pdfView?.autoScales = true }
    var canZoomIn: Bool { pdfView?.canZoomIn ?? false }
    var canZoomOut: Bool { pdfView?.canZoomOut ?? false }
}

struct PDFPreviewPanel: View {
    let document: PDFDocument
    @Binding var currentPage: Int
    var generation: Int = 0

    @State private var proxy = PDFViewProxy()

    var body: some View {
        PDFPreviewView(document: document, currentPage: $currentPage, generation: generation, proxy: proxy)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: Color(nsColor: .shadowColor).opacity(0.15), radius: 8, y: 2)
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 4) {
                    Button { proxy.zoomOut() } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    Button { proxy.fitToView() } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    Button { proxy.zoomIn() } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .padding(6)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                .padding(8)
            }
            .padding(20)
    }
}
