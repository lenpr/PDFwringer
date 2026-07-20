import Foundation
import PDFKit

/// Runs CPU-heavy work against an isolated, single-page PDF document.
/// Callers snapshot the authoritative PDFPage on MainActor and only Data crosses
/// into the detached task; PDFKit reference types never cross actor boundaries.
enum PDFPageWorker {
    struct EncodedPage: Sendable {
        let data: Data
        let displaySize: CGSize
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
