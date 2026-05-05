import CoreGraphics
import Foundation
import PDFKit

/// Merges multiple PDF files into a single document, preserving page content and order.
/// Processes sources sequentially to limit memory usage with large files.
@MainActor
struct PDFConcatenator {

    /// Concatenates PDFs from `sources` (in order) into a single file at `destination`.
    func concatenate(
        sources: [URL],
        destination: URL,
        progress: (Double) -> Void
    ) async throws {
        guard !sources.isEmpty else { throw PDFwringerError.emptyFileList }

        // Validate all source files are readable before starting
        for url in sources {
            guard FileManager.default.isReadableFile(atPath: url.path(percentEncoded: false)) else {
                throw PDFwringerError.fileNotReadable(url.lastPathComponent)
            }
        }

        // First pass: count total pages without keeping docs in memory
        var totalPages = 0
        for url in sources {
            guard let doc = PDFDocument(url: url) else { continue }
            if doc.isLocked { throw PDFwringerError.documentIsLocked }
            totalPages += doc.pageCount
        }
        guard totalPages > 0 else { throw PDFwringerError.emptyFileList }

        // Second pass: build output one source at a time to limit peak memory
        let output = PDFDocument()
        var insertIndex = 0

        for url in sources {
            guard let sourceDoc = PDFDocument(url: url) else { continue }

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

        do {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: tempURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }
}
