import CoreGraphics
import Foundation
import PDFKit

/// Adds page numbers to a PDF by rendering each page with a number overlay.
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

        for i in 0..<pageCount {
            try Task.checkCancellation()

            if indicesToNumber.contains(i), let page = doc.page(at: i) {
                let displayNumber = options.startNumber + indicesToNumber.sorted().firstIndex(of: i)!
                let text = "\(options.prefix)\(displayNumber)\(options.suffix)"
                addNumberAnnotation(to: page, text: text, options: options)
            }

            progress(Double(i + 1) / Double(pageCount))
        }

        try AtomicFileWriter.write(to: destination) { tempURL in
            doc.write(to: tempURL)
        }

        let elapsed = ContinuousClock.now - start
        Log.app.info("Page numbers added: \(indicesToNumber.count) pages numbered, duration=\(elapsed)")
    }

    private func addNumberAnnotation(to page: PDFPage, text: String, options: Options) {
        let bounds = page.bounds(for: .cropBox)
        let font = NSFont.systemFont(ofSize: options.fontSize)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]

        let textSize = (text as NSString).size(withAttributes: attrs)
        let point = calculatePosition(
            bounds: bounds,
            textSize: textSize,
            position: options.position,
            margin: options.margin
        )

        let annotation = PDFAnnotation(bounds: CGRect(origin: point, size: textSize), forType: .freeText, withProperties: nil)
        annotation.font = font
        annotation.fontColor = .black
        annotation.contents = text
        annotation.color = .clear
        annotation.alignment = .center
        page.addAnnotation(annotation)
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
