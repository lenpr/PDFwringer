import AppKit
import CoreGraphics
import Foundation
import PDFKit

/// Adds page numbers to a PDF by overlaying text onto each page via CGContext.
/// Produces a new PDF where numbers are burned into page content (not annotations).
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
        Log.app.info("Adding page numbers: \(pageCount) pages, position=\(options.position.rawValue)")

        let indicesToNumber: Set<Int>
        if let indices = pageIndices {
            indicesToNumber = Set(indices)
        } else {
            indicesToNumber = Set(0..<pageCount)
        }

        // Build output PDF with page numbers overlaid via CGContext
        let tempURL = AtomicFileWriter.tempDirectory.appending(component: UUID().uuidString + ".pdf")
        var emptyBox = CGRect.zero
        guard let outputCtx = CGContext(tempURL as CFURL, mediaBox: &emptyBox, nil) else {
            throw PDFwringerError.cannotCreateOutput
        }

        let sortedIndices = indicesToNumber.sorted()

        for i in 0..<pageCount {
            try Task.checkCancellation()

            guard let page = doc.page(at: i) else { continue }

            // Use cropBox (what the user sees) normalized to origin (0,0)
            let cropBox = page.bounds(for: .cropBox)
            var pageBox = CGRect(origin: .zero, size: cropBox.size)

            outputCtx.beginPage(mediaBox: &pageBox)

            // Draw the original page content mapped into our normalized box
            if let cgPage = page.pageRef {
                outputCtx.saveGState()
                let transform = cgPage.getDrawingTransform(.cropBox, rect: pageBox, rotate: 0, preserveAspectRatio: true)
                outputCtx.concatenate(transform)
                outputCtx.drawPDFPage(cgPage)
                outputCtx.restoreGState()
            }

            // Overlay page number — coordinates are now (0,0) to (width,height) matching the visible page
            if indicesToNumber.contains(i) {
                let displayNumber = options.startNumber + (sortedIndices.firstIndex(of: i) ?? 0)
                let text = "\(options.prefix)\(displayNumber)\(options.suffix)"
                drawPageNumber(text: text, in: pageBox, context: outputCtx, options: options)
            }

            outputCtx.endPage()
            progress(Double(i + 1) / Double(pageCount))
            await Task.yield()
        }

        outputCtx.closePDF()

        try AtomicFileWriter.write(to: destination) { destTemp in
            try FileManager.default.moveItem(at: tempURL, to: destTemp)
            return true
        }

        let elapsed = ContinuousClock.now - start
        Log.app.info("Page numbers added: \(indicesToNumber.count) pages numbered, duration=\(elapsed)")
    }

    private func drawPageNumber(text: String, in bounds: CGRect, context: CGContext, options: Options) {
        let font = CTFontCreateWithName("Helvetica" as CFString, options.fontSize, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: options.color
        ]

        let attrString = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attrString)
        let textBounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        let textWidth = textBounds.width
        let textHeight = textBounds.height

        let point = calculatePosition(
            bounds: bounds,
            textSize: CGSize(width: textWidth, height: textHeight),
            position: options.position,
            margin: options.margin
        )

        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: point.x, y: point.y)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private func calculatePosition(bounds: CGRect, textSize: CGSize, position: Position, margin: CGFloat) -> CGPoint {
        let x: CGFloat
        let y: CGFloat

        switch position {
        case .bottomLeft:
            x = bounds.minX + margin
            y = bounds.minY + margin
        case .bottomCenter:
            x = bounds.midX - textSize.width / 2
            y = bounds.minY + margin
        case .bottomRight:
            x = bounds.maxX - margin - textSize.width
            y = bounds.minY + margin
        case .topLeft:
            x = bounds.minX + margin
            y = bounds.maxY - margin - textSize.height
        case .topCenter:
            x = bounds.midX - textSize.width / 2
            y = bounds.maxY - margin - textSize.height
        case .topRight:
            x = bounds.maxX - margin - textSize.width
            y = bounds.maxY - margin - textSize.height
        }

        return CGPoint(x: x, y: y)
    }
}
