import AppKit
import CoreGraphics
import CoreText
import Foundation
import PDFKit

/// Adds page numbers to a PDF using custom annotations with explicit appearance rendering.
/// The annotations draw themselves in the correct page coordinate space via PDFKit.
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

        for i in 0..<pageCount {
            try Task.checkCancellation()

            if indicesToNumber.contains(i), let page = doc.page(at: i) {
                let displayNumber = options.startNumber + (sortedIndices.firstIndex(of: i) ?? 0)
                let text = "\(options.prefix)\(displayNumber)\(options.suffix)"
                addNumberToPage(page, text: text, options: options)
            }

            progress(Double(i + 1) / Double(pageCount))
        }

        try AtomicFileWriter.write(to: destination) { tempURL in
            doc.write(to: tempURL)
        }

        let elapsed = ContinuousClock.now - start
        Log.app.info("Page numbers added: \(indicesToNumber.count) pages, duration=\(elapsed)")
    }

    private func addNumberToPage(_ page: PDFPage, text: String, options: Options) {
        let font = NSFont(name: "Helvetica", size: options.fontSize) ?? NSFont.systemFont(ofSize: options.fontSize)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: options.color
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)

        let pageBounds = page.bounds(for: .cropBox)
        let annotRect = calculateRect(
            pageBounds: pageBounds,
            textSize: textSize,
            position: options.position,
            margin: options.margin
        )

        let annotation = PageNumberAnnotation(
            bounds: annotRect,
            text: text,
            font: font,
            color: options.color
        )
        page.addAnnotation(annotation)
    }

    private func calculateRect(pageBounds: CGRect, textSize: CGSize, position: Position, margin: CGFloat) -> CGRect {
        // Add padding around text
        let padding: CGFloat = 2
        let width = textSize.width + padding * 2
        let height = textSize.height + padding * 2

        let x: CGFloat
        let y: CGFloat

        switch position {
        case .bottomLeft:
            x = pageBounds.minX + margin
            y = pageBounds.minY + margin
        case .bottomCenter:
            x = pageBounds.midX - width / 2
            y = pageBounds.minY + margin
        case .bottomRight:
            x = pageBounds.maxX - margin - width
            y = pageBounds.minY + margin
        case .topLeft:
            x = pageBounds.minX + margin
            y = pageBounds.maxY - margin - height
        case .topCenter:
            x = pageBounds.midX - width / 2
            y = pageBounds.maxY - margin - height
        case .topRight:
            x = pageBounds.maxX - margin - width
            y = pageBounds.maxY - margin - height
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// Custom annotation that draws page number text with a proper appearance stream.
/// PDFKit calls draw(with:in:) during serialization to generate the appearance.
final class PageNumberAnnotation: PDFAnnotation {
    private let text: String
    private let numberFont: NSFont
    private let textColor: NSColor

    init(bounds: CGRect, text: String, font: NSFont, color: NSColor) {
        self.text = text
        self.numberFont = font
        self.textColor = color
        super.init(bounds: bounds, forType: .freeText, withProperties: nil)
        // Transparent background — no visible box
        self.color = .clear
        self.font = font
        self.fontColor = color
        self.contents = text
        self.alignment = .center
        // Critical: disable border
        let border = PDFBorder()
        border.lineWidth = 0
        self.border = border
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        // Draw text at the annotation's bounds origin
        let attrs: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: textColor
        ]
        let attrString = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attrString)

        context.saveGState()
        context.textMatrix = .identity
        // Position text within the annotation bounds (with small padding)
        context.textPosition = CGPoint(x: bounds.origin.x + 2, y: bounds.origin.y + 2)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
