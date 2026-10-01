import Foundation
import PDFKit
import Testing

@Suite("Optimization safety")
@MainActor
struct OptimizationSafetyTests {
    @Test("Source-byte snapshots match authoritative rendering and reject changed geometry")
    func readOnlySnapshots() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2)
        defer { TestPDFGenerator.cleanup(source) }
        let data = try Data(contentsOf: source)
        let document = try #require(PDFDocument(data: data))
        let page = try #require(document.page(at: 0))
        let isolated = try #require(await PDFPageWorker.readOnlySnapshot(sourceData: data, index: 0,
            rotation: page.rotation, cropBox: page.bounds(for: .cropBox), mediaBox: page.bounds(for: .mediaBox)))
        let expectedData = try #require(page.dataRepresentation)
        let pixels = CGSize(width: 128, height: 192)
        let expected = try await PDFPageWorker.run(pageData: expectedData) {
            try #require(PDFRasterizer.renderPreview($0, pixelSize: pixels))
        }
        let actual = try await PDFPageWorker.run(pageData: isolated) {
            try #require(PDFRasterizer.renderPreview($0, pixelSize: pixels))
        }
        #expect(expected.width == actual.width && expected.height == actual.height)
        #expect(expected.dataProvider?.data == actual.dataProvider?.data)
        #expect(try await PDFPageWorker.readOnlySnapshot(sourceData: data, index: 0,
            rotation: 90, cropBox: page.bounds(for: .cropBox), mediaBox: page.bounds(for: .mediaBox)) == nil)
        #expect(try await PDFPageWorker.readOnlySnapshot(sourceData: data, index: 999,
            rotation: 0, cropBox: .zero, mediaBox: .zero) == nil)
    }

    @Test("Optional estimates compute only displayed settings and retain earlier cached settings")
    func scopedEstimates() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2)
        defer { TestPDFGenerator.cleanup(source) }
        let vm = CompressViewModel()
        vm.setSource(source)
        defer { vm.cancelEstimation() }
        try await waitUntil { vm.estimatedSizes.count == 4 }
        #expect(vm.estimatedSizes.keys.allSatisfy { $0.hasSuffix("-good-false") })
        let first = vm.estimatedSizes
        vm.selectedQuality = .low
        vm.grayscale = true
        try await waitUntil { vm.estimatedSizes.count == 8 }
        for (key, value) in first { #expect(vm.estimatedSizes[key] == value) }
        let scoped = try PDFCompressor().estimateFirstPageSizes(source: source, quality: .low, grayscale: true)
        #expect(scoped.count == 4)
        for (key, value) in scoped { #expect(vm.estimatedSizes[key] == value) }
        vm.mode = .targetSize
        vm.selectedQuality = .best
        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.estimatedSizes.count == 8)
        vm.cancelEstimation()
        vm.selectedQuality = .moderate
        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.estimatedSizes.count == 8)
    }

    @Test("Cancelling file intake cannot publish a stale document or retain a recent-file grant")
    func cancelledIntake() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2)
        defer { TestPDFGenerator.cleanup(source) }
        var started = 0
        var ended = 0
        let vm = AppViewModel(beginSecurityScopedAccess: { _ in started += 1; return true },
                              endSecurityScopedAccess: { _ in ended += 1 })
        vm.openRecentDocument(source)
        #expect(vm.isLoadingFile)
        vm.cancelFileIntake()
        try await waitUntil { ended == 1 }
        #expect(started == ended && vm.isLanding && !vm.isLoadingFile)
        vm.loadSingleFile(source)
        await vm.waitForFileIntake()
        guard case .singleFile(_, let document) = vm.state else { Issue.record("Intake failed"); return }
        #expect(vm.previewSourceData(for: document) == (try Data(contentsOf: source)))
        let copied = try #require(document.copy() as? PDFDocument)
        #expect(vm.previewSourceData(for: copied) == nil)
        vm.startOver()
        #expect(vm.previewSourceData(for: document) == nil)
    }

    @Test("Split and image-export completion follows publication", arguments: ["split", "extract", "export"])
    func completionIsPublished(mode: String) async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2)
        let directory = TestPDFGenerator.makeTempDirectory()
        defer { TestPDFGenerator.cleanup(source); TestPDFGenerator.cleanup(directory) }
        var completed = false
        let progress: (Double) -> Void = { value in
            if value == 1 {
                completed = true
                let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                    includingPropertiesForKeys: nil)) ?? []
                #expect(!files.isEmpty)
            } else { #expect(value >= 0 && value < 1) }
        }
        if mode == "export" {
            _ = try await PDFImageExporter().exportPages(source: source, outputDirectory: directory,
                options: .init(format: .jpeg, dpi: 72), pageIndices: nil, progress: progress)
        } else {
            _ = try await PDFSplitter().split(source: source,
                mode: mode == "split" ? .splitEveryN(1) : .keepPages([1]),
                destination: mode == "split" ? directory : directory.appending(component: "output.pdf"),
                progress: progress)
        }
        #expect(completed)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(20)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw PDFwringerError.cannotCreateOutput }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
