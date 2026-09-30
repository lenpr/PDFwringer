import SwiftUI
import PDFKit
import QuartzCore

struct PDFPreviewView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var currentPage: Int
    var generation: Int = 0
    var proxy: PDFViewProxy?
    var overlayProvider: (() -> NSView)? = nil
    var preserveViewport = false

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
        coordinator.pendingViewport = nil
        coordinator.navigationGeneration += 1
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
        var pendingViewport: PDFPreviewViewport?
        var navigationGeneration = 0
        weak var overlay: NSView?
        private var isUpdating = false

        init(parent: PDFPreviewView) {
            self.parent = parent
        }

        /// Refresh bindings on every SwiftUI update and supersede queued navigation,
        /// including when the latest request is already the visible page.
        func update(_ pdfView: PDFView, parent: PDFPreviewView) {
            navigationGeneration += 1
            let navigationGeneration = self.navigationGeneration
            let replacingDocument = pdfView.document !== parent.document
            var viewport = parent.preserveViewport
                ? (pendingViewport ?? (replacingDocument ? PDFPreviewViewport.capture(pdfView) : nil)) : nil
            if viewport?.pageIndex != parent.currentPage { viewport = nil }
            self.parent = parent
            pendingNavigation?.cancel()
            pendingNavigation = nil
            pendingViewport = nil
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

            if currentIndex != currentPage || viewport != nil,
               let page = document.page(at: currentPage) {
                let preservedViewport = viewport
                let item = DispatchWorkItem { [weak self, weak pdfView] in
                    guard let self, let pdfView, pdfView.document === document,
                          self.navigationGeneration == navigationGeneration,
                          self.parent.document === document, self.parent.currentPage == currentPage else { return }
                    self.isUpdating = true
                    defer {
                        self.isUpdating = false
                        self.pendingNavigation = nil
                        self.pendingViewport = nil
                    }
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    pdfView.go(to: page)
                    if let preservedViewport {
                        preservedViewport.restore(in: pdfView, page: page)
                    } else if !self.parent.preserveViewport {
                        pdfView.autoScales = true
                    }
                    CATransaction.commit()
                }
                pendingViewport = viewport
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
    var preserveViewport = false

    @State private var proxy = PDFViewProxy()

    var body: some View {
        PDFPreviewView(
            document: document,
            currentPage: $currentPage,
            generation: generation,
            proxy: proxy,
            overlayProvider: overlayProvider,
            preserveViewport: preserveViewport
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color(nsColor: .shadowColor).opacity(0.15), radius: 8, y: 2)
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 4) {
                Button { proxy.zoomOut() } label: {
                    Image(systemName: "minus.magnifyingglass")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(String(localized: "Zoom out"))
                .help(String(localized: "Zoom out"))
                Button { proxy.fitToView() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(String(localized: "Fit to view"))
                .help(String(localized: "Fit to view"))
                Button { proxy.zoomIn() } label: {
                    Image(systemName: "plus.magnifyingglass")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(String(localized: "Zoom in"))
                .help(String(localized: "Zoom in"))
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

/// Value-only viewport: PDFDestination and PDFPage never belong to two documents.
struct PDFPreviewViewport {
    let pageIndex: Int
    let normalizedPoint: CGPoint
    let relativeZoom: CGFloat
    let fitsToView: Bool

    @MainActor
    static func capture(_ view: PDFView) -> Self? {
        guard let document = view.document, let destination = view.currentDestination,
              let page = destination.page,
              let point = normalized(destination.point, on: page),
              view.scaleFactorForSizeToFit > 0 else { return nil }
        let zoom = view.scaleFactor / view.scaleFactorForSizeToFit
        guard zoom.isFinite, zoom > 0 else { return nil }
        return Self(pageIndex: document.index(for: page), normalizedPoint: point,
                    relativeZoom: zoom, fitsToView: view.autoScales)
    }

    @MainActor
    func restore(in view: PDFView, page: PDFPage) {
        view.autoScales = fitsToView
        view.layoutDocumentView()
        guard !fitsToView, let point = Self.pagePoint(normalizedPoint, on: page) else { return }
        let scale = view.scaleFactorForSizeToFit * relativeZoom
        guard scale.isFinite, scale > 0 else { return }
        view.scaleFactor = scale
        let destination = PDFDestination(page: page, at: point)
        destination.zoom = view.scaleFactor
        view.go(to: destination)
    }

    @MainActor
    static func normalized(_ point: CGPoint, on page: PDFPage) -> CGPoint? {
        let bounds = page.bounds(for: .cropBox)
        guard valid(bounds), point.x.isFinite, point.y.isFinite,
              point.x != kPDFDestinationUnspecifiedValue,
              point.y != kPDFDestinationUnspecifiedValue else { return nil }
        let x = (point.x - bounds.minX) / bounds.width
        let y = (point.y - bounds.minY) / bounds.height
        switch rotation(page) {
        case 90: return CGPoint(x: y, y: 1 - x)
        case 180: return CGPoint(x: 1 - x, y: 1 - y)
        case 270: return CGPoint(x: 1 - y, y: x)
        default: return CGPoint(x: x, y: y)
        }
    }

    @MainActor
    static func pagePoint(_ point: CGPoint, on page: PDFPage) -> CGPoint? {
        let bounds = page.bounds(for: .cropBox)
        guard valid(bounds), point.x.isFinite, point.y.isFinite else { return nil }
        let unrotated: CGPoint
        switch rotation(page) {
        case 90: unrotated = CGPoint(x: 1 - point.y, y: point.x)
        case 180: unrotated = CGPoint(x: 1 - point.x, y: 1 - point.y)
        case 270: unrotated = CGPoint(x: point.y, y: 1 - point.x)
        default: unrotated = point
        }
        return CGPoint(x: bounds.minX + unrotated.x * bounds.width,
                       y: bounds.minY + unrotated.y * bounds.height)
    }

    @MainActor
    private static func rotation(_ page: PDFPage) -> Int { ((page.rotation % 360) + 360) % 360 }

    private static func valid(_ bounds: CGRect) -> Bool {
        bounds.minX.isFinite && bounds.minY.isFinite && bounds.width.isFinite && bounds.height.isFinite
            && bounds.width > 0 && bounds.height > 0
    }
}
