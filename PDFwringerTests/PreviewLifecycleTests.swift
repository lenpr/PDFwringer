import AppKit
import PDFKit
import Testing

@Suite("Preview lifecycle")
@MainActor
struct PreviewLifecycleTests {
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

    override var dataRepresentation: Data? {
        snapshotCount += 1
        return super.dataRepresentation
    }
}
