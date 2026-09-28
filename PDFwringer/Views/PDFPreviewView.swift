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
        context.coordinator.update(pdfView, parent: self)
    }

    static func dismantleNSView(_ pdfView: PDFView, coordinator: Coordinator) {
        coordinator.pendingNavigation?.cancel()
        coordinator.pendingNavigation = nil
        NotificationCenter.default.removeObserver(coordinator)
        if coordinator.parent.proxy?.pdfView === pdfView {
            coordinator.parent.proxy?.pdfView = nil
        }
        pdfView.document = nil
    }

    @MainActor
    class Coordinator: NSObject {
        var parent: PDFPreviewView
        var lastGeneration = 0
        var pendingNavigation: DispatchWorkItem?
        weak var overlay: NSView?
        private var isUpdating = false

        init(parent: PDFPreviewView) {
            self.parent = parent
        }

        /// Refresh bindings on every SwiftUI update and supersede queued navigation,
        /// including when the latest request is already the visible page.
        func update(_ pdfView: PDFView, parent: PDFPreviewView) {
            self.parent = parent
            pendingNavigation?.cancel()
            pendingNavigation = nil
            let document = parent.document
            let generation = parent.generation
            let currentPage = parent.currentPage
            isUpdating = true
            defer { isUpdating = false }
            if pdfView.document !== document || lastGeneration != generation {
                pdfView.document = document
                lastGeneration = generation
                pdfView.autoScales = true
                pdfView.layoutDocumentView()
            }

            parent.proxy?.pdfView = pdfView

            let currentIndex: Int? = {
                guard let page = pdfView.currentPage else { return nil }
                return pdfView.document?.index(for: page)
            }()

            if currentIndex != currentPage,
               let page = document.page(at: currentPage) {
                let item = DispatchWorkItem { [weak pdfView] in
                    guard let pdfView, pdfView.document === document else { return }
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    pdfView.go(to: page)
                    pdfView.autoScales = true
                    CATransaction.commit()
                }
                pendingNavigation = item
                DispatchQueue.main.async(execute: item)
            }

            if let overlay = overlay {
                overlay.frame = pdfView.bounds
                overlay.needsDisplay = true
            }
        }

        @objc func pageChanged(_ notification: Notification) {
            guard !isUpdating,
                  let pdfView = notification.object as? PDFView,
                  pdfView.document === parent.document,
                  let page = pdfView.currentPage else { return }
            let index = parent.document.index(for: page)
            guard (0..<parent.document.pageCount).contains(index) else { return }
            if parent.currentPage != index {
                parent.currentPage = index
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
