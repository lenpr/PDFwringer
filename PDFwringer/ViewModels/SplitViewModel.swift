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
    var lastOutputURL: URL?
    var errorSource: ErrorSource?

    enum ErrorSource: Equatable { case split, keep, remove }

    private let splitter = PDFSplitter()
    private var lastOperation: ErrorSource?

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
        lastOperation = .split
        errorSource = nil
        guard let source = sourceURL, !isProcessing else { return }
        guard splitPagesPerFile >= 1 else {
            resultMessage = "Pages per file must be at least 1."
            isError = true
            errorSource = .split
            return
        }
        if splitPagesPerFile > sourcePageCount {
            resultMessage = "Pages per file exceeds total page count (\(sourcePageCount))."
            isError = true
            errorSource = .split
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
            lastOutputURL = outputDir
        } catch is CancellationError {
            resultMessage = "Cancelled."
            isError = false
        } catch {
            resultMessage = error.localizedDescription
            isError = true
            errorSource = .split
        }

        isProcessing = false
    }

    func keepPages() async {
        lastOperation = .keep
        errorSource = nil
        guard let source = sourceURL, !isProcessing else { return }

        do {
            let indices = try PageRangeParser.parse(keepPagesText, pageCount: sourcePageCount)
            guard !indices.isEmpty else {
                resultMessage = "No pages specified."
                isError = true
                errorSource = .keep
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
            lastOutputURL = destination
            _ = outputs
        } catch is CancellationError {
            resultMessage = "Cancelled."
            isError = false
        } catch {
            resultMessage = error.localizedDescription
            isError = true
            errorSource = .keep
        }

        isProcessing = false
    }

    func removePages() async {
        lastOperation = .remove
        errorSource = nil
        guard let source = sourceURL, !isProcessing else { return }

        do {
            let indices = try PageRangeParser.parse(removePagesText, pageCount: sourcePageCount)
            guard !indices.isEmpty else {
                resultMessage = "No pages specified."
                isError = true
                errorSource = .remove
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
            lastOutputURL = destination
            _ = outputs
        } catch is CancellationError {
            resultMessage = "Cancelled."
            isError = false
        } catch {
            resultMessage = error.localizedDescription
            isError = true
            errorSource = .remove
        }

        isProcessing = false
    }

    func retryLastOperation() async {
        switch lastOperation {
        case .split: await splitByPages()
        case .keep: await keepPages()
        case .remove: await removePages()
        case nil: break
        }
    }
}
