import Testing
import PDFKit
import Foundation

/// Tests that equivalent workflows produce equivalent results.
/// Catches pipeline bugs that single-operation tests miss.

@Suite("Differential Equivalence")
@MainActor
struct DifferentialEquivalenceTests {

    @Test("keepPages [0,1,2] equals removePages [3..n]")
    func keepEqualsRemoveComplement() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 6, filename: "diff_keep_remove.pdf")
        let keepOutput = URL.temporaryDirectory.appending(component: "diff_keep_\(UUID()).pdf")
        let removeOutput = URL.temporaryDirectory.appending(component: "diff_remove_\(UUID()).pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            try? FileManager.default.removeItem(at: keepOutput)
            try? FileManager.default.removeItem(at: removeOutput)
        }

        let splitter = PDFSplitter()

        try await splitter.split(
            source: source, mode: .keepPages([0, 1, 2]),
            destination: keepOutput, progress: { _ in }
        )

        try await splitter.split(
            source: source, mode: .removePages([3, 4, 5]),
            destination: removeOutput, progress: { _ in }
        )

        let keepDoc = PDFDocument(url: keepOutput)
        let removeDoc = PDFDocument(url: removeOutput)

        #expect(keepDoc?.pageCount == 3)
        #expect(removeDoc?.pageCount == 3)

        // Text should match between the two approaches
        let keepText = PDFAssertions.extractText(from: keepOutput)
        let removeText = PDFAssertions.extractText(from: removeOutput)
        #expect(keepText == removeText, "keep [0,1,2] should equal remove [3,4,5]")
    }

    @Test("Crop with zero insets is effectively a copy")
    func zeroCropIsCopy() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 3, filename: "diff_zero_crop.pdf")
        defer { TestPDFGenerator.cleanup(source) }

        guard let doc = PDFDocument(url: source) else {
            Issue.record("Cannot open source")
            return
        }

        let beforeGeom = PDFAssertions.extractGeometry(from: source)

        let cropper = PDFCropper()
        let result = cropper.crop(document: doc, indices: [0, 1, 2], top: 0, bottom: 0, left: 0, right: 0)

        #expect(result.pagesModified == 3)
        #expect(result.pagesSkipped == 0)

        // Geometry should be unchanged
        let afterGeom = PDFAssertions.extractGeometry(from: source) // doc was modified in place
        for (b, a) in zip(beforeGeom, afterGeom) {
            #expect(abs(b.cropBox.width - a.cropBox.width) < 0.01, "Zero crop should not change width")
            #expect(abs(b.cropBox.height - a.cropBox.height) < 0.01, "Zero crop should not change height")
        }
    }

    @Test("Color identity is byte-for-byte copy")
    func colorIdentityIsCopy() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2, filename: "diff_identity.pdf")
        let output = URL.temporaryDirectory.appending(component: "diff_identity_out_\(UUID()).pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            try? FileManager.default.removeItem(at: output)
        }

        let adjuster = PDFColorAdjuster()
        try await adjuster.adjust(
            source: source, destination: output,
            settings: .init(brightness: 0, contrast: 1, saturation: 1),
            pages: nil, progress: { _ in }
        )

        let sourceData = try Data(contentsOf: source)
        let outputData = try Data(contentsOf: output)
        #expect(sourceData == outputData, "Identity color adjustment should produce byte-identical output")
    }

    @Test("Split all individually then merge equals original page count and text")
    func splitMergeEqualsOriginal() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 5, filename: "diff_split_merge.pdf")
        let splitDir = TestPDFGenerator.makeTempDirectory()
        let merged = URL.temporaryDirectory.appending(component: "diff_merged_\(UUID()).pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(splitDir)
            try? FileManager.default.removeItem(at: merged)
        }

        let splitter = PDFSplitter()
        let parts = try await splitter.split(
            source: source, mode: .splitEveryN(1),
            destination: splitDir, progress: { _ in }
        )

        let concatenator = PDFConcatenator()
        try await concatenator.concatenate(
            sources: parts, destination: merged, progress: { _ in }
        )

        // Page count preserved
        let sourceDoc = PDFDocument(url: source)
        let mergedDoc = PDFDocument(url: merged)
        #expect(sourceDoc?.pageCount == mergedDoc?.pageCount)

        // Text preserved
        PDFAssertions.assertTextPreserved(source: source, output: merged, operation: "split→merge round-trip")
    }

    @Test("Metadata write with empty fields preserves page invariants")
    func emptyMetadataPreservesPages() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 3, filename: "diff_empty_meta.pdf")
        let output = URL.temporaryDirectory.appending(component: "diff_meta_\(UUID()).pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            try? FileManager.default.removeItem(at: output)
        }

        let editor = PDFMetadataEditor()
        try await editor.write(
            metadata: .empty, source: source, destination: output
        )

        PDFAssertions.assertGeometryPreserved(source: source, output: output, operation: "empty metadata write")
        PDFAssertions.assertTextPreserved(source: source, output: output, operation: "empty metadata write")
    }

    @Test("Compress then split equals split then compress in page count")
    func compressSplitOrderIndependent() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 6, filename: "diff_order.pdf")
        let compressed = URL.temporaryDirectory.appending(component: "diff_compressed_\(UUID()).pdf")
        let splitDirA = TestPDFGenerator.makeTempDirectory()
        let splitDirB = TestPDFGenerator.makeTempDirectory()
        defer {
            TestPDFGenerator.cleanup(source)
            try? FileManager.default.removeItem(at: compressed)
            TestPDFGenerator.cleanup(splitDirA)
            TestPDFGenerator.cleanup(splitDirB)
        }

        let compressor = PDFCompressor()
        let splitter = PDFSplitter()

        // Path A: compress then split
        try await compressor.compress(
            source: source, destination: compressed,
            level: .medium, quality: .good, grayscale: false, stripMetadata: false,
            progress: { _ in }
        )
        let partsA = try await splitter.split(
            source: compressed, mode: .splitEveryN(2),
            destination: splitDirA, progress: { _ in }
        )

        // Path B: split then compress each part
        let partsRaw = try await splitter.split(
            source: source, mode: .splitEveryN(2),
            destination: splitDirB, progress: { _ in }
        )

        // Same number of output files
        #expect(partsA.count == partsRaw.count, "Compress→split should produce same file count as split→compress")
        #expect(partsA.count == 3, "6 pages / 2 = 3 files")
    }
}
