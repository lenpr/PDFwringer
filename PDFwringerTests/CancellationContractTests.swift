import Testing
import PDFKit
import Foundation

/// Tests that cancellation is a reliable contract across all long-running services.
/// Each test starts an operation, cancels after first progress, and verifies cleanup.

@Suite("Cancellation Contract")
@MainActor
struct CancellationContractTests {

    private func expectCancellationAtFinalProgress(
        output: URL,
        operation: @escaping @MainActor (@escaping (Double) -> Void) async throws -> Void
    ) async {
        var operationTask: Task<Void, Error>?
        operationTask = Task { @MainActor in
            try await operation { value in
                if value >= 1 {
                    operationTask?.cancel()
                }
            }
        }

        do {
            try await operationTask?.value
            Issue.record("Expected cancellation before output publication")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }

        #expect(!FileManager.default.fileExists(atPath: output.path(percentEncoded: false)))
    }

    /// Creates a 50-page PDF for cancellation testing (enough pages to cancel mid-operation).
    private func makeLargeSource() -> URL {
        TestPDFGenerator.makeRenderedPDF(pageCount: 50, filename: "cancel_source.pdf")
    }

    @Test("PDFCompressor cancellation cleans up and preserves source")
    func compressorCancellation() async throws {
        let source = makeLargeSource()
        let output = URL.temporaryDirectory.appending(component: "cancel_compress_\(UUID()).pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            try? FileManager.default.removeItem(at: output)
        }

        let sourceData = try Data(contentsOf: source)

        let compressor = PDFCompressor()
        var operationTask: Task<Void, Error>?
        operationTask = Task { @MainActor in
            _ = try await compressor.compress(
                source: source, destination: output,
                level: .medium, quality: .good, grayscale: false,
                progress: { p in
                    if p > 0 { operationTask?.cancel() }
                }
            )
        }
        let task = try #require(operationTask)

        await #expect(throws: CancellationError.self) {
            try await task.value
        }

        PDFAssertions.assertSourceUnmodified(
            url: source,
            originalData: sourceData,
            operation: "compress cancel"
        )
        #expect(!FileManager.default.fileExists(atPath: output.path(percentEncoded: false)))
    }

    @Test("PDFSplitter cancellation cleans up")
    func splitterCancellation() async throws {
        let source = makeLargeSource()
        let outputDirectory = TestPDFGenerator.makeTempDirectory()
        let output = outputDirectory.appending(component: "cancelled.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDirectory)
        }

        let sourceData = try Data(contentsOf: source)

        let splitter = PDFSplitter()
        var operationTask: Task<Void, Error>?
        operationTask = Task { @MainActor in
            _ = try await splitter.split(
                source: source,
                mode: .keepPages(Array(0..<50)),
                destination: output,
                progress: { p in
                    if p > 0 { operationTask?.cancel() }
                }
            )
        }
        let task = try #require(operationTask)

        await #expect(throws: CancellationError.self) {
            try await task.value
        }

        PDFAssertions.assertSourceUnmodified(
            url: source,
            originalData: sourceData,
            operation: "split cancel"
        )
        #expect(!FileManager.default.fileExists(atPath: output.path(percentEncoded: false)))
    }

    @Test("PDFSplitter batch cancellation publishes no partial files")
    func splitterBatchCancellation() async throws {
        let source = makeLargeSource()
        let outputDirectory = TestPDFGenerator.makeTempDirectory()
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDirectory)
        }

        var operationTask: Task<Void, Error>?
        operationTask = Task { @MainActor in
            _ = try await PDFSplitter().split(
                source: source,
                mode: .splitEveryN(1),
                destination: outputDirectory,
                progress: { value in
                    if value > 0 { operationTask?.cancel() }
                }
            )
        }
        let task = try #require(operationTask)

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        let outputs = try FileManager.default.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: nil
        )
        #expect(outputs.isEmpty)
    }

    @Test("PDFConcatenator cancellation cleans up")
    func concatenatorCancellation() async throws {
        let source1 = makeLargeSource()
        let source2 = makeLargeSource()
        let output = URL.temporaryDirectory.appending(component: "cancel_merge_\(UUID()).pdf")
        defer {
            TestPDFGenerator.cleanup(source1)
            TestPDFGenerator.cleanup(source2)
            try? FileManager.default.removeItem(at: output)
        }

        let concatenator = PDFConcatenator()
        var operationTask: Task<Void, Error>?
        operationTask = Task { @MainActor in
            _ = try await concatenator.concatenate(
                sources: [source1, source2],
                destination: output,
                progress: { p in
                    if p > 0 { operationTask?.cancel() }
                }
            )
        }
        let task = try #require(operationTask)

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(!FileManager.default.fileExists(atPath: output.path(percentEncoded: false)))
    }

    @Test("PDFMetadataEditor flatten cancellation cleans up")
    func metadataFlattenCancellation() async throws {
        let source = makeLargeSource()
        let output = URL.temporaryDirectory.appending(component: "cancel_flatten_\(UUID()).pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            try? FileManager.default.removeItem(at: output)
        }

        let sourceData = try Data(contentsOf: source)

        let editor = PDFMetadataEditor()
        var operationTask: Task<Void, Error>?
        operationTask = Task { @MainActor in
            try await editor.write(
                metadata: .empty, source: source, destination: output,
                flattenAnnotations: true,
                progress: { p in
                    if p > 0 { operationTask?.cancel() }
                }
            )
        }
        let task = try #require(operationTask)

        await #expect(throws: CancellationError.self) {
            try await task.value
        }

        PDFAssertions.assertSourceUnmodified(
            url: source,
            originalData: sourceData,
            operation: "flatten cancel"
        )
        #expect(!FileManager.default.fileExists(atPath: output.path(percentEncoded: false)))
    }

    @Test("PDFColorAdjuster cancellation cleans up and source untouched")
    func colorAdjusterCancellation() async throws {
        let source = makeLargeSource()
        let output = URL.temporaryDirectory.appending(component: "cancel_color_\(UUID()).pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            try? FileManager.default.removeItem(at: output)
        }

        let sourceData = try Data(contentsOf: source)

        let adjuster = PDFColorAdjuster()
        var operationTask: Task<Void, Error>?
        operationTask = Task { @MainActor in
            try await adjuster.adjust(
                source: source, destination: output,
                settings: .init(brightness: 0.2, contrast: 1.3, saturation: 0.8),
                pages: nil,
                progress: { p in
                    if p > 0 { operationTask?.cancel() }
                }
            )
        }
        let task = try #require(operationTask)

        await #expect(throws: CancellationError.self) {
            try await task.value
        }

        PDFAssertions.assertSourceUnmodified(
            url: source,
            originalData: sourceData,
            operation: "color adjust cancel"
        )
        #expect(!FileManager.default.fileExists(atPath: output.path(percentEncoded: false)))
    }

    @Test("Cancellation at final progress prevents publishing raster outputs")
    func cancellationAtFinalProgress() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "final_cancel.pdf")
        let directory = TestPDFGenerator.makeTempDirectory()
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(directory)
        }

        let compressed = directory.appending(component: "compressed.pdf")
        await expectCancellationAtFinalProgress(output: compressed) { reportProgress in
            _ = try await PDFCompressor().compress(
                source: source,
                destination: compressed,
                level: .medium,
                quality: .good,
                grayscale: false,
                progress: reportProgress
            )
        }

        let adjusted = directory.appending(component: "adjusted.pdf")
        await expectCancellationAtFinalProgress(output: adjusted) { reportProgress in
            try await PDFColorAdjuster().adjust(
                source: source,
                destination: adjusted,
                settings: .init(brightness: 0.1, contrast: 1, saturation: 1),
                pages: nil,
                dpi: 72,
                progress: reportProgress
            )
        }

        let identityAdjusted = directory.appending(component: "identity-adjusted.pdf")
        await expectCancellationAtFinalProgress(output: identityAdjusted) { reportProgress in
            try await PDFColorAdjuster().adjust(
                source: source,
                destination: identityAdjusted,
                settings: .init(),
                pages: nil,
                progress: reportProgress
            )
        }

        let flattened = directory.appending(component: "flattened.pdf")
        await expectCancellationAtFinalProgress(output: flattened) { reportProgress in
            try await PDFMetadataEditor().write(
                metadata: .empty,
                source: source,
                destination: flattened,
                flattenAnnotations: true,
                progress: reportProgress
            )
        }

        let extracted = directory.appending(component: "extracted.pdf")
        await expectCancellationAtFinalProgress(output: extracted) { reportProgress in
            _ = try await PDFSplitter().split(
                source: source,
                mode: .keepPages([0]),
                destination: extracted,
                progress: reportProgress
            )
        }

        let merged = directory.appending(component: "merged.pdf")
        await expectCancellationAtFinalProgress(output: merged) { reportProgress in
            _ = try await PDFConcatenator().concatenate(
                sources: [source],
                destination: merged,
                progress: reportProgress
            )
        }
    }

    @Test("Image export cancellation at final progress publishes no files")
    func imageExporterCancellationAtFinalProgress() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(
            pageCount: 1,
            filename: "final_cancel_export.pdf"
        )
        let outputDirectory = TestPDFGenerator.makeTempDirectory()
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDirectory)
        }
        let sourceData = try Data(contentsOf: source)

        var operationTask: Task<[URL], Error>?
        operationTask = Task { @MainActor in
            try await PDFImageExporter().exportPages(
                source: source,
                outputDirectory: outputDirectory,
                options: .init(format: .jpeg, dpi: 72, quality: 0.8),
                pageIndices: nil,
                progress: { value in
                    if value >= 1 {
                        operationTask?.cancel()
                    }
                }
            )
        }
        let task = try #require(operationTask)

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(try FileManager.default.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: nil
        ).isEmpty)
        PDFAssertions.assertSourceUnmodified(
            url: source,
            originalData: sourceData,
            operation: "image export final-progress cancel"
        )
    }

    @Test("Rotation cancellation at final progress preserves source and publishes no output")
    func rotatorCancellationAtFinalProgress() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(
            pageCount: 1,
            filename: "final_cancel_rotate.pdf"
        )
        let directory = TestPDFGenerator.makeTempDirectory()
        let output = directory.appending(component: "rotated.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(directory)
        }
        let sourceData = try Data(contentsOf: source)

        await expectCancellationAtFinalProgress(output: output) { reportProgress in
            try await PDFRotator().rotate(
                source: source,
                destination: output,
                angle: .ninety,
                pageIndices: nil,
                progress: reportProgress
            )
        }
        PDFAssertions.assertSourceUnmodified(
            url: source,
            originalData: sourceData,
            operation: "rotation final-progress cancel"
        )
    }

    @Test("Page reordering cancellation prevents publication")
    func pageReorderingCancellation() async throws {
        let source = makeLargeSource()
        let directory = TestPDFGenerator.makeTempDirectory()
        let output = directory.appending(component: "cancelled-reorder.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(directory)
        }
        let document = try #require(PDFDocument(url: source))

        await expectCancellationAtFinalProgress(output: output) { reportProgress in
            try await PDFPageReorderer().reorder(
                document: document,
                source: source,
                destination: output,
                pageOrder: Array((0..<document.pageCount).reversed()),
                progress: reportProgress
            )
        }
    }

    @Test("Pre-cancelled lossless compression does not publish output")
    func preCancelledLosslessCompression() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "lossless_cancel.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "lossless_cancel_out.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        let task = Task { @MainActor in
            try await PDFCompressor().compress(
                source: source,
                destination: output,
                level: .lossless,
                quality: .good,
                grayscale: false,
                removeAnnotations: true,
                progress: { _ in }
            )
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(!FileManager.default.fileExists(atPath: output.path(percentEncoded: false)))
    }
}
