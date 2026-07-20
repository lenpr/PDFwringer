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
        guard let document = PDFDocument(url: source) else {
            throw PDFwringerError.cannotOpenDocument
        }
        if document.isLocked { throw PDFwringerError.documentIsLocked }

        return try await split(
            document: document,
            source: source,
            mode: mode,
            destination: destination,
            progress: progress
        )
    }

    /// Splits the supplied, already-open document. The source URL is used for
    /// identity and output naming, not to reopen the PDF.
    func split(
        document: PDFDocument,
        source: URL,
        mode: Mode,
        destination: URL,
        progress: (Double) -> Void
    ) async throws -> [URL] {
        switch mode {
        case .splitEveryN:
            break
        case .keepPages, .removePages:
            try FileSystemIdentity.requireDistinct(source, destination)
        }

        if document.isLocked { throw PDFwringerError.documentIsLocked }

        let pageCount = document.pageCount
        guard pageCount > 0 else { throw PDFwringerError.cannotOpenDocument }

        let start = ContinuousClock.now
        Log.split.info("Starting split: \(pageCount) pages")

        let results: [URL]
        switch mode {
        case .splitEveryN(let n):
            results = try await splitEveryN(
                sourceDoc: document,
                n: max(1, n),
                baseName: source.deletingPathExtension().lastPathComponent,
                outputDir: destination,
                progress: progress
            )

        case .keepPages(let indices):
            let outputURL = destination
            try await extractPages(
                sourceDoc: document,
                pageIndices: indices,
                destination: outputURL,
                progress: progress
            )
            results = [outputURL]

        case .removePages(let indicesToRemove):
            let allIndices = Array(0..<pageCount)
            let removeSet = Set(indicesToRemove)
            let keepIndices = allIndices.filter { !removeSet.contains($0) }
            let outputURL = destination
            try await extractPages(
                sourceDoc: document,
                pageIndices: keepIndices,
                destination: outputURL,
                progress: progress
            )
            results = [outputURL]
        }

        let elapsed = ContinuousClock.now - start
        Log.split.info("Split complete: \(results.count) output files, duration=\(elapsed)")
        return results
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
        var processedPages = 0

        let totalChunks = (pageCount + n - 1) / n

        guard totalChunks <= 5_000 else {
            throw PDFwringerError.documentTooLarge("Split would create \(totalChunks) files, exceeding the 5,000 file limit")
        }

        let fileManager = FileManager.default
        let stagingDirectory = try fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: outputDir,
            create: true
        )
        defer { try? fileManager.removeItem(at: stagingDirectory) }
        var stagedOutputs: [ExclusiveFilePublisher.StagedFile] = []
        stagedOutputs.reserveCapacity(totalChunks)

        for chunkIndex in 0..<totalChunks {
            try Task.checkCancellation()

            let startPage = chunkIndex * n
            let endPage = min(startPage + n, pageCount)

            let chunkDoc = PDFDocument()
            for pageIdx in startPage..<endPage {
                let copiedPage: PDFPage? = autoreleasepool {
                    guard let page = sourceDoc.page(at: pageIdx) else { return nil }
                    return page.copy() as? PDFPage
                }
                guard let copiedPage else { throw PDFwringerError.cannotOpenDocument }
                chunkDoc.insert(copiedPage, at: chunkDoc.pageCount)
                processedPages += 1
            }

            let stagedURL = stagingDirectory
                .appending(component: UUID().uuidString)
                .appendingPathExtension("pdf")
            let expectedPageCount = endPage - startPage
            guard chunkDoc.write(to: stagedURL),
                  let verificationDocument = PDFDocument(url: stagedURL),
                  verificationDocument.pageCount == expectedPageCount,
                  (0..<expectedPageCount).allSatisfy({ verificationDocument.page(at: $0) != nil }) else {
                throw PDFwringerError.cannotWriteOutput
            }
            stagedOutputs.append(ExclusiveFilePublisher.StagedFile(
                url: stagedURL,
                preferredStem: String(format: "%@_%03d", baseName, chunkIndex + 1),
                pathExtension: "pdf"
            ))
            progress(Double(processedPages) / Double(pageCount))
            await Task.yield()
        }

        try Task.checkCancellation()
        return try ExclusiveFilePublisher.publish(stagedOutputs, to: outputDir)
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

            let copiedPage: PDFPage? = autoreleasepool {
                guard pageIdx >= 0, pageIdx < sourceDoc.pageCount,
                      let page = sourceDoc.page(at: pageIdx)
                else { return nil }
                return page.copy() as? PDFPage
            }
            guard let copiedPage else { continue }
            outputDoc.insert(copiedPage, at: outputDoc.pageCount)

            progress(Double(i + 1) / Double(pageIndices.count))

            if (i + 1) % 10 == 0 {
                await Task.yield()
            }
        }

        guard outputDoc.pageCount > 0 else {
            throw PDFwringerError.invalidPageRange("no valid pages in range")
        }

        try Task.checkCancellation()
        try AtomicFileWriter.write(to: destination) { tempURL in
            guard outputDoc.write(to: tempURL),
                  let verificationDocument = PDFDocument(url: tempURL),
                  verificationDocument.pageCount == outputDoc.pageCount else {
                return false
            }
            return (0..<outputDoc.pageCount).allSatisfy {
                verificationDocument.page(at: $0) != nil
            }
        }
    }
}
