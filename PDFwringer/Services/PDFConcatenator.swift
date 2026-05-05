import CoreGraphics
import Foundation
import PDFKit

@MainActor
struct PDFConcatenator {

    func concatenate(
        sources: [URL],
        destination: URL,
        progress: (Double) -> Void
    ) async throws {
        guard !sources.isEmpty else { throw PDFwringerError.emptyFileList }

        // Open all source documents and keep them alive until write completes
        var sourceDocs: [(URL, PDFDocument)] = []
        var totalPages = 0

        for url in sources {
            guard let doc = PDFDocument(url: url) else { continue }
            if doc.isLocked { throw PDFwringerError.documentIsLocked }
            totalPages += doc.pageCount
            sourceDocs.append((url, doc))
        }

        guard totalPages > 0 else { throw PDFwringerError.emptyFileList }

        let output = PDFDocument()
        var insertIndex = 0

        for (_, sourceDoc) in sourceDocs {
            for pageIdx in 0..<sourceDoc.pageCount {
                try Task.checkCancellation()

                autoreleasepool {
                    guard let page = sourceDoc.page(at: pageIdx) else { return }
                    output.insert(page, at: insertIndex)
                    insertIndex += 1
                }

                progress(Double(insertIndex) / Double(totalPages))

                if insertIndex % 10 == 0 {
                    await Task.yield()
                }
            }
        }

        let tempURL = URL.temporaryDirectory.appending(component: UUID().uuidString + ".pdf")
        guard output.write(to: tempURL) else {
            throw PDFwringerError.cannotWriteOutput
        }

        _ = try FileManager.default.replaceItemAt(destination, withItemAt: tempURL)

        // sourceDocs stays alive until here — file handles released after write
    }
}
