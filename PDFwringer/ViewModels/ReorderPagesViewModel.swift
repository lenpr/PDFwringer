import Foundation
import PDFKit

/// Owns page-order state and the cancellable reordered-document save operation.
@MainActor @Observable
final class ReorderPagesViewModel {
    var pageOrder: [Int] = [] {
        didSet {
            if pageOrder != oldValue && !isSaving {
                resultMessage = nil; lastOutputURL = nil; isError = false
            }
        }
    }
    var resultMessage: String?
    var isError = false
    var lastOutputURL: URL?
    var isSaving = false
    var progress: Double = 0

    private var sourcePageCount = 0
    private var savedPageOrder: [Int] = []
    var hasUnsavedChanges: Bool { pageOrder != savedPageOrder }
    private var operationTask: Task<Void, Never>?
    private let reorderer = PDFPageReorderer()

    var canSave: Bool {
        !isSaving
            && pageOrder.count == sourcePageCount
            && Set(pageOrder) == Set(0..<sourcePageCount)
            && hasUnsavedChanges
    }

    func setDocument(_ document: PDFDocument) {
        cancel()
        sourcePageCount = document.pageCount
        pageOrder = Array(0..<sourcePageCount)
        savedPageOrder = pageOrder
        resultMessage = nil
        isError = false
        lastOutputURL = nil
        progress = 0
    }

    /// Move by page identity so repeated actions follow the page after it moves.
    func movePage(_ page: Int, by offset: Int) {
        guard !isSaving, offset == -1 || offset == 1,
              let position = pageOrder.firstIndex(of: page),
              pageOrder.indices.contains(position + offset) else { return }
        pageOrder.swapAt(position, position + offset)
    }

    func reset() {
        pageOrder = Array(0..<sourcePageCount)
    }

    func save(source: URL, document: PDFDocument) async {
        guard canSave else { return }
        let suggestedName = source.deletingPathExtension().lastPathComponent + "_reordered.pdf"
        guard let destination = FileDialogHelper.showSavePanel(suggestedName: suggestedName) else { return }
        await save(source: source, document: document, destination: destination)
    }

    func save(source: URL, document: PDFDocument, destination: URL) async {
        guard canSave else { return }

        let order = pageOrder
        isSaving = true
        progress = 0
        resultMessage = nil
        isError = false
        lastOutputURL = nil

        operationTask = Task {
            defer {
                operationTask = nil
                isSaving = false
            }
            do {
                try await reorderer.reorder(
                    document: document,
                    source: source,
                    destination: destination,
                    pageOrder: order,
                    progress: { [weak self] value in self?.progress = value }
                )
                resultMessage = document.isEncrypted
                    ? String(localized: "Saved. Password protection was removed.")
                    : String(localized: "Saved.")
                savedPageOrder = order
                isError = false
                lastOutputURL = destination
            } catch is CancellationError {
                resultMessage = String(localized: "Cancelled.")
                isError = false
            } catch {
                resultMessage = PDFwringerError.userMessage(for: error)
                isError = true
            }
        }
        await operationTask?.value
    }

    func cancel() {
        operationTask?.cancel()
    }
}
