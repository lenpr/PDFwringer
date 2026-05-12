import AppKit
import CoreGraphics
import CoreText
import Foundation
import PDFKit

/// Adds a text watermark to PDF pages by overlaying rotated, semi-transparent text.
@MainActor
struct PDFWatermarker {

    struct Options {
        var text: String = "DRAFT"
        var fontSize: CGFloat = 60
        var color: NSColor = .red
        var opacity: CGFloat = 0.3
        var rotation: CGFloat = -45 // degrees
        var position: Position = .center
    }

    enum Position: String, CaseIterable, Identifiable {
        case center
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight

        var id: String { rawValue }

        var title: String {
            switch self {
            case .center: String(localized: "Center")
            case .topLeft: String(localized: "Top Left")
            case .topRight: String(localized: "Top Right")
            case .bottomLeft: String(localized: "Bottom Left")
            case .bottomRight: String(localized: "Bottom Right")
            }
        }
    }

    func addWatermark(
        source: URL,
        destination: URL,
        options: Options,
        pageIndices: [Int]?,
        progress: (Double) -> Void
    ) async throws {
        guard !options.text.isEmpty else { return }

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

        let indicesToMark: Set<Int>
        if let indices = pageIndices {
            indicesToMark = Set(indices)
        } else {
            indicesToMark = Set(0..<pageCount)
        }

        // Create output PDF
        let tempURL = AtomicFileWriter.tempDirectory.appending(component: UUID().uuidString + ".pdf")
        var emptyBox = CGRect.zero
        guard let ctx = CGContext(tempURL as CFURL, mediaBox: &emptyBox, nil) else {
            throw PDFwringerError.cannotCreateOutput
        }

        for i in 0..<pageCount {
            try Task.checkCancellation()

            guard let page = doc.page(at: i) else { continue }

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

            var pageBox = CGRect(x: 0, y: 0, width: displayWidth, height: displayHeight)
            ctx.beginPage(mediaBox: &pageBox)

            // Draw the original page
            ctx.saveGState()
            page.transform(ctx, for: .cropBox)
            page.draw(with: .cropBox, to: ctx)
            ctx.restoreGState()

            // Overlay watermark
            if indicesToMark.contains(i) {
                drawWatermark(pageWidth: displayWidth, pageHeight: displayHeight, context: ctx, options: options)
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
        Log.app.info("Watermark added: \(indicesToMark.count) pages, duration=\(elapsed)")
    }

    private func drawWatermark(pageWidth: CGFloat, pageHeight: CGFloat, context: CGContext, options: Options) {
        let font = NSFont(name: "Helvetica-Bold", size: options.fontSize) ?? NSFont.boldSystemFont(ofSize: options.fontSize)
        let colorWithOpacity = options.color.withAlphaComponent(options.opacity)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: colorWithOpacity
        ]
        let attrString = NSAttributedString(string: options.text, attributes: attrs)
        let textSize = attrString.size()

        // Calculate center position based on option
        let centerX: CGFloat
        let centerY: CGFloat
        let margin: CGFloat = 60

        switch options.position {
        case .center:
            centerX = pageWidth / 2
            centerY = pageHeight / 2
        case .topLeft:
            centerX = margin + textSize.width / 2
            centerY = pageHeight - margin - textSize.height / 2
        case .topRight:
            centerX = pageWidth - margin - textSize.width / 2
            centerY = pageHeight - margin - textSize.height / 2
        case .bottomLeft:
            centerX = margin + textSize.width / 2
            centerY = margin + textSize.height / 2
        case .bottomRight:
            centerX = pageWidth - margin - textSize.width / 2
            centerY = margin + textSize.height / 2
        }

        // Draw rotated text
        context.saveGState()
        context.translateBy(x: centerX, y: centerY)
        context.rotate(by: options.rotation * .pi / 180)

        // Draw using NSAttributedString
        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext
        attrString.draw(at: NSPoint(x: -textSize.width / 2, y: -textSize.height / 2))
        NSGraphicsContext.restoreGraphicsState()

        context.restoreGState()
    }
}
