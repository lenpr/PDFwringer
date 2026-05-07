import SwiftUI
import PDFKit

// MARK: - Crop Overlay NSView

class CropOverlayView: NSView {
    weak var pdfView: PDFView?
    var cropInsets: NSEdgeInsets = NSEdgeInsets()
    var resizeTarget: CGSize? = nil
    var currentPageIndex: Int = 0

    private static let coralColor = NSColor(red: 0.91, green: 0.39, blue: 0.30, alpha: 1.0)

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let pdfView, let document = pdfView.document,
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

        if cropInsets.top > 0 {
            let stripPage = CGRect(x: pageBounds.minX, y: pageBounds.maxY - cropInsets.top, width: pageBounds.width, height: cropInsets.top)
            let local = convert(pdfView.convert(stripPage, from: page), from: pdfView)
            fillColor.setFill()
            local.fill()
            let linePt = CGRect(x: pageBounds.minX, y: pageBounds.maxY - cropInsets.top, width: pageBounds.width, height: 0)
            let localLine = convert(pdfView.convert(linePt, from: page), from: pdfView)
            drawDashedLine(from: NSPoint(x: localLine.minX, y: localLine.midY), to: NSPoint(x: localLine.maxX, y: localLine.midY), color: lineColor)
        }

        if cropInsets.bottom > 0 {
            let stripPage = CGRect(x: pageBounds.minX, y: pageBounds.minY, width: pageBounds.width, height: cropInsets.bottom)
            let local = convert(pdfView.convert(stripPage, from: page), from: pdfView)
            fillColor.setFill()
            local.fill()
            let linePt = CGRect(x: pageBounds.minX, y: pageBounds.minY + cropInsets.bottom, width: pageBounds.width, height: 0)
            let localLine = convert(pdfView.convert(linePt, from: page), from: pdfView)
            drawDashedLine(from: NSPoint(x: localLine.minX, y: localLine.midY), to: NSPoint(x: localLine.maxX, y: localLine.midY), color: lineColor)
        }

        if cropInsets.left > 0 {
            let stripPage = CGRect(x: pageBounds.minX, y: pageBounds.minY, width: cropInsets.left, height: pageBounds.height)
            let local = convert(pdfView.convert(stripPage, from: page), from: pdfView)
            fillColor.setFill()
            local.fill()
            let linePt = CGRect(x: pageBounds.minX + cropInsets.left, y: pageBounds.minY, width: 0, height: pageBounds.height)
            let localLine = convert(pdfView.convert(linePt, from: page), from: pdfView)
            drawDashedLine(from: NSPoint(x: localLine.midX, y: localLine.minY), to: NSPoint(x: localLine.midX, y: localLine.maxY), color: lineColor)
        }

        if cropInsets.right > 0 {
            let stripPage = CGRect(x: pageBounds.maxX - cropInsets.right, y: pageBounds.minY, width: cropInsets.right, height: pageBounds.height)
            let local = convert(pdfView.convert(stripPage, from: page), from: pdfView)
            fillColor.setFill()
            local.fill()
            let linePt = CGRect(x: pageBounds.maxX - cropInsets.right, y: pageBounds.minY, width: 0, height: pageBounds.height)
            let localLine = convert(pdfView.convert(linePt, from: page), from: pdfView)
            drawDashedLine(from: NSPoint(x: localLine.midX, y: localLine.minY), to: NSPoint(x: localLine.midX, y: localLine.maxY), color: lineColor)
        }
    }

    private func drawResizeOverlay(pdfView: PDFView, page: PDFPage, pageBounds: CGRect, targetSize: CGSize) {
        let lineColor = Self.coralColor.withAlphaComponent(0.7)
        let centeredRect = CGRect(
            x: pageBounds.midX - targetSize.width / 2,
            y: pageBounds.midY - targetSize.height / 2,
            width: targetSize.width,
            height: targetSize.height
        )
        let localRect = convert(pdfView.convert(centeredRect, from: page), from: pdfView)
        let path = NSBezierPath(rect: localRect)
        path.lineWidth = 1.5
        let pattern: [CGFloat] = [6, 4]
        path.setLineDash(pattern, count: 2, phase: 0)
        lineColor.setStroke()
        path.stroke()
    }

    private func drawDashedLine(from start: NSPoint, to end: NSPoint, color: NSColor) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = 1.5
        let pattern: [CGFloat] = [4, 3]
        path.setLineDash(pattern, count: 2, phase: 0)
        color.setStroke()
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
