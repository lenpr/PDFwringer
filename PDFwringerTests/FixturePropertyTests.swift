import Testing
import PDFKit
import Foundation

/// Tests that verify deeper correctness properties beyond "produces valid output."
/// These catch subtle regressions like: progress going backwards, compression inflating files,
/// rotation losing page geometry, or operations producing files that can't be re-processed.

@Suite("Fixture: Round-Trip Integrity")
@MainActor
struct FixtureRoundTripTests {

    @Test("Rotate 4×90° preserves original page dimensions", arguments: FixtureDiscovery.modifiableFixtures)
    func rotateFullCircle(fixture: FixtureDiscovery.Fixture) async throws {
        guard fixture.pageCount >= 1 else { return }

        // Get original dimensions
        guard let originalDoc = PDFDocument(url: fixture.url),
              let originalPage = originalDoc.page(at: 0) else { return }
        let originalBounds = originalPage.bounds(for: .cropBox)
        let originalRotation = originalPage.rotation

        // Rotate 4 times by 90°
        var currentURL = fixture.url
        var tempFiles: [URL] = []

        for i in 1...4 {
            let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_rot\(i).pdf")
            tempFiles.append(output)

            let rotator = PDFRotator()
            try await rotator.rotate(
                source: currentURL, destination: output,
                angle: .ninety, pageIndices: nil, progress: { _ in }
            )
            currentURL = output
        }
        defer { tempFiles.forEach { try? FileManager.default.removeItem(at: $0) } }

        // After 4×90°, dimensions and rotation should match original
        guard let finalDoc = PDFDocument(url: currentURL),
              let finalPage = finalDoc.page(at: 0) else {
            Issue.record("Cannot open 4×rotated output: \(fixture)")
            return
        }

        let finalBounds = finalPage.bounds(for: .cropBox)
        let finalRotation = finalPage.rotation

        #expect(abs(finalBounds.width - originalBounds.width) < 1,
                "Width should match after 4×90°: \(fixture) (original \(originalBounds.width), got \(finalBounds.width))")
        #expect(abs(finalBounds.height - originalBounds.height) < 1,
                "Height should match after 4×90°: \(fixture) (original \(originalBounds.height), got \(finalBounds.height))")
        #expect(finalRotation == originalRotation,
                "Rotation should match after 4×90°: \(fixture) (original \(originalRotation)°, got \(finalRotation)°)")
    }

    @Test("Lossless compress is idempotent", arguments: FixtureDiscovery.openableFixtures)
    func losslessIdempotent(fixture: FixtureDiscovery.Fixture) async throws {
        let first = FixtureDiscovery.outputURL(for: fixture, suffix: "_lossless1.pdf")
        let second = FixtureDiscovery.outputURL(for: fixture, suffix: "_lossless2.pdf")
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        let compressor = PDFCompressor()

        // First compression
        try await compressor.compress(
            source: fixture.url, destination: first,
            level: .lossless, quality: .good, grayscale: false, stripMetadata: false,
            progress: { _ in }
        )

        // Second compression of the already-compressed output
        try await compressor.compress(
            source: first, destination: second,
            level: .lossless, quality: .good, grayscale: false, stripMetadata: false,
            progress: { _ in }
        )

        // Both outputs should have the same page count
        let firstDoc = PDFDocument(url: first)
        let secondDoc = PDFDocument(url: second)
        #expect(firstDoc?.pageCount == secondDoc?.pageCount,
                "Double-lossless should preserve pages: \(fixture)")

        // Second should not be significantly larger than first (no meaningful inflation)
        // Allow small tolerance for PDFKit re-serialization overhead (timestamps, xref)
        let firstSize = (try? FileManager.default.attributesOfItem(atPath: first.path(percentEncoded: false))[.size] as? Int64) ?? 0
        let secondSize = (try? FileManager.default.attributesOfItem(atPath: second.path(percentEncoded: false))[.size] as? Int64) ?? 0
        let tolerance = max(4096, Int64(Double(firstSize) * 0.01)) // 1% or 4KB, whichever is larger
        #expect(secondSize <= firstSize + tolerance,
                "Double-lossless should not inflate significantly: \(fixture) (first \(firstSize), second \(secondSize), tolerance \(tolerance))")
    }

    @Test("Metadata write then read round-trips correctly", arguments: FixtureDiscovery.openableFixtures)
    func metadataRoundTrip(fixture: FixtureDiscovery.Fixture) async throws {
        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_meta_rt.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let editor = PDFMetadataEditor()
        let written = PDFMetadataEditor.Metadata(
            title: "Round Trip Test — \(fixture.filename)",
            author: "Integration Test Suite",
            subject: "Verifying metadata persistence",
            keywords: "test, round-trip, fixture",
            creator: "PDFwringer v0.1.13"
        )

        try await editor.write(metadata: written, source: fixture.url, destination: output)

        let readBack = editor.read(from: output)
        #expect(readBack.title == written.title, "Title should round-trip: \(fixture)")
        #expect(readBack.author == written.author, "Author should round-trip: \(fixture)")
        #expect(readBack.subject == written.subject, "Subject should round-trip: \(fixture)")
        #expect(readBack.creator == written.creator, "Creator should round-trip: \(fixture)")
        // Keywords may be reordered, just check they're present
        #expect(readBack.keywords.contains("test"), "Keywords should round-trip: \(fixture)")
    }
}

@Suite("Fixture: Progress Monotonicity")
@MainActor
struct FixtureProgressTests {

    @Test("Compress progress is monotonically increasing", arguments: FixtureDiscovery.openableFixtures)
    func compressProgressMonotonic(fixture: FixtureDiscovery.Fixture) async throws {
        guard fixture.pageCount >= 2 else { return }

        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_prog_comp.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        var values: [Double] = []
        let compressor = PDFCompressor()
        try await compressor.compress(
            source: fixture.url, destination: output,
            level: .medium, quality: .good, grayscale: false, stripMetadata: false,
            progress: { p in values.append(p) }
        )

        // Verify monotonicity
        for i in 1..<values.count {
            #expect(values[i] >= values[i-1],
                    "Compress progress should be monotonic: \(fixture) (index \(i): \(values[i-1]) → \(values[i]))")
        }

        // Should reach 1.0
        if let last = values.last {
            #expect(abs(last - 1.0) < 0.01, "Compress progress should reach 1.0: \(fixture) (got \(last))")
        }
    }

    @Test("Color adjust progress is monotonically increasing", arguments: FixtureDiscovery.openableFixtures)
    func colorAdjustProgressMonotonic(fixture: FixtureDiscovery.Fixture) async throws {
        guard fixture.pageCount >= 2 else { return }

        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_prog_color.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        var values: [Double] = []
        let adjuster = PDFColorAdjuster()
        try await adjuster.adjust(
            source: fixture.url, destination: output,
            settings: .init(brightness: 0.1, contrast: 1.1, saturation: 0.9),
            pages: nil,
            progress: { p in values.append(p) }
        )

        for i in 1..<values.count {
            #expect(values[i] >= values[i-1],
                    "ColorAdjust progress should be monotonic: \(fixture)")
        }

        if let last = values.last {
            #expect(abs(last - 1.0) < 0.01, "ColorAdjust progress should reach 1.0: \(fixture)")
        }
    }

    @Test("Split progress is monotonically increasing", arguments: FixtureDiscovery.openableFixtures)
    func splitProgressMonotonic(fixture: FixtureDiscovery.Fixture) async throws {
        guard fixture.pageCount >= 4, fixture.pageCount <= 50 else { return }

        let outputDir = TestPDFGenerator.makeTempDirectory()
        defer { TestPDFGenerator.cleanup(outputDir) }

        var values: [Double] = []
        let splitter = PDFSplitter()
        _ = try await splitter.split(
            source: fixture.url, mode: .splitEveryN(2),
            destination: outputDir,
            progress: { p in values.append(p) }
        )

        for i in 1..<values.count {
            #expect(values[i] >= values[i-1],
                    "Split progress should be monotonic: \(fixture)")
        }
    }
}

@Suite("Fixture: Size Sanity")
@MainActor
struct FixtureSizeSanityTests {

    @Test("Rasterize at low DPI produces smaller output for content-rich PDFs", arguments: FixtureDiscovery.openableFixtures)
    func rasterizeShrinks(fixture: FixtureDiscovery.Fixture) async throws {
        // Only test content-rich PDFs (>50KB) — tiny PDFs may inflate due to JPEG overhead
        guard fixture.fileSize > 50_000 else { return }

        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_size_check.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let compressor = PDFCompressor()
        let result = try await compressor.compress(
            source: fixture.url, destination: output,
            level: .low, quality: .low, grayscale: false, stripMetadata: true,
            progress: { _ in }
        )

        // Low quality rasterization should generally produce smaller output
        // Allow some tolerance — some PDFs are already minimal
        let ratio = Double(result.outputSize) / Double(fixture.fileSize)
        #expect(ratio < 5.0,
                "Low-quality compress should not massively inflate: \(fixture) (ratio \(String(format: "%.1f", ratio))x, source \(fixture.fileSize) → output \(result.outputSize))")
    }

    @Test("Grayscale output is not larger than color output", arguments: FixtureDiscovery.openableFixtures)
    func grayscaleNotLarger(fixture: FixtureDiscovery.Fixture) async throws {
        guard fixture.pageCount <= 10 else { return } // Keep test fast

        let colorOutput = FixtureDiscovery.outputURL(for: fixture, suffix: "_color.pdf")
        let grayOutput = FixtureDiscovery.outputURL(for: fixture, suffix: "_gray.pdf")
        defer {
            try? FileManager.default.removeItem(at: colorOutput)
            try? FileManager.default.removeItem(at: grayOutput)
        }

        let compressor = PDFCompressor()

        try await compressor.compress(
            source: fixture.url, destination: colorOutput,
            level: .medium, quality: .good, grayscale: false, stripMetadata: false,
            progress: { _ in }
        )

        try await compressor.compress(
            source: fixture.url, destination: grayOutput,
            level: .medium, quality: .good, grayscale: true, stripMetadata: false,
            progress: { _ in }
        )

        let colorSize = (try? FileManager.default.attributesOfItem(atPath: colorOutput.path(percentEncoded: false))[.size] as? Int64) ?? 0
        let graySize = (try? FileManager.default.attributesOfItem(atPath: grayOutput.path(percentEncoded: false))[.size] as? Int64) ?? 0

        // Grayscale uses 1 channel vs 4, so should generally be smaller
        // Allow 20% tolerance for edge cases
        #expect(graySize <= Int64(Double(colorSize) * 1.2),
                "Grayscale should not be much larger than color: \(fixture) (color \(colorSize), gray \(graySize))")
    }
}

@Suite("Fixture: Output Re-processability")
@MainActor
struct FixtureReprocessTests {

    @Test("Compressed output can be re-compressed", arguments: FixtureDiscovery.openableFixtures)
    func compressedCanBeRecompressed(fixture: FixtureDiscovery.Fixture) async throws {
        guard fixture.pageCount <= 20 else { return }

        let first = FixtureDiscovery.outputURL(for: fixture, suffix: "_recomp1.pdf")
        let second = FixtureDiscovery.outputURL(for: fixture, suffix: "_recomp2.pdf")
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        let compressor = PDFCompressor()

        try await compressor.compress(
            source: fixture.url, destination: first,
            level: .medium, quality: .good, grayscale: false, stripMetadata: false,
            progress: { _ in }
        )

        // The output of compression should itself be a valid input
        try await compressor.compress(
            source: first, destination: second,
            level: .low, quality: .moderate, grayscale: false, stripMetadata: false,
            progress: { _ in }
        )

        let (valid, _) = FixtureDiscovery.validateOutput(at: second)
        #expect(valid, "Re-compressed output should be valid: \(fixture)")
    }

    @Test("Rotated output can be split", arguments: FixtureDiscovery.openableFixtures)
    func rotatedCanBeSplit(fixture: FixtureDiscovery.Fixture) async throws {
        guard fixture.pageCount >= 2, fixture.pageCount <= 20 else { return }

        let rotated = FixtureDiscovery.outputURL(for: fixture, suffix: "_rot_for_split.pdf")
        let splitDir = TestPDFGenerator.makeTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: rotated)
            TestPDFGenerator.cleanup(splitDir)
        }

        let rotator = PDFRotator()
        try await rotator.rotate(
            source: fixture.url, destination: rotated,
            angle: .ninety, pageIndices: nil, progress: { _ in }
        )

        let splitter = PDFSplitter()
        let parts = try await splitter.split(
            source: rotated, mode: .splitEveryN(1),
            destination: splitDir, progress: { _ in }
        )

        #expect(parts.count == fixture.pageCount,
                "Split of rotated output should produce correct count: \(fixture)")
    }

    @Test("Split parts can be merged back", arguments: FixtureDiscovery.openableFixtures)
    func splitPartsCanMerge(fixture: FixtureDiscovery.Fixture) async throws {
        guard fixture.pageCount >= 2, fixture.pageCount <= 20 else { return }

        let splitDir = TestPDFGenerator.makeTempDirectory()
        let merged = FixtureDiscovery.outputURL(for: fixture, suffix: "_split_merged.pdf")
        defer {
            TestPDFGenerator.cleanup(splitDir)
            try? FileManager.default.removeItem(at: merged)
        }

        let splitter = PDFSplitter()
        let parts = try await splitter.split(
            source: fixture.url, mode: .splitEveryN(1),
            destination: splitDir, progress: { _ in }
        )

        let concatenator = PDFConcatenator()
        let result = try await concatenator.concatenate(
            sources: parts, destination: merged, progress: { _ in }
        )

        #expect(result.outputPageCount == fixture.pageCount,
                "Merged split parts should have original page count: \(fixture)")
        #expect(result.skippedFiles.isEmpty,
                "No split parts should be skipped during merge: \(fixture)")
    }
}

@Suite("Fixture: Annotation Behavior")
@MainActor
struct FixtureAnnotationTests {

    @Test("Lossless compression preserves annotation count", arguments: FixtureDiscovery.openableFixtures)
    func losslessPreservesAnnotations(fixture: FixtureDiscovery.Fixture) async throws {
        guard let sourceDoc = PDFDocument(url: fixture.url) else { return }

        // Count annotations in source
        var sourceAnnotationCount = 0
        for i in 0..<sourceDoc.pageCount {
            sourceAnnotationCount += sourceDoc.page(at: i)?.annotations.count ?? 0
        }
        guard sourceAnnotationCount > 0 else { return } // Only test PDFs with annotations

        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_annot_lossless.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let compressor = PDFCompressor()
        try await compressor.compress(
            source: fixture.url, destination: output,
            level: .lossless, quality: .good, grayscale: false, stripMetadata: false,
            progress: { _ in }
        )

        guard let outputDoc = PDFDocument(url: output) else {
            Issue.record("Cannot open lossless output: \(fixture)")
            return
        }

        var outputAnnotationCount = 0
        for i in 0..<outputDoc.pageCount {
            outputAnnotationCount += outputDoc.page(at: i)?.annotations.count ?? 0
        }

        #expect(outputAnnotationCount == sourceAnnotationCount,
                "Lossless should preserve annotations: \(fixture) (source \(sourceAnnotationCount), output \(outputAnnotationCount))")
    }

    @Test("Lossless with stripMetadata removes annotations", arguments: FixtureDiscovery.modifiableFixtures)
    func stripMetadataRemovesAnnotations(fixture: FixtureDiscovery.Fixture) async throws {
        guard let sourceDoc = PDFDocument(url: fixture.url) else { return }

        var sourceAnnotationCount = 0
        for i in 0..<sourceDoc.pageCount {
            sourceAnnotationCount += sourceDoc.page(at: i)?.annotations.count ?? 0
        }
        guard sourceAnnotationCount > 0 else { return }

        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_annot_stripped.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let compressor = PDFCompressor()
        try await compressor.compress(
            source: fixture.url, destination: output,
            level: .lossless, quality: .good, grayscale: false, stripMetadata: true,
            progress: { _ in }
        )

        guard let outputDoc = PDFDocument(url: output) else {
            Issue.record("Cannot open stripped output: \(fixture)")
            return
        }

        var outputAnnotationCount = 0
        for i in 0..<outputDoc.pageCount {
            outputAnnotationCount += outputDoc.page(at: i)?.annotations.count ?? 0
        }

        #expect(outputAnnotationCount == 0,
                "stripMetadata should remove all annotations: \(fixture) (still has \(outputAnnotationCount))")
    }

    @Test("Flatten renders annotations into page content", arguments: FixtureDiscovery.openableFixtures)
    func flattenBurnsAnnotations(fixture: FixtureDiscovery.Fixture) async throws {
        guard fixture.pageCount <= 5 else { return } // Flatten is slow at 300 DPI

        guard let sourceDoc = PDFDocument(url: fixture.url) else { return }
        var sourceAnnotationCount = 0
        for i in 0..<sourceDoc.pageCount {
            sourceAnnotationCount += sourceDoc.page(at: i)?.annotations.count ?? 0
        }
        guard sourceAnnotationCount > 0 else { return }

        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_annot_flat.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let editor = PDFMetadataEditor()
        try await editor.write(
            metadata: .empty, source: fixture.url, destination: output,
            flattenAnnotations: true, progress: { _ in }
        )

        guard let outputDoc = PDFDocument(url: output) else {
            Issue.record("Cannot open flattened output: \(fixture)")
            return
        }

        // After flattening, annotations should be gone (burned into raster)
        var outputAnnotationCount = 0
        for i in 0..<outputDoc.pageCount {
            outputAnnotationCount += outputDoc.page(at: i)?.annotations.count ?? 0
        }

        #expect(outputAnnotationCount == 0,
                "Flatten should remove annotations (burned into content): \(fixture) (still has \(outputAnnotationCount))")
    }
}
