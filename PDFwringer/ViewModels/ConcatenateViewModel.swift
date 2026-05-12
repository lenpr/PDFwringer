import Foundation

/// Drives the merge execution. File list management is handled by the view's binding.
@MainActor @Observable
class ConcatenateViewModel {
    var files: [PDFFileItem] = []
    var isProcessing = false
    var progress: Double = 0
    var resultMessage: String?
    var isError = false
    var lastOutputURL: URL?

    private let concatenator = PDFConcatenator()
    private var operationTask: Task<Void, Never>?

    var canConcatenate: Bool {
        files.count >= 2 && !isProcessing
    }

    func concatenate() async {
        guard canConcatenate, !isProcessing else { return }

        guard let destination = FileDialogHelper.showSavePanel(suggestedName: "merged.pdf") else { return }

        isProcessing = true
        progress = 0
        resultMessage = nil
        isError = false

        operationTask = Task {
            defer { operationTask = nil }
            do {
                let urls = files.map(\.url)
                let result = try await concatenator.concatenate(
                    sources: urls,
                    destination: destination,
                    progress: { [weak self] p in self?.progress = p }
                )

                let totalPages = files.reduce(0) { $0 + $1.pageCount }
                if result.skippedFiles.isEmpty {
                    resultMessage = "Done! Merged \(files.count) files (\(totalPages) pages)."
                } else {
                    resultMessage = "Merged with warnings: could not open \(result.skippedFiles.joined(separator: ", "))."
                }
                isError = false
                lastOutputURL = destination
            } catch is CancellationError {
                resultMessage = "Cancelled."
                isError = false
            } catch {
                resultMessage = error.localizedDescription
                isError = true
            }

            isProcessing = false
        }
        await operationTask?.value
    }

    func cancel() {
        operationTask?.cancel()
    }
}
