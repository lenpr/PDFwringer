import Foundation
import PDFKit
import Testing

@Suite("Cooperative editors")
@MainActor
struct CooperativeEditorTests {
    @Test("Large working copies finish isolation before navigation", arguments: [false, true])
    func largeWorkingCopy(crop: Bool) async throws {
        let source = document(pages: 180)
        let vm = AppViewModel()
        let url = URL(fileURLWithPath: "/not-opened/cooperative.pdf")
        vm.state = .singleFile(url, source)
        if crop { vm.selectCrop() } else { vm.selectRotate() }
        #expect(vm.isPreparingTool && !vm.canSelectSingleFileAction)
        try await waitUntil { !vm.isPreparingTool }
        let copy: PDFDocument
        switch vm.state {
        case .cropping(_, let original, let working), .rotating(_, let original, let working):
            #expect(original === source)
            copy = working
        default: throw TestFailure.unexpectedState
        }
        for index in 0..<source.pageCount { #expect(source.page(at: index) !== copy.page(at: index)) }
    }

    @Test("Cancelled or superseded tool preparation cannot navigate later", arguments: ["cancel", "replace", "other-tool"])
    func cancelledPreparation(action: String) async throws {
        let source = document(pages: 180)
        let vm = AppViewModel()
        let url = URL(fileURLWithPath: "/not-opened/cooperative.pdf")
        vm.state = .singleFile(url, source)
        vm.selectRotate()
        if action == "cancel" { vm.cancelToolPreparation() }
        if action == "replace" { vm.state = .landing }
        if action == "other-tool" { vm.selectCompress() }
        for _ in 0..<50 { await Task.yield() }
        #expect(!vm.isPreparingTool)
        switch action {
        case "cancel": if case .singleFile = vm.state {} else { Issue.record("Cancelled preparation navigated") }
        case "replace": if case .landing = vm.state {} else { Issue.record("Replacement was lost") }
        default: if case .compressing = vm.state {} else { Issue.record("New tool was lost") }
        }
    }

    @Test("Cooperative rotation preserves duplicate-index behavior and leaves other pages alone")
    func rotationDuplicates() async throws {
        let source = document(pages: 180)
        let indices = Array(0..<130) + [0, 0]
        let count = try await PDFRotator().rotateInBatches(document: source, angle: .ninety,
                                                         pageIndices: indices, progress: { _ in })
        #expect(count == 132 && source.page(at: 0)?.rotation == 270)
        #expect(source.page(at: 129)?.rotation == 90 && source.page(at: 130)?.rotation == 0)
    }

    @Test("Cancelling rotation after mutations restores all pages")
    func cancelRotation() async throws {
        let source = document(pages: 180)
        var task: Task<Int, Error>?
        task = Task { @MainActor in
            try await PDFRotator().rotateInBatches(document: source, angle: .ninety, pageIndices: nil) { value in
                if value >= 0.2 { task?.cancel() }
            }
        }
        await #expect(throws: CancellationError.self) { try await task?.value }
        #expect((0..<source.pageCount).allSatisfy { source.page(at: $0)?.rotation == 0 })
    }

    @Test("Cancelling crop/resize after mutations restores media and crop bounds", arguments: [false, true])
    func cancelBoundsEdit(resize: Bool) async throws {
        let source = PDFDocument()
        let pages = (0..<180).map { _ in BoundsHookPage() }
        let original = CGRect(x: 5, y: 7, width: 200, height: 300)
        for (index, page) in pages.enumerated() {
            page.setBounds(original, for: .mediaBox)
            page.setBounds(original, for: .cropBox)
            source.insert(page, at: index)
        }
        var task: Task<PDFCropper.CropResult, Error>?
        pages[35].hook = { task?.cancel() }
        task = Task { @MainActor in
            if resize {
                return try await PDFCropper().resizeInBatches(document: source, indices: Array(0..<180),
                                                             targetSize: CGSize(width: 180, height: 280))
            }
            return try await PDFCropper().cropInBatches(document: source, indices: Array(0..<180),
                                                       top: 10, bottom: 10, left: 10, right: 10)
        }
        await #expect(throws: CancellationError.self) { try await task?.value }
        #expect(pages.allSatisfy { $0.bounds(for: .cropBox) == original && $0.bounds(for: .mediaBox) == original })
    }

    @Test("Cooperative crop/resize match established geometry", arguments: [false, true])
    func boundsParity(resize: Bool) async throws {
        let source = document(pages: 180)
        let copy = try #require(source.copy() as? PDFDocument)
        let indices = Array(0..<150) + [0, -1, 999]
        let cropper = PDFCropper()
        let expected: PDFCropper.CropResult
        let actual: PDFCropper.CropResult
        if resize {
            let size = CGSize(width: 170, height: 260)
            expected = try cropper.resize(document: source, indices: indices, targetSize: size)
            actual = try await cropper.resizeInBatches(document: copy, indices: indices, targetSize: size)
        } else {
            expected = try cropper.crop(document: source, indices: indices, top: 10, bottom: 11, left: 12, right: 13)
            actual = try await cropper.cropInBatches(document: copy, indices: indices, top: 10, bottom: 11, left: 12, right: 13)
        }
        #expect(actual.pagesModified == expected.pagesModified && actual.pagesSkipped == expected.pagesSkipped)
        for index in 0..<source.pageCount {
            #expect(source.page(at: index)?.bounds(for: .cropBox) == copy.page(at: index)?.bounds(for: .cropBox))
            #expect(source.page(at: index)?.bounds(for: .mediaBox) == copy.page(at: index)?.bounds(for: .mediaBox))
        }
    }

    @Test("Page commands cannot navigate during an edit/save")
    func guardedPageCommands() {
        let vm = AppViewModel()
        vm.state = .singleFile(URL(fileURLWithPath: "/not-opened/cooperative.pdf"), document(pages: 5))
        vm.currentPage = 2
        vm.operationIsRunning = { true }
        vm.nextPage(); vm.previousPage(); vm.goToFirstPage(); vm.goToLastPage()
        #expect(vm.currentPage == 2)
    }

    private func document(pages: Int) -> PDFDocument {
        let document = PDFDocument()
        for _ in 0..<pages {
            let page = PDFPage()
            page.setBounds(CGRect(x: 0, y: 0, width: 200, height: 300), for: .mediaBox)
            document.insert(page, at: document.pageCount)
        }
        return document
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(15)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(condition())
    }
    private enum TestFailure: Error { case unexpectedState }
}

private final class BoundsHookPage: PDFPage {
    var hook: (@MainActor () -> Void)?
    override func setBounds(_ bounds: CGRect, for box: PDFDisplayBox) {
        super.setBounds(bounds, for: box)
        let callback = hook
        hook = nil
        MainActor.assumeIsolated { callback?() }
    }
}
