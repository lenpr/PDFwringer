import Foundation
import PDFKit

/// Reads and writes PDF document metadata (title, author, subject, keywords, creator).
@MainActor
struct PDFMetadataEditor {

    struct Metadata {
        var title: String
        var author: String
        var subject: String
        var keywords: String
        var creator: String

        static let empty = Metadata(title: "", author: "", subject: "", keywords: "", creator: "")
    }

    /// Reads metadata from a PDF file.
    func read(from url: URL) -> Metadata {
        guard let doc = PDFDocument(url: url),
              let attrs = doc.documentAttributes else {
            return .empty
        }

        return Metadata(
            title: attrs[PDFDocumentAttribute.titleAttribute] as? String ?? "",
            author: attrs[PDFDocumentAttribute.authorAttribute] as? String ?? "",
            subject: attrs[PDFDocumentAttribute.subjectAttribute] as? String ?? "",
            keywords: (attrs[PDFDocumentAttribute.keywordsAttribute] as? [String])?.joined(separator: ", ") ?? "",
            creator: attrs[PDFDocumentAttribute.creatorAttribute] as? String ?? ""
        )
    }

    /// Writes metadata to a PDF file, saving to destination.
    func write(
        metadata: Metadata,
        source: URL,
        destination: URL
    ) throws {
        guard let doc = PDFDocument(url: source) else {
            throw PDFwringerError.cannotOpenDocument
        }
        if doc.isLocked { throw PDFwringerError.documentIsLocked }

        var attrs: [PDFDocumentAttribute: Any] = [:]
        if !metadata.title.isEmpty { attrs[.titleAttribute] = metadata.title }
        if !metadata.author.isEmpty { attrs[.authorAttribute] = metadata.author }
        if !metadata.subject.isEmpty { attrs[.subjectAttribute] = metadata.subject }
        if !metadata.keywords.isEmpty {
            attrs[.keywordsAttribute] = metadata.keywords
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
        if !metadata.creator.isEmpty { attrs[.creatorAttribute] = metadata.creator }

        doc.documentAttributes = attrs

        let tempURL = URL.temporaryDirectory.appending(component: UUID().uuidString + ".pdf")
        guard doc.write(to: tempURL) else {
            throw PDFwringerError.cannotWriteOutput
        }
        _ = try FileManager.default.replaceItemAt(destination, withItemAt: tempURL)
    }
}
