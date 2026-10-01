import CoreGraphics
import Foundation
import PDFKit

/// Merges multiple PDF files into a single document, preserving page content and order.
/// Each source is opened once and processed sequentially to limit memory and avoid
/// validation/use races.
@MainActor
struct PDFConcatenator {

    struct Result: Sendable {
        let outputPageCount: Int
    }

    /// Concatenates PDFs from `sources` (in order) into a single file at `destination`.
    /// The operation fails without publishing if any selected source or page is unreadable.
    @discardableResult
    func concatenate(
        sources: [URL],
        destination: URL,
        progress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws -> Result {
        // The worker owns every PDFKit object; only URLs, progress, and the
        // value result cross actors. Cancellation must reach the detached task
        // even while PDFKit is inside its non-interruptible writer.
        let worker = Task.detached(priority: .userInitiated) {
            try await Self.merge(sources: sources, destination: destination, progress: progress)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private nonisolated static func merge(
        sources: [URL], destination: URL,
        progress: @MainActor @Sendable (Double) -> Void
    ) async throws -> Result {
        guard !sources.isEmpty else { throw PDFwringerError.emptyFileList }

        for source in sources {
            try FileSystemIdentity.requireDistinct(source, destination)
        }

        let start = ContinuousClock.now
        Log.merge.info("Starting merge: \(sources.count) files")

        // Capture destination approval before any long preparation or callback.
        let staged = try AtomicFileWriter.StagedFile(destination: destination)
        defer { staged.cleanup() }
        let output = PDFDocument()
        var lastProgress = ContinuousClock.now
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
            try PDFPermissionPolicy.require(
                .copyContent,
                .assembleDocument,
                for: sourceDocument
            )

            for pageIndex in 0..<sourceDocument.pageCount {
                try Task.checkCancellation()
                guard let page = sourceDocument.page(at: pageIndex) else {
                    throw PDFwringerError.cannotOpenDocument
                }
                output.insert(page, at: insertIndex)
                insertIndex += 1

                let completedSourceFraction = Double(pageIndex + 1) / Double(sourceDocument.pageCount)
                let now = ContinuousClock.now
                if pageIndex + 1 == sourceDocument.pageCount || now - lastProgress >= .milliseconds(33) {
                    await progress(min(0.99, (Double(sourceIndex) + completedSourceFraction) / Double(sources.count)))
                    lastProgress = now
                }
            }
        }

        guard insertIndex > 0, output.pageCount == insertIndex else {
            throw PDFwringerError.cannotWriteOutput
        }
        try Task.checkCancellation()
        guard output.write(to: staged.url) else { throw PDFwringerError.cannotWriteOutput }
        try Task.checkCancellation()
        guard let verificationDocument = PDFDocument(url: staged.url),
              !verificationDocument.isLocked,
              verificationDocument.pageCount == insertIndex else {
            throw PDFwringerError.cannotWriteOutput
        }
        for index in 0..<insertIndex {
            try Task.checkCancellation()
            guard verificationDocument.page(at: index) != nil else {
                throw PDFwringerError.cannotWriteOutput
            }
        }
        for source in sources { try FileSystemIdentity.requireDistinct(source, destination) }
        try staged.commit()
        await progress(1.0)

        let elapsed = ContinuousClock.now - start
        Log.merge.info("Merge complete: \(insertIndex) pages, duration=\(elapsed)")

        return Result(outputPageCount: insertIndex)
    }
}
