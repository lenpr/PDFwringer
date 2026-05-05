import Foundation
import PDFKit

/// Represents a user-selected PDF file with its security-scoped bookmark for sandbox access.
struct PDFFileItem: Identifiable {
    let id = UUID()
    let url: URL
    let bookmarkData: Data
    let filename: String
    let pageCount: Int

    init(url: URL, bookmarkData: Data, pageCount: Int) {
        self.url = url
        self.bookmarkData = bookmarkData
        self.filename = url.lastPathComponent
        self.pageCount = pageCount
    }

    /// Creates a PDFFileItem from a URL, generating a security-scoped bookmark and reading page count.
    /// Returns nil if the URL is not a PDF.
    static func from(url: URL) -> PDFFileItem? {
        guard url.pathExtension.lowercased() == "pdf" else { return nil }
        let pageCount = PDFDocument(url: url)?.pageCount ?? 0
        let bookmarkData = (try? url.bookmarkData(options: .withSecurityScope)) ?? Data()
        return PDFFileItem(url: url, bookmarkData: bookmarkData, pageCount: pageCount)
    }

    /// Creates PDFFileItems from multiple URLs, filtering to valid PDFs.
    static func from(urls: [URL]) -> [PDFFileItem] {
        urls.compactMap { from(url: $0) }
    }
}
