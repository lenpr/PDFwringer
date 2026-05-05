import Foundation
import PDFKit

/// Drives the split/extract flow: split-by-N, keep-pages, and remove-pages operations.
@MainActor @Observable
class SplitViewModel {
    var sourceURL: URL?
    var sourcePageCount: Int = 0
    var splitPagesPerFile: Int = 1
    var keepPagesText: String = ""
    var removePagesText: String = ""
    var isProcessing = false
    var progress: Double = 0
    var resultMessage: String?
    var isError = false

    private let splitter = PDFSplitter()

    var canProcess: Bool {
        sourceURL != nil && !isProcessing
    }

    func setSource(_ url: URL) {
        sourceURL = url
        resultMessage = nil
        isError = false
        if let doc = PDFDocument(url: url) {
            sourcePageCount = doc.pageCount
        }
    }

    func splitByPages() async {
        guard let source = sourceURL else { return }
        guard splitPagesPerFile >= 1 else {
            resultMessage = "Pages per file must be at least 1."
            isError = true
            return
        }

        guard let outputDir = FileDialogHelper.showDirectoryPanel() else { return }

        isProcessing = true
        progress = 0
        resultMessage = nil
        isError = false

        do {
            let outputs = try await splitter.split(
                source: source,
                mode: .splitEveryN(splitPagesPerFile),
                destination: outputDir,
                progress: { [weak self] p in self?.progress = p }
            )
            resultMessage = "Done! Created \(outputs.count) files."
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

    func keepPages() async {
        guard let source = sourceURL else { return }

        do {
            let indices = try PageRangeParser.parse(keepPagesText, pageCount: sourcePageCount)
            guard !indices.isEmpty else {
                resultMessage = "No pages specified."
                isError = true
                return
            }

            let suggestedName = source.deletingPathExtension().lastPathComponent + "_extracted.pdf"
            guard let destination = FileDialogHelper.showSavePanel(suggestedName: suggestedName) else { return }

            isProcessing = true
            progress = 0
            resultMessage = nil
            isError = false

            let outputs = try await splitter.split(
                source: source,
                mode: .keepPages(indices),
                destination: destination,
                progress: { [weak self] p in self?.progress = p }
            )
            resultMessage = "Done! Extracted \(indices.count) pages."
            isError = false
            _ = outputs
        } catch is CancellationError {
            resultMessage = "Cancelled."
            isError = false
        } catch {
            resultMessage = error.localizedDescription
            isError = true
        }

        isProcessing = false
    }

    func removePages() async {
        guard let source = sourceURL else { return }

        do {
            let indices = try PageRangeParser.parse(removePagesText, pageCount: sourcePageCount)
            guard !indices.isEmpty else {
                resultMessage = "No pages specified."
                isError = true
                return
            }

            let suggestedName = source.deletingPathExtension().lastPathComponent + "_trimmed.pdf"
            guard let destination = FileDialogHelper.showSavePanel(suggestedName: suggestedName) else { return }

            isProcessing = true
            progress = 0
            resultMessage = nil
            isError = false

            let outputs = try await splitter.split(
                source: source,
                mode: .removePages(indices),
                destination: destination,
                progress: { [weak self] p in self?.progress = p }
            )
            let remainingPages = sourcePageCount - Set(indices).count
            resultMessage = "Done! Kept \(remainingPages) pages."
            isError = false
            _ = outputs
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
