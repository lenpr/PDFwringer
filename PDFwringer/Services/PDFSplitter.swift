import Foundation
import PDFKit

/// Splits or extracts pages from a PDF into one or more output files.
@MainActor
struct PDFSplitter {

    /// Determines how pages are selected for output.
    enum Mode {
        /// Split into chunks of N pages each (last chunk may have fewer).
        case splitEveryN(Int)
        /// Keep only the specified 0-based page indices.
        case keepPages([Int])
        /// Remove the specified 0-based page indices, keeping everything else.
        case removePages([Int])
    }

    /// Splits or extracts pages from `source` according to `mode`, writing results at/under `destination`.
    /// Returns the URLs of all output files created.
    func split(
        source: URL,
        mode: Mode,
        destination: URL,
        progress: (Double) -> Void
    ) async throws -> [URL] {
        guard FileManager.default.isReadableFile(atPath: source.path(percentEncoded: false)) else {
            throw PDFwringerError.fileNotReadable(source.lastPathComponent)
        }

        guard let sourceDoc = PDFDocument(url: source) else {
            throw PDFwringerError.cannotOpenDocument
        }
        if sourceDoc.isLocked { throw PDFwringerError.documentIsLocked }

        let pageCount = sourceDoc.pageCount
        guard pageCount > 0 else { throw PDFwringerError.cannotOpenDocument }

        switch mode {
        case .splitEveryN(let n):
            return try await splitEveryN(
                sourceDoc: sourceDoc,
                n: max(1, n),
                baseName: source.deletingPathExtension().lastPathComponent,
                outputDir: destination,
                progress: progress
            )

        case .keepPages(let indices):
            let outputURL = destination
            try await extractPages(
                sourceDoc: sourceDoc,
                pageIndices: indices,
                destination: outputURL,
                progress: progress
            )
            return [outputURL]

        case .removePages(let indicesToRemove):
            let allIndices = Array(0..<pageCount)
            let removeSet = Set(indicesToRemove)
            let keepIndices = allIndices.filter { !removeSet.contains($0) }
            let outputURL = destination
            try await extractPages(
                sourceDoc: sourceDoc,
                pageIndices: keepIndices,
                destination: outputURL,
                progress: progress
            )
            return [outputURL]
        }
    }

    // MARK: - Split every N pages

    private func splitEveryN(
        sourceDoc: PDFDocument,
        n: Int,
        baseName: String,
        outputDir: URL,
        progress: (Double) -> Void
    ) async throws -> [URL] {
        let pageCount = sourceDoc.pageCount
        var outputURLs: [URL] = []
        var processedPages = 0

        let totalChunks = (pageCount + n - 1) / n

        for chunkIndex in 0..<totalChunks {
            try Task.checkCancellation()

            let startPage = chunkIndex * n
            let endPage = min(startPage + n, pageCount)

            let chunkDoc = PDFDocument()
            for pageIdx in startPage..<endPage {
                autoreleasepool {
                    guard let page = sourceDoc.page(at: pageIdx) else { return }
                    chunkDoc.insert(page, at: chunkDoc.pageCount)
                }
                processedPages += 1
            }

            let filename = String(format: "%@_%03d.pdf", baseName, chunkIndex + 1)
            let outputURL = outputDir.appending(component: filename)
            let tempURL = URL.temporaryDirectory.appending(component: UUID().uuidString + ".pdf")

            guard chunkDoc.write(to: tempURL) else {
                throw PDFwringerError.cannotWriteOutput
            }

            do {
                if FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false)) {
                    _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: tempURL)
                } else {
                    try FileManager.default.moveItem(at: tempURL, to: outputURL)
                }
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                throw error
            }

            outputURLs.append(outputURL)
            progress(Double(processedPages) / Double(pageCount))
            await Task.yield()
        }

        return outputURLs
    }

    // MARK: - Extract specific pages

    private func extractPages(
        sourceDoc: PDFDocument,
        pageIndices: [Int],
        destination: URL,
        progress: (Double) -> Void
    ) async throws {
        guard !pageIndices.isEmpty else { throw PDFwringerError.invalidPageRange("empty") }

        let outputDoc = PDFDocument()

        for (i, pageIdx) in pageIndices.enumerated() {
            try Task.checkCancellation()

            autoreleasepool {
                guard pageIdx >= 0, pageIdx < sourceDoc.pageCount,
                      let page = sourceDoc.page(at: pageIdx)
                else { return }
                outputDoc.insert(page, at: outputDoc.pageCount)
            }

            progress(Double(i + 1) / Double(pageIndices.count))

            if (i + 1) % 10 == 0 {
                await Task.yield()
            }
        }

        try AtomicFileWriter.write(to: destination) { tempURL in
            outputDoc.write(to: tempURL)
        }
    }
}
