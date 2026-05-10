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

    // MARK: - Pixel dimension capping

    @Test("renderPage caps oversized pages to A3 dimensions")
    func renderPageCapsOversizedPages() async throws {
        let source = TestPDFGenerator.makeOversizedPDF(pageCount: 1, width: 3024, height: 4032)
        defer { TestPDFGenerator.cleanup(source) }

        let doc = PDFCompressor.openPDF(at: source)!
        let page = doc.page(at: 1)!

        let dpi: CGFloat = 150
        let result = PDFCompressor.renderPage(page, dpi: dpi, grayscale: false)

        #expect(result != nil)
        let image = result!.image
        let maxLong = Int(16.5 * dpi)   // 2475
        let maxShort = Int(11.7 * dpi)  // 1755
        let longSide = max(image.width, image.height)
        let shortSide = min(image.width, image.height)

        #expect(longSide <= maxLong, "Long side \(longSide) exceeds A3 cap \(maxLong)")
        #expect(shortSide <= maxShort, "Short side \(shortSide) exceeds A3 cap \(maxShort)")
    }

    @Test("Normal-sized pages are not capped by A3 limit")
    func renderPageDoesNotCapNormalPages() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "normal.pdf")
        defer { TestPDFGenerator.cleanup(source) }

        let doc = PDFCompressor.openPDF(at: source)!
        let page = doc.page(at: 1)!

        let dpi: CGFloat = 150
        let result = PDFCompressor.renderPage(page, dpi: dpi, grayscale: false)

        #expect(result != nil)
        let image = result!.image
        // US Letter at 150 DPI = 1275×1650 — well within A3 cap
        let expectedW = Int(612.0 * dpi / 72.0)  // 1275
        let expectedH = Int(792.0 * dpi / 72.0)  // 1650
        #expect(image.width == expectedW)
        #expect(image.height == expectedH)
    }

    @Test("Rasterizing oversized PDF produces capped output size")
    func rasterizeOversizedPDFProducesReasonableSize() async throws {
        let source = TestPDFGenerator.makeOversizedPDF(pageCount: 3)
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "oversized_out.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        let compressor = PDFCompressor()
        try await compressor.compress(
            source: source, destination: output,
            level: .medium, quality: .good,
            grayscale: false, stripMetadata: false,
            progress: { _ in }
        )

        let outputSize = try FileManager.default.attributesOfItem(
            atPath: output.path(percentEncoded: false)
        )[.size] as! Int64

        // Without pixel capping, 3024×4032 pt at 150 DPI would produce enormous bitmaps.
        // With capping, each page is ≤ 2475×1755 px ≈ 4.3 MP × 3 bytes × 0.07 JPEG ratio ≈ 900 KB/page.
        // 3 pages should be well under 5 MB.
        #expect(outputSize < 5_000_000, "Output \(outputSize) bytes exceeds expected capped size")
        #expect(outputSize > 0)

        let result = PDFDocument(url: output)
        #expect(result?.pageCount == 3)
    }

    // MARK: - Estimation accuracy

    @Test("compressFirstPage estimate is in reasonable range of actual output")
    func compressFirstPageEstimateReasonable() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 4, filename: "est_acc.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "est_out.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        let compressor = PDFCompressor()
        let estimate = compressor.compressFirstPage(
            source: source, level: .medium, quality: .good, grayscale: false
        )
        #expect(estimate != nil)

        try await compressor.compress(
            source: source, destination: output,
            level: .medium, quality: .good,
            grayscale: false, stripMetadata: false,
            progress: { _ in }
        )

        let actualSize = try FileManager.default.attributesOfItem(
            atPath: output.path(percentEncoded: false)
        )[.size] as! Int64

        // Estimate should be within 5x of actual (it extrapolates from first page)
        #expect(estimate! < actualSize * 5, "Estimate \(estimate!) is too high vs actual \(actualSize)")
        #expect(estimate! > actualSize / 5, "Estimate \(estimate!) is too low vs actual \(actualSize)")
    }

    @Test("compressFirstPage lossless returns ~95% of source size")
    func compressFirstPageLosslessReturnsEstimate() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 3, filename: "lossless_est.pdf")
        defer { TestPDFGenerator.cleanup(source) }

        let sourceSize = try FileManager.default.attributesOfItem(
            atPath: source.path(percentEncoded: false)
        )[.size] as! Int64

        let compressor = PDFCompressor()
        let estimate = compressor.compressFirstPage(
            source: source, level: .lossless, quality: .good, grayscale: false
        )

        #expect(estimate != nil)
        let expected = Int64(Double(sourceSize) * 0.95)
        #expect(estimate == expected)
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
