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
        #expect(vm.state == .landing)
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
        #expect(vm.state == .landing)
    }

    @Test("loadMultipleFiles transitions to multiFile state")
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

        if case .multiFile(let items) = vm.state {
            #expect(items.count == 2)
            #expect(items[0].pageCount == 1)
            #expect(items[1].pageCount == 3)
        } else {
            Issue.record("Expected multiFile state")
        }
    }

    @Test("loadMultipleFiles filters non-PDF URLs")
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

        if case .multiFile(let items) = vm.state {
            #expect(items.count == 1)
        } else {
            // Single valid PDF → singleFile via handleDrop, but loadMultipleFiles goes directly to multiFile
            if case .singleFile = vm.state {
                // Also acceptable
            } else {
                Issue.record("Expected multiFile or singleFile state")
            }
        }
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

    @Test("handleDrop with multiple PDFs goes to multiFile")
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

        if case .multiFile(let items) = vm.state {
            #expect(items.count == 2)
        } else {
            Issue.record("Expected multiFile state")
        }
    }

    @Test("handleDrop ignores non-PDF files entirely")
    func handleDropNonPDF() {
        let vm = AppViewModel()
        let txt = URL.temporaryDirectory.appending(component: "file.txt")
        try! "data".write(to: txt, atomically: true, encoding: .utf8)
        defer { TestPDFGenerator.cleanup(txt) }

        vm.handleDrop([txt])
        #expect(vm.state == .landing)
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

    @Test("selectMerge from multiFile goes to merging")
    func selectMerge() async throws {
        let url1 = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "m1.pdf")
        let url2 = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "m2.pdf")
        defer {
            TestPDFGenerator.cleanup(url1)
            TestPDFGenerator.cleanup(url2)
        }

        let vm = AppViewModel()
        vm.loadMultipleFiles([url1, url2])
        try await waitForStateChange(vm)
        vm.selectMerge()

        if case .merging(let items) = vm.state {
            #expect(items.count == 2)
        } else {
            Issue.record("Expected merging state")
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

    @Test("goBack from merging returns to multiFile")
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
        vm.selectMerge()
        vm.goBack()

        if case .multiFile(let items) = vm.state {
            #expect(items.count == 2)
        } else {
            Issue.record("Expected multiFile state")
        }
    }

    @Test("startOver returns to landing from any state")
    func startOver() {
        let url = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "so.pdf")
        defer { TestPDFGenerator.cleanup(url) }

        let vm = AppViewModel()
        vm.loadSingleFile(url)
        vm.selectCompress()
        vm.startOver()
        #expect(vm.state == .landing)
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
    }
}
