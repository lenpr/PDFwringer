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

        let destStandardized = destination.standardizedFileURL
        if sources.contains(where: { $0.standardizedFileURL == destStandardized }) {
            throw PDFwringerError.sourceEqualsDestination
        }

        let start = ContinuousClock.now
        Log.merge.info("Starting merge: \(sources.count) files")

        // Validate all source files are readable before starting
        for url in sources {
            guard FileManager.default.isReadableFile(atPath: url.path(percentEncoded: false)) else {
                throw PDFwringerError.fileNotReadable(url.lastPathComponent)
            }
        }

        // Pass 1: validate all sources and count pages (release docs immediately)
        var totalPages = 0
        var pageCounts: [Int] = []
        var skippedFiles: [String] = []
        for url in sources {
            guard let doc = PDFDocument(url: url) else {
                skippedFiles.append(url.lastPathComponent)
                pageCounts.append(0)
                continue
            }
            if doc.isLocked { throw PDFwringerError.documentIsLocked }
            pageCounts.append(doc.pageCount)
            totalPages += doc.pageCount
        }
        guard totalPages > 0 else { throw PDFwringerError.emptyFileList }

        // Pass 2: build output one source at a time to limit memory
        let output = PDFDocument()
        var insertIndex = 0

        for (idx, url) in sources.enumerated() {
            guard pageCounts[idx] > 0, let sourceDoc = PDFDocument(url: url) else { continue }

            for pageIdx in 0..<pageCounts[idx] {
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

        try AtomicFileWriter.write(to: destination) { tempURL in
            output.write(to: tempURL)
        }

        let elapsed = ContinuousClock.now - start
        if !skippedFiles.isEmpty {
            Log.merge.warning("Merge complete with \(skippedFiles.count) skipped file(s)")
        }
        Log.merge.info("Merge complete: \(insertIndex) pages, duration=\(elapsed)")

        return Result(outputPageCount: insertIndex, skippedFiles: skippedFiles)
    }
}
