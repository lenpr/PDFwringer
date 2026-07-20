import Foundation
import PDFKit

/// Rebuilds a PDF with every source page in a caller-supplied order.
@MainActor
struct PDFPageReorderer {
    func reorder(
        document: PDFDocument,
        source: URL,
        destination: URL,
        pageOrder: [Int],
        progress: (Double) -> Void
    ) async throws {
        try FileSystemIdentity.requireDistinct(source, destination)
        if document.isLocked { throw PDFwringerError.documentIsLocked }

        let pageCount = document.pageCount
        guard pageCount > 0 else { throw PDFwringerError.cannotOpenDocument }
        guard pageOrder.count == pageCount,
              Set(pageOrder) == Set(0..<pageCount) else {
            throw PDFwringerError.invalidPageOrder
        }
        try PDFPermissionPolicy.require(.copyContent, .assembleDocument, for: document)
        try Task.checkCancellation()

        let output = PDFDocument()
        output.documentAttributes = document.documentAttributes
        for (position, pageIndex) in pageOrder.enumerated() {
            try Task.checkCancellation()
            guard let page = document.page(at: pageIndex),
                  let pageData = page.dataRepresentation,
                  let pageDocument = PDFDocument(data: pageData),
                  let copiedPage = pageDocument.page(at: 0)?.copy() as? PDFPage else {
                throw PDFwringerError.cannotOpenDocument
            }
            output.insert(copiedPage, at: output.pageCount)
            progress(Double(position + 1) / Double(pageCount))
            try Task.checkCancellation()
            await Task.yield()
        }

        guard output.pageCount == pageCount,
              let outputData = output.dataRepresentation() else {
            throw PDFwringerError.cannotWriteOutput
        }
        await Task.yield()
        try Task.checkCancellation()

        try await AtomicFileWriter.write(to: destination) { stagedURL in
            try await Task.detached(priority: .utility) {
                try outputData.write(to: stagedURL)
            }.value
            try Task.checkCancellation()

            guard let verificationDocument = PDFDocument(url: stagedURL),
                  !verificationDocument.isLocked,
                  verificationDocument.pageCount == pageCount,
                  (0..<pageCount).allSatisfy({ verificationDocument.page(at: $0) != nil }) else {
                return false
            }
            return true
        }
    }
}
