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
        progress: @escaping @MainActor @Sendable (Double) -> Void
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

        let staged = try AtomicFileWriter.StagedFile(destination: destination)
        defer { staged.cleanup() }
        // A document snapshot preserves unsaved in-memory content. The worker
        // reconstructs its own PDFKit graph instead of sharing reference objects.
        // Encrypted snapshots can relock. PDFKit also changes some annotation
        // geometry when serializing a whole document instead of one page.
        // Keep the established isolation path for those preservation cases.
        let hasAnnotations = (0..<pageCount).contains { document.page(at: $0)?.annotations.isEmpty == false }
        if !document.isEncrypted && !hasAnnotations {
            guard let snapshot = document.dataRepresentation(), !snapshot.isEmpty else {
                throw PDFwringerError.cannotWriteOutput
            }
            let worker = Task.detached(priority: .userInitiated) {
                try await Self.writeReordered(snapshot: snapshot, expectedCount: pageCount,
                                              source: source, staged: staged,
                                              order: pageOrder, progress: progress)
            }
            try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: { worker.cancel() }
            return
        }

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
            progress(min(0.99, Double(position + 1) / Double(pageCount)))
            try Task.checkCancellation()
            await Task.yield()
        }

        guard output.pageCount == pageCount,
              let outputData = output.dataRepresentation() else {
            throw PDFwringerError.cannotWriteOutput
        }
        await Task.yield()
        try Task.checkCancellation()

        try await AtomicFileWriter.write(to: staged.url) { stagedURL in
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
        try FileSystemIdentity.requireDistinct(source, destination)
        try staged.commit()
        progress(1)
    }

    private nonisolated static func writeReordered(
        snapshot: Data, expectedCount: Int, source: URL,
        staged: AtomicFileWriter.StagedFile, order: [Int],
        progress: @MainActor @Sendable (Double) -> Void
    ) async throws {
        try Task.checkCancellation()
        guard let document = PDFDocument(data: snapshot), !document.isLocked,
              document.pageCount == expectedCount else {
            throw PDFwringerError.cannotOpenDocument
        }
        let output = PDFDocument()
        output.documentAttributes = document.documentAttributes
        for (position, index) in order.enumerated() {
            try Task.checkCancellation()
            guard let page = document.page(at: index),
                  let copy = page.copy() as? PDFPage, copy !== page else {
                throw PDFwringerError.cannotOpenDocument
            }
            output.insert(copy, at: output.pageCount)
            await progress(min(0.99, Double(position + 1) / Double(expectedCount)))
        }
        try Task.checkCancellation()
        guard output.write(to: staged.url) else { throw PDFwringerError.cannotWriteOutput }
        try Task.checkCancellation()
        guard let verification = PDFDocument(url: staged.url), !verification.isEncrypted,
              verification.pageCount == expectedCount else { throw PDFwringerError.cannotWriteOutput }
        for index in 0..<expectedCount {
            try Task.checkCancellation()
            guard verification.page(at: index) != nil else { throw PDFwringerError.cannotWriteOutput }
        }
        try FileSystemIdentity.requireDistinct(source, staged.destination)
        try staged.commit()
        await progress(1)
    }
}
