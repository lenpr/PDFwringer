import CoreGraphics
import Foundation
import PDFKit

/// Merges multiple PDF files into a single document, preserving page content and order.
/// Each source is opened once and processed sequentially to limit memory and avoid
/// validation/use races.
@MainActor
struct PDFConcatenator {

    struct Result {
        let outputPageCount: Int
    }

    /// Concatenates PDFs from `sources` (in order) into a single file at `destination`.
    /// The operation fails without publishing if any selected source or page is unreadable.
    @discardableResult
    func concatenate(
        sources: [URL],
        destination: URL,
        progress: (Double) -> Void
    ) async throws -> Result {
        guard !sources.isEmpty else { throw PDFwringerError.emptyFileList }

        for source in sources {
            try FileSystemIdentity.requireDistinct(source, destination)
        }

        let start = ContinuousClock.now
        Log.merge.info("Starting merge: \(sources.count) files")

        let output = PDFDocument()
        var insertIndex = 0

        for (sourceIndex, url) in sources.enumerated() {
            try Task.checkCancellation()
            guard FileManager.default.isReadableFile(atPath: url.path(percentEncoded: false)) else {
                throw PDFwringerError.fileNotReadable(url.lastPathComponent)
            }
            guard let sourceDocument = PDFDocument(url: url), sourceDocument.pageCount > 0 else {
                throw PDFwringerError.cannotOpenDocument
            }
            if sourceDocument.isLocked { throw PDFwringerError.documentIsLocked }
            try PDFPermissionPolicy.require(.assembleDocument, for: sourceDocument)

            for pageIndex in 0..<sourceDocument.pageCount {
                try Task.checkCancellation()
                guard let page = sourceDocument.page(at: pageIndex) else {
                    throw PDFwringerError.cannotOpenDocument
                }
                output.insert(page, at: insertIndex)
                insertIndex += 1

                let completedSourceFraction = Double(pageIndex + 1) / Double(sourceDocument.pageCount)
                progress(
                    (Double(sourceIndex) + completedSourceFraction) / Double(sources.count)
                )

                if insertIndex % 10 == 0 {
                    await Task.yield()
                }
            }
        }

        guard insertIndex > 0, output.pageCount == insertIndex else {
            throw PDFwringerError.cannotWriteOutput
        }
        try Task.checkCancellation()
        try AtomicFileWriter.write(to: destination) { tempURL in
            guard output.write(to: tempURL),
                  let verificationDocument = PDFDocument(url: tempURL),
                  verificationDocument.pageCount == insertIndex else {
                return false
            }
            return (0..<insertIndex).allSatisfy {
                verificationDocument.page(at: $0) != nil
            }
        }

        let elapsed = ContinuousClock.now - start
        Log.merge.info("Merge complete: \(insertIndex) pages, duration=\(elapsed)")

        return Result(outputPageCount: insertIndex)
    }
}
