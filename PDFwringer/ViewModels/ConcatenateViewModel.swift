import Foundation

/// Drives the merge flow: manages the ordered file list and merge execution.
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

    func addFiles(_ urls: [URL]) {
        files.append(contentsOf: PDFFileItem.from(urls: urls))
    }

    func removeFile(at offsets: IndexSet) {
        for index in offsets.sorted().reversed() {
            files.remove(at: index)
        }
    }

    func moveFiles(from source: IndexSet, to destination: Int) {
        var items = files
        let moved = source.sorted().map { items[$0] }
        for index in source.sorted().reversed() {
            items.remove(at: index)
        }
        let insertAt = min(destination, items.count)
        items.insert(contentsOf: moved, at: insertAt)
        files = items
    }

    func sortAlphabetical() {
        files.sort { $0.filename.localizedCaseInsensitiveCompare($1.filename) == .orderedAscending }
    }

    func sortReverseAlphabetical() {
        files.sort { $0.filename.localizedCaseInsensitiveCompare($1.filename) == .orderedDescending }
    }

    func clearFiles() {
        files.removeAll()
        resultMessage = nil
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
