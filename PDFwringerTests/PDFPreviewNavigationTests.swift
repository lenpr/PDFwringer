import AppKit
import PDFKit
import SwiftUI
import Testing

@Suite("PDF preview navigation", .serialized)
@MainActor
struct PDFPreviewNavigationTests {
    @Test("Comparison preserves zoom and visible location across crop origins and rotations", arguments: [0, 90, 180, 270])
    func comparisonViewport(rotation: Int) async throws {
        let source = TestPDFGenerator.makeCroppedRasterFixture(cropOrigin: CGPoint(x: 70, y: 90), rotation: rotation)
        let directory = TestPDFGenerator.makeTempDirectory()
        defer { TestPDFGenerator.cleanup(source); try? FileManager.default.removeItem(at: directory) }
        let original = try #require(PDFDocument(url: source))
        let candidate = try await PDFCompressor().prepare(document: original, source: source,
            destination: directory.appending(component: "result.pdf"), level: .medium,
            quality: .good, grayscale: false, progress: { _ in })
        let result = try #require(candidate.previewDocument)
        let originalPage = try #require(original.page(at: 0))
        let pdfView = makeView(original)
        pdfView.autoScales = true
        pdfView.layoutDocumentView()
        pdfView.autoScales = false
        pdfView.scaleFactor = pdfView.scaleFactorForSizeToFit * 2.5
        let point = try #require(PDFPreviewViewport.pagePoint(CGPoint(x: 0.3, y: 0.7), on: originalPage))
        let destination = PDFDestination(page: originalPage, at: point)
        destination.zoom = pdfView.scaleFactor
        pdfView.go(to: destination)
        await drainMainQueue()
        let before = try #require(PDFPreviewViewport.capture(pdfView))
        let centerBefore = try #require(PDFPreviewViewport.normalized(
            pdfView.convert(CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY), to: originalPage), on: originalPage))
        let first = PDFPreviewView(document: original, currentPage: .constant(0), preserveViewport: true)
        let coordinator = first.makeCoordinator()
        let replacement = PDFPreviewView(document: result, currentPage: .constant(0), preserveViewport: true)
        coordinator.update(pdfView, parent: replacement)
        // SwiftUI can update again before the queued navigation runs.
        coordinator.update(pdfView, parent: replacement)
        await drainMainQueue()
        let after = try #require(PDFPreviewViewport.capture(pdfView))
        let resultPage = try #require(result.page(at: 0))
        let centerAfter = try #require(PDFPreviewViewport.normalized(
            pdfView.convert(CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY), to: resultPage), on: resultPage))
        #expect(!pdfView.autoScales)
        #expect(abs(before.relativeZoom - after.relativeZoom) < 0.01)
        #expect(abs(centerBefore.x - centerAfter.x) < 0.04)
        #expect(abs(centerBefore.y - centerAfter.y) < 0.04)
        coordinator.update(pdfView, parent: first)
        await drainMainQueue()
        let returned = try #require(PDFPreviewViewport.capture(pdfView))
        #expect(abs(before.relativeZoom - returned.relativeZoom) < 0.01)
        #expect(pdfView.document === original)
    }

    @Test("Rapid comparison toggles preserve the requested page and fit mode")
    func rapidComparison() async throws {
        let first = makeDocument()
        let second = makeDocument()
        let view = makeView(first)
        view.autoScales = true
        view.go(to: try #require(first.page(at: 2)))
        let firstParent = PDFPreviewView(document: first, currentPage: .constant(2), preserveViewport: true)
        let secondParent = PDFPreviewView(document: second, currentPage: .constant(2), preserveViewport: true)
        let coordinator = firstParent.makeCoordinator()
        coordinator.update(view, parent: secondParent)
        let queued = try #require(coordinator.pendingNavigation)
        coordinator.update(view, parent: firstParent)
        coordinator.update(view, parent: secondParent)
        await drainMainQueue()
        #expect(queued.isCancelled)
        #expect(view.currentPage === second.page(at: 2))
        #expect(view.autoScales)
        PDFPreviewView.dismantleNSView(view, coordinator: coordinator)
    }

    @Test("Returning to the visible page cancels an older queued navigation")
    func supersededNavigation() async throws {
        let document = makeDocument()
        let pdfView = makeView(document)
        var selectedPage = 1
        let parent = PDFPreviewView(document: document, currentPage: Binding(
            get: { selectedPage }, set: { selectedPage = $0 }
        ))
        let coordinator = parent.makeCoordinator()
        coordinator.update(pdfView, parent: parent)
        let queued = try #require(coordinator.pendingNavigation)

        selectedPage = 0
        coordinator.update(pdfView, parent: parent)
        #expect(queued.isCancelled)
        await drainMainQueue()
        #expect(pdfView.currentPage === document.page(at: 0))
        #expect(selectedPage == 0)
    }

    @Test("Document replacement cancels old work and refreshes the page binding")
    func replacedDocumentAndBinding() async throws {
        let first = makeDocument()
        let second = makeDocument()
        let pdfView = makeView(first)
        var oldSelection = 1
        var newSelection = 0
        let oldParent = PDFPreviewView(document: first, currentPage: Binding(
            get: { oldSelection }, set: { oldSelection = $0 }
        ))
        let coordinator = oldParent.makeCoordinator()
        coordinator.update(pdfView, parent: oldParent)
        let queued = try #require(coordinator.pendingNavigation)
        let newParent = PDFPreviewView(document: second, currentPage: Binding(
            get: { newSelection }, set: { newSelection = $0 }
        ))
        coordinator.update(pdfView, parent: newParent)
        await drainMainQueue()
        #expect(queued.isCancelled)
        #expect(pdfView.document === second)
        pdfView.go(to: try #require(second.page(at: 2)))
        coordinator.pageChanged(Notification(name: .PDFViewPageChanged, object: pdfView))
        #expect(newSelection == 2)
        #expect(oldSelection == 1)

        let staleView = makeView(first)
        coordinator.pageChanged(Notification(name: .PDFViewPageChanged, object: staleView))
        #expect(newSelection == 2)
    }

    @Test("Preview teardown cancels queued navigation and releases the document and proxy")
    func teardown() async throws {
        let document = makeDocument()
        let pdfView = makeView(document)
        let proxy = PDFViewProxy()
        let parent = PDFPreviewView(document: document, currentPage: .constant(1), proxy: proxy)
        let coordinator = parent.makeCoordinator()
        coordinator.update(pdfView, parent: parent)
        let queued = try #require(coordinator.pendingNavigation)
        #expect(proxy.pdfView === pdfView)
        PDFPreviewView.dismantleNSView(pdfView, coordinator: coordinator)
        await drainMainQueue()
        #expect(queued.isCancelled)
        #expect(coordinator.pendingNavigation == nil)
        #expect(proxy.pdfView == nil)
        #expect(pdfView.document == nil)
    }

    private func makeDocument() -> PDFDocument {
        let document = PDFDocument()
        for _ in 0..<3 {
            let page = PDFPage()
            page.setBounds(CGRect(x: 0, y: 0, width: 300, height: 400), for: .mediaBox)
            document.insert(page, at: document.pageCount)
        }
        return document
    }

    private func makeView(_ document: PDFDocument) -> PDFView {
        let view = PDFView(frame: CGRect(x: 0, y: 0, width: 300, height: 400))
        view.displayMode = .singlePage
        view.document = document
        if let page = document.page(at: 0) { view.go(to: page) }
        return view
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
