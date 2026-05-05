import Testing
import PDFKit

@Suite("PDFCompressor")
@MainActor
struct PDFCompressorTests {

    // MARK: - Lossless path

    @Test("Lossless compression produces valid output with same page count")
    func losslessPreservesPages() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 3, filename: "source.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "compressed.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        let compressor = PDFCompressor()
        try await compressor.compress(
            source: source,
            destination: output,
            level: .lossless,
            quality: .good,
            grayscale: false,
            stripMetadata: false,
            progress: { _ in }
        )

        let result = PDFDocument(url: output)
        #expect(result != nil)
        #expect(result?.pageCount == 3)
    }

    @Test("Lossless with stripMetadata produces output")
    func losslessStripMetadata() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2, filename: "meta.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "stripped.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        let compressor = PDFCompressor()
        try await compressor.compress(
            source: source,
            destination: output,
            level: .lossless,
            quality: .good,
            grayscale: false,
            stripMetadata: true,
            progress: { _ in }
        )

        let result = PDFDocument(url: output)
        #expect(result != nil)
        #expect(result?.pageCount == 2)
    }

    // MARK: - Rasterize path

    @Test("Rasterize at medium DPI produces valid output")
    func rasterizeMedium() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2, filename: "raster.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "rasterized.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        let compressor = PDFCompressor()
        try await compressor.compress(
            source: source,
            destination: output,
            level: .medium,
            quality: .good,
            grayscale: false,
            stripMetadata: false,
            progress: { _ in }
        )

        let result = PDFDocument(url: output)
        #expect(result != nil)
        #expect(result?.pageCount == 2)
    }

    @Test("Rasterize with grayscale produces valid output")
    func rasterizeGrayscale() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2, filename: "gray.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "gray_out.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        let compressor = PDFCompressor()
        try await compressor.compress(
            source: source,
            destination: output,
            level: .low,
            quality: .moderate,
            grayscale: true,
            stripMetadata: false,
            progress: { _ in }
        )

        let result = PDFDocument(url: output)
        #expect(result != nil)
        #expect(result?.pageCount == 2)
    }

    @Test("Rasterize at low DPI produces smaller file than high DPI")
    func lowDPISmaller() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 3, filename: "compare.pdf")
        let outputLow = TestPDFGenerator.makeTempDirectory().appending(component: "low.pdf")
        let outputHigh = TestPDFGenerator.makeTempDirectory().appending(component: "high.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputLow)
            TestPDFGenerator.cleanup(outputHigh)
        }

        let compressor = PDFCompressor()

        try await compressor.compress(
            source: source, destination: outputLow,
            level: .low, quality: .low, grayscale: false, stripMetadata: false,
            progress: { _ in }
        )

        try await compressor.compress(
            source: source, destination: outputHigh,
            level: .high, quality: .best, grayscale: false, stripMetadata: false,
            progress: { _ in }
        )

        let lowSize = try FileManager.default.attributesOfItem(atPath: outputLow.path(percentEncoded: false))[.size] as! Int64
        let highSize = try FileManager.default.attributesOfItem(atPath: outputHigh.path(percentEncoded: false))[.size] as! Int64

        #expect(lowSize < highSize)
    }

    // MARK: - Size estimation

    @Test("compressFirstPage returns non-nil estimate for rendered PDF")
    func sizeEstimation() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 5, filename: "estimate.pdf")
        defer { TestPDFGenerator.cleanup(source) }

        let compressor = PDFCompressor()
        let estimate = compressor.compressFirstPage(
            source: source,
            level: .medium,
            quality: .good,
            grayscale: false
        )

        #expect(estimate != nil)
        #expect(estimate! > 0)
    }

    @Test("compressFirstPage returns nil for nonexistent file")
    func sizeEstimationBadFile() async throws {
        let bogus = URL.temporaryDirectory.appending(component: "nonexistent.pdf")
        let compressor = PDFCompressor()
        let estimate = compressor.compressFirstPage(
            source: bogus,
            level: .medium,
            quality: .good,
            grayscale: false
        )

        #expect(estimate == nil)
    }

    // MARK: - Error cases

    @Test("Compression of nonexistent file throws")
    func nonexistentFileThrows() async throws {
        let bogus = URL.temporaryDirectory.appending(component: "ghost.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "out.pdf")
        defer { TestPDFGenerator.cleanup(output) }

        let compressor = PDFCompressor()
        await #expect(throws: PDFwringerError.self) {
            try await compressor.compress(
                source: bogus, destination: output,
                level: .lossless, quality: .good,
                grayscale: false, stripMetadata: false,
                progress: { _ in }
            )
        }
    }

    // MARK: - Progress

    @Test("Reports progress reaching 1.0")
    func progressReachesCompletion() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 4, filename: "prog.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "prog_out.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        var lastProgress: Double = 0
        let compressor = PDFCompressor()
        try await compressor.compress(
            source: source, destination: output,
            level: .medium, quality: .good,
            grayscale: false, stripMetadata: false,
            progress: { p in lastProgress = p }
        )

        #expect(lastProgress == 1.0)
    }
}
