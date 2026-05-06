import CoreGraphics
import Foundation
import PDFKit

/// Merges multiple PDF files into a single document, preserving page content and order.
/// Processes sources sequentially to limit memory usage with large files.
@MainActor
struct PDFConcatenator {

    struct Result {
        var outputPageCount: Int
        var skippedFiles: [String]
    }

    /// Concatenates PDFs from `sources` (in order) into a single file at `destination`.
    /// Returns a result indicating any files that could not be opened.
    @discardableResult
    func concatenate(
        sources: [URL],
        destination: URL,
        progress: (Double) -> Void
    ) async throws -> Result {
        guard !sources.isEmpty else { throw PDFwringerError.emptyFileList }

        // Validate all source files are readable before starting
        for url in sources {
            guard FileManager.default.isReadableFile(atPath: url.path(percentEncoded: false)) else {
                throw PDFwringerError.fileNotReadable(url.lastPathComponent)
            }
        }

        // Single pass: count total pages and check for locked docs, then build output
        var totalPages = 0
        var sourceDocs: [(PDFDocument, Int)] = []
        var skippedFiles: [String] = []
        for url in sources {
            guard let doc = PDFDocument(url: url) else {
                skippedFiles.append(url.lastPathComponent)
                continue
            }
            if doc.isLocked { throw PDFwringerError.documentIsLocked }
            totalPages += doc.pageCount
            sourceDocs.append((doc, doc.pageCount))
        }
        guard totalPages > 0 else { throw PDFwringerError.emptyFileList }

        // Build output one source at a time
        let output = PDFDocument()
        var insertIndex = 0

        for (sourceDoc, pageCount) in sourceDocs {
            for pageIdx in 0..<pageCount {
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

        return Result(outputPageCount: insertIndex, skippedFiles: skippedFiles)
    }
}
