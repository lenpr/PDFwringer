import Foundation
import PDFKit

/// Drives the Concatenate tab: manages the ordered file list, reordering, and merge execution.
@MainActor @Observable
class ConcatenateViewModel {
    var files: [PDFFileItem] = []
    var isProcessing = false
    var progress: Double = 0
    var resultMessage: String?
    var isError = false

    private let concatenator = PDFConcatenator()

    var canConcatenate: Bool {
        files.count >= 2 && !isProcessing
    }

    func addFiles(_ urls: [URL]) {
        for url in urls {
            guard url.pathExtension.lowercased() == "pdf" else { continue }
            let pageCount: Int
            if let doc = PDFDocument(url: url) {
                pageCount = doc.pageCount
            } else {
                pageCount = 0
            }
            let bookmarkData = (try? url.bookmarkData(options: .withSecurityScope)) ?? Data()
            let item = PDFFileItem(url: url, bookmarkData: bookmarkData, pageCount: pageCount)
            files.append(item)
        }
    }

    func removeFile(at offsets: IndexSet) {
        files.remove(atOffsets: offsets)
    }

    func moveFiles(from source: IndexSet, to destination: Int) {
        files.move(fromOffsets: source, toOffset: destination)
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
        guard canConcatenate else { return }

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
