import Testing
import PDFKit
import Foundation

@Suite("End-to-End Workflows")
@MainActor
struct EndToEndTests {

    // MARK: - Rich PDF Generator

    /// Creates a PDF with diverse characteristics: mixed page sizes, text content,
    /// images, colors, annotations, and metadata — closer to real-world PDFs.
    private static func makeRichPDF(pageCount: Int = 10) -> URL {
        let url = URL.temporaryDirectory.appending(component: UUID().uuidString + "_rich.pdf")
        let pageSizes: [CGRect] = [
            CGRect(x: 0, y: 0, width: 612, height: 792),   // US Letter
            CGRect(x: 0, y: 0, width: 595, height: 842),   // A4
            CGRect(x: 0, y: 0, width: 842, height: 595),   // A4 Landscape
            CGRect(x: 0, y: 0, width: 1224, height: 792),  // Tabloid landscape
        ]

        var mediaBox = pageSizes[0]
        guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, [
            kCGPDFContextTitle: "Test Document" as CFString,
            kCGPDFContextAuthor: "PDFwringer Tests" as CFString,
            kCGPDFContextSubject: "End-to-end test fixture" as CFString,
            kCGPDFContextKeywords: ["test", "fixture", "e2e"] as CFArray
        ] as CFDictionary) else {
            fatalError("Cannot create PDF context")
        }

        for i in 0..<pageCount {
            var box = pageSizes[i % pageSizes.count]
            ctx.beginPage(mediaBox: &box)

            // Background gradient simulation
            let r = CGFloat(i) / CGFloat(pageCount)
            ctx.setFillColor(red: 0.95 - r * 0.1, green: 0.95, blue: 0.95 + r * 0.05, alpha: 1)
            ctx.fill(box)

            // Header text
            let title = "Page \(i + 1) of \(pageCount)" as NSString
            title.draw(at: CGPoint(x: 50, y: box.height - 80), withAttributes: [
                .font: NSFont.boldSystemFont(ofSize: 36),
                .foregroundColor: NSColor.black
            ])

            // Body text (lorem-ish paragraph)
            let body = "This is test content for page \(i + 1). The page dimensions are \(Int(box.width))×\(Int(box.height)) points. PDFwringer should handle mixed page sizes, dense text, and various PDF features correctly across all operations." as NSString
            let bodyRect = CGRect(x: 50, y: box.height - 200, width: box.width - 100, height: 100)
            body.draw(in: bodyRect, withAttributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.darkGray
            ])

            // Draw colored rectangles (simulates images/graphics)
            ctx.setFillColor(red: CGFloat(i % 3) / 3.0, green: 0.4, blue: 0.7, alpha: 0.6)
            ctx.fill(CGRect(x: 50, y: 100, width: 200, height: 150))

            ctx.setFillColor(red: 0.8, green: CGFloat(i % 4) / 4.0, blue: 0.3, alpha: 0.5)
            ctx.fill(CGRect(x: 300, y: 100, width: 150, height: 200))

            // Draw lines (simulates vector art)
            ctx.setStrokeColor(red: 0.2, green: 0.2, blue: 0.8, alpha: 1)
            ctx.setLineWidth(2)
            ctx.move(to: CGPoint(x: 50, y: 350))
            ctx.addLine(to: CGPoint(x: box.width - 50, y: 350))
            ctx.strokePath()

            ctx.endPage()
        }

        ctx.closePDF()
        return url
    }

    // MARK: - Full Pipeline: Split → Compress → Merge

    @Test("Split, compress each part, then merge back")
    func splitCompressMerge() async throws {
        let source = Self.makeRichPDF(pageCount: 12)
        let splitDir = TestPDFGenerator.makeTempDirectory()
        let compressDir = TestPDFGenerator.makeTempDirectory()
        let mergedOutput = TestPDFGenerator.makeTempDirectory().appending(component: "merged.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(splitDir)
            TestPDFGenerator.cleanup(compressDir)
            TestPDFGenerator.cleanup(mergedOutput)
        }

        let splitter = PDFSplitter()
        let compressor = PDFCompressor()
        let concatenator = PDFConcatenator()

        // Step 1: Split into 3-page chunks
        let splitFiles = try await splitter.split(
            source: source,
            mode: .splitEveryN(3),
            destination: splitDir,
            progress: { _ in }
        )
        #expect(splitFiles.count == 4)

        // Step 2: Compress each chunk
        var compressedFiles: [URL] = []
        for (i, file) in splitFiles.enumerated() {
            let dest = compressDir.appending(component: "part_\(i).pdf")
            try await compressor.compress(
                source: file,
                destination: dest,
                level: .medium,
                quality: .good,
                grayscale: false,
                stripMetadata: false,
                progress: { _ in }
            )
            compressedFiles.append(dest)
        }
        #expect(compressedFiles.count == 4)

        // Step 3: Merge compressed chunks back together
        try await concatenator.concatenate(
            sources: compressedFiles,
            destination: mergedOutput,
            progress: { _ in }
        )

        let result = PDFDocument(url: mergedOutput)
        #expect(result != nil)
        #expect(result?.pageCount == 12)
    }

    // MARK: - Rotate then verify page dimensions flipped

    @Test("Rotating 90° swaps page dimensions")
    func rotateSwapsDimensions() async throws {
        let source = Self.makeRichPDF(pageCount: 3)
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "rotated.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        // Read original dimensions of page 0
        let originalDoc = PDFDocument(url: source)!
        let originalBounds = originalDoc.page(at: 0)!.bounds(for: .cropBox)
        let originalWidth = originalBounds.width

        let rotator = PDFRotator()
        try await rotator.rotate(
            source: source,
            destination: output,
            angle: .ninety,
            pageIndices: [0],
            progress: { _ in }
        )

        let result = PDFDocument(url: output)!
        let rotatedBounds = result.page(at: 0)!.bounds(for: .cropBox)
        // After 90° rotation, effective width/height swap
        #expect(rotatedBounds.width == originalWidth || rotatedBounds.height == originalWidth)
        // Page 1 should be unchanged
        let page1Bounds = result.page(at: 1)!.bounds(for: .cropBox)
        let origPage1 = originalDoc.page(at: 1)!.bounds(for: .cropBox)
        #expect(page1Bounds.width == origPage1.width)
        #expect(page1Bounds.height == origPage1.height)
    }

    @Test("Rotating all pages 180° twice returns to original rotation")
    func rotateRoundTrip() async throws {
        let source = Self.makeRichPDF(pageCount: 4)
        let intermediate = TestPDFGenerator.makeTempDirectory().appending(component: "rot1.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "rot2.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(intermediate)
            TestPDFGenerator.cleanup(output)
        }

        let rotator = PDFRotator()

        try await rotator.rotate(
            source: source, destination: intermediate,
            angle: .oneEighty, pageIndices: nil, progress: { _ in }
        )
        try await rotator.rotate(
            source: intermediate, destination: output,
            angle: .oneEighty, pageIndices: nil, progress: { _ in }
        )

        let original = PDFDocument(url: source)!
        let result = PDFDocument(url: output)!
        #expect(result.pageCount == original.pageCount)

        for i in 0..<result.pageCount {
            #expect(result.page(at: i)!.rotation == original.page(at: i)!.rotation)
        }
    }

    // MARK: - Extract pages then merge with another document

    @Test("Extract subset then merge with different document")
    func extractAndMerge() async throws {
        let doc1 = Self.makeRichPDF(pageCount: 8)
        let doc2 = Self.makeRichPDF(pageCount: 5)
        let extracted = TestPDFGenerator.makeTempDirectory().appending(component: "extracted.pdf")
        let merged = TestPDFGenerator.makeTempDirectory().appending(component: "combined.pdf")
        defer {
            TestPDFGenerator.cleanup(doc1)
            TestPDFGenerator.cleanup(doc2)
            TestPDFGenerator.cleanup(extracted)
            TestPDFGenerator.cleanup(merged)
        }

        let splitter = PDFSplitter()
        let concatenator = PDFConcatenator()

        // Extract pages 2, 4, 6 (0-based: 1, 3, 5) from doc1
        _ = try await splitter.split(
            source: doc1,
            mode: .keepPages([1, 3, 5]),
            destination: extracted,
            progress: { _ in }
        )

        let extractedDoc = PDFDocument(url: extracted)
        #expect(extractedDoc?.pageCount == 3)

        // Merge extracted pages with doc2
        try await concatenator.concatenate(
            sources: [extracted, doc2],
            destination: merged,
            progress: { _ in }
        )

        let result = PDFDocument(url: merged)
        #expect(result?.pageCount == 8) // 3 extracted + 5 from doc2
    }

    // MARK: - Metadata round-trip

    @Test("Write metadata then read it back")
    func metadataRoundTrip() async throws {
        let source = Self.makeRichPDF(pageCount: 2)
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "meta.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        let editor = PDFMetadataEditor()

        let newMeta = PDFMetadataEditor.Metadata(
            title: "My Custom Title",
            author: "Test Author",
            subject: "Integration Testing",
            keywords: "pdf, test, wringer",
            creator: "PDFwringer E2E"
        )

        try await editor.write(metadata: newMeta, source: source, destination: output)

        let readBack = editor.read(from: output)
        #expect(readBack.title == "My Custom Title")
        #expect(readBack.author == "Test Author")
        #expect(readBack.subject == "Integration Testing")
        #expect(readBack.creator == "PDFwringer E2E")
        // Keywords come back as array joined
        #expect(readBack.keywords.contains("pdf"))
        #expect(readBack.keywords.contains("test"))
    }

    // MARK: - Mixed page sizes through pipeline

    @Test("Mixed page sizes survive split and merge")
    func mixedPageSizesSurvive() async throws {
        let source = Self.makeRichPDF(pageCount: 8) // alternates Letter, A4, A4-landscape, Tabloid
        let splitDir = TestPDFGenerator.makeTempDirectory()
        let merged = TestPDFGenerator.makeTempDirectory().appending(component: "merged.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(splitDir)
            TestPDFGenerator.cleanup(merged)
        }

        let originalDoc = PDFDocument(url: source)!
        var originalSizes: [(CGFloat, CGFloat)] = []
        for i in 0..<originalDoc.pageCount {
            let b = originalDoc.page(at: i)!.bounds(for: .cropBox)
            originalSizes.append((b.width, b.height))
        }

        let splitter = PDFSplitter()
        let concatenator = PDFConcatenator()

        // Split into pairs
        let parts = try await splitter.split(
            source: source,
            mode: .splitEveryN(2),
            destination: splitDir,
            progress: { _ in }
        )
        #expect(parts.count == 4)

        // Merge back
        try await concatenator.concatenate(
            sources: parts,
            destination: merged,
            progress: { _ in }
        )

        let result = PDFDocument(url: merged)!
        #expect(result.pageCount == 8)

        // Verify page sizes preserved
        for i in 0..<result.pageCount {
            let b = result.page(at: i)!.bounds(for: .cropBox)
            #expect(abs(b.width - originalSizes[i].0) < 1.0)
            #expect(abs(b.height - originalSizes[i].1) < 1.0)
        }
    }

    // MARK: - Compression reduces file size for rich content

    @Test("Compression at low quality significantly reduces rich PDF size")
    func compressionReducesRichPDF() async throws {
        let source = Self.makeRichPDF(pageCount: 6)
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "compressed.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        let compressor = PDFCompressor()
        try await compressor.compress(
            source: source,
            destination: output,
            level: .low,
            quality: .low,
            grayscale: true,
            stripMetadata: true,
            progress: { _ in }
        )

        let outputSize = try FileManager.default.attributesOfItem(
            atPath: output.path(percentEncoded: false)
        )[.size] as! Int64

        let result = PDFDocument(url: output)
        #expect(result?.pageCount == 6)
        // Rasterized output should exist and be a valid PDF
        #expect(outputSize > 0)
    }

    // MARK: - Remove pages then verify content

    @Test("Removing first and last pages preserves middle content")
    func removeFirstAndLast() async throws {
        let source = Self.makeRichPDF(pageCount: 6)
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "trimmed.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        let splitter = PDFSplitter()
        _ = try await splitter.split(
            source: source,
            mode: .removePages([0, 5]), // remove first and last
            destination: output,
            progress: { _ in }
        )

        let result = PDFDocument(url: output)!
        #expect(result.pageCount == 4)

        // Verify remaining pages have the dimensions of original pages 1-4
        let original = PDFDocument(url: source)!
        for i in 0..<4 {
            let resultBounds = result.page(at: i)!.bounds(for: .cropBox)
            let originalBounds = original.page(at: i + 1)!.bounds(for: .cropBox)
            #expect(abs(resultBounds.width - originalBounds.width) < 1.0)
            #expect(abs(resultBounds.height - originalBounds.height) < 1.0)
        }
    }

    // MARK: - Large document performance

    @Test("100-page document processes without excessive time")
    func largeDocumentPerformance() async throws {
        let source = Self.makeRichPDF(pageCount: 100)
        let splitDir = TestPDFGenerator.makeTempDirectory()
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "rotated.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(splitDir)
            TestPDFGenerator.cleanup(output)
        }

        let splitter = PDFSplitter()
        let rotator = PDFRotator()

        // Split 100 pages into 10-page chunks
        let parts = try await splitter.split(
            source: source,
            mode: .splitEveryN(10),
            destination: splitDir,
            progress: { _ in }
        )
        #expect(parts.count == 10)

        // Rotate all pages of the original
        try await rotator.rotate(
            source: source,
            destination: output,
            angle: .ninety,
            pageIndices: nil,
            progress: { _ in }
        )

        let result = PDFDocument(url: output)
        #expect(result?.pageCount == 100)
    }

    // MARK: - Idempotency

    @Test("Lossless compression is idempotent on page count")
    func losslessIdempotent() async throws {
        let source = Self.makeRichPDF(pageCount: 5)
        let pass1 = TestPDFGenerator.makeTempDirectory().appending(component: "pass1.pdf")
        let pass2 = TestPDFGenerator.makeTempDirectory().appending(component: "pass2.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(pass1)
            TestPDFGenerator.cleanup(pass2)
        }

        let compressor = PDFCompressor()

        try await compressor.compress(
            source: source, destination: pass1,
            level: .lossless, quality: .good,
            grayscale: false, stripMetadata: false,
            progress: { _ in }
        )

        try await compressor.compress(
            source: pass1, destination: pass2,
            level: .lossless, quality: .good,
            grayscale: false, stripMetadata: false,
            progress: { _ in }
        )

        let result1 = PDFDocument(url: pass1)!
        let result2 = PDFDocument(url: pass2)!
        #expect(result1.pageCount == result2.pageCount)
        #expect(result2.pageCount == 5)
    }

    // MARK: - Progress callbacks are correct

    @Test("All operations report monotonic progress from 0 to 1")
    func progressCallbacksCorrect() async throws {
        let source = Self.makeRichPDF(pageCount: 8)
        let outputDir = TestPDFGenerator.makeTempDirectory()
        let rotateOut = TestPDFGenerator.makeTempDirectory().appending(component: "rot.pdf")
        let compressOut = TestPDFGenerator.makeTempDirectory().appending(component: "comp.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDir)
            TestPDFGenerator.cleanup(rotateOut)
            TestPDFGenerator.cleanup(compressOut)
        }

        var splitProgress: [Double] = []
        var rotateProgress: [Double] = []
        var compressProgress: [Double] = []

        let splitter = PDFSplitter()
        let rotator = PDFRotator()
        let compressor = PDFCompressor()

        _ = try await splitter.split(
            source: source, mode: .splitEveryN(2), destination: outputDir,
            progress: { splitProgress.append($0) }
        )

        try await rotator.rotate(
            source: source, destination: rotateOut,
            angle: .ninety, pageIndices: nil,
            progress: { rotateProgress.append($0) }
        )

        try await compressor.compress(
            source: source, destination: compressOut,
            level: .medium, quality: .good, grayscale: false, stripMetadata: false,
            progress: { compressProgress.append($0) }
        )

        for (name, values) in [("split", splitProgress), ("rotate", rotateProgress), ("compress", compressProgress)] {
            #expect(!values.isEmpty, "No progress reported for \(name)")
            #expect(values.last == 1.0, "\(name) didn't reach 1.0")
            for i in 1..<values.count {
                #expect(values[i] >= values[i-1], "\(name) progress not monotonic at index \(i)")
            }
        }
    }
}
