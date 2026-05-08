import SwiftUI
import PDFKit
import QuartzCore

struct PDFPreviewView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var currentPage: Int
    var generation: Int = 0
    var proxy: PDFViewProxy?
    var overlayProvider: (() -> NSView)? = nil

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

        if let overlay = overlayProvider?() {
            overlay.autoresizingMask = [.width, .height]
            overlay.frame = pdfView.bounds
            pdfView.addSubview(overlay)
            context.coordinator.overlay = overlay
        }

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.viewChanged(_:)),
            name: .PDFViewScaleChanged,
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

        if let overlay = context.coordinator.overlay {
            overlay.frame = pdfView.bounds
            overlay.needsDisplay = true
        }
    }

    class Coordinator: NSObject {
        var parent: PDFPreviewView
        var lastGeneration = 0
        var pendingNavigation: DispatchWorkItem?
        weak var overlay: NSView?

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

        @objc func viewChanged(_ notification: Notification) {
            overlay?.needsDisplay = true
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
    var overlayProvider: (() -> NSView)? = nil

    @State private var proxy = PDFViewProxy()

    var body: some View {
        PDFPreviewView(
            document: document,
            currentPage: $currentPage,
            generation: generation,
            proxy: proxy,
            overlayProvider: overlayProvider
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color(nsColor: .shadowColor).opacity(0.15), radius: 8, y: 2)
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 4) {
                Button { proxy.zoomOut() } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .accessibilityLabel(String(localized: "Zoom out"))
                Button { proxy.fitToView() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .accessibilityLabel(String(localized: "Fit to view"))
                Button { proxy.zoomIn() } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .accessibilityLabel(String(localized: "Zoom in"))
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
