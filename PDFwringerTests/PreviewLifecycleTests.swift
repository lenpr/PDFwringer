import AppKit
import PDFKit
import Testing

@Suite("Preview lifecycle")
@MainActor
struct PreviewLifecycleTests {
    @Test("Current thumbnails precede older queued pages and ordinary work remains FIFO")
    func preferredThumbnailOrder() async throws {
        let document = PDFDocument()
        let pages = (0..<5).map { _ in SnapshotCountingPage() }
        var snapshots: [Int] = []
        for (index, page) in pages.enumerated() {
            page.setBounds(CGRect(x: 0, y: 0, width: 200, height: 300), for: .mediaBox)
            page.snapshotHook = { snapshots.append(index) }
            document.insert(page, at: index)
        }
        let cache = ThumbnailCache()
        defer { cache.cancel() }
        let size = CGSize(width: 48, height: 64)
        for index in pages.indices {
            _ = cache.thumbnail(for: index, document: document, size: size, priority: index == 4)
        }
        #expect(snapshots.isEmpty)
        try await waitUntil { cache.generation == 5 }
        #expect(snapshots == [4, 0, 1, 2, 3])
        #expect(pages.allSatisfy { $0.snapshotCount == 1 })
    }

    @Test("A new preferred page can bypass the queue after a render starts")
    func preferredThumbnailDuringRender() async throws {
        let document = PDFDocument()
        let pages = (0..<5).map { _ in SnapshotCountingPage() }
        var snapshots: [Int] = []
        let cache = ThumbnailCache()
        defer { cache.cancel() }
        let size = CGSize(width: 48, height: 64)
        for (index, page) in pages.enumerated() {
            page.setBounds(CGRect(x: 0, y: 0, width: 200, height: 300), for: .mediaBox)
            page.snapshotHook = {
                snapshots.append(index)
                if index == 0 { _ = cache.thumbnail(for: 4, document: document, size: size, priority: true) }
            }
            document.insert(page, at: index)
        }
        for index in pages.indices { _ = cache.thumbnail(for: index, document: document, size: size) }
        try await waitUntil { cache.generation == 5 }
        #expect(snapshots == [0, 4, 1, 2, 3])
        #expect(pages.allSatisfy { $0.snapshotCount == 1 })
    }

    @Test("Offscreen queued cells do not snapshot, and reappearing can request again")
    func discardingQueuedThumbnails() async throws {
        let document = PDFDocument()
        let pages = (0..<5).map { _ in SnapshotCountingPage() }
        for (index, page) in pages.enumerated() {
            page.setBounds(CGRect(x: 0, y: 0, width: 200, height: 300), for: .mediaBox)
            document.insert(page, at: index)
        }
        let cache = ThumbnailCache()
        defer { cache.cancel() }
        let size = CGSize(width: 48, height: 64)
        for index in pages.indices { _ = cache.thumbnail(for: index, document: document, size: size) }
        for index in 0..<4 { cache.discardQueued(for: index, document: document, size: size) }
        try await waitUntil { cache.generation == 1 }
        #expect(pages.dropLast().allSatisfy { $0.snapshotCount == 0 })
        #expect(pages[4].snapshotCount == 1)
        _ = cache.thumbnail(for: 0, document: document, size: size)
        try await waitUntil { cache.generation == 2 }
        #expect(pages[0].snapshotCount == 1)
    }

    @Test("Old-view disappearance cannot discard another document's queued cell")
    func oldViewCannotDiscardNewDocument() async throws {
        let old = try coloredDocument(red: 1, blue: 0)
        let current = try coloredDocument(red: 0, blue: 1)
        let cache = ThumbnailCache()
        defer { cache.cancel() }
        let size = CGSize(width: 48, height: 64)
        _ = cache.thumbnail(for: 0, document: old, size: size)
        _ = cache.thumbnail(for: 0, document: current, size: size)
        cache.discardQueued(for: 0, document: old, size: size)
        _ = try await waitForThumbnail(cache, document: current, size: size)
        #expect(cache.generation == 1)
    }

    @Test("Cancellation and immediate requeue preserve one snapshot in flight")
    func cancellingInFlightThumbnailQueue() async throws {
        let document = PDFDocument()
        let page = SnapshotCountingPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 200, height: 300), for: .mediaBox)
        document.insert(page, at: 0)
        let cache = ThumbnailCache()
        defer { cache.cancel() }
        let size = CGSize(width: 48, height: 64)
        page.snapshotHook = {
            cache.cancel()
            _ = cache.thumbnail(for: 0, document: document, size: size, priority: true)
        }
        _ = cache.thumbnail(for: 0, document: document, size: size)
        try await waitUntil { cache.generation == 1 }
        #expect(page.snapshotCount == 2)
        #expect(cache.thumbnail(for: 0, document: document, size: size) != nil)
    }

    @Test("Geometry changes during thumbnail preparation cannot populate an obsolete cache key")
    func thumbnailGeometryDuringRender() async throws {
        let document = PDFDocument()
        let page = SnapshotCountingPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 200, height: 300), for: .mediaBox)
        document.insert(page, at: 0)
        let cache = ThumbnailCache()
        defer { cache.cancel() }
        let size = CGSize(width: 48, height: 64)
        page.snapshotHook = {
            page.rotation = 90
            _ = cache.thumbnail(for: 0, document: document, size: size)
        }
        _ = cache.thumbnail(for: 0, document: document, size: size)
        try await waitUntil { cache.generation == 1 }
        #expect(page.snapshotCount == 2)
        #expect(cache.thumbnail(for: 0, document: document, size: size) != nil)
        page.rotation = 0
        #expect(cache.thumbnail(for: 0, document: document, size: size) == nil)
    }

    @Test("Rapid cold revisioned requests restart and publish only the latest settings")
    func rapidColdRevisionedRequests() async throws {
        let document = PDFDocument()
        let page = SnapshotCountingPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 200, height: 300), for: .mediaBox)
        document.insert(page, at: 0)
        let vm = ColorAdjustViewModel()
        defer { vm.cancelPreview() }
        for brightness: Float in [0.1, 0.2, 0.3] {
            vm.brightness = brightness
            vm.updatePreview(document: document, page: 0, documentRevision: 0)
        }
        #expect(page.snapshotCount == 0)
        try await waitUntil { !vm.isRendering }
        #expect(page.snapshotCount == 1 && vm.previewImage != nil)
        #expect(vm.lastPublishedPreviewSettings == vm.settings)
        #expect(!vm.isPreviewUpdating)
    }

    @Test("Switching source during base preparation cannot publish the abandoned source")
    func sourceSwitchDuringBasePreparation() async throws {
        let first = PDFDocument()
        let page = SnapshotCountingPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 200, height: 300), for: .mediaBox)
        first.insert(page, at: 0)
        let second = try coloredDocument(red: 0, blue: 1)
        let vm = ColorAdjustViewModel()
        defer { vm.cancelPreview() }
        page.snapshotHook = { vm.updatePreview(document: second, page: 0, documentRevision: 0) }
        vm.updatePreview(document: first, page: 0, documentRevision: 0)
        try await waitUntil { !vm.isRendering }
        let bitmap = try #require(vm.previewImage?.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let color = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
        #expect(color.blueComponent > 0.9 && color.redComponent < 0.1)
        #expect(page.snapshotCount == 1 && !vm.isPreviewUpdating)
    }

    @Test("Excluded pages reuse an unchanged preview and inclusion applies the latest settings")
    func selectionReusesBase() async throws {
        let document = PDFDocument()
        let page = SnapshotCountingPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 200, height: 300), for: .mediaBox)
        document.insert(page, at: 0)
        let vm = ColorAdjustViewModel()
        defer { vm.cancelPreview() }
        var selection = PageSelection()
        selection.appliesToAll = false
        selection.selectedPages = []
        vm.brightness = 0.1
        vm.updatePreview(document: document, page: 0, selection: selection, documentRevision: 0)
        try await waitUntil { !vm.isRendering }
        let image = vm.previewImage
        vm.brightness = 0.3
        vm.updatePreview(document: document, page: 0, selection: selection, documentRevision: 0)
        try await waitUntil { !vm.isRendering }
        #expect(vm.previewImage === image && vm.lastPublishedPreviewSettings?.isIdentity == true)
        selection.selectedPages = [0]
        vm.updatePreview(document: document, page: 0, selection: selection, documentRevision: 0)
        try await waitUntil { !vm.isRendering }
        #expect(page.snapshotCount == 1 && vm.lastPublishedPreviewSettings == vm.settings)
    }

    @Test("Revisioned color previews reuse one snapshot across settings and duplicate requests")
    func reusableColorBase() async throws {
        let document = PDFDocument()
        let page = SnapshotCountingPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 200, height: 300), for: .mediaBox)
        document.insert(page, at: 0)
        let vm = ColorAdjustViewModel()
        defer { vm.cancelPreview() }
        let pixels = CGSize(width: 128, height: 192)
        vm.updatePreview(document: document, page: 0, documentRevision: 0, pixelSize: pixels)
        try await waitUntil { !vm.isRendering }
        for brightness: Float in [0.1, 0.2, 0.3] {
            vm.brightness = brightness
            vm.updatePreview(document: document, page: 0, documentRevision: 0, pixelSize: pixels)
            try await waitUntil { !vm.isRendering }
            #expect(vm.lastPublishedPreviewSettings == vm.settings)
        }
        #expect(page.snapshotCount == 1)
        let published = vm.previewImage
        vm.updatePreview(document: document, page: 0, documentRevision: 0, pixelSize: pixels)
        try await waitUntil { !vm.isRendering }
        #expect(vm.previewImage === published)
        #expect(page.snapshotCount == 1)
        #expect(!vm.isPreviewUpdating)
    }

    @Test("Color cache invalidates for revisions, geometry, page replacement and pixel budget")
    func colorCacheInvalidation() async throws {
        let document = PDFDocument()
        let page = SnapshotCountingPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 200, height: 300), for: .mediaBox)
        document.insert(page, at: 0)
        let vm = ColorAdjustViewModel()
        defer { vm.cancelPreview() }
        var pixels = CGSize(width: 128, height: 192)
        func refresh(revision: Int = 0) async throws {
            vm.updatePreview(document: document, page: 0, documentRevision: revision, pixelSize: pixels)
            try await waitUntil { !vm.isRendering }
            #expect(vm.previewImage != nil)
        }
        try await refresh()
        page.rotation = 90
        try await refresh()
        page.setBounds(CGRect(x: 10, y: 20, width: 100, height: 180), for: .cropBox)
        try await refresh()
        let annotation = PDFAnnotation(bounds: CGRect(x: 20, y: 30, width: 40, height: 20),
                                       forType: .freeText, withProperties: nil)
        annotation.contents = "Changed content"
        page.addAnnotation(annotation)
        try await refresh(revision: 1)
        pixels = CGSize(width: 256, height: 384)
        try await refresh(revision: 1)
        #expect(page.snapshotCount == 5)
        let replacement = SnapshotCountingPage()
        replacement.setBounds(page.bounds(for: .mediaBox), for: .mediaBox)
        replacement.setBounds(page.bounds(for: .cropBox), for: .cropBox)
        replacement.rotation = page.rotation
        document.removePage(at: 0)
        document.insert(replacement, at: 0)
        try await refresh(revision: 1)
        #expect(replacement.snapshotCount == 1)
    }

    @Test("Unrevisioned color callers always capture mutable PDFKit content afresh")
    func uncachedMutableColorDocument() async throws {
        let document = PDFDocument()
        let page = SnapshotCountingPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 200, height: 300), for: .mediaBox)
        document.insert(page, at: 0)
        let vm = ColorAdjustViewModel()
        defer { vm.cancelPreview() }
        vm.updatePreview(document: document, page: 0)
        try await waitUntil { !vm.isRendering }
        page.addAnnotation(PDFAnnotation(bounds: CGRect(x: 10, y: 10, width: 40, height: 20),
                                         forType: .freeText, withProperties: nil))
        vm.updatePreview(document: document, page: 0)
        try await waitUntil { !vm.isRendering }
        #expect(page.snapshotCount == 2)
    }

    @Test("Settings changes during base preparation do not serialize the page again")
    func latestSettingsDuringBasePreparation() async throws {
        let document = PDFDocument()
        let page = SnapshotCountingPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 200, height: 300), for: .mediaBox)
        document.insert(page, at: 0)
        let vm = ColorAdjustViewModel()
        defer { vm.cancelPreview() }
        page.snapshotHook = {
            vm.brightness = 0.4
            vm.updatePreview(document: document, page: 0, documentRevision: 0)
        }
        vm.updatePreview(document: document, page: 0, documentRevision: 0)
        try await waitUntil { !vm.isRendering }
        #expect(page.snapshotCount == 1)
        #expect(vm.lastPublishedPreviewSettings == vm.settings)
        #expect(vm.previewImage != nil)
    }

    @Test("Rapid warm changes publish the latest settings without additional snapshots")
    func rapidWarmColorChanges() async throws {
        let document = PDFDocument()
        let page = SnapshotCountingPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 200, height: 300), for: .mediaBox)
        document.insert(page, at: 0)
        let vm = ColorAdjustViewModel()
        defer { vm.cancelPreview() }
        vm.updatePreview(document: document, page: 0, documentRevision: 0)
        try await waitUntil { !vm.isRendering }
        for step in 1...40 {
            vm.brightness = Float(step) / 100
            vm.updatePreview(document: document, page: 0, documentRevision: 0)
            if step.isMultiple(of: 4) { await Task.yield() }
        }
        try await waitUntil { !vm.isRendering }
        #expect(page.snapshotCount == 1)
        #expect(vm.lastPublishedPreviewSettings == vm.settings)
        #expect(!vm.isPreviewUpdating)
    }

    @Test("Changing documents at the same page clears stale color imagery immediately")
    func changingColorDocument() async throws {
        let red = try coloredDocument(red: 1, blue: 0)
        let blue = try coloredDocument(red: 0, blue: 1)
        let vm = ColorAdjustViewModel()
        defer { vm.cancelPreview() }
        vm.updatePreview(document: red, page: 0, documentRevision: 0)
        try await waitUntil { !vm.isRendering }
        #expect(vm.previewImage != nil)
        vm.updatePreview(document: blue, page: 0, documentRevision: 0)
        #expect(vm.previewImage == nil)
        try await waitUntil { !vm.isRendering }
        let bitmap = try #require(vm.previewImage?.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let color = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
        #expect(color.blueComponent > 0.9 && color.redComponent < 0.1)
    }

    @Test("Cancelling cached color work discards the base and returning snapshots afresh")
    func cancellingCachedColorWork() async throws {
        let document = PDFDocument()
        let page = SnapshotCountingPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 200, height: 300), for: .mediaBox)
        document.insert(page, at: 0)
        let vm = ColorAdjustViewModel()
        vm.updatePreview(document: document, page: 0, documentRevision: 0)
        try await waitUntil { !vm.isRendering }
        vm.brightness = 0.3
        vm.updatePreview(document: document, page: 0, documentRevision: 0)
        vm.cancelPreview()
        try await waitUntil { !vm.isRendering }
        #expect(!vm.isPreviewUpdating && page.snapshotCount == 1)
        vm.updatePreview(document: document, page: 0, documentRevision: 0)
        try await waitUntil { !vm.isRendering }
        #expect(page.snapshotCount == 2)
        #expect(vm.lastPublishedPreviewSettings == vm.settings)
        vm.cancelPreview()
    }

    @Test("Color preview cache does not retain the source PDFDocument")
    func colorCacheReleasesDocument() async throws {
        let vm = ColorAdjustViewModel()
        defer { vm.cancelPreview() }
        weak var observed: PDFDocument?
        do {
            let document = try coloredDocument(red: 1, blue: 0)
            observed = document
            vm.updatePreview(document: document, page: 0, documentRevision: 0)
            try await waitUntil { !vm.isRendering }
        }
        #expect(vm.previewImage != nil)
        #expect(observed == nil)
    }

    @Test("Preview pixels are bounded and invalid budgets fail before snapshotting",
          arguments: [CGSize(width: 64, height: 96), CGSize(width: 1024, height: 1024),
                      CGSize.zero, CGSize(width: 0.5, height: 200),
                      CGSize(width: CGFloat.infinity, height: 200), CGSize(width: 4097, height: 200)])
    func colorPixelBudget(pixels: CGSize) async throws {
        let document = PDFDocument()
        let page = SnapshotCountingPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 200, height: 300), for: .mediaBox)
        document.insert(page, at: 0)
        let vm = ColorAdjustViewModel()
        defer { vm.cancelPreview() }
        vm.updatePreview(document: document, page: 0, documentRevision: 0, pixelSize: pixels)
        try await waitUntil { !vm.isRendering }
        if pixels.width >= 1 && pixels.height >= 1 && pixels.width.isFinite && pixels.width <= 4096 {
            let image = try #require(vm.previewImage?.cgImage(forProposedRect: nil, context: nil, hints: nil))
            #expect(CGFloat(image.width) <= pixels.width && CGFloat(image.height) <= pixels.height)
            #expect(page.snapshotCount == 1)
        } else {
            #expect(vm.previewUnavailable && vm.previewImage == nil)
            #expect(page.snapshotCount == 0)
        }
    }

    @Test("Preview raster budgets remain bounded for large, fractional and rotated pages",
          arguments: [0, 90, 180, 270])
    func unusualPreviewGeometry(rotation: Int) throws {
        let page = PDFPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 6120.7, height: 7920.3), for: .mediaBox)
        page.setBounds(CGRect(x: 11.1, y: 13.2, width: 5000.9, height: 7000.8), for: .cropBox)
        page.rotation = rotation
        let budget = CGSize(width: 127, height: 193)
        let image = try #require(PDFRasterizer.renderPreview(page, pixelSize: budget))
        #expect(image.width <= 127 && image.height <= 193)
        let displaySize = PDFRasterizer.rotatedDisplaySize(page.bounds(for: .cropBox).size, rotation: rotation)
        #expect(abs(Double(image.width) / Double(image.height) - displaySize.width / displaySize.height) < 0.02)
    }

    @Test("Thumbnail requests keep only one page snapshot in flight", .timeLimit(.minutes(1)))
    func boundedThumbnailWork() async throws {
        let document = PDFDocument()
        let pages = (0..<24).map { _ in SnapshotCountingPage() }
        for (index, page) in pages.enumerated() {
            page.setBounds(CGRect(x: 0, y: 0, width: 200, height: 300), for: .mediaBox)
            document.insert(page, at: index)
        }
        let cache = ThumbnailCache()
        defer { cache.cancel() }
        for index in pages.indices {
            _ = cache.thumbnail(for: index, document: document, size: CGSize(width: 300, height: 400))
        }
        var maximumInFlight = 0
        while cache.generation < pages.count {
            try Task.checkCancellation()
            let snapshots = pages.reduce(0) { $0 + $1.snapshotCount }
            maximumInFlight = max(maximumInFlight, snapshots - cache.generation)
            await Task.yield()
        }
        print("Maximum in-flight thumbnail snapshots: \(maximumInFlight)")
        #expect(maximumInFlight <= 1)
        #expect(pages.allSatisfy { $0.snapshotCount == 1 })
    }

    @Test("Thumbnail requests defer snapshots and cancellation skips discarded pages")
    func deferredThumbnailSnapshots() async throws {
        let document = PDFDocument()
        let pages = (0..<80).map { _ in SnapshotCountingPage() }
        for (index, page) in pages.enumerated() {
            page.setBounds(CGRect(x: 0, y: 0, width: 200, height: 300), for: .mediaBox)
            document.insert(page, at: index)
        }
        let cache = ThumbnailCache()
        defer { cache.cancel() }
        let size = CGSize(width: 48, height: 64)
        let start = ContinuousClock.now
        for index in pages.indices {
            _ = cache.thumbnail(for: index, document: document, size: size)
        }
        print("80 thumbnail requests: \(ContinuousClock.now - start), synchronous snapshots: \(pages.reduce(0) { $0 + $1.snapshotCount })")
        #expect(pages.allSatisfy { $0.snapshotCount == 0 })
        cache.cancel()
        // A fresh render proves the actor has processed queued work as well.
        _ = try await waitForThumbnail(cache, document: document, size: size)
        #expect(pages[0].snapshotCount == 1)
        #expect(pages.dropFirst().allSatisfy { $0.snapshotCount == 0 })
    }

    @Test("Cancelled preview requests do not access PDF pages before debounce")
    func debounceBeforeSnapshot() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        defer { TestPDFGenerator.cleanup(source) }
        let document = try #require(PageAccessCountingDocument(data: Data(contentsOf: source)))
        document.pageAccessCount = 0
        let vm = ColorAdjustViewModel()
        defer { vm.cancelPreview() }

        for brightness: Float in [0.1, 0.2, 0.3] {
            vm.brightness = brightness
            vm.updatePreview(document: document, page: 0)
        }
        #expect(document.pageAccessCount == 0)
        vm.cancelPreview()
        try await waitUntil { !vm.isRendering }
        #expect(document.pageAccessCount == 0)

        vm.updatePreview(document: document, page: 0)
        try await waitUntil { !vm.isRendering }
        #expect(document.pageAccessCount > 0)
        #expect(vm.previewImage != nil)
        #expect(vm.lastPublishedPreviewSettings == vm.settings)
    }

    @Test("Leaving after rapid preview changes does not restart queued work")
    func cancellingQueuedColorPreview() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        defer { TestPDFGenerator.cleanup(source) }
        let document = try #require(PDFDocument(url: source))
        let vm = ColorAdjustViewModel()
        for brightness: Float in [0.1, 0.2, 0.3] {
            vm.brightness = brightness
            vm.updatePreview(document: document, page: 0)
        }
        vm.cancelPreview()
        try await waitUntil { !vm.isRendering }
        #expect(vm.previewImage == nil)
        #expect(vm.lastPublishedPreviewSettings == nil)

        // Returning to the editor must still allow a fresh render.
        vm.brightness = 0.4
        vm.updatePreview(document: document, page: 0)
        try await waitUntil { !vm.isRendering }
        #expect(vm.previewImage != nil)
        #expect(vm.lastPublishedPreviewSettings == vm.settings)
    }

    @Test("Color preview leaves excluded pages unchanged and refreshes selection")
    func colorPreviewSelection() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2)
        defer { TestPDFGenerator.cleanup(source) }
        let document = try #require(PDFDocument(url: source))
        let vm = ColorAdjustViewModel()
        defer { vm.cancelPreview() }
        vm.brightness = 0.4
        let selection = PageSelection(appliesToAll: false, selectedPages: [1])
        vm.updatePreview(document: document, page: 0, selection: selection)
        try await waitUntil { !vm.isRendering }
        #expect(vm.previewImage != nil)
        #expect(vm.lastPublishedPreviewSettings?.isIdentity == true)
        #expect(vm.lastPublishedPreviewPage == 0)
        vm.updatePreview(document: document, page: 1, selection: selection)
        #expect(vm.previewImage == nil)
        try await waitUntil { !vm.isRendering }
        #expect(vm.lastPublishedPreviewSettings == vm.settings)
        #expect(vm.lastPublishedPreviewPage == 1)
        vm.updatePreview(document: document, page: 1, selection: PageSelection(appliesToAll: false))
        try await waitUntil { !vm.isRendering }
        #expect(vm.lastPublishedPreviewSettings?.isIdentity == true)
        #expect(!vm.isPreviewUpdating)
    }

    @Test("Failed color preview clears old imagery, settles, and can recover")
    func failedColorPreview() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        defer { TestPDFGenerator.cleanup(source) }
        let document = try #require(PDFDocument(url: source))
        let vm = ColorAdjustViewModel()
        defer { vm.cancelPreview() }
        vm.updatePreview(document: document, page: 0)
        try await waitUntil { !vm.isRendering }
        #expect(vm.previewImage != nil)
        vm.updatePreview(document: document, page: 4)
        #expect(vm.previewImage == nil)
        try await waitUntil { !vm.isRendering }
        #expect(vm.previewUnavailable)
        #expect(!vm.isPreviewUpdating)
        #expect(vm.previewImage == nil)
        vm.updatePreview(document: document, page: 0)
        try await waitUntil { !vm.isRendering }
        #expect(!vm.previewUnavailable)
        #expect(vm.previewImage != nil)
    }

    @Test("A new document cannot receive an older document's pending thumbnail")
    func switchingDocumentsDuringRender() async throws {
        let red = try coloredDocument(red: 1, blue: 0)
        let blue = try coloredDocument(red: 0, blue: 1)
        let cache = ThumbnailCache()
        let size = CGSize(width: 48, height: 64)
        #expect(cache.thumbnail(for: 0, document: red, size: size) == nil)
        #expect(cache.thumbnail(for: 0, document: blue, size: size) == nil)
        let thumbnail = try await waitForThumbnail(cache, document: blue, size: size)
        let imageData = try #require(thumbnail.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: imageData))
        let center = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
        #expect(center.blueComponent > 0.9)
        #expect(center.redComponent < 0.1)
        // Returning to the first document also invalidates the second cache.
        #expect(cache.thumbnail(for: 0, document: red, size: size) == nil)
        cache.cancel()
    }

    @Test("Cached thumbnails refresh for crop, rotation and requested size")
    func changingPageGeometry() async throws {
        let document = try coloredDocument(red: 1, blue: 0)
        let page = try #require(document.page(at: 0))
        let cache = ThumbnailCache()
        defer { cache.cancel() }
        let size = CGSize(width: 48, height: 64)
        _ = try await waitForThumbnail(cache, document: document, size: size)
        page.rotation = 90
        #expect(cache.thumbnail(for: 0, document: document, size: size) == nil)
        _ = try await waitForThumbnail(cache, document: document, size: size)
        page.setBounds(CGRect(x: 0, y: 0, width: 100, height: 100), for: .cropBox)
        #expect(cache.thumbnail(for: 0, document: document, size: size) == nil)
        _ = try await waitForThumbnail(cache, document: document, size: size)
        #expect(cache.thumbnail(for: 0, document: document, size: CGSize(width: 96, height: 128)) == nil)
    }

    @Test("Cancelling thumbnails permits a fresh request without stale completion")
    func cancellingAndRestartingThumbnails() async throws {
        let document = try coloredDocument(red: 0, blue: 1)
        let cache = ThumbnailCache()
        let size = CGSize(width: 48, height: 64)
        _ = cache.thumbnail(for: 0, document: document, size: size)
        cache.cancel()
        #expect(cache.thumbnail(for: 0, document: document, size: size) == nil)
        _ = try await waitForThumbnail(cache, document: document, size: size)
        #expect(cache.generation == 1)
        cache.cancel()
        #expect(cache.thumbnail(for: 0, document: document, size: .zero) == nil)
        #expect(cache.thumbnail(for: 0, document: document, size: CGSize(width: CGFloat.infinity, height: 10)) == nil)
    }

    private func waitForThumbnail(_ cache: ThumbnailCache, document: PDFDocument, size: CGSize) async throws -> NSImage {
        var image: NSImage?
        try await waitUntil {
            image = cache.thumbnail(for: 0, document: document, size: size)
            return image != nil
        }
        return try #require(image)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(15)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition(), "Preview work did not complete")
    }

    private func coloredDocument(red: CGFloat, blue: CGFloat) throws -> PDFDocument {
        let data = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: data))
        var box = CGRect(x: 0, y: 0, width: 200, height: 300)
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.setFillColor(red: red, green: 0, blue: blue, alpha: 1)
        context.fill(box)
        context.endPDFPage()
        context.closePDF()
        return try #require(PDFDocument(data: data as Data))
    }
}

/// Counts only the authoritative document's page access; background rendering
/// reconstructs a separate PDFDocument from its snapshot.
private final class PageAccessCountingDocument: PDFDocument {
    var pageAccessCount = 0

    override func page(at index: Int) -> PDFPage? {
        pageAccessCount += 1
        return super.page(at: index)
    }
}

private final class SnapshotCountingPage: PDFPage {
    var snapshotCount = 0
    var snapshotHook: (@MainActor () -> Void)?

    override var dataRepresentation: Data? {
        snapshotCount += 1
        let data = super.dataRepresentation
        let hook = snapshotHook
        snapshotHook = nil
        MainActor.assumeIsolated { hook?() }
        return data
    }
}
