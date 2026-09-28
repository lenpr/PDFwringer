import AppKit
import PDFKit
import SwiftUI
import Testing

@Suite("PDF preview navigation", .serialized)
@MainActor
struct PDFPreviewNavigationTests {
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
