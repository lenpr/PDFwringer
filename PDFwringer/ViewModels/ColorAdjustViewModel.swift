import AppKit
import PDFKit

/// Drives color adjustment: preview rendering, preset application, and save operations.
@MainActor @Observable
class ColorAdjustViewModel {
    var brightness: Float = 0
    var contrast: Float = 1
    var saturation: Float = 1

    var previewImage: NSImage?
    @ObservationIgnored private(set) var lastPublishedPreviewSettings: PDFColorAdjuster.Settings?
    var resultMessage: String?
    var isError = false
    var isSaving = false
    var progress: Double = 0
    var lastOutputURL: URL?

    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private var previewGeneration = 0
    @ObservationIgnored private weak var pendingPreviewDocument: PDFDocument?
    @ObservationIgnored private var pendingPreviewPage = 0
    /// Single-flight guard: prevents concurrent preview renders from exhausting resources.
    @ObservationIgnored private var isRendering = false
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

    // MARK: - Preview

    func updatePreview(document: PDFDocument, page: Int) {
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
        let currentSettings = settings

        // Snapshot on MainActor; the worker reconstructs its own one-page document.
        guard let pageData = document.page(at: pendingPreviewPage)?.dataRepresentation else { return }

        isRendering = true

        previewTask = Task { @MainActor [weak self] in
            defer { self?.finishPreview(generation: gen) }
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }

            guard !Task.isCancelled else { return }

            do {
                let previewData = try await PDFPageWorker.run(pageData: pageData) { page in
                    guard let (rendered, _) = PDFRasterizer.render(
                        page,
                        dpi: 150,
                        grayscale: false
                    ) else {
                        throw PDFwringerError.cannotCreateOutput
                    }

                    let adjusted = PDFColorAdjuster.adjustImage(
                        rendered,
                        settings: currentSettings
                    ) ?? rendered
                    guard let data = PDFRasterizer.jpegData(for: adjusted, quality: 0.9) else {
                        throw PDFwringerError.cannotCreateOutput
                    }
                    return data
                }
                try Task.checkCancellation()

                guard let self,
                      self.previewGeneration == gen,
                      let preview = NSImage(data: previewData) else { return }
                self.lastPublishedPreviewSettings = currentSettings
                self.previewImage = preview
            } catch {
                // Preview generation is best-effort; a subsequent change retries it.
            }
        }
    }

    private func finishPreview(generation: Int) {
        isRendering = false
        if previewGeneration != generation {
            startPendingPreviewIfNeeded()
        }
    }

    func cancelPreview() {
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

        resultMessage = nil
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
                    settings: settings,
                    pages: pageIndices,
                    dpi: 150,
                    quality: 0.85,
                    progress: { [weak self] p in self?.progress = p }
                )
                resultMessage = String(localized: "Saved.")
                if document.isEncrypted && !settings.isIdentity {
                    resultMessage? += String(localized: " Password protection was removed.")
                }
                isError = false
                lastOutputURL = destination
            } catch is CancellationError {
                resultMessage = String(localized: "Cancelled.")
                isError = false
            } catch {
                resultMessage = error.localizedDescription
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
