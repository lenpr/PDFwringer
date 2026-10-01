import Foundation
import PDFKit

/// Drives the compress flow: manages source file state, compression settings, background size estimation, and execution.
///
/// Optional probes compute only the displayed quality/color configuration;
/// estimates from previously displayed settings remain cached for this source.
@MainActor @Observable
class CompressViewModel {
    var sourceURL: URL?
    var sourcePageCount: Int = 0
    var sourceFileSize: Int64 = 0
    var mode: CompressionMode = .manual { didSet { if mode != oldValue { settingsChanged(); estimateConfigurationChanged() } } }
    var targetMegabytes = "10" { didSet { if targetMegabytes != oldValue { settingsChanged() } } }
    var allowRasterization = false { didSet { if allowRasterization != oldValue { settingsChanged() } } }
    var selectedLevel: CompressionLevel = .medium { didSet { if selectedLevel != oldValue { settingsChanged() } } }
    var selectedQuality: JPEGQuality = .good { didSet { if selectedQuality != oldValue { settingsChanged(); estimateConfigurationChanged() } } }
    var grayscale = false { didSet { if grayscale != oldValue { settingsChanged(); estimateConfigurationChanged() } } }
    var removeAnnotations = false { didSet { if removeAnnotations != oldValue { settingsChanged() } } }
    private(set) var prepared: PDFCompressor.PreparedCompression?
    var comparisonShowsResult = false
    private var operationGeneration = 0
    var isProcessing = false
    private(set) var isPublishing = false
    var progress: Double = 0
    var resultMessage: String?
    var isError = false
    var lastOutputURL: URL?
    var pdfDocument: PDFDocument?

    // Background-computed real sizes per level (keyed by "level-quality-grayscale")
    var estimatedSizes: [String: Int64] = [:]
    // Instant heuristic estimates (available immediately on file load)
    var heuristicSizes: [String: Int64] = [:]
    private var estimationTask: Task<Void, Never>?
    private var estimationGeneration = 0
    private var estimationEnabled = false

    private let compressor = PDFCompressor()

    var canCompress: Bool {
        sourceURL != nil && !isProcessing && (mode == .manual || targetBytes != nil)
    }

    var targetBytes: Int64? { CompressionTarget.bytes(from: targetMegabytes) }
    var hasPreparedResult: Bool { prepared != nil }
    var canCompare: Bool { prepared?.previewDocument != nil }
    var rasterizationAllowed: Bool {
        mode == .manual ? selectedLevel.isRasterize : allowRasterization
    }

    private static let largeFileThreshold: Int64 = 500_000_000 // 500 MB

    var largeFileWarning: String? {
        guard sourceFileSize > Self.largeFileThreshold, rasterizationAllowed else { return nil }
        return "Large file (\(Formatting.fileSize(sourceFileSize))). Rasterization may use significant memory and take a while."
    }

    /// Convenience for non-interactive callers. Production flows should pass the
    /// already-loaded document so an unlocked encrypted source is not reopened.
    func setSource(_ url: URL) {
        discardPreparedResult()
        allowRasterization = false
        resultMessage = nil
        isError = false
        progress = 0
        guard let document = PDFDocument(url: url), !document.isLocked else {
            invalidateEstimation()
            estimationEnabled = false
            sourceURL = nil
            sourcePageCount = 0
            sourceFileSize = 0
            pdfDocument = nil
            estimatedSizes = [:]
            heuristicSizes = [:]
            return
        }
        setSource(url, document: document)
    }

    func setSource(_ url: URL, document: PDFDocument) {
        discardPreparedResult()
        allowRasterization = false
        invalidateEstimation()
        sourceURL = url
        resultMessage = nil
        isError = false
        progress = 0
        estimatedSizes = [:]
        heuristicSizes = [:]
        sourcePageCount = document.pageCount
        pdfDocument = document

        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)),
           let size = attrs[.size] as? Int64 {
            sourceFileSize = size
        } else {
            sourceFileSize = 0
        }

        computeHeuristics()
        estimationEnabled = true
        startBackgroundEstimation()
    }

    private func computeHeuristics() {
        guard sourceFileSize > 0, sourcePageCount > 0 else { return }

        let pageCount = sourcePageCount

        // Sample at most 10 pages to estimate average dimensions (avoids UI freeze on large PDFs)
        var avgPixelsAt72: Double = 595.0 * 842.0
        if let doc = pdfDocument {
            var totalPixels: Double = 0
            var validPages = 0
            let samplesToTake = min(pageCount, 10)
            for i in 0..<samplesToTake {
                if let page = doc.page(at: i) {
                    let bounds = page.bounds(for: .cropBox)
                    if bounds.width > 0 && bounds.height > 0 && bounds.width < 100_000 && bounds.height < 100_000 {
                        totalPixels += Double(bounds.width) * Double(bounds.height)
                        validPages += 1
                    }
                }
            }
            if validPages > 0 {
                avgPixelsAt72 = totalPixels / Double(validPages)
            }
        }

        for level in CompressionLevel.allCases {
            let dpi = Double(level.dpi)
            let maxLong = 16.5 * dpi
            let maxShort = 11.7 * dpi

            for quality in JPEGQuality.allCases {
                for gs in [false, true] {
                    let key = PDFCompressor.estimateKey(
                        level: level,
                        quality: quality,
                        grayscale: gs
                    )
                    let estimate: Int64

                    if !level.isRasterize {
                        estimate = Int64(Double(sourceFileSize) * 0.95)
                    } else {
                        let scale = dpi / 72.0
                        let rawW = sqrt(avgPixelsAt72) * scale
                        let rawH = sqrt(avgPixelsAt72) * scale
                        var pixW = rawW
                        var pixH = rawH
                        let longSide = max(pixW, pixH)
                        let shortSide = min(pixW, pixH)
                        if longSide > maxLong || shortSide > maxShort {
                            let downscale = min(maxLong / longSide, maxShort / shortSide)
                            pixW *= downscale
                            pixH *= downscale
                        }
                        let pixelsPerPage = pixW * pixH
                        let channels: Double = gs ? 1.0 : 3.0
                        let jpegRatio: Double
                        switch quality {
                        case .best: jpegRatio = 0.12
                        case .good: jpegRatio = 0.07
                        case .moderate: jpegRatio = 0.04
                        case .low: jpegRatio = 0.025
                        }
                        let rawEstimate = pixelsPerPage * Double(pageCount) * channels * jpegRatio + 1000
                        // Guard against Inf/NaN from extreme page dimensions
                        estimate = rawEstimate.isFinite && rawEstimate > 0 && rawEstimate < Double(Int64.max)
                            ? Int64(rawEstimate)
                            : Int64(Double(sourceFileSize) * 0.5)
                    }

                    heuristicSizes[key] = estimate
                }
            }
        }
    }

    private func startBackgroundEstimation() {
        guard estimationEnabled, estimationTask == nil, !isProcessing, prepared == nil, mode == .manual,
              let source = sourceURL,
              pdfDocument?.isEncrypted != true else { return }
        let quality = selectedQuality
        let grayscale = grayscale
        let keys = CompressionLevel.allCases.map {
            PDFCompressor.estimateKey(level: $0, quality: quality, grayscale: grayscale)
        }
        guard keys.contains(where: { estimatedSizes[$0] == nil }) else { return }
        let compressor = compressor
        let generation = estimationGeneration
        estimationTask = Task { @MainActor [weak self] in
            defer {
                if let self {
                    self.estimationTask = nil
                    if self.estimationGeneration != generation { self.startBackgroundEstimation() }
                }
            }
            do {
                // Coalesce optional work during rapid setting/source changes.
                try await Task.sleep(for: .milliseconds(100))
                try Task.checkCancellation()
                let worker = Task.detached(priority: .utility) {
                    try compressor.estimateFirstPageSizes(source: source, quality: quality, grayscale: grayscale)
                }
                let estimates = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                guard let self, self.estimationGeneration == generation, self.sourceURL == source else { return }
                self.estimatedSizes.merge(estimates) { _, latest in latest }
            } catch {
                // Heuristics remain available; failures do not trigger retries.
            }
        }
    }

    private func invalidateEstimation() {
        estimationGeneration += 1
        // Keep the slot until a noninterruptible render has actually finished.
        estimationTask?.cancel()
    }

    private func estimateConfigurationChanged() {
        invalidateEstimation()
        startBackgroundEstimation()
    }

    func cancelEstimation() {
        estimationEnabled = false
        invalidateEstimation()
    }

    func performCompression() async {
        guard canCompress, let source = sourceURL else { return }
        if mode == .targetSize, let targetBytes {
            do {
                let size = try FileManager.default.attributesOfItem(atPath: source.path(percentEncoded: false))[.size] as? Int64 ?? 0
                guard size > 0 else { throw PDFwringerError.cannotOpenDocument }
                if size < targetBytes {
                    discardPreparedResult()
                    isError = false
                    resultMessage = "Already below \(Formatting.fileSize(targetBytes)). No compression needed."
                    return
                }
            } catch {
                resultMessage = PDFwringerError.userMessage(for: error)
                isError = true
                return
            }
        }
        let suggestedName = source.deletingPathExtension().lastPathComponent + "_compressed.pdf"
        guard let destination = FileDialogHelper.showSavePanel(
            suggestedName: suggestedName,
            title: String(localized: "Choose where to save the result"),
            prompt: String(localized: "Prepare"),
            message: String(localized: "Your destination will not change until you review the result and select Save Result.")
        ) else { return }
        await prepare(to: destination)
    }

    /// Also used by tests without presenting a native file panel.
    func prepare(to destination: URL) async {
        guard canCompress, let source = sourceURL, let document = pdfDocument else { return }
        let operationMode = mode
        let operationLimit = targetBytes
        let operationAllowRasterization = allowRasterization
        let operationLevel = selectedLevel
        let operationQuality = selectedQuality
        let operationGrayscale = grayscale
        let operationRemoveAnnotations = removeAnnotations

        discardPreparedResult()
        invalidateEstimation()
        let generation = operationGeneration
        isProcessing = true
        progress = 0
        resultMessage = nil
        isError = false
        lastOutputURL = nil

        operationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.operationTask = nil
                self.isProcessing = false
                self.startBackgroundEstimation()
            }
            do {
                let reportProgress: (Double) -> Void = { [weak self] value in
                    guard let self, self.operationGeneration == generation else { return }
                    self.progress = value
                }
                let result: PDFCompressor.TargetResult
                if operationMode == .targetSize, let operationLimit {
                    result = try await self.compressor.prepareToFit(
                        document: document, source: source, destination: destination,
                        limitBytes: operationLimit, allowRasterization: operationAllowRasterization,
                        grayscale: operationGrayscale, progress: reportProgress)
                } else {
                    result = .prepared(try await self.compressor.prepare(
                        document: document, source: source, destination: destination,
                        level: operationLevel, quality: operationQuality, grayscale: operationGrayscale,
                        removeAnnotations: operationRemoveAnnotations, progress: reportProgress))
                }
                try Task.checkCancellation()
                guard self.operationGeneration == generation else { return }
                switch result {
                case .prepared(let candidate):
                    self.prepared = candidate
                    self.comparisonShowsResult = candidate.previewDocument != nil
                    let protectionNote = document.isEncrypted && candidate.level.isRasterize
                        ? " This copy is not password-protected." : ""
                    self.resultMessage = "Prepared \(Formatting.fileSize(candidate.outputSize)) using \(candidate.level.title). Not saved yet. Review it, then choose Save Result.\(protectionNote)"
                case .alreadyUnderLimit:
                    self.resultMessage = "Already below \(Formatting.fileSize(operationLimit ?? 0)). No compression needed."
                case .unattainable(let smallest):
                    self.resultMessage = "Couldn't get below \(Formatting.fileSize(operationLimit ?? 0)) with these settings. Smallest result: \(Formatting.fileSize(smallest)). Nothing saved. Try a larger limit or Manual compression."
                    self.isError = true
                }
            } catch {
                guard self.operationGeneration == generation else { return }
                if error is CancellationError {
                    self.resultMessage = "Cancelled. Nothing saved."
                } else {
                    self.resultMessage = PDFwringerError.userMessage(for: error)
                    self.isError = true
                }
            }
        }
        await operationTask?.value
    }

    func savePreparedResult() async {
        guard !isProcessing, let candidate = prepared else { return }
        comparisonShowsResult = false
        let generation = operationGeneration
        isProcessing = true
        isPublishing = true
        resultMessage = nil
        isError = false
        operationTask = Task { [self] in
            defer { operationTask = nil; isProcessing = false; isPublishing = false }
            do {
                try await candidate.commit()
                guard generation == operationGeneration else { return }
                lastOutputURL = candidate.destination
                let protectionNote = pdfDocument?.isEncrypted == true && candidate.level.isRasterize
                    ? " This copy is not password-protected." : ""
                resultMessage = "Saved \(Formatting.fileSize(candidate.outputSize)) using \(candidate.level.title).\(protectionNote)"
                isError = false
                prepared = nil
            } catch {
                guard generation == operationGeneration else { return }
                resultMessage = error is CancellationError
                    ? "Cancelled. Nothing saved. Your prepared result is still available."
                    : PDFwringerError.userMessage(for: error)
                isError = !(error is CancellationError)
            }
        }
        await operationTask?.value
    }

    private func settingsChanged() {
        discardPreparedResult()
        resultMessage = nil
        isError = false
        lastOutputURL = nil
    }

    func discardPreparedResult() {
        operationGeneration += 1
        operationTask?.cancel()
        comparisonShowsResult = false
        prepared = nil
        lastOutputURL = nil
    }

    func cancel() {
        operationTask?.cancel()
        if isPublishing { return }
        if prepared != nil {
            discardPreparedResult()
            resultMessage = "Cancelled. Nothing saved."
            isError = false
        }
    }

    private var operationTask: Task<Void, Never>?
}
