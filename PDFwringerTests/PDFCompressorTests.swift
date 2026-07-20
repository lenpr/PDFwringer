import Dispatch
import Testing
import PDFKit

private final class MissingPagePDFDocument: PDFDocument {
    var inaccessiblePageIndex: Int?

    override func page(at index: Int) -> PDFPage? {
        if index == inaccessiblePageIndex { return nil }
        return super.page(at: index)
    }
}

private final class InvalidBoundsPDFPage: PDFPage {
    override func bounds(for box: PDFDisplayBox) -> CGRect {
        CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 792)
    }
}

private final class BoundaryBoundsPDFPage: PDFPage {
    override func bounds(for box: PDFDisplayBox) -> CGRect {
        CGRect(x: 0, y: 0, width: CGFloat(Int.max), height: 1)
    }
}

private func rgbaPixels(of image: CGImage) -> [UInt8]? {
    let bytesPerRow = image.width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
    guard let context = CGContext(
        data: &pixels,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return pixels
}

private func significantPixelDifference(_ first: CGImage, _ second: CGImage) -> Double? {
    guard first.width == second.width,
          first.height == second.height,
          let firstPixels = rgbaPixels(of: first),
          let secondPixels = rgbaPixels(of: second) else {
        return nil
    }

    var changedPixels = 0
    for offset in stride(from: 0, to: firstPixels.count, by: 4) {
        let difference = abs(Int(firstPixels[offset]) - Int(secondPixels[offset]))
            + abs(Int(firstPixels[offset + 1]) - Int(secondPixels[offset + 1]))
            + abs(Int(firstPixels[offset + 2]) - Int(secondPixels[offset + 2]))
        if difference > 30 { changedPixels += 1 }
    }
    return Double(changedPixels) / Double(first.width * first.height)
}

@Suite("PDFCompressor")
@MainActor
struct PDFCompressorTests {

    // MARK: - Lossless path

    @Test("Lossless strips document metadata while preserving pages and annotations")
    func losslessStripsDocumentMetadata() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 3, filename: "source.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "compressed.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        let sourceDocument = try #require(PDFDocument(url: source))
        sourceDocument.documentAttributes = [
            PDFDocumentAttribute.titleAttribute: "Private title"
        ]
        let firstPage = try #require(sourceDocument.page(at: 0))
        firstPage.addAnnotation(PDFAnnotation(
            bounds: CGRect(x: 20, y: 20, width: 30, height: 30),
            forType: .text,
            withProperties: nil
        ))
        #expect(sourceDocument.write(to: source))
        let persistedSource = try #require(PDFDocument(url: source))
        let sourceAnnotationCount = try #require(persistedSource.page(at: 0)).annotations.count
        #expect(sourceAnnotationCount > 0)

        let compressor = PDFCompressor()
        try await compressor.compress(
            source: source,
            destination: output,
            level: .lossless,
            quality: .good,
            grayscale: false,
            progress: { _ in }
        )

        let result = PDFDocument(url: output)
        #expect(result != nil)
        #expect(result?.pageCount == 3)
        #expect(result?.documentAttributes?[PDFDocumentAttribute.titleAttribute] == nil)
        #expect(result?.page(at: 0)?.annotations.count == sourceAnnotationCount)
    }

    @Test("Lossless annotation removal produces output")
    func losslessRemovesAnnotations() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2, filename: "meta.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "stripped.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        let sourceDocument = try #require(PDFDocument(url: source))
        let firstPage = try #require(sourceDocument.page(at: 0))
        firstPage.addAnnotation(PDFAnnotation(
            bounds: CGRect(x: 20, y: 20, width: 30, height: 30),
            forType: .text,
            withProperties: nil
        ))
        #expect(sourceDocument.write(to: source))

        let compressor = PDFCompressor()
        let compressionResult = try await compressor.compress(
            source: source,
            destination: output,
            level: .lossless,
            quality: .good,
            grayscale: false,
            removeAnnotations: true,
            progress: { _ in }
        )

        let result = PDFDocument(url: output)
        #expect(result != nil)
        #expect(result?.pageCount == 2)
        #expect(result?.page(at: 0)?.annotations.isEmpty == true)
        #expect(compressionResult.outputSize > 0)
    }

    @Test("Lossless annotation removal refuses forms and redactions")
    func losslessRefusesSensitiveAnnotations() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "sensitive.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "stripped.pdf")
        let originalDestination = Data("existing destination".utf8)
        try originalDestination.write(to: output)
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        let sourceDocument = try #require(PDFDocument(url: source))
        let page = try #require(sourceDocument.page(at: 0))
        let form = PDFAnnotation(
            bounds: CGRect(x: 20, y: 20, width: 120, height: 24),
            forType: .widget,
            withProperties: nil
        )
        form.widgetFieldType = .text
        form.widgetStringValue = "private form value"
        page.addAnnotation(form)
        let redaction = PDFAnnotation(
            bounds: CGRect(x: 20, y: 60, width: 120, height: 24),
            forType: PDFAnnotationSubtype(rawValue: "/Redact"),
            withProperties: nil
        )
        page.addAnnotation(redaction)
        #expect(sourceDocument.write(to: source))

        do {
            _ = try await PDFCompressor().compress(
                source: source,
                destination: output,
                level: .lossless,
                quality: .good,
                grayscale: false,
                removeAnnotations: true,
                progress: { _ in }
            )
            Issue.record("Expected sensitiveAnnotationsRequireFlattening")
        } catch PDFwringerError.sensitiveAnnotationsRequireFlattening {
            // Expected.
        } catch {
            Issue.record("Expected sensitiveAnnotationsRequireFlattening, got \(error)")
        }

        #expect(try Data(contentsOf: output) == originalDestination)
        let preservedSource = try #require(PDFDocument(url: source))
        #expect(preservedSource.page(at: 0)?.annotations.count == 2)
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
            progress: { _ in }
        )

        let result = PDFDocument(url: output)
        #expect(result != nil)
        #expect(result?.pageCount == 2)
    }

    @Test("Rasterization suspends MainActor before reporting page progress")
    func rasterizationKeepsMainActorResponsive() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "responsive.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "responsive_out.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        var mainActorHeartbeat = false
        var heartbeatAtFirstProgress: Bool?
        Task { @MainActor in
            mainActorHeartbeat = true
        }

        try await PDFCompressor().compress(
            source: source,
            destination: output,
            level: .medium,
            quality: .good,
            grayscale: false,
            progress: { _ in
                if heartbeatAtFirstProgress == nil {
                    heartbeatAtFirstProgress = mainActorHeartbeat
                }
            }
        )

        #expect(heartbeatAtFirstProgress == true)
    }

    @Test("Page worker propagates cancellation to detached rendering")
    func pageWorkerPropagatesCancellation() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "worker_cancel.pdf")
        defer { TestPDFGenerator.cleanup(source) }

        let document = try #require(PDFDocument(url: source))
        let page = try #require(document.page(at: 0))
        let pageData = try #require(page.dataRepresentation)
        let (started, signalStarted) = AsyncStream<Void>.makeStream()
        let releaseWorker = DispatchSemaphore(value: 0)
        defer {
            signalStarted.finish()
            releaseWorker.signal()
        }

        let operation = Task {
            try await PDFPageWorker.run(pageData: pageData) { _ in
                signalStarted.yield()
                releaseWorker.wait()
                try Task.checkCancellation()
            }
        }

        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        operation.cancel()
        releaseWorker.signal()

        await #expect(throws: CancellationError.self) {
            try await operation.value
        }
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
            level: .low, quality: .low, grayscale: false,
            progress: { _ in }
        )

        try await compressor.compress(
            source: source, destination: outputHigh,
            level: .high, quality: .best, grayscale: false,
            progress: { _ in }
        )

        let lowSize = try FileManager.default.attributesOfItem(atPath: outputLow.path(percentEncoded: false))[.size] as! Int64
        let highSize = try FileManager.default.attributesOfItem(atPath: outputHigh.path(percentEncoded: false))[.size] as! Int64

        #expect(lowSize < highSize)
    }

    // MARK: - Size estimation

    @Test("Batched first-page estimation returns every settings combination")
    func batchedSizeEstimation() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 5, filename: "estimate.pdf")
        defer { TestPDFGenerator.cleanup(source) }

        let compressor = PDFCompressor()
        let estimates = try compressor.estimateFirstPageSizes(source: source)

        let expectedCount = CompressionLevel.allCases.count * JPEGQuality.allCases.count * 2
        #expect(estimates.count == expectedCount)
        #expect(estimates.values.allSatisfy { $0 > 0 })
    }

    @Test("Batched first-page estimation rejects a nonexistent file")
    func batchedSizeEstimationBadFile() async throws {
        let bogus = URL.temporaryDirectory.appending(component: "nonexistent.pdf")
        let compressor = PDFCompressor()

        #expect(throws: PDFwringerError.self) {
            try compressor.estimateFirstPageSizes(source: bogus)
        }
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
                grayscale: false,
                progress: { _ in }
            )
        }
    }

    @Test("Rasterization fails without replacing destination when any page is inaccessible")
    func inaccessiblePageFailsEntireCompression() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 3, filename: "missing_page.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "out.pdf")
        let originalDestination = Data("existing destination".utf8)
        try originalDestination.write(to: output)
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        let data = try Data(contentsOf: source)
        let document = try #require(MissingPagePDFDocument(data: data))
        document.inaccessiblePageIndex = 1

        let compressor = PDFCompressor()
        await #expect(throws: PDFwringerError.self) {
            try await compressor.compress(
                document: document,
                source: source,
                destination: output,
                level: .medium,
                quality: .good,
                grayscale: false,
                progress: { _ in }
            )
        }

        #expect(try Data(contentsOf: output) == originalDestination)
    }

    @Test("Rendering rejects invalid page geometry instead of trapping")
    func invalidPageGeometryFailsRendering() {
        let page = InvalidBoundsPDFPage()

        let result = PDFRasterizer.render(page, dpi: 150, grayscale: false)

        #expect(result == nil)
    }

    @Test("Rendering rejects the rounded Int boundary instead of trapping")
    func integerBoundaryPageGeometryFailsRendering() {
        let page = BoundaryBoundsPDFPage()

        let result = PDFRasterizer.render(page, dpi: 72, grayscale: false)

        #expect(result == nil)
    }

    @Test("PDFKit raster matches Core Graphics for rotated pages")
    func pdfKitRasterPreservesRotatedPage() throws {
        let source = TestPDFGenerator.makeCroppedRasterFixture(
            cropOrigin: .zero,
            rotation: 90,
            filename: "rotated.pdf"
        )
        defer { TestPDFGenerator.cleanup(source.deletingLastPathComponent()) }

        try assertPDFKitRasterMatchesCoreGraphics(source)
    }

    @Test("PDFKit raster matches Core Graphics for nonzero crop origins")
    func pdfKitRasterPreservesOffsetCropBox() throws {
        let source = TestPDFGenerator.makeCroppedRasterFixture(
            cropOrigin: CGPoint(x: 108, y: 126),
            rotation: 0,
            filename: "offset-crop.pdf"
        )
        defer { TestPDFGenerator.cleanup(source.deletingLastPathComponent()) }

        try assertPDFKitRasterMatchesCoreGraphics(source)
    }

    private func assertPDFKitRasterMatchesCoreGraphics(
        _ source: URL,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let pdfKitDocument = try #require(PDFDocument(url: source), sourceLocation: sourceLocation)
        let pdfKitPage = try #require(pdfKitDocument.page(at: 0), sourceLocation: sourceLocation)
        let coreGraphicsDocument = try #require(
            PDFRasterizer.openDocument(at: source),
            sourceLocation: sourceLocation
        )
        let coreGraphicsPage = try #require(
            coreGraphicsDocument.page(at: 1),
            sourceLocation: sourceLocation
        )
        let pdfKitRaster = try #require(
            PDFRasterizer.render(pdfKitPage, dpi: 72, grayscale: false),
            sourceLocation: sourceLocation
        )
        let coreGraphicsRaster = try #require(
            PDFRasterizer.render(coreGraphicsPage, dpi: 72, grayscale: false),
            sourceLocation: sourceLocation
        )

        #expect(pdfKitRaster.image.width == coreGraphicsRaster.image.width, sourceLocation: sourceLocation)
        #expect(pdfKitRaster.image.height == coreGraphicsRaster.image.height, sourceLocation: sourceLocation)
        let difference = try #require(
            significantPixelDifference(pdfKitRaster.image, coreGraphicsRaster.image),
            sourceLocation: sourceLocation
        )
        #expect(
            difference < 0.01,
            "PDFKit raster lost or displaced page content (pixel difference: \(difference))",
            sourceLocation: sourceLocation
        )
    }

    // MARK: - Pixel dimension capping

    @Test("renderPage caps oversized pages to A3 dimensions")
    func renderPageCapsOversizedPages() async throws {
        let source = TestPDFGenerator.makeOversizedPDF(pageCount: 1, width: 3024, height: 4032)
        defer { TestPDFGenerator.cleanup(source) }

        let doc = PDFRasterizer.openDocument(at: source)!
        let page = doc.page(at: 1)!

        let dpi: CGFloat = 150
        let result = PDFRasterizer.render(page, dpi: dpi, grayscale: false)

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

        let doc = PDFRasterizer.openDocument(at: source)!
        let page = doc.page(at: 1)!

        let dpi: CGFloat = 150
        let result = PDFRasterizer.render(page, dpi: dpi, grayscale: false)

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
            grayscale: false,
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

    @Test("Batched first-page estimate is in reasonable range of actual output")
    func batchedFirstPageEstimateReasonable() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 4, filename: "est_acc.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "est_out.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        let compressor = PDFCompressor()
        let estimates = try compressor.estimateFirstPageSizes(source: source)
        let key = PDFCompressor.estimateKey(
            level: .medium,
            quality: .good,
            grayscale: false
        )
        let estimate = estimates[key]
        #expect(estimate != nil)

        try await compressor.compress(
            source: source, destination: output,
            level: .medium, quality: .good,
            grayscale: false,
            progress: { _ in }
        )

        let actualSize = try FileManager.default.attributesOfItem(
            atPath: output.path(percentEncoded: false)
        )[.size] as! Int64

        // Estimate should be within 5x of actual (it extrapolates from first page)
        #expect(estimate! < actualSize * 5, "Estimate \(estimate!) is too high vs actual \(actualSize)")
        #expect(estimate! > actualSize / 5, "Estimate \(estimate!) is too low vs actual \(actualSize)")
    }

    @Test("Batched estimation gives every lossless setting the same estimate")
    func batchedLosslessEstimate() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 3, filename: "lossless_est.pdf")
        defer { TestPDFGenerator.cleanup(source) }

        let sourceSize = try FileManager.default.attributesOfItem(
            atPath: source.path(percentEncoded: false)
        )[.size] as! Int64

        let compressor = PDFCompressor()
        let estimates = try compressor.estimateFirstPageSizes(source: source)
        let expected = Int64(Double(sourceSize) * 0.95)
        for quality in JPEGQuality.allCases {
            for grayscale in [false, true] {
                let key = PDFCompressor.estimateKey(
                    level: .lossless,
                    quality: quality,
                    grayscale: grayscale
                )
                #expect(estimates[key] == expected)
            }
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
            grayscale: false,
            progress: { p in lastProgress = p }
        )

        #expect(lastProgress == 1.0)
    }
}
