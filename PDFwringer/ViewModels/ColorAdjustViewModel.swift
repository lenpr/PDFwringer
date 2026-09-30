import AppKit
import PDFKit

/// Drives color adjustment: preview rendering, preset application, and save operations.
@MainActor @Observable
class ColorAdjustViewModel {
    var brightness: Float = 0
    var contrast: Float = 1
    var saturation: Float = 1

    var previewImage: NSImage?
    private(set) var previewUnavailable = false
    private(set) var isPreviewUpdating = false
    private(set) var lastPublishedPreviewPage: Int?
    @ObservationIgnored private(set) var lastPublishedPreviewSettings: PDFColorAdjuster.Settings?
    var resultMessage: String?
    var isError = false
    var isSaving = false
    var progress: Double = 0
    var lastOutputURL: URL?
    private(set) var successfulSaveCount = 0

    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private var previewGeneration = 0
    @ObservationIgnored private weak var pendingPreviewDocument: PDFDocument?
    @ObservationIgnored private var pendingPreviewPage = 0
    @ObservationIgnored private var pendingPreviewSettings = PDFColorAdjuster.Settings(brightness: 0, contrast: 1, saturation: 1)
    /// Single-flight guard: prevents concurrent preview renders from exhausting resources.
    @ObservationIgnored private(set) var isRendering = false
    @ObservationIgnored private let adjuster = PDFColorAdjuster()

    var settings: PDFColorAdjuster.Settings {
        .init(brightness: brightness, contrast: contrast, saturation: saturation)
    }

    var isIdentity: Bool { settings.isIdentity }

    func applyPreset(_ preset: ColorPreset) {
        brightness = preset.settings.brightness
        contrast = preset.settings.contrast
        saturation = preset.settings.saturation
    }

    func reset() {
        brightness = 0
        contrast = 1
        saturation = 1
    }

    private var savedSettings = PDFColorAdjuster.Settings(brightness: 0, contrast: 1, saturation: 1)
    var hasUnsavedChanges: Bool { settings != savedSettings }

    // MARK: - Preview

    func updatePreview(document: PDFDocument, page: Int, selection: PageSelection? = nil) {
        if lastPublishedPreviewPage != page { previewImage = nil }
        previewUnavailable = false
        isPreviewUpdating = true
        let includesPage = selection.map { $0.includes(page) } ?? true
        pendingPreviewSettings = includesPage ? settings : .init(brightness: 0, contrast: 1, saturation: 1)
        previewTask?.cancel()
        previewGeneration += 1
        pendingPreviewDocument = document
        pendingPreviewPage = page
        startPendingPreviewIfNeeded()
    }

    private func startPendingPreviewIfNeeded() {
        guard !isRendering,
              let document = pendingPreviewDocument else { return }

        let gen = previewGeneration
        let currentSettings = pendingPreviewSettings

        let pageIndex = pendingPreviewPage

        isRendering = true

        previewTask = Task { @MainActor [weak self] in
            defer { self?.finishPreview(generation: gen) }
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }

            // Debounce before serializing a potentially expensive page. Cancelled
            // slider changes must not perform this work on the UI thread.
            // PDFKit access stays on MainActor; the worker receives only Data.
            do {
                guard let pageData = document.page(at: pageIndex)?.dataRepresentation else {
                    throw PDFwringerError.cannotCreateOutput
                }
                let previewData = try await PDFPageWorker.run(pageData: pageData) { page in
                    guard let (rendered, _) = PDFRasterizer.render(
                        page,
                        dpi: 150,
                        grayscale: false
                    ) else {
                        throw PDFwringerError.cannotCreateOutput
                    }

                    guard let adjusted = PDFColorAdjuster.adjustImage(
                        rendered,
                        settings: currentSettings
                    ) else { throw PDFwringerError.cannotCreateOutput }
                    guard let data = PDFRasterizer.jpegData(for: adjusted, quality: 0.9) else {
                        throw PDFwringerError.cannotCreateOutput
                    }
                    return data
                }
                try Task.checkCancellation()

                guard let self, self.previewGeneration == gen else { return }
                guard let preview = NSImage(data: previewData) else {
                    throw PDFwringerError.cannotCreateOutput
                }
                self.lastPublishedPreviewPage = pageIndex
                self.lastPublishedPreviewSettings = currentSettings
                self.previewImage = preview
            } catch {
                guard let self, self.previewGeneration == gen, !(error is CancellationError) else { return }
                self.previewImage = nil
                self.previewUnavailable = true
            }
        }
    }

    private func finishPreview(generation: Int) {
        isRendering = false
        if previewGeneration != generation {
            startPendingPreviewIfNeeded()
        } else {
            isPreviewUpdating = false
        }
    }

    func cancelPreview() {
        isPreviewUpdating = false
        pendingPreviewDocument = nil
        previewGeneration += 1
        previewTask?.cancel()
    }

    // MARK: - Save

    func save(
        source: URL,
        document: PDFDocument,
        pageIndices: [Int]?
    ) async {
        let suggestedName = source.deletingPathExtension().lastPathComponent + "_adjusted.pdf"
        guard let destination = FileDialogHelper.showSavePanel(suggestedName: suggestedName) else { return }

        let operationSettings = settings
        let operationPageIndices = pageIndices
        let sourceWasEncrypted = document.isEncrypted

        resultMessage = nil
        lastOutputURL = nil
        isError = false
        isSaving = true
        progress = 0

        operationTask = Task {
            defer { operationTask = nil }
            do {
                try await adjuster.adjust(
                    document: document,
                    source: source,
                    destination: destination,
                    settings: operationSettings,
                    pages: operationPageIndices,
                    dpi: 150,
                    quality: 0.85,
                    progress: { [weak self] p in self?.progress = p }
                )
                resultMessage = String(localized: "Saved.")
                if sourceWasEncrypted && !operationSettings.isIdentity {
                    resultMessage? += String(localized: " Password protection was removed.")
                }
                isError = false
                savedSettings = operationSettings
                successfulSaveCount += 1
                lastOutputURL = destination
            } catch is CancellationError {
                resultMessage = String(localized: "Cancelled.")
                isError = false
            } catch {
                resultMessage = PDFwringerError.userMessage(for: error)
                isError = true
            }

            isSaving = false
        }
        await operationTask?.value
    }

    func cancel() {
        operationTask?.cancel()
    }
}
