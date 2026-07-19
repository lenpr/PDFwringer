import Foundation
import PDFKit

/// Drives the split/extract flow: split-by-N, keep-pages, and remove-pages operations.
@MainActor @Observable
class SplitViewModel {
    var sourceURL: URL?
    var sourceDocument: PDFDocument?
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
    private var operationTask: Task<Void, Never>?

    var canProcess: Bool {
        sourceURL != nil && !isProcessing
    }

    /// Convenience for non-interactive callers. Production flows should pass the
    /// already-loaded document so an unlocked encrypted source is not reopened.
    func setSource(_ url: URL) {
        guard let document = PDFDocument(url: url), !document.isLocked else {
            sourceURL = nil
            sourceDocument = nil
            sourcePageCount = 0
            return
        }
        setSource(url, document: document)
    }

    func setSource(_ url: URL, document: PDFDocument) {
        sourceURL = url
        sourceDocument = document
        resultMessage = nil
        isError = false
        sourcePageCount = document.pageCount
    }

    func splitByPages() async {
        lastOperation = .split
        errorSource = nil
        guard let source = sourceURL, let document = sourceDocument, !isProcessing else { return }
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

        operationTask = Task {
            defer { operationTask = nil }
            do {
                let outputs = try await splitter.split(
                    document: document,
                    source: source,
                    mode: .splitEveryN(splitPagesPerFile),
                    destination: outputDir,
                    progress: { [weak self] p in self?.progress = p }
                )
                let protectionNote = document.isEncrypted ? " Password protection was removed." : ""
                resultMessage = "Done! Created \(outputs.count) files.\(protectionNote)"
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
        await operationTask?.value
    }

    func keepPages() async {
        lastOperation = .keep
        errorSource = nil
        guard let source = sourceURL, let document = sourceDocument, !isProcessing else { return }

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

            operationTask = Task {
                defer { operationTask = nil }
                do {
                    let outputs = try await splitter.split(
                        document: document,
                        source: source,
                        mode: .keepPages(indices),
                        destination: destination,
                        progress: { [weak self] p in self?.progress = p }
                    )
                    let protectionNote = document.isEncrypted ? " Password protection was removed." : ""
                    resultMessage = "Done! Extracted \(indices.count) pages.\(protectionNote)"
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
            await operationTask?.value
        } catch {
            resultMessage = error.localizedDescription
            isError = true
            errorSource = .keep
        }
    }

    func removePages() async {
        lastOperation = .remove
        errorSource = nil
        guard let source = sourceURL, let document = sourceDocument, !isProcessing else { return }

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

            operationTask = Task {
                defer { operationTask = nil }
                do {
                    let outputs = try await splitter.split(
                        document: document,
                        source: source,
                        mode: .removePages(indices),
                        destination: destination,
                        progress: { [weak self] p in self?.progress = p }
                    )
                    let remainingPages = sourcePageCount - Set(indices).count
                    let protectionNote = document.isEncrypted ? " Password protection was removed." : ""
                    resultMessage = "Done! Kept \(remainingPages) pages.\(protectionNote)"
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
            await operationTask?.value
        } catch {
            resultMessage = error.localizedDescription
            isError = true
            errorSource = .remove
        }
    }

    func retryLastOperation() async {
        switch lastOperation {
        case .split: await splitByPages()
        case .keep: await keepPages()
        case .remove: await removePages()
        case nil: break
        }
    }

    func cancel() {
        operationTask?.cancel()
    }
}
