import Testing
import PDFKit

/// Waits for AppViewModel state to transition from landing, polling every 50ms up to 5 seconds.
@MainActor
private func waitForStateChange(_ vm: AppViewModel) async throws {
    for _ in 0..<100 {
        if case .landing = vm.state {
            try await Task.sleep(for: .milliseconds(50))
        } else {
            return
        }
    }
}

@Suite("AppViewModel")
@MainActor
struct AppViewModelTests {

    // MARK: - Initial state

    @Test("Starts in landing state")
    func initialState() {
        let vm = AppViewModel()
        #expect(vm.isLanding)
        #expect(vm.windowTitle == "PDFwringer")
    }

    // MARK: - File loading

    @Test("loadSingleFile transitions to singleFile state")
    func loadSingleFile() {
        let url = TestPDFGenerator.makeRenderedPDF(pageCount: 2, filename: "single.pdf")
        defer { TestPDFGenerator.cleanup(url) }

        let vm = AppViewModel()
        vm.loadSingleFile(url)

        if case .singleFile(let loadedURL, let doc) = vm.state {
            #expect(loadedURL == url)
            #expect(doc.pageCount == 2)
        } else {
            Issue.record("Expected singleFile state")
        }
    }

    @Test("loadSingleFile with invalid URL stays in current state")
    func loadInvalidFile() {
        let vm = AppViewModel()
        vm.loadSingleFile(URL.temporaryDirectory.appending(component: "nonexistent.pdf"))
        #expect(vm.isLanding)
    }

    @Test("loadMultipleFiles transitions directly to merging state")
    func loadMultipleFiles() async throws {
        let url1 = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "a.pdf")
        let url2 = TestPDFGenerator.makeRenderedPDF(pageCount: 3, filename: "b.pdf")
        defer {
            TestPDFGenerator.cleanup(url1)
            TestPDFGenerator.cleanup(url2)
        }

        let vm = AppViewModel()
        vm.loadMultipleFiles([url1, url2])
        try await waitForStateChange(vm)

        if case .merging(let items) = vm.state {
            #expect(items.count == 2)
            #expect(items[0].pageCount == 1)
            #expect(items[1].pageCount == 3)
        } else {
            Issue.record("Expected merging state")
        }
    }

    @Test("loadMultipleFiles routes one valid PDF to single-file state")
    func loadMultipleFilesFiltersNonPDF() async throws {
        let pdf = TestPDFGenerator.makeRenderedPDF(pageCount: 2, filename: "valid.pdf")
        let txt = URL.temporaryDirectory.appending(component: "readme.txt")
        try! "hello".write(to: txt, atomically: true, encoding: .utf8)
        defer {
            TestPDFGenerator.cleanup(pdf)
            TestPDFGenerator.cleanup(txt)
        }

        let vm = AppViewModel()
        vm.loadMultipleFiles([pdf, txt])
        try await waitForStateChange(vm)

        if case .singleFile(let loadedURL, let document) = vm.state {
            #expect(loadedURL == pdf)
            #expect(document.pageCount == 2)
        } else {
            Issue.record("Expected singleFile state")
        }
    }

    @Test("newer single-file intake cannot be overwritten by older parsing")
    func newerSingleFileWins() async {
        let old1 = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "old-1.pdf")
        let old2 = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "old-2.pdf")
        let newer = TestPDFGenerator.makeRenderedPDF(pageCount: 2, filename: "newer.pdf")
        defer {
            TestPDFGenerator.cleanup(old1)
            TestPDFGenerator.cleanup(old2)
            TestPDFGenerator.cleanup(newer)
        }

        let vm = AppViewModel()
        let staleIntake = vm.loadMultipleFiles([old1, old2])
        vm.loadSingleFile(newer)
        await staleIntake.value

        guard case .singleFile(let loadedURL, let document) = vm.state else {
            Issue.record("Expected newer singleFile state")
            return
        }
        #expect(loadedURL == newer)
        #expect(document.pageCount == 2)
    }

    @Test("startOver invalidates pending file intake")
    func startOverInvalidatesPendingIntake() async {
        let url1 = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "pending-1.pdf")
        let url2 = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "pending-2.pdf")
        defer {
            TestPDFGenerator.cleanup(url1)
            TestPDFGenerator.cleanup(url2)
        }

        let vm = AppViewModel()
        let staleIntake = vm.loadMultipleFiles([url1, url2])
        vm.startOver()
        await staleIntake.value

        #expect(vm.isLanding)
    }

    // MARK: - handleDrop routing

    @Test("handleDrop with one PDF goes to singleFile")
    func handleDropSingle() {
        let url = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "drop.pdf")
        defer { TestPDFGenerator.cleanup(url) }

        let vm = AppViewModel()
        vm.handleDrop([url])

        if case .singleFile = vm.state {
            // pass
        } else {
            Issue.record("Expected singleFile state")
        }
    }

    @Test("handleDrop with multiple PDFs goes directly to merging")
    func handleDropMultiple() async throws {
        let url1 = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "x.pdf")
        let url2 = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "y.pdf")
        defer {
            TestPDFGenerator.cleanup(url1)
            TestPDFGenerator.cleanup(url2)
        }

        let vm = AppViewModel()
        vm.handleDrop([url1, url2])
        try await waitForStateChange(vm)

        if case .merging(let items) = vm.state {
            #expect(items.count == 2)
        } else {
            Issue.record("Expected merging state")
        }
    }

    @Test("handleDrop ignores non-PDF files, including images")
    func handleDropNonPDF() {
        let vm = AppViewModel()
        let stem = UUID().uuidString
        let txt = URL.temporaryDirectory.appending(component: "\(stem).txt")
        let image = URL.temporaryDirectory.appending(component: "\(stem).png")
        try! "data".write(to: txt, atomically: true, encoding: .utf8)
        try! "data".write(to: image, atomically: true, encoding: .utf8)
        defer {
            TestPDFGenerator.cleanup(txt)
            TestPDFGenerator.cleanup(image)
        }

        vm.handleDrop([txt, image])
        #expect(vm.isLanding)
    }

    // MARK: - State transitions

    @Test("selectCompress from singleFile goes to compressing")
    func selectCompress() {
        let url = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "c.pdf")
        defer { TestPDFGenerator.cleanup(url) }

        let vm = AppViewModel()
        vm.loadSingleFile(url)
        vm.selectCompress()

        if case .compressing(let u, _) = vm.state {
            #expect(u == url)
        } else {
            Issue.record("Expected compressing state")
        }
    }

    @Test("selectSplit from singleFile goes to splitting")
    func selectSplit() {
        let url = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "s.pdf")
        defer { TestPDFGenerator.cleanup(url) }

        let vm = AppViewModel()
        vm.loadSingleFile(url)
        vm.selectSplit()

        if case .splitting(let u, _) = vm.state {
            #expect(u == url)
        } else {
            Issue.record("Expected splitting state")
        }
    }

    @Test("goBack from compressing returns to singleFile")
    func goBackFromCompress() {
        let url = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "gb.pdf")
        defer { TestPDFGenerator.cleanup(url) }

        let vm = AppViewModel()
        vm.loadSingleFile(url)
        vm.selectCompress()
        vm.goBack()

        if case .singleFile(let u, _) = vm.state {
            #expect(u == url)
        } else {
            Issue.record("Expected singleFile state")
        }
    }

    @Test("goBack from merging returns to landing")
    func goBackFromMerge() async throws {
        let url1 = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "g1.pdf")
        let url2 = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "g2.pdf")
        defer {
            TestPDFGenerator.cleanup(url1)
            TestPDFGenerator.cleanup(url2)
        }

        let vm = AppViewModel()
        vm.loadMultipleFiles([url1, url2])
        try await waitForStateChange(vm)
        vm.goBack()

        #expect(vm.isLanding)
    }

    @Test("startOver clears workflow navigation and confirmation state")
    func startOver() {
        let url = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "so.pdf")
        defer { TestPDFGenerator.cleanup(url) }

        let vm = AppViewModel()
        vm.loadSingleFile(url)
        vm.selectCompress()
        vm.currentPage = 4
        vm.currentFileSize = 123
        vm.navigationDirection = .leading
        vm.hasUnsavedChanges = true
        vm.confirmStartOver()
        #expect(vm.showStartOverConfirm)

        vm.startOver()

        #expect(vm.isLanding)
        #expect(vm.currentPage == 0)
        #expect(vm.currentFileSize == 0)
        #expect(vm.navigationDirection == .trailing)
        #expect(!vm.hasUnsavedChanges)
        #expect(!vm.showStartOverConfirm)
    }

    @Test("goBack is a true no-op outside child workflows")
    func unsupportedGoBackIsNoOp() {
        let url = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "no-op.pdf")
        defer { TestPDFGenerator.cleanup(url) }

        let vm = AppViewModel()
        vm.navigationDirection = .trailing
        vm.hasUnsavedChanges = true
        vm.goBack()
        #expect(vm.isLanding)
        #expect(vm.navigationDirection == .trailing)
        #expect(vm.hasUnsavedChanges)

        vm.loadSingleFile(url)
        vm.navigationDirection = .trailing
        vm.hasUnsavedChanges = true
        vm.goBack()
        guard case .singleFile(let selectedURL, _) = vm.state else {
            Issue.record("Expected singleFile state")
            return
        }
        #expect(selectedURL == url)
        #expect(vm.navigationDirection == .trailing)
        #expect(vm.hasUnsavedChanges)
    }

    @Test("export navigation enables page commands and Back")
    func exportNavigation() {
        let url = TestPDFGenerator.makeRenderedPDF(pageCount: 3, filename: "export.pdf")
        defer { TestPDFGenerator.cleanup(url) }

        let vm = AppViewModel()
        vm.loadSingleFile(url)
        vm.selectExportImages()

        #expect(vm.canGoBack)
        #expect(vm.currentPageCount == 3)
        #expect(vm.hasDocument)
        vm.goToLastPage()
        #expect(vm.currentPage == 2)
        vm.nextPage()
        #expect(vm.currentPage == 2)
        vm.goToFirstPage()
        #expect(vm.currentPage == 0)

        vm.goBack()
        guard case .singleFile(let selectedURL, _) = vm.state else {
            Issue.record("Expected singleFile state")
            return
        }
        #expect(selectedURL == url)
    }

    @Test("reorder navigation enables Back")
    func reorderNavigation() {
        let url = TestPDFGenerator.makeRenderedPDF(pageCount: 2, filename: "reorder.pdf")
        defer { TestPDFGenerator.cleanup(url) }

        let vm = AppViewModel()
        vm.loadSingleFile(url)
        vm.selectReorderPages()
        #expect(vm.canGoBack)

        vm.goBack()
        guard case .singleFile(let selectedURL, _) = vm.state else {
            Issue.record("Expected singleFile state")
            return
        }
        #expect(selectedURL == url)
    }

    // MARK: - Window title

    @Test("windowTitle reflects current state")
    func windowTitle() async throws {
        let url = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "title.pdf")
        let url2 = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "t2.pdf")
        defer {
            TestPDFGenerator.cleanup(url)
            TestPDFGenerator.cleanup(url2)
        }

        let vm = AppViewModel()
        #expect(vm.windowTitle == "PDFwringer")

        vm.loadSingleFile(url)
        #expect(vm.windowTitle.hasSuffix("title.pdf"))

        vm.startOver()
        vm.loadMultipleFiles([url, url2])
        try await waitForStateChange(vm)
        #expect(vm.windowTitle == "PDFwringer — 2 files")
    }

    // MARK: - Rotate and Metadata transitions

    @Test("selectRotate creates an isolated working document")
    func selectRotate() throws {
        let url = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "r.pdf")
        defer { TestPDFGenerator.cleanup(url) }

        let vm = AppViewModel()
        vm.loadSingleFile(url)
        guard case .singleFile(_, let originalDocument) = vm.state else {
            Issue.record("Expected singleFile state")
            return
        }
        vm.selectRotate()

        guard case .rotating(let selectedURL, let sourceDocument, let workingDocument) = vm.state else {
            Issue.record("Expected rotating state")
            return
        }
        #expect(selectedURL == url)
        #expect(sourceDocument === originalDocument)
        #expect(workingDocument !== sourceDocument)
        let sourcePage = try #require(sourceDocument.page(at: 0))
        let workingPage = try #require(workingDocument.page(at: 0))
        #expect(workingPage !== sourcePage)
    }

    @Test("selectMetadata from singleFile goes to editingMetadata")
    func selectMetadata() {
        let url = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "m.pdf")
        defer { TestPDFGenerator.cleanup(url) }

        let vm = AppViewModel()
        vm.loadSingleFile(url)
        vm.selectMetadata()

        if case .editingMetadata(let u, _) = vm.state {
            #expect(u == url)
        } else {
            Issue.record("Expected editingMetadata state")
        }
    }

    @Test("goBack from splitting returns to singleFile")
    func goBackFromSplit() {
        let url = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "gs.pdf")
        defer { TestPDFGenerator.cleanup(url) }

        let vm = AppViewModel()
        vm.loadSingleFile(url)
        vm.selectSplit()
        vm.goBack()

        if case .singleFile(let u, _) = vm.state {
            #expect(u == url)
        } else {
            Issue.record("Expected singleFile state")
        }
    }

    @Test("goBack from rotating discards working mutations")
    func goBackFromRotate() throws {
        let url = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "gr.pdf")
        defer { TestPDFGenerator.cleanup(url) }

        let vm = AppViewModel()
        vm.loadSingleFile(url)
        vm.selectRotate()
        guard case .rotating(_, let sourceDocument, let workingDocument) = vm.state else {
            Issue.record("Expected rotating state")
            return
        }
        try PDFRotator().rotate(
            document: workingDocument,
            angle: .ninety,
            pageIndices: nil,
            progress: { _ in }
        )
        vm.hasUnsavedChanges = true
        #expect(sourceDocument.page(at: 0)?.rotation == 0)
        #expect(workingDocument.page(at: 0)?.rotation == 90)

        vm.goBack()

        guard case .singleFile(let selectedURL, let restoredDocument) = vm.state else {
            Issue.record("Expected singleFile state")
            return
        }
        #expect(selectedURL == url)
        #expect(restoredDocument === sourceDocument)
        #expect(restoredDocument.page(at: 0)?.rotation == 0)
        #expect(!vm.hasUnsavedChanges)
    }

    @Test("goBack from editingMetadata returns to singleFile")
    func goBackFromMetadata() {
        let url = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "gm.pdf")
        defer { TestPDFGenerator.cleanup(url) }

        let vm = AppViewModel()
        vm.loadSingleFile(url)
        vm.selectMetadata()
        vm.goBack()

        if case .singleFile(let u, _) = vm.state {
            #expect(u == url)
        } else {
            Issue.record("Expected singleFile state")
        }
    }

    // MARK: - Crop transitions

    @Test("selectCrop creates an isolated working document")
    func selectCrop() throws {
        let url = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "cr.pdf")
        defer { TestPDFGenerator.cleanup(url) }

        let vm = AppViewModel()
        vm.loadSingleFile(url)
        guard case .singleFile(_, let originalDocument) = vm.state else {
            Issue.record("Expected singleFile state")
            return
        }
        vm.selectCrop()

        guard case .cropping(let selectedURL, let sourceDocument, let workingDocument) = vm.state else {
            Issue.record("Expected cropping state")
            return
        }
        #expect(selectedURL == url)
        #expect(sourceDocument === originalDocument)
        #expect(workingDocument !== sourceDocument)
        let sourcePage = try #require(sourceDocument.page(at: 0))
        let workingPage = try #require(workingDocument.page(at: 0))
        #expect(workingPage !== sourcePage)
    }

    @Test("goBack from cropping discards working mutations")
    func goBackFromCrop() throws {
        let url = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "gc.pdf")
        defer { TestPDFGenerator.cleanup(url) }

        let vm = AppViewModel()
        vm.loadSingleFile(url)
        vm.selectCrop()
        guard case .cropping(_, let sourceDocument, let workingDocument) = vm.state else {
            Issue.record("Expected cropping state")
            return
        }
        let originalBounds = try #require(sourceDocument.page(at: 0)).bounds(for: .cropBox)
        let result = PDFCropper().crop(
            document: workingDocument,
            indices: [0],
            top: 10,
            bottom: 10,
            left: 10,
            right: 10
        )
        vm.hasUnsavedChanges = true
        #expect(result.pagesModified == 1)
        #expect(workingDocument.page(at: 0)?.bounds(for: .cropBox) != originalBounds)
        #expect(sourceDocument.page(at: 0)?.bounds(for: .cropBox) == originalBounds)

        vm.goBack()

        guard case .singleFile(let selectedURL, let restoredDocument) = vm.state else {
            Issue.record("Expected singleFile state")
            return
        }
        #expect(selectedURL == url)
        #expect(restoredDocument === sourceDocument)
        #expect(restoredDocument.page(at: 0)?.bounds(for: .cropBox) == originalBounds)
        #expect(!vm.hasUnsavedChanges)
    }

    // MARK: - File size caching

    @Test("loadSingleFile populates currentFileSize")
    func fileSizePopulated() {
        let url = TestPDFGenerator.makeRenderedPDF(pageCount: 3, filename: "sized.pdf")
        defer { TestPDFGenerator.cleanup(url) }

        let vm = AppViewModel()
        vm.loadSingleFile(url)
        #expect(vm.currentFileSize > 0)
    }

    // MARK: - Password state

    @Test("cancelPassword resets all password state")
    func cancelPasswordResetsState() {
        let vm = AppViewModel()
        vm.showPasswordPrompt = true
        vm.passwordText = "secret"
        vm.wrongPasswordAttempt = true

        vm.cancelPassword()

        #expect(vm.passwordText == "")
        #expect(vm.wrongPasswordAttempt == false)
        #expect(!vm.showPasswordPrompt)
    }
}
