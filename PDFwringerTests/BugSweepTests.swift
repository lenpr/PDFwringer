import Foundation
import PDFKit
import Testing

@Suite("Bug sweep regressions")
@MainActor
struct BugSweepTests {
    @Test("Discard confirmation rejects nested navigation and file intake")
    func discardReentrancy() async throws {
        let first = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        let second = TestPDFGenerator.makeRenderedPDF(pageCount: 2)
        defer { TestPDFGenerator.cleanup(first); TestPDFGenerator.cleanup(second) }
        var model: AppViewModel?
        var prompts = 0
        var nestedIntake: Task<Void, Never>?
        let vm = AppViewModel(confirmDiscard: {
            prompts += 1
            if prompts > 1 { return true }
            model?.startOver()
            model?.loadSingleFile(second)
            nestedIntake = model?.loadMultipleFiles([first, second])
            return false
        })
        model = vm
        defer { model = nil }
        vm.loadSingleFile(first)
        await vm.waitForFileIntake()
        vm.selectMetadata()
        vm.hasUnsavedChanges = true
        #expect(!vm.closeWorkflow())
        await nestedIntake?.value
        await vm.waitForFileIntake()
        #expect(prompts == 1)
        #expect(vm.hasUnsavedChanges)
        guard case .editingMetadata(let url, _) = vm.state else {
            Issue.record("Nested event replaced the unsaved editor")
            return
        }
        #expect(url == first)
        vm.hasUnsavedChanges = false
        #expect(vm.closeWorkflow())
    }

    @Test("Extreme chunk sizes preserve all pages without overflow", arguments: [Int.max, Int.max - 1, Int.min])
    func extremeChunks(size: Int) async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 3)
        let directory = TestPDFGenerator.makeTempDirectory()
        defer { TestPDFGenerator.cleanup(source); TestPDFGenerator.cleanup(directory) }
        let outputs = try await PDFSplitter().split(source: source, mode: .splitEveryN(size),
            destination: directory, progress: { _ in })
        #expect(outputs.count == (size > 0 ? 1 : 3))
        #expect(outputs.reduce(0) { $0 + (PDFDocument(url: $1)?.pageCount ?? 0) } == 3)
    }

    @Test("Extreme color indices fail without changing the destination", arguments: [false, true])
    func extremeColorIndices(loaded: Bool) async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        let directory = TestPDFGenerator.makeTempDirectory()
        defer { TestPDFGenerator.cleanup(source); TestPDFGenerator.cleanup(directory) }
        let destination = directory.appending(component: "existing.pdf")
        let sentinel = Data("Existing output".utf8)
        try sentinel.write(to: destination)
        let adjuster = PDFColorAdjuster()
        let settings = PDFColorAdjuster.Settings(brightness: 0.1)
        for index in [Int.max, Int.min] {
            await #expect(throws: PDFwringerError.self) {
                if loaded {
                    let document = try #require(PDFDocument(url: source))
                    try await adjuster.adjust(document: document, source: source,
                        destination: destination, settings: settings, pages: [index], progress: { _ in })
                } else {
                    try await adjuster.adjust(source: source, destination: destination,
                        settings: settings, pages: [index], progress: { _ in })
                }
            }
            #expect(try Data(contentsOf: destination) == sentinel)
        }
    }

}
