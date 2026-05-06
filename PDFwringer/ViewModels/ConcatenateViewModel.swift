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

        do {
            let urls = files.map(\.url)
            try await concatenator.concatenate(
                sources: urls,
                destination: destination,
                progress: { [weak self] p in self?.progress = p }
            )

            let totalPages = files.reduce(0) { $0 + $1.pageCount }
            resultMessage = "Done! Merged \(files.count) files (\(totalPages) pages)."
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
}
