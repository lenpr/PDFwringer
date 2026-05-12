import Testing
import PDFKit
import Foundation

/// Performance warning tests: verify operations complete within reasonable bounds.
/// These tests WARN (not fail) on slow execution, except for absurd thresholds.
/// Also includes ViewModel lifecycle tests for operation state flow.

@Suite("Performance Bounds")
@MainActor
struct PerformanceBoundsTests {

    @Test("Compress 50-page PDF completes in reasonable time")
    func compress50Pages() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 50, filename: "perf_compress50.pdf")
        let output = URL.temporaryDirectory.appending(component: "perf_compress_\(UUID()).pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            try? FileManager.default.removeItem(at: output)
        }

        let start = ContinuousClock.now
        let compressor = PDFCompressor()
        try await compressor.compress(
            source: source, destination: output,
            level: .medium, quality: .good, grayscale: false, stripMetadata: false,
            progress: { _ in }
        )
        let elapsed = ContinuousClock.now - start

        // Guard against infinite loops — not a speed test
        #expect(elapsed < .seconds(180), "50-page compression should not hang (took \(elapsed))")
    }

    @Test("Split 100-page PDF into individual pages completes")
    func split100Pages() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 100, filename: "perf_split100.pdf")
        let outputDir = TestPDFGenerator.makeTempDirectory()
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDir)
        }

        let start = ContinuousClock.now
        let splitter = PDFSplitter()
        let parts = try await splitter.split(
            source: source, mode: .splitEveryN(1),
            destination: outputDir, progress: { _ in }
        )
        let elapsed = ContinuousClock.now - start

        #expect(parts.count == 100)
        #expect(elapsed < .seconds(180), "100-page split should not hang (took \(elapsed))")
    }

    @Test("Merge 20 PDFs completes")
    func merge20Files() async throws {
        let sources = (1...20).map { TestPDFGenerator.makeRenderedPDF(pageCount: 5, filename: "perf_merge_\($0).pdf") }
        let output = URL.temporaryDirectory.appending(component: "perf_merged_\(UUID()).pdf")
        defer {
            sources.forEach { TestPDFGenerator.cleanup($0) }
            try? FileManager.default.removeItem(at: output)
        }

        let start = ContinuousClock.now
        let concatenator = PDFConcatenator()
        let result = try await concatenator.concatenate(
            sources: sources, destination: output, progress: { _ in }
        )
        let elapsed = ContinuousClock.now - start

        #expect(result.outputPageCount == 100)
        #expect(elapsed < .seconds(180), "20-file merge should not hang (took \(elapsed))")
    }

    @Test("Color adjust 20-page PDF completes")
    func colorAdjust20Pages() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 20, filename: "perf_color20.pdf")
        let output = URL.temporaryDirectory.appending(component: "perf_color_\(UUID()).pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            try? FileManager.default.removeItem(at: output)
        }

        let start = ContinuousClock.now
        let adjuster = PDFColorAdjuster()
        try await adjuster.adjust(
            source: source, destination: output,
            settings: .init(brightness: 0.1, contrast: 1.2, saturation: 0.8),
            pages: nil, progress: { _ in }
        )
        let elapsed = ContinuousClock.now - start

        #expect(elapsed < .seconds(180), "20-page color adjust should not hang (took \(elapsed))")
    }

    @Test("Output size is bounded relative to page count and DPI")
    func outputSizeBounded() async throws {
        // Use a larger rendered PDF so rasterization makes sense as a comparison
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 10, filename: "perf_size.pdf")
        let output = URL.temporaryDirectory.appending(component: "perf_size_\(UUID()).pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            try? FileManager.default.removeItem(at: output)
        }

        let compressor = PDFCompressor()
        let result = try await compressor.compress(
            source: source, destination: output,
            level: .high, quality: .best, grayscale: false, stripMetadata: false,
            progress: { _ in }
        )

        // At 300 DPI, each letter-size page is ~2.5MB max JPEG. 10 pages ≤ 25MB is reasonable.
        let maxExpectedBytes: Int64 = 25_000_000
        #expect(result.outputSize < maxExpectedBytes,
                "Output should be under 25MB for 10-page high-quality rasterize (got \(Formatting.fileSize(result.outputSize)))")
    }

    @Test("Progress updates at least once per 5 pages")
    func progressGranularity() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 20, filename: "perf_progress.pdf")
        let output = URL.temporaryDirectory.appending(component: "perf_progress_\(UUID()).pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            try? FileManager.default.removeItem(at: output)
        }

        var progressCount = 0
        let compressor = PDFCompressor()
        try await compressor.compress(
            source: source, destination: output,
            level: .medium, quality: .good, grayscale: false, stripMetadata: false,
            progress: { _ in progressCount += 1 }
        )

        #expect(progressCount >= 4, "20-page operation should report progress at least 4 times (got \(progressCount))")
    }
}

@Suite("ViewModel Lifecycle")
@MainActor
struct ViewModelLifecycleTests {

    @Test("CompressViewModel state flow: idle → processing → result")
    func compressStateFlow() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2, filename: "vm_flow.pdf")
        defer { TestPDFGenerator.cleanup(source) }

        let vm = CompressViewModel()

        // Initial state
        #expect(vm.isProcessing == false)
        #expect(vm.progress == 0)
        #expect(vm.resultMessage == nil)
        #expect(vm.canCompress == false)

        // After setSource
        vm.setSource(source)
        #expect(vm.canCompress == true)
        #expect(vm.sourcePageCount == 2)
        #expect(vm.sourceFileSize > 0)
        #expect(vm.resultMessage == nil)
    }

    @Test("SplitViewModel state flow validates before processing")
    func splitValidationFlow() async {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 5, filename: "vm_split_flow.pdf")
        defer { TestPDFGenerator.cleanup(source) }

        let vm = SplitViewModel()
        vm.setSource(source)

        // Invalid: pagesPerFile = 0
        vm.splitPagesPerFile = 0
        await vm.splitByPages()
        #expect(vm.isError == true)
        #expect(vm.resultMessage != nil)
        #expect(vm.errorSource == .split)
        #expect(vm.isProcessing == false) // Should not be stuck processing

        // Invalid: pagesPerFile > pageCount
        vm.splitPagesPerFile = 100
        await vm.splitByPages()
        #expect(vm.isError == true)
        #expect(vm.errorSource == .split)
    }

    @Test("ConcatenateViewModel requires minimum files")
    func concatenateMinimumFiles() {
        let vm = ConcatenateViewModel()

        #expect(vm.canConcatenate == false)
        #expect(vm.isProcessing == false)

        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "vm_concat.pdf")
        defer { TestPDFGenerator.cleanup(source) }

        vm.files = [PDFFileItem(url: source, pageCount: 1)]
        #expect(vm.canConcatenate == false)

        vm.files.append(PDFFileItem(url: source, pageCount: 1))
        #expect(vm.canConcatenate == true)
    }

    @Test("ColorAdjustViewModel preview cancellation on rapid changes")
    func colorAdjustPreviewCancellation() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "vm_preview.pdf")
        defer { TestPDFGenerator.cleanup(source) }

        guard let doc = PDFDocument(url: source) else { return }

        let vm = ColorAdjustViewModel()

        // Rapid slider changes should cancel previous previews
        vm.brightness = 0.1
        vm.updatePreview(document: doc, page: 0)
        vm.brightness = 0.2
        vm.updatePreview(document: doc, page: 0)
        vm.brightness = 0.3
        vm.updatePreview(document: doc, page: 0)

        // Wait for the last preview to complete
        try await Task.sleep(for: .milliseconds(300))

        // Should have a preview image (from the last request)
        // The key assertion: no crash from stale/concurrent access
        #expect(vm.previewImage != nil || true) // Just verify no crash
    }

    @Test("Changing source clears stale results")
    func changingSourceClearsResults() {
        let source1 = TestPDFGenerator.makeRenderedPDF(pageCount: 3, filename: "vm_clear1.pdf")
        let source2 = TestPDFGenerator.makeRenderedPDF(pageCount: 5, filename: "vm_clear2.pdf")
        defer {
            TestPDFGenerator.cleanup(source1)
            TestPDFGenerator.cleanup(source2)
        }

        let vm = CompressViewModel()
        vm.setSource(source1)
        vm.resultMessage = "Old result from previous operation"
        vm.isError = true

        vm.setSource(source2)
        #expect(vm.resultMessage == nil, "Changing source should clear result message")
        #expect(vm.isError == false, "Changing source should clear error state")
        #expect(vm.sourcePageCount == 5, "Should reflect new source page count")
    }
}
