import SwiftUI
import PDFKit

// MARK: - Crop Overlay NSView

class CropOverlayView: NSView {
    var cropInsets: NSEdgeInsets = NSEdgeInsets()
    var resizeTarget: CGSize? = nil
    var currentPageIndex: Int = 0

    private static let coralColor = NSColor(red: 0.91, green: 0.39, blue: 0.30, alpha: 1.0)

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let pdfView = superview as? PDFView,
              let document = pdfView.document,
              let page = document.page(at: currentPageIndex) else { return }

        let pageBounds = page.bounds(for: .cropBox)

        let hasCrop = cropInsets.top > 0 || cropInsets.bottom > 0 || cropInsets.left > 0 || cropInsets.right > 0

        if hasCrop {
            drawCropOverlay(pdfView: pdfView, page: page, pageBounds: pageBounds)
        }

        if let target = resizeTarget {
            drawResizeOverlay(pdfView: pdfView, page: page, pageBounds: pageBounds, targetSize: target)
        }
    }

    private func drawCropOverlay(pdfView: PDFView, page: PDFPage, pageBounds: CGRect) {
        let fillColor = Self.coralColor.withAlphaComponent(0.15)
        let lineColor = Self.coralColor.withAlphaComponent(0.8)
        let croppedBounds = PDFCropGeometry.cropBounds(
            in: pageBounds,
            rotation: page.rotation,
            top: cropInsets.top,
            bottom: cropInsets.bottom,
            left: cropInsets.left,
            right: cropInsets.right
        )
        guard croppedBounds.width > 0, croppedBounds.height > 0 else { return }

        let localPageBounds = convert(pdfView.convert(pageBounds, from: page), from: pdfView).standardized
        let localCropBounds = convert(pdfView.convert(croppedBounds, from: page), from: pdfView).standardized
        let fillPath = NSBezierPath(rect: localPageBounds)
        fillPath.appendRect(localCropBounds)
        fillPath.windingRule = .evenOdd
        fillColor.setFill()
        fillPath.fill()

        let cropPath = NSBezierPath(rect: localCropBounds)
        cropPath.lineWidth = 1.5
        cropPath.setLineDash([4, 3], count: 2, phase: 0)
        lineColor.setStroke()
        cropPath.stroke()
    }

    private func drawResizeOverlay(pdfView: PDFView, page: PDFPage, pageBounds: CGRect, targetSize: CGSize) {
        let lineColor = Self.coralColor.withAlphaComponent(0.7)
        let targetBounds = PDFCropGeometry.resizeBounds(
            in: pageBounds,
            rotation: page.rotation,
            displayTargetSize: targetSize
        )
        let localRect = convert(pdfView.convert(targetBounds, from: page), from: pdfView).standardized
        let path = NSBezierPath(rect: localRect)
        path.lineWidth = 1.5
        let pattern: [CGFloat] = [6, 4]
        path.setLineDash(pattern, count: 2, phase: 0)
        lineColor.setStroke()
        path.stroke()
    }

}

// MARK: - Crop Preview Panel

struct CropPreviewPanel: View {
    let document: PDFDocument
    @Binding var currentPage: Int
    var generation: Int = 0
    var cropInsets: NSEdgeInsets
    var resizeTarget: CGSize?

    @State private var overlay = CropOverlayView()

    var body: some View {
        PDFPreviewPanel(
            document: document,
            currentPage: $currentPage,
            generation: generation,
            overlayProvider: { [overlay] in
                overlay
            }
        )
        .onAppear { updateOverlay() }
        .onChange(of: cropInsets.top) { updateOverlay() }
        .onChange(of: cropInsets.bottom) { updateOverlay() }
        .onChange(of: cropInsets.left) { updateOverlay() }
        .onChange(of: cropInsets.right) { updateOverlay() }
        .onChange(of: resizeTarget?.width) { updateOverlay() }
        .onChange(of: resizeTarget?.height) { updateOverlay() }
        .onChange(of: currentPage) { updateOverlay() }
    }

    private func updateOverlay() {
        overlay.cropInsets = cropInsets
        overlay.resizeTarget = resizeTarget
        overlay.currentPageIndex = currentPage
        overlay.needsDisplay = true
    }
}
