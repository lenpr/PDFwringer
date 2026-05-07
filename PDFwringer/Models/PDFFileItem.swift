import Foundation
import PDFKit

/// Represents a user-selected PDF file with its metadata for display.
struct PDFFileItem: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let filename: String
    let pageCount: Int

    init(url: URL, pageCount: Int) {
        self.url = url
        self.filename = url.lastPathComponent
        self.pageCount = pageCount
    }

    /// Creates a PDFFileItem from a URL, reading page count.
    /// Returns nil if the URL is not a PDF.
    static func from(url: URL) -> PDFFileItem? {
        guard url.pathExtension.lowercased() == "pdf" else { return nil }
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else { return nil }
        return PDFFileItem(url: url, pageCount: doc.pageCount)
    }

    /// Creates PDFFileItems from multiple URLs, filtering to valid PDFs.
    static func from(urls: [URL]) -> [PDFFileItem] {
        urls.compactMap { from(url: $0) }
    }
}
