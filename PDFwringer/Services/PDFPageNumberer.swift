import AppKit
import CoreGraphics
import CoreText
import Foundation
import PDFKit

/// Adds page numbers to a PDF by creating a new PDF with text overlaid on each page.
/// Uses PDFPage.draw to preserve vector content, then overlays text via CoreText.
@MainActor
struct PDFPageNumberer {

    enum Position: String, CaseIterable, Identifiable {
        case bottomCenter
        case bottomLeft
        case bottomRight
        case topCenter
        case topLeft
        case topRight

        var id: String { rawValue }

        var title: String {
            switch self {
            case .bottomCenter: String(localized: "Bottom Center")
            case .bottomLeft: String(localized: "Bottom Left")
            case .bottomRight: String(localized: "Bottom Right")
            case .topCenter: String(localized: "Top Center")
            case .topLeft: String(localized: "Top Left")
            case .topRight: String(localized: "Top Right")
            }
        }
    }

    struct Options {
        var position: Position = .bottomCenter
        var startNumber: Int = 1
        var fontSize: CGFloat = 11
        var margin: CGFloat = 36 // 0.5 inch
        var prefix: String = ""
        var suffix: String = ""
        var color: NSColor = .black
    }

    func addPageNumbers(
        source: URL,
        destination: URL,
        options: Options,
        pageIndices: [Int]?,
        progress: (Double) -> Void
    ) async throws {
        guard source.standardizedFileURL != destination.standardizedFileURL else {
            throw PDFwringerError.sourceEqualsDestination
        }

        guard FileManager.default.isReadableFile(atPath: source.path(percentEncoded: false)) else {
            throw PDFwringerError.fileNotReadable(source.lastPathComponent)
        }

        guard let doc = PDFDocument(url: source) else {
            throw PDFwringerError.cannotOpenDocument
        }
        if doc.isLocked { throw PDFwringerError.documentIsLocked }

        let pageCount = doc.pageCount
        guard pageCount > 0 else { throw PDFwringerError.cannotOpenDocument }

        let start = ContinuousClock.now

        let indicesToNumber: Set<Int>
        if let indices = pageIndices {
            indicesToNumber = Set(indices)
        } else {
            indicesToNumber = Set(0..<pageCount)
        }

        let sortedIndices = indicesToNumber.sorted()

        // Create output PDF
        let tempURL = AtomicFileWriter.tempDirectory.appending(component: UUID().uuidString + ".pdf")
        var emptyBox = CGRect.zero
        guard let ctx = CGContext(tempURL as CFURL, mediaBox: &emptyBox, nil) else {
            throw PDFwringerError.cannotCreateOutput
        }

        for i in 0..<pageCount {
            try Task.checkCancellation()

            guard let page = doc.page(at: i) else { continue }

            // Get page dimensions accounting for rotation
            let cropBox = page.bounds(for: .cropBox)
            let rotation = page.rotation
            let displayWidth: CGFloat
            let displayHeight: CGFloat
            if rotation == 90 || rotation == 270 {
                displayWidth = cropBox.height
                displayHeight = cropBox.width
            } else {
                displayWidth = cropBox.width
                displayHeight = cropBox.height
            }

            // Output page uses display dimensions (post-rotation)
            var pageBox = CGRect(x: 0, y: 0, width: displayWidth, height: displayHeight)
            ctx.beginPage(mediaBox: &pageBox)

            // Draw the original page content
            ctx.saveGState()
            // page.transform sets up the correct coordinate mapping for the page's rotation and box
            page.transform(ctx, for: .cropBox)
            page.draw(with: .cropBox, to: ctx)
            ctx.restoreGState()

            // Overlay page number in the output coordinate space (0,0 = bottom-left, width×height = top-right)
            if indicesToNumber.contains(i) {
                let displayNumber = options.startNumber + (sortedIndices.firstIndex(of: i) ?? 0)
                let text = "\(options.prefix)\(displayNumber)\(options.suffix)"
                drawNumber(text: text, pageWidth: displayWidth, pageHeight: displayHeight, context: ctx, options: options)
            }

            ctx.endPage()
            progress(Double(i + 1) / Double(pageCount))
            await Task.yield()
        }

        ctx.closePDF()

        try AtomicFileWriter.write(to: destination) { destTemp in
            try FileManager.default.moveItem(at: tempURL, to: destTemp)
            return true
        }

        let elapsed = ContinuousClock.now - start
        Log.app.info("Page numbers added: \(indicesToNumber.count) pages, duration=\(elapsed)")
    }

    private func drawNumber(text: String, pageWidth: CGFloat, pageHeight: CGFloat, context: CGContext, options: Options) {
        let font = NSFont(name: "Helvetica", size: options.fontSize) ?? NSFont.systemFont(ofSize: options.fontSize)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: options.color
        ]
        let attrString = NSAttributedString(string: text, attributes: attrs)
        let textSize = attrString.size()

        // Calculate position in the output coordinate space
        let margin = options.margin
        let x: CGFloat
        let y: CGFloat

        switch options.position {
        case .bottomLeft:
            x = margin
            y = margin
        case .bottomCenter:
            x = (pageWidth - textSize.width) / 2
            y = margin
        case .bottomRight:
            x = pageWidth - margin - textSize.width
            y = margin
        case .topLeft:
            x = margin
            y = pageHeight - margin - textSize.height
        case .topCenter:
            x = (pageWidth - textSize.width) / 2
            y = pageHeight - margin - textSize.height
        case .topRight:
            x = pageWidth - margin - textSize.width
            y = pageHeight - margin - textSize.height
        }

        // Draw using NSAttributedString in an NSGraphicsContext (reliable for PDF contexts)
        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext
        attrString.draw(at: NSPoint(x: x, y: y))
        NSGraphicsContext.restoreGraphicsState()
    }
}
