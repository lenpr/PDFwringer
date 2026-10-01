import Foundation
import PDFKit

/// Runs CPU-heavy work against an isolated, single-page PDF document.
/// Callers snapshot the authoritative PDFPage on MainActor and only Data crosses
/// into the detached task; PDFKit reference types never cross actor boundaries.
enum PDFPageWorker {
    /// Optional read-only fast path. The caller must have constructed its
    /// authoritative document from these exact immutable bytes. Changed bounds,
    /// protection and annotations keep the authoritative snapshot fallback.
    static func readOnlySnapshot(
        sourceData: Data, index: Int, rotation: Int, cropBox: CGRect, mediaBox: CGRect
    ) async throws -> Data? {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return autoreleasepool {
                guard let document = PDFDocument(data: sourceData), !document.isEncrypted,
                      (0..<document.pageCount).contains(index), let page = document.page(at: index),
                      page.annotations.isEmpty, page.rotation == rotation,
                      page.bounds(for: .cropBox) == cropBox, page.bounds(for: .mediaBox) == mediaBox else { return nil as Data? }
                return page.dataRepresentation
            }
        }
        return try await withTaskCancellationHandler {
            let data = try await worker.value
            try Task.checkCancellation()
            return data
        } onCancel: { worker.cancel() }
    }

    static func run<Output: Sendable>(
        pageData: Data,
        operation: @escaping @Sendable (PDFPage) throws -> Output
    ) async throws -> Output {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try autoreleasepool {
                guard let document = PDFDocument(data: pageData),
                      document.pageCount == 1,
                      let page = document.page(at: 0) else {
                    throw PDFwringerError.cannotOpenDocument
                }

                let output = try operation(page)
                try Task.checkCancellation()
                return output
            }
        }

        return try await withTaskCancellationHandler {
            do {
                let output = try await worker.value
                try Task.checkCancellation()
                return output
            } catch {
                try Task.checkCancellation()
                throw error
            }
        } onCancel: {
            worker.cancel()
        }
    }
}
