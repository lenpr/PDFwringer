import Foundation
import PDFKit

/// Drives the compress flow: manages source file state, compression settings, background size estimation, and execution.
///
/// Size estimates are computed in the background for every combination of level/quality/grayscale
/// and cached by a composite key (e.g. "medium-good-false"). This allows instant display when the
/// user switches settings.
@MainActor @Observable
class CompressViewModel {
    var sourceURL: URL?
    var sourcePageCount: Int = 0
    var sourceFileSize: Int64 = 0
    var selectedLevel: CompressionLevel = .medium
    var selectedQuality: JPEGQuality = .good
    var grayscale: Bool = false
    var stripMetadata: Bool = false
    var isProcessing = false
    var progress: Double = 0
    var resultMessage: String?
    var isError = false
    var isWarning = false
    var lastOutputURL: URL?
    var pdfDocument: PDFDocument?

    // Background-computed real sizes per level (keyed by "level-quality-grayscale")
    var estimatedSizes: [String: Int64] = [:]
    private var estimationTask: Task<Void, Never>?

    private let compressor = PDFCompressor()

    var canCompress: Bool {
        sourceURL != nil && !isProcessing
    }

    private static let largeFileThreshold: Int64 = 500_000_000 // 500 MB

    var largeFileWarning: String? {
        guard sourceFileSize > Self.largeFileThreshold, selectedLevel.isRasterize else { return nil }
        return "Large file (\(Formatting.fileSize(sourceFileSize))). Rasterization may use significant memory and take a while."
    }

    var currentEstimateKey: String {
        "\(selectedLevel.rawValue)-\(selectedQuality.rawValue)-\(grayscale)"
    }

    var estimatedSizeText: String? {
        guard sourceFileSize > 0 else { return nil }
        guard let estimated = estimatedSizes[currentEstimateKey] else { return nil }
        if estimated >= sourceFileSize {
            return "\(Formatting.fileSize(estimated)) (may not reduce)"
        }
        let ratio = Int((1.0 - Double(estimated) / Double(sourceFileSize)) * 100)
        return "\(Formatting.fileSize(estimated)) (\(ratio)% smaller)"
    }

    var isEstimating: Bool {
        estimatedSizes[currentEstimateKey] == nil && sourceURL != nil
    }

    func setSource(_ url: URL) {
        sourceURL = url
        resultMessage = nil
        isError = false
        estimatedSizes = [:]

        if let doc = PDFDocument(url: url) {
            sourcePageCount = doc.pageCount
            pdfDocument = doc
        } else {
            sourcePageCount = 0
            pdfDocument = nil
        }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)),
           let size = attrs[.size] as? Int64 {
            sourceFileSize = size
        } else {
            sourceFileSize = 0
        }

        startBackgroundEstimation()
    }

    func onSettingsChanged() {
        // If we don't have an estimate for the current settings, compute it
        if estimatedSizes[currentEstimateKey] == nil {
            startBackgroundEstimation()
        }
    }

    private func startBackgroundEstimation() {
        estimationTask?.cancel()

        guard let source = sourceURL else { return }
        let compressor = self.compressor

        estimationTask = Task.detached(priority: .utility) {
            for level in CompressionLevel.allCases {
                for quality in JPEGQuality.allCases {
                    for gs in [false, true] {
                        let key = "\(level.rawValue)-\(quality.rawValue)-\(gs)"

                        if Task.isCancelled { return }

                        let size = compressor.compressFirstPage(source: source, level: level, quality: quality, grayscale: gs)
                        if Task.isCancelled { return }

                        if let size {
                            await MainActor.run {
                                self.estimatedSizes[key] = size
                            }
                        }
                        await Task.yield()
                    }
                }
            }
        }
    }

    func performCompression() async {
        guard let source = sourceURL, !isProcessing else { return }

        let suggestedName = source.deletingPathExtension().lastPathComponent + "_compressed.pdf"
        guard let destination = FileDialogHelper.showSavePanel(suggestedName: suggestedName) else { return }

        isProcessing = true
        progress = 0
        resultMessage = nil
        isError = false
        isWarning = false
        lastOutputURL = nil

        do {
            let result = try await compressor.compress(
                source: source,
                destination: destination,
                level: selectedLevel,
                quality: selectedQuality,
                grayscale: grayscale,
                stripMetadata: stripMetadata,
                progress: { [weak self] p in self?.progress = p }
            )

            let newSize = result.outputSize

            if result.skippedPages > 0 {
                let ratio = sourceFileSize > 0
                    ? Int((1.0 - Double(newSize) / Double(sourceFileSize)) * 100)
                    : 0
                resultMessage = "Done (\(ratio)% smaller) but \(result.skippedPages) of \(result.totalPages) pages could not be processed."
                isError = false
                isWarning = true
                lastOutputURL = destination
            } else if newSize >= sourceFileSize && sourceFileSize > 0 {
                resultMessage = "Result (\(Formatting.fileSize(newSize))) is not smaller than original (\(Formatting.fileSize(sourceFileSize))). File saved."
                isError = false
                isWarning = false
                lastOutputURL = destination
            } else {
                let ratio = sourceFileSize > 0
                    ? Int((1.0 - Double(newSize) / Double(sourceFileSize)) * 100)
                    : 0
                resultMessage = "Done! \(ratio)% smaller (\(Formatting.fileSize(sourceFileSize)) → \(Formatting.fileSize(newSize)))"
                isError = false
                isWarning = false
                lastOutputURL = destination
            }
        } catch is CancellationError {
            resultMessage = "Cancelled."
            isError = false
            isWarning = false
        } catch {
            resultMessage = error.localizedDescription
            isError = true
            isWarning = false
        }

        isProcessing = false
    }
}
