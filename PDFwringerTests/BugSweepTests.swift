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


    @Test("Failed source replacement clears old operation feedback and recovers", arguments: ["missing", "corrupt", "locked"])
    func failedSourceRecovery(kind: String) async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2)
        let directory = TestPDFGenerator.makeTempDirectory()
        defer { TestPDFGenerator.cleanup(source); TestPDFGenerator.cleanup(directory) }
        let invalid = directory.appending(component: "invalid.pdf")
        if kind == "corrupt" { try Data("not a PDF".utf8).write(to: invalid) }
        if kind == "locked" {
            let document = try #require(PDFDocument(url: source))
            #expect(document.write(to: invalid, withOptions: [.ownerPasswordOption: "secret", .userPasswordOption: "secret"]))
        }
        let compressor = CompressViewModel()
        defer { compressor.cancelEstimation() }
        compressor.setSource(source)
        compressor.selectedLevel = .lossless
        let output = directory.appending(component: "result.pdf")
        await compressor.prepare(to: output)
        await compressor.savePreparedResult()
        #expect(compressor.lastOutputURL == output)
        #expect(compressor.resultMessage != nil)
        compressor.setSource(invalid)
        #expect(!compressor.canCompress && compressor.pdfDocument == nil)
        #expect(compressor.resultMessage == nil && !compressor.isError)
        #expect(compressor.lastOutputURL == nil && compressor.progress == 0)
        #expect(compressor.estimatedSizes.isEmpty && compressor.heuristicSizes.isEmpty)
        compressor.setSource(source)
        #expect(compressor.canCompress && compressor.sourcePageCount == 2)
        #expect(compressor.resultMessage == nil && compressor.progress == 0)
        #expect(PDFDocument(url: output)?.pageCount == 2)

        let splitter = SplitViewModel()
        splitter.setSource(source)
        splitter.splitPagesPerFile = 0
        await splitter.splitByPages()
        #expect(splitter.isError && splitter.errorSource == .split)
        splitter.setSource(invalid)
        #expect(!splitter.canProcess && splitter.sourceDocument == nil)
        #expect(splitter.resultMessage == nil && !splitter.isError && splitter.errorSource == nil)
        splitter.setSource(source)
        #expect(splitter.canProcess && splitter.sourcePageCount == 2)
        #expect(splitter.resultMessage == nil && splitter.errorSource == nil)
    }


    @Test("Write completion observes a verified published PDF", arguments: ["compress", "flatten", "password", "rotate"])
    func publishedCompletion(operation: String) async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        let directory = TestPDFGenerator.makeTempDirectory()
        defer { TestPDFGenerator.cleanup(source); TestPDFGenerator.cleanup(directory) }
        let output = directory.appending(component: "result.pdf")
        let original = try Data(contentsOf: source)
        var completionCount = 0
        let progress: (Double) -> Void = { value in
            #expect((0...1).contains(value))
            if value == 1 {
                completionCount += 1
                guard let result = PDFDocument(url: output) else {
                    Issue.record("Completion preceded publication")
                    return
                }
                if operation == "password" { #expect(result.unlock(withPassword: "secret")) }
                #expect(result.pageCount == 1)
                if operation == "rotate" { #expect(result.page(at: 0)?.rotation == 90) }
            }
        }
        if operation == "compress" {
            _ = try await PDFCompressor().compress(source: source, destination: output,
                level: .medium, quality: .good, grayscale: false, progress: progress)
        } else if operation == "rotate" {
            try await PDFRotator().rotate(source: source, destination: output,
                angle: .ninety, pageIndices: nil, progress: progress)
        } else {
            try await PDFMetadataEditor().write(metadata: .empty, source: source,
                destination: output, password: operation == "password" ? "secret" : nil,
                flattenAnnotations: true, progress: progress)
        }
        #expect(completionCount == 1)
        #expect(try Data(contentsOf: source) == original)
    }


    @Test("Failed publication never reports completion", arguments: ["compress", "flatten", "rotate"])
    func noFalseCompletion(operation: String) async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        let directory = TestPDFGenerator.makeTempDirectory()
        defer { TestPDFGenerator.cleanup(source); TestPDFGenerator.cleanup(directory) }
        let output = directory.appending(component: "result.pdf")
        try Data("Original destination".utf8).write(to: output)
        let replacement = Data("Concurrent replacement".utf8)
        var replaced = false
        var completed = false
        let progress: (Double) -> Void = { value in
            if value == 1 { completed = true }
            if value >= 0.99, !replaced {
                do {
                    try FileManager.default.moveItem(at: output,
                        to: directory.appending(component: "prior-result.pdf"))
                    try replacement.write(to: output)
                    replaced = true
                } catch { Issue.record("Could not inject destination replacement: \(error)") }
            }
        }
        do {
            if operation == "compress" {
                _ = try await PDFCompressor().compress(source: source, destination: output,
                    level: .medium, quality: .good, grayscale: false, progress: progress)
            } else if operation == "rotate" {
                try await PDFRotator().rotate(source: source, destination: output,
                    angle: .ninety, pageIndices: nil, progress: progress)
            } else {
                try await PDFMetadataEditor().write(metadata: .empty, source: source,
                    destination: output, flattenAnnotations: true, progress: progress)
            }
            Issue.record("Expected changed-destination rejection")
        } catch PDFwringerError.destinationChanged {
            // The concurrent replacement must remain untouched.
        }
        #expect(replaced && !completed)
        #expect(try Data(contentsOf: output) == replacement)
    }

}
