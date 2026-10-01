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
    @ObservationIgnored private var pendingPreviewRevision: Int?
    @ObservationIgnored private var pendingPreviewPixels: CGSize?
    @ObservationIgnored private var pendingSourceData: Data?
    @ObservationIgnored private var isPreparingPreviewBase = false
    @ObservationIgnored private weak var cachedPreviewDocument: PDFDocument?
    @ObservationIgnored private var cachedPreviewKey: PreviewKey?
    @ObservationIgnored private var cachedPreviewBase: CGImage?
    @ObservationIgnored private weak var publishedPreviewDocument: PDFDocument?
    @ObservationIgnored private var publishedPreviewKey: PreviewKey?

    private struct PreviewKey: Equatable {
        let page: Int
        let revision: Int?
        let pixels: CGSize?
        let pageIdentity: ObjectIdentifier
        let rotation: Int
        let cropBox: CGRect
        let mediaBox: CGRect
    }
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

    /// Reuse is opt-in: callers must advance the revision for content edits.
    /// Geometry/page identity are checked too. Without a revision, always take
    /// a fresh snapshot so arbitrary PDFKit edits cannot leave a stale preview.
    func updatePreview(
        document: PDFDocument, page: Int, selection: PageSelection? = nil,
        documentRevision: Int? = nil, pixelSize: CGSize? = nil, sourceData: Data? = nil
    ) {
        guard !isSaving else { return }
        let sameInput = matchesPending(document, page: page, revision: documentRevision, pixels: pixelSize)
        let hasReusableBase = matchesCache(document, page: page, revision: documentRevision, pixels: pixelSize)
        if !(sameInput && (hasReusableBase || (documentRevision != nil && isPreparingPreviewBase))) {
            previewTask?.cancel()
        }
        if !hasReusableBase { clearPreviewBase() }
        if publishedPreviewDocument !== document || lastPublishedPreviewPage != page
            || publishedPreviewKey?.revision != documentRevision {
            previewImage = nil
        }
        previewUnavailable = false
        isPreviewUpdating = true
        let includesPage = selection.map { $0.includes(page) } ?? true
        pendingPreviewSettings = includesPage ? settings : .init()
        previewGeneration += 1
        pendingPreviewDocument = document
        pendingPreviewPage = page
        pendingPreviewRevision = documentRevision
        pendingPreviewPixels = pixelSize
        pendingSourceData = sourceData
        startPendingPreviewIfNeeded()
    }

    private func matchesPending(_ document: PDFDocument, page: Int, revision: Int?, pixels: CGSize?) -> Bool {
        pendingPreviewDocument === document && pendingPreviewPage == page
            && pendingPreviewRevision == revision && pendingPreviewPixels == pixels
    }

    private func matchesCache(_ document: PDFDocument, page: Int, revision: Int?, pixels: CGSize?) -> Bool {
        revision != nil && cachedPreviewDocument === document && cachedPreviewBase != nil
            && cachedPreviewKey?.page == page && cachedPreviewKey?.revision == revision
            && cachedPreviewKey?.pixels == pixels
    }

    private func previewSource(
        _ document: PDFDocument, page index: Int, revision: Int?, pixels: CGSize?
    ) throws -> (PDFPage, PreviewKey) {
        if let pixels {
            guard pixels.width.isFinite, pixels.height.isFinite,
                  pixels.width >= 1, pixels.height >= 1,
                  pixels.width <= 4096, pixels.height <= 4096 else {
                throw PDFwringerError.cannotCreateOutput
            }
        }
        guard let page = document.page(at: index) else { throw PDFwringerError.cannotCreateOutput }
        let crop = page.bounds(for: .cropBox)
        let media = page.bounds(for: .mediaBox)
        guard [crop.minX, crop.minY, crop.width, crop.height, media.minX, media.minY, media.width, media.height]
                .allSatisfy(\.isFinite), crop.width > 0, crop.height > 0 else {
            throw PDFwringerError.cannotCreateOutput
        }
        return (page, PreviewKey(page: index, revision: revision, pixels: pixels,
                                 pageIdentity: ObjectIdentifier(page), rotation: page.rotation,
                                 cropBox: crop, mediaBox: media))
    }

    private func startPendingPreviewIfNeeded() {
        guard !isRendering, let document = pendingPreviewDocument else { return }
        let pageIndex = pendingPreviewPage
        let revision = pendingPreviewRevision
        let pixels = pendingPreviewPixels
        let sourceData = pendingSourceData
        let isWarm = matchesCache(document, page: pageIndex, revision: revision, pixels: pixels)
        let initialGeneration = previewGeneration
        isRendering = true

        previewTask = Task { @MainActor [weak self] in
            var generation = initialGeneration
            defer { self?.finishPreview(generation: generation) }
            // Cold requests debounce before PDFKit access. Warm requests coalesce
            // at a frame cadence, taking the newest settings after the wait.
            try? await Task.sleep(for: .milliseconds(isWarm ? 16 : 100))
            guard !Task.isCancelled, let self,
                  self.matchesPending(document, page: pageIndex, revision: revision, pixels: pixels) else { return }
            generation = self.previewGeneration
            do {
                let (page, key) = try self.previewSource(document, page: pageIndex, revision: revision, pixels: pixels)
                let base: CGImage
                if self.cachedPreviewDocument === document, self.cachedPreviewKey == key,
                   let image = self.cachedPreviewBase {
                    base = image
                } else {
                    self.isPreparingPreviewBase = true
                    var data: Data?
                    if revision != nil, page.annotations.isEmpty, let sourceData {
                        data = try await PDFPageWorker.readOnlySnapshot(sourceData: sourceData, index: pageIndex,
                            rotation: key.rotation, cropBox: key.cropBox, mediaBox: key.mediaBox)
                    }
                    try Task.checkCancellation()
                    if data == nil { data = page.dataRepresentation }
                    guard let data else { throw PDFwringerError.cannotCreateOutput }
                    let image = try await PDFPageWorker.run(pageData: data) { isolatedPage in
                        guard let image = PDFRasterizer.renderPreview(isolatedPage, pixelSize: pixels) else {
                            throw PDFwringerError.cannotCreateOutput
                        }
                        return image
                    }
                    self.isPreparingPreviewBase = false
                    try Task.checkCancellation()
                    guard self.matchesPending(document, page: pageIndex, revision: revision, pixels: pixels),
                          try self.previewSource(document, page: pageIndex, revision: revision, pixels: pixels).1 == key else { return }
                    base = image
                    if revision != nil {
                        self.cachedPreviewDocument = document
                        self.cachedPreviewKey = key
                        self.cachedPreviewBase = image
                    }
                }
                generation = self.previewGeneration
                let currentSettings = self.pendingPreviewSettings
                if revision != nil, self.publishedPreviewDocument === document,
                   self.publishedPreviewKey == key, self.lastPublishedPreviewSettings == currentSettings,
                   self.previewImage != nil { return }
                let worker = Task.detached(priority: .userInitiated) {
                    try Task.checkCancellation()
                    guard let image = PDFColorAdjuster.adjustImage(base, settings: currentSettings, renderImmediately: true) else {
                        throw PDFwringerError.cannotCreateOutput
                    }
                    try Task.checkCancellation()
                    return image
                }
                let image = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                guard self.previewGeneration == generation,
                      try self.previewSource(document, page: pageIndex, revision: revision, pixels: pixels).1 == key else { return }
                self.previewImage = NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
                self.publishedPreviewDocument = document
                self.publishedPreviewKey = key
                self.lastPublishedPreviewPage = pageIndex
                self.lastPublishedPreviewSettings = currentSettings
            } catch {
                guard self.previewGeneration == generation, !(error is CancellationError) else { return }
                self.clearPreviewBase()
                self.previewImage = nil
                self.previewUnavailable = true
            }
        }
    }

    private func finishPreview(generation: Int) {
        isPreparingPreviewBase = false
        isRendering = false
        if previewGeneration != generation {
            startPendingPreviewIfNeeded()
        } else {
            isPreviewUpdating = false
        }
    }

    private func clearPreviewBase() {
        cachedPreviewBase = nil
        cachedPreviewKey = nil
        cachedPreviewDocument = nil
    }

    func cancelPreview() {
        isPreviewUpdating = false
        pendingPreviewDocument = nil
        pendingSourceData = nil
        previewGeneration += 1
        previewTask?.cancel()
        clearPreviewBase()
    }

    // MARK: - Save

    func save(
        source: URL,
        document: PDFDocument,
        pageIndices: [Int]?
    ) async {
        guard !isSaving else { return }
        let suggestedName = source.deletingPathExtension().lastPathComponent + "_adjusted.pdf"
        guard let destination = FileDialogHelper.showSavePanel(suggestedName: suggestedName) else { return }

        let operationSettings = settings
        let operationPageIndices = pageIndices
        let sourceWasEncrypted = document.isEncrypted

        resultMessage = nil
        lastOutputURL = nil
        isError = false
        isSaving = true
        cancelPreview()
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
