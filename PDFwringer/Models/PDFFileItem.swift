import Foundation

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
}
