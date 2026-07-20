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

    /// Loads a batch away from actor-isolated callers while preserving input order.
    static func load(urls: [URL]) async throws -> [PDFFileItem] {
        var items: [PDFFileItem] = []
        items.reserveCapacity(urls.count)
        for (index, url) in urls.enumerated() {
            try Task.checkCancellation()
            if let item = from(url: url) {
                items.append(item)
            }
            if (index + 1).isMultiple(of: 10) {
                await Task.yield()
            }
        }
        try Task.checkCancellation()
        return items
    }
}
