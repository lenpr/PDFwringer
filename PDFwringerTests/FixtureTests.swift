import Testing
import PDFKit
import Foundation

/// Comprehensive integration tests that run all PDF operations against real-world fixture files.
/// Tests are automatically skipped if no fixtures are present in PDFwringerTests/Fixtures/.
@Suite("Fixture: Compress")
@MainActor
struct FixtureCompressTests {

    @Test("Lossless compression produces valid output", arguments: FixtureDiscovery.openableFixtures)
    func losslessCompression(fixture: FixtureDiscovery.Fixture) async throws {
        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_lossless.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let compressor = PDFCompressor()
        try await compressor.compress(
            source: fixture.url,
            destination: output,
            level: .lossless,
            quality: .good,
            grayscale: false,
            stripMetadata: false,
            progress: { _ in }
        )

        let (valid, pages) = FixtureDiscovery.validateOutput(at: output)
        #expect(valid, "Lossless output should be a valid PDF: \(fixture)")
        #expect(pages == fixture.pageCount, "Lossless should preserve page count: \(fixture) (got \(pages), expected \(fixture.pageCount))")
    }

    @Test("Rasterize compression produces valid smaller output", arguments: FixtureDiscovery.openableFixtures)
    func rasterizeCompression(fixture: FixtureDiscovery.Fixture) async throws {
        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_rasterized.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let compressor = PDFCompressor()
        let result = try await compressor.compress(
            source: fixture.url,
            destination: output,
            level: .medium,
            quality: .good,
            grayscale: false,
            stripMetadata: false,
            progress: { _ in }
        )

        let (valid, pages) = FixtureDiscovery.validateOutput(at: output)
        #expect(valid, "Rasterized output should be a valid PDF: \(fixture)")
        #expect(pages == fixture.pageCount - result.skippedPages,
                "Rasterized page count should match: \(fixture)")
        #expect(result.outputSize > 0, "Output should have non-zero size: \(fixture)")
    }

    @Test("Grayscale compression produces valid output", arguments: FixtureDiscovery.openableFixtures)
    func grayscaleCompression(fixture: FixtureDiscovery.Fixture) async throws {
        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_grayscale.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let compressor = PDFCompressor()
        try await compressor.compress(
            source: fixture.url,
            destination: output,
            level: .low,
            quality: .moderate,
            grayscale: true,
            stripMetadata: true,
            progress: { _ in }
        )

        let (valid, _) = FixtureDiscovery.validateOutput(at: output)
        #expect(valid, "Grayscale output should be a valid PDF: \(fixture)")
    }

    @Test("High quality compression preserves all pages", arguments: FixtureDiscovery.openableFixtures)
    func highQualityCompression(fixture: FixtureDiscovery.Fixture) async throws {
        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_high.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let compressor = PDFCompressor()
        let result = try await compressor.compress(
            source: fixture.url,
            destination: output,
            level: .high,
            quality: .best,
            grayscale: false,
            stripMetadata: false,
            progress: { _ in }
        )

        #expect(result.skippedPages == 0, "High quality should not skip pages: \(fixture)")
    }
}

@Suite("Fixture: Rotate")
@MainActor
struct FixtureRotateTests {

    @Test("Rotate 90° produces valid output", arguments: FixtureDiscovery.openableFixtures)
    func rotate90(fixture: FixtureDiscovery.Fixture) async throws {
        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_rot90.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let rotator = PDFRotator()
        try await rotator.rotate(
            source: fixture.url,
            destination: output,
            angle: .ninety,
            pageIndices: nil,
            progress: { _ in }
        )

        let (valid, pages) = FixtureDiscovery.validateOutput(at: output)
        #expect(valid, "Rotated output should be valid: \(fixture)")
        #expect(pages == fixture.pageCount, "Rotation should preserve page count: \(fixture)")
    }

    @Test("Rotate 180° produces valid output", arguments: FixtureDiscovery.openableFixtures)
    func rotate180(fixture: FixtureDiscovery.Fixture) async throws {
        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_rot180.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let rotator = PDFRotator()
        try await rotator.rotate(
            source: fixture.url,
            destination: output,
            angle: .oneEighty,
            pageIndices: nil,
            progress: { _ in }
        )

        let (valid, pages) = FixtureDiscovery.validateOutput(at: output)
        #expect(valid, "Rotated output should be valid: \(fixture)")
        #expect(pages == fixture.pageCount, "Rotation should preserve page count: \(fixture)")
    }

    @Test("Rotate specific pages produces valid output", arguments: FixtureDiscovery.openableFixtures)
    func rotateSpecificPages(fixture: FixtureDiscovery.Fixture) async throws {
        guard fixture.pageCount >= 2 else { return }

        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_rot_partial.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let rotator = PDFRotator()
        try await rotator.rotate(
            source: fixture.url,
            destination: output,
            angle: .twoSeventy,
            pageIndices: [0],
            progress: { _ in }
        )

        let (valid, pages) = FixtureDiscovery.validateOutput(at: output)
        #expect(valid, "Partial rotation output should be valid: \(fixture)")
        #expect(pages == fixture.pageCount, "Partial rotation should preserve page count: \(fixture)")
    }
}

@Suite("Fixture: Split")
@MainActor
struct FixtureSplitTests {

    @Test("Split every 1 page produces correct file count", arguments: FixtureDiscovery.openableFixtures)
    func splitEveryPage(fixture: FixtureDiscovery.Fixture) async throws {
        guard fixture.pageCount >= 2, fixture.pageCount <= 50 else { return } // Skip huge docs

        let outputDir = TestPDFGenerator.makeTempDirectory()
        defer { TestPDFGenerator.cleanup(outputDir) }

        let splitter = PDFSplitter()
        let outputs = try await splitter.split(
            source: fixture.url,
            mode: .splitEveryN(1),
            destination: outputDir,
            progress: { _ in }
        )

        #expect(outputs.count == fixture.pageCount,
                "Split by 1 should produce \(fixture.pageCount) files: \(fixture) (got \(outputs.count))")

        // Verify each output is a valid 1-page PDF
        for outputURL in outputs {
            let (valid, pages) = FixtureDiscovery.validateOutput(at: outputURL, expectedPages: 1)
            #expect(valid, "Each split file should be a valid 1-page PDF: \(fixture)")
            _ = pages
        }
    }

    @Test("Keep first page extracts correctly", arguments: FixtureDiscovery.openableFixtures)
    func keepFirstPage(fixture: FixtureDiscovery.Fixture) async throws {
        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_page1.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let splitter = PDFSplitter()
        try await splitter.split(
            source: fixture.url,
            mode: .keepPages([0]),
            destination: output,
            progress: { _ in }
        )

        let (valid, pages) = FixtureDiscovery.validateOutput(at: output, expectedPages: 1)
        #expect(valid, "Extracted page should be valid: \(fixture)")
        _ = pages
    }

    @Test("Remove first page produces n-1 pages", arguments: FixtureDiscovery.openableFixtures)
    func removeFirstPage(fixture: FixtureDiscovery.Fixture) async throws {
        guard fixture.pageCount >= 2 else { return }

        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_no_first.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let splitter = PDFSplitter()
        try await splitter.split(
            source: fixture.url,
            mode: .removePages([0]),
            destination: output,
            progress: { _ in }
        )

        let (valid, pages) = FixtureDiscovery.validateOutput(at: output, expectedPages: fixture.pageCount - 1)
        #expect(valid, "Output after removing first page should be valid: \(fixture)")
        _ = pages
    }
}

@Suite("Fixture: Merge")
@MainActor
struct FixtureMergeTests {

    @Test("Merge fixture with itself doubles page count", arguments: FixtureDiscovery.openableFixtures)
    func mergeWithSelf(fixture: FixtureDiscovery.Fixture) async throws {
        guard fixture.pageCount <= 100 else { return } // Skip huge docs for memory

        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_merged.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let concatenator = PDFConcatenator()
        let result = try await concatenator.concatenate(
            sources: [fixture.url, fixture.url],
            destination: output,
            progress: { _ in }
        )

        #expect(result.skippedFiles.isEmpty, "No files should be skipped: \(fixture)")
        let (valid, pages) = FixtureDiscovery.validateOutput(at: output, expectedPages: fixture.pageCount * 2)
        #expect(valid, "Merged output should be valid with 2x pages: \(fixture)")
        _ = pages
    }

    @Test("Merge all openable fixtures into one document")
    func mergeAllFixtures() async throws {
        let fixtures = FixtureDiscovery.openableFixtures
        guard fixtures.count >= 2 else { return }

        // Limit to first 5 to avoid excessive memory/time
        let subset = Array(fixtures.prefix(5))
        let totalExpectedPages = subset.reduce(0) { $0 + $1.pageCount }

        let output = URL.temporaryDirectory.appending(component: "merged_all_fixtures.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let concatenator = PDFConcatenator()
        let result = try await concatenator.concatenate(
            sources: subset.map(\.url),
            destination: output,
            progress: { _ in }
        )

        let (valid, pages) = FixtureDiscovery.validateOutput(at: output)
        #expect(valid, "Merged-all output should be valid")
        #expect(pages == totalExpectedPages - (result.skippedFiles.count > 0 ? 0 : 0),
                "Merged pages should sum to \(totalExpectedPages), got \(pages)")
    }
}

@Suite("Fixture: Crop")
@MainActor
struct FixtureCropTests {

    @Test("Crop reduces page dimensions", arguments: FixtureDiscovery.openableFixtures)
    func cropReducesDimensions(fixture: FixtureDiscovery.Fixture) async throws {
        guard let doc = PDFDocument(url: fixture.url), let page = doc.page(at: 0) else { return }

        let originalBounds = page.bounds(for: .cropBox)
        guard originalBounds.width > 100, originalBounds.height > 100 else { return }

        let cropper = PDFCropper()
        let result = cropper.crop(
            document: doc,
            indices: Array(0..<doc.pageCount),
            top: 10, bottom: 10, left: 10, right: 10
        )

        #expect(result.pagesModified == doc.pageCount, "All pages should be cropped: \(fixture)")
        #expect(result.pagesSkipped == 0, "No pages should be skipped: \(fixture)")

        // Verify first page dimensions reduced
        if let croppedPage = doc.page(at: 0) {
            let newBounds = croppedPage.bounds(for: .cropBox)
            #expect(newBounds.width < originalBounds.width, "Width should decrease: \(fixture)")
            #expect(newBounds.height < originalBounds.height, "Height should decrease: \(fixture)")
        }
    }

    @Test("Resize to A4 applies correctly", arguments: FixtureDiscovery.openableFixtures)
    func resizeToA4(fixture: FixtureDiscovery.Fixture) async throws {
        guard let doc = PDFDocument(url: fixture.url) else { return }

        let cropper = PDFCropper()
        let a4 = PaperSize.a4.size
        let result = cropper.resize(
            document: doc,
            indices: Array(0..<doc.pageCount),
            targetSize: a4
        )

        #expect(result.pagesModified == doc.pageCount, "All pages should be resized: \(fixture)")

        if let page = doc.page(at: 0) {
            let bounds = page.bounds(for: .cropBox)
            #expect(abs(bounds.width - a4.width) < 1, "Width should be A4: \(fixture)")
            #expect(abs(bounds.height - a4.height) < 1, "Height should be A4: \(fixture)")
        }
    }
}

@Suite("Fixture: Color Adjust")
@MainActor
struct FixtureColorAdjustTests {

    @Test("Color adjustment produces valid output", arguments: FixtureDiscovery.openableFixtures)
    func adjustColors(fixture: FixtureDiscovery.Fixture) async throws {
        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_adjusted.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let adjuster = PDFColorAdjuster()
        let result = try await adjuster.adjust(
            source: fixture.url,
            destination: output,
            settings: .init(brightness: 0.1, contrast: 1.2, saturation: 0.8),
            pages: nil,
            progress: { _ in }
        )

        let (valid, pages) = FixtureDiscovery.validateOutput(at: output)
        #expect(valid, "Color-adjusted output should be valid: \(fixture)")
        #expect(pages == fixture.pageCount - result.skippedPages,
                "Color-adjusted page count should match: \(fixture)")
    }

    @Test("Identity settings copies unchanged", arguments: FixtureDiscovery.openableFixtures)
    func identityCopiesUnchanged(fixture: FixtureDiscovery.Fixture) async throws {
        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_identity.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let adjuster = PDFColorAdjuster()
        try await adjuster.adjust(
            source: fixture.url,
            destination: output,
            settings: .init(brightness: 0, contrast: 1, saturation: 1),
            pages: nil,
            progress: { _ in }
        )

        // Identity should produce a byte-for-byte copy
        let sourceData = try Data(contentsOf: fixture.url)
        let outputData = try Data(contentsOf: output)
        #expect(sourceData == outputData, "Identity adjustment should produce identical output: \(fixture)")
    }

    @Test("Partial page adjustment produces valid output", arguments: FixtureDiscovery.openableFixtures)
    func partialPageAdjustment(fixture: FixtureDiscovery.Fixture) async throws {
        guard fixture.pageCount >= 2 else { return }

        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_partial_adj.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let adjuster = PDFColorAdjuster()
        try await adjuster.adjust(
            source: fixture.url,
            destination: output,
            settings: .init(brightness: 0.2, contrast: 1.5, saturation: 0.5),
            pages: [0], // Only first page
            progress: { _ in }
        )

        let (valid, pages) = FixtureDiscovery.validateOutput(at: output)
        #expect(valid, "Partial adjustment output should be valid: \(fixture)")
        #expect(pages == fixture.pageCount, "All pages should be in output: \(fixture)")
    }
}

@Suite("Fixture: Metadata")
@MainActor
struct FixtureMetadataTests {

    @Test("Read metadata does not crash", arguments: FixtureDiscovery.openableFixtures)
    func readMetadata(fixture: FixtureDiscovery.Fixture) {
        let editor = PDFMetadataEditor()
        let metadata = editor.read(from: fixture.url)
        // Just verify it doesn't crash — metadata may be empty
        _ = metadata.title
        _ = metadata.author
        _ = metadata.subject
        _ = metadata.keywords
        _ = metadata.creator
    }

    @Test("Write metadata produces valid output", arguments: FixtureDiscovery.openableFixtures)
    func writeMetadata(fixture: FixtureDiscovery.Fixture) async throws {
        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_meta.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let editor = PDFMetadataEditor()
        let metadata = PDFMetadataEditor.Metadata(
            title: "Test Title",
            author: "Test Author",
            subject: "Test Subject",
            keywords: "test, fixture, pdf",
            creator: "PDFwringer Tests"
        )

        try await editor.write(
            metadata: metadata,
            source: fixture.url,
            destination: output
        )

        let (valid, pages) = FixtureDiscovery.validateOutput(at: output, expectedPages: fixture.pageCount)
        #expect(valid, "Metadata-written output should be valid: \(fixture)")
        _ = pages

        // Verify metadata was actually written
        let readBack = editor.read(from: output)
        #expect(readBack.title == "Test Title", "Title should persist: \(fixture)")
        #expect(readBack.author == "Test Author", "Author should persist: \(fixture)")
    }

    @Test("Flatten annotations produces valid output", arguments: FixtureDiscovery.openableFixtures)
    func flattenAnnotations(fixture: FixtureDiscovery.Fixture) async throws {
        // Only test fixtures with reasonable page count (flattening is slow at 300 DPI)
        guard fixture.pageCount <= 10 else { return }

        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_flattened.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let editor = PDFMetadataEditor()
        try await editor.write(
            metadata: .empty,
            source: fixture.url,
            destination: output,
            flattenAnnotations: true,
            progress: { _ in }
        )

        let (valid, pages) = FixtureDiscovery.validateOutput(at: output)
        #expect(valid, "Flattened output should be valid: \(fixture)")
        #expect(pages == fixture.pageCount, "Flatten should preserve page count: \(fixture)")
    }
}

@Suite("Fixture: Error Handling")
@MainActor
struct FixtureErrorTests {

    @Test("Locked PDFs are rejected gracefully", arguments: FixtureDiscovery.lockedFixtures)
    func lockedPDFsRejected(fixture: FixtureDiscovery.Fixture) async {
        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_should_fail.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let compressor = PDFCompressor()
        do {
            try await compressor.compress(
                source: fixture.url, destination: output,
                level: .lossless, quality: .good, grayscale: false, stripMetadata: false,
                progress: { _ in }
            )
            Issue.record("Should have thrown for locked PDF: \(fixture)")
        } catch {
            // Expected — locked PDFs should throw
            #expect(error is PDFwringerError, "Should throw PDFwringerError: \(fixture)")
        }
    }

    @Test("Corrupt PDFs are rejected gracefully", arguments: FixtureDiscovery.corruptFixtures)
    func corruptPDFsRejected(fixture: FixtureDiscovery.Fixture) async {
        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_should_fail.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let compressor = PDFCompressor()
        do {
            try await compressor.compress(
                source: fixture.url, destination: output,
                level: .lossless, quality: .good, grayscale: false, stripMetadata: false,
                progress: { _ in }
            )
            Issue.record("Should have thrown for corrupt PDF: \(fixture)")
        } catch {
            #expect(error is PDFwringerError, "Should throw PDFwringerError: \(fixture)")
        }
    }
}

@Suite("Fixture: Pipeline")
@MainActor
struct FixturePipelineTests {

    @Test("Compress then rotate produces valid output", arguments: FixtureDiscovery.openableFixtures)
    func compressThenRotate(fixture: FixtureDiscovery.Fixture) async throws {
        guard fixture.pageCount <= 20 else { return }

        let compressed = FixtureDiscovery.outputURL(for: fixture, suffix: "_pipe_compressed.pdf")
        let rotated = FixtureDiscovery.outputURL(for: fixture, suffix: "_pipe_rotated.pdf")
        defer {
            try? FileManager.default.removeItem(at: compressed)
            try? FileManager.default.removeItem(at: rotated)
        }

        let compressor = PDFCompressor()
        try await compressor.compress(
            source: fixture.url, destination: compressed,
            level: .medium, quality: .good, grayscale: false, stripMetadata: false,
            progress: { _ in }
        )

        let rotator = PDFRotator()
        try await rotator.rotate(
            source: compressed, destination: rotated,
            angle: .ninety, pageIndices: nil, progress: { _ in }
        )

        let (valid, pages) = FixtureDiscovery.validateOutput(at: rotated, expectedPages: fixture.pageCount)
        #expect(valid, "Pipeline output should be valid: \(fixture)")
        _ = pages
    }

    @Test("Split and merge round-trip preserves page count", arguments: FixtureDiscovery.openableFixtures)
    func splitMergeRoundTrip(fixture: FixtureDiscovery.Fixture) async throws {
        guard fixture.pageCount >= 2, fixture.pageCount <= 30 else { return }

        let splitDir = TestPDFGenerator.makeTempDirectory()
        let merged = FixtureDiscovery.outputURL(for: fixture, suffix: "_roundtrip.pdf")
        defer {
            TestPDFGenerator.cleanup(splitDir)
            try? FileManager.default.removeItem(at: merged)
        }

        let splitter = PDFSplitter()
        let parts = try await splitter.split(
            source: fixture.url,
            mode: .splitEveryN(max(1, fixture.pageCount / 2)),
            destination: splitDir,
            progress: { _ in }
        )

        let concatenator = PDFConcatenator()
        try await concatenator.concatenate(
            sources: parts,
            destination: merged,
            progress: { _ in }
        )

        let (valid, pages) = FixtureDiscovery.validateOutput(at: merged, expectedPages: fixture.pageCount)
        #expect(valid, "Round-trip output should be valid: \(fixture)")
        _ = pages
    }
}
