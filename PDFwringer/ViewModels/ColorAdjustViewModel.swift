import AppKit
import PDFKit

/// Drives color adjustment: preview rendering, preset application, and save operations.
@MainActor @Observable
class ColorAdjustViewModel {
    var brightness: Float = 0
    var contrast: Float = 1
    var saturation: Float = 1
    var applyAll = true
    var pageRangeText = ""
    var selectedPages: Set<Int> = []

    var previewImage: NSImage?
    var resultMessage: String?
    var isError = false
    var isWarning = false
    var isSaving = false
    var progress: Double = 0
    var lastOutputURL: URL?

    private var previewTask: Task<Void, Never>?
    private var operationTask: Task<Void, Never>?
    private var previewGeneration = 0
    /// Single-flight guard: prevents concurrent preview renders from exhausting resources.
    private var isRendering = false
    private let adjuster = PDFColorAdjuster()

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
        let gen = previewGeneration
        let currentSettings = settings

        // Get CGPDFPage ref on MainActor (PDFKit thread safety)
        guard let pageRef = document.page(at: page)?.pageRef else { return }

        // Single-flight: if a render is already in progress, just cancel it and
        // let the generation check discard its result. Don't spawn concurrent renders.
        guard !isRendering else { return }
        isRendering = true

        // Render off MainActor to avoid blocking UI
        previewTask = Task.detached(priority: .userInitiated) { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.isRendering = false
                    // If generation moved on while we were rendering, trigger one more update
                    if let self, self.previewGeneration != gen {
                        // Schedule a re-render for the latest state on next runloop cycle
                        self.previewTask = Task { [weak self] in
                            try? await Task.sleep(for: .milliseconds(50))
                            guard let self else { return }
                            self.updatePreview(document: document, page: page)
                        }
                    }
                }
            }

            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }

            guard let (rendered, _) = PDFCompressor.renderPage(pageRef, dpi: 150, grayscale: false) else { return }
            guard !Task.isCancelled else { return }

            let adjusted = PDFColorAdjuster.adjustImage(rendered, settings: currentSettings) ?? rendered
            guard !Task.isCancelled else { return }

            let nsImage = NSImage(cgImage: adjusted, size: NSSize(width: adjusted.width, height: adjusted.height))

            await MainActor.run { [weak self] in
                guard let self, self.previewGeneration == gen else { return }
                self.previewImage = nsImage
            }
        }
    }

    func cancelPreview() {
        previewTask?.cancel()
    }

    // MARK: - Save

    func save(source: URL, pageCount: Int, onMutate: (() -> Void)?) async {
        let suggestedName = source.deletingPathExtension().lastPathComponent + "_adjusted.pdf"
        guard let destination = FileDialogHelper.showSavePanel(suggestedName: suggestedName) else { return }

        resultMessage = nil
        isError = false
        isWarning = false
        isSaving = true
        progress = 0
        onMutate?()

        let pages: [Int]?
        if applyAll {
            pages = nil
        } else if let parsed = try? PageRangeParser.parse(pageRangeText, pageCount: pageCount), !parsed.isEmpty {
            pages = parsed
        } else if !selectedPages.isEmpty {
            pages = Array(selectedPages.sorted())
        } else {
            isSaving = false
            return
        }

        operationTask = Task {
            defer { operationTask = nil }
            do {
                let result = try await adjuster.adjust(
                    source: source,
                    destination: destination,
                    settings: settings,
                    pages: pages,
                    dpi: 150,
                    quality: 0.85,
                    progress: { [weak self] p in self?.progress = p }
                )
                if result.skippedPages > 0 {
                    resultMessage = String(localized: "Saved with \(result.skippedPages) of \(result.totalPages) pages skipped due to rendering issues.")
                    isWarning = true
                } else {
                    resultMessage = String(localized: "Saved.")
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
