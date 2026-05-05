import Foundation
import PDFKit

@MainActor
struct PDFSplitter {

    enum Mode {
        case splitEveryN(Int)
        case keepPages([Int])
        case removePages([Int])
    }

    func split(
        source: URL,
        mode: Mode,
        destination: URL,
        progress: (Double) -> Void
    ) async throws -> [URL] {
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

            if FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false)) {
                _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: tempURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: outputURL)
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

        let tempURL = URL.temporaryDirectory.appending(component: UUID().uuidString + ".pdf")
        guard outputDoc.write(to: tempURL) else {
            throw PDFwringerError.cannotWriteOutput
        }

        _ = try FileManager.default.replaceItemAt(destination, withItemAt: tempURL)
    }
}
