import Foundation
import PDFKit

/// Generates simple multi-page PDFs in a temp directory for use in tests.
enum TestPDFGenerator {

    /// Creates a PDF with the given number of pages at a temp location.
    /// Each page contains its page number as text for identification.
    static func makePDF(pageCount: Int, filename: String = "test.pdf") -> URL {
        let doc = PDFDocument()

        for i in 0..<pageCount {
            let page = PDFPage()
            doc.insert(page, at: i)
        }

        let url = URL.temporaryDirectory.appending(component: UUID().uuidString + "_" + filename)
        doc.write(to: url)
        return url
    }

    /// Creates a PDF by rendering text onto each page via CoreGraphics for richer content.
    static func makeRenderedPDF(pageCount: Int, filename: String = "rendered.pdf") -> URL {
        let url = URL.temporaryDirectory.appending(component: UUID().uuidString + "_" + filename)
        let pageSize = CGRect(x: 0, y: 0, width: 612, height: 792)

        var mediaBox = pageSize
        guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            fatalError("Cannot create PDF context for test")
        }

        for i in 1...pageCount {
            ctx.beginPage(mediaBox: &mediaBox)
            ctx.setFillColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1)
            ctx.fill(pageSize)

            let text = "Page \(i)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 48),
                .foregroundColor: NSColor.black
            ]
            text.draw(at: CGPoint(x: 100, y: 400), withAttributes: attrs)
            ctx.endPage()
        }

        ctx.closePDF()
        return url
    }

    /// Returns a fresh temp directory for output files.
    static func makeTempDirectory() -> URL {
        let dir = URL.temporaryDirectory.appending(component: UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Cleans up a temp file or directory.
    static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
