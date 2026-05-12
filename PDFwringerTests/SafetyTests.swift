import Testing
import PDFKit
import Foundation

/// Tests that operations handle I/O failures gracefully without corrupting source files.
/// Also tests path edge cases (spaces, Unicode, long names).

@Suite("Atomic Write Safety")
@MainActor
struct AtomicWriteSafetyTests {

    @Test("Destination directory missing does not corrupt source")
    func missingDestinationDir() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2, filename: "safe_missing_dir.pdf")
        defer { TestPDFGenerator.cleanup(source) }

        let sourceSize = (try? FileManager.default.attributesOfItem(atPath: source.path(percentEncoded: false))[.size] as? Int64) ?? 0
        let badDest = URL.temporaryDirectory.appending(component: "nonexistent_dir_\(UUID())/output.pdf")

        let compressor = PDFCompressor()
        do {
            try await compressor.compress(
                source: source, destination: badDest,
                level: .lossless, quality: .good, grayscale: false, stripMetadata: false,
                progress: { _ in }
            )
            Issue.record("Should have thrown for missing destination directory")
        } catch {
            // Expected failure
        }

        PDFAssertions.assertSourceUnmodified(url: source, originalSize: sourceSize, operation: "missing dest dir")
    }

    @Test("Destination is a directory does not corrupt source")
    func destinationIsDirectory() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2, filename: "safe_dir_dest.pdf")
        let destDir = TestPDFGenerator.makeTempDirectory()
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(destDir)
        }

        let sourceSize = (try? FileManager.default.attributesOfItem(atPath: source.path(percentEncoded: false))[.size] as? Int64) ?? 0

        let rotator = PDFRotator()
        do {
            try await rotator.rotate(
                source: source, destination: destDir,
                angle: .ninety, pageIndices: nil, progress: { _ in }
            )
            // May succeed (replaceItemAt can overwrite a directory) or fail
        } catch {
            // Expected failure is acceptable
        }

        PDFAssertions.assertSourceUnmodified(url: source, originalSize: sourceSize, operation: "dir as dest")
    }

    @Test("Existing destination file is safely overwritten")
    func existingDestinationOverwritten() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 3, filename: "safe_existing.pdf")
        let output = URL.temporaryDirectory.appending(component: "existing_dest_\(UUID()).pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            try? FileManager.default.removeItem(at: output)
        }

        // Create existing destination file
        try "dummy content".write(to: output, atomically: true, encoding: .utf8)

        let compressor = PDFCompressor()
        try await compressor.compress(
            source: source, destination: output,
            level: .lossless, quality: .good, grayscale: false, stripMetadata: false,
            progress: { _ in }
        )

        // Output should be a valid 3-page PDF, not the dummy content
        let doc = PDFDocument(url: output)
        #expect(doc?.pageCount == 3, "Existing destination should be safely overwritten")
    }

    @Test("Source remains readable after failed operation")
    func sourceReadableAfterFailure() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2, filename: "safe_readable.pdf")
        defer { TestPDFGenerator.cleanup(source) }

        // Force a failure by using source == destination
        let compressor = PDFCompressor()
        do {
            try await compressor.compress(
                source: source, destination: source,
                level: .lossless, quality: .good, grayscale: false, stripMetadata: false,
                progress: { _ in }
            )
        } catch {
            // Expected
        }

        // Source should still be openable
        let doc = PDFDocument(url: source)
        #expect(doc != nil, "Source should remain readable after failed operation")
        #expect(doc?.pageCount == 2, "Source content should be intact")
    }
}

@Suite("Path Edge Cases")
@MainActor
struct PathEdgeCaseTests {

    @Test("Filename with spaces works")
    func filenameWithSpaces() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2, filename: "file with spaces.pdf")
        let output = URL.temporaryDirectory.appending(component: "output with spaces \(UUID()).pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            try? FileManager.default.removeItem(at: output)
        }

        let compressor = PDFCompressor()
        try await compressor.compress(
            source: source, destination: output,
            level: .lossless, quality: .good, grayscale: false, stripMetadata: false,
            progress: { _ in }
        )

        let doc = PDFDocument(url: output)
        #expect(doc?.pageCount == 2)
    }

    @Test("Filename with Unicode characters works")
    func filenameWithUnicode() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2, filename: "résumé_日本語.pdf")
        let output = URL.temporaryDirectory.appending(component: "ausgabe_über_\(UUID()).pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            try? FileManager.default.removeItem(at: output)
        }

        let rotator = PDFRotator()
        try await rotator.rotate(
            source: source, destination: output,
            angle: .ninety, pageIndices: nil, progress: { _ in }
        )

        let doc = PDFDocument(url: output)
        #expect(doc?.pageCount == 2)
    }

    @Test("Filename with emoji works")
    func filenameWithEmoji() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "document_📄_test.pdf")
        let output = URL.temporaryDirectory.appending(component: "result_✅_\(UUID()).pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            try? FileManager.default.removeItem(at: output)
        }

        let splitter = PDFSplitter()
        try await splitter.split(
            source: source, mode: .keepPages([0]),
            destination: output, progress: { _ in }
        )

        let doc = PDFDocument(url: output)
        #expect(doc?.pageCount == 1)
    }

    @Test("Uppercase .PDF extension works")
    func uppercaseExtension() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2, filename: "DOCUMENT.PDF")
        let output = URL.temporaryDirectory.appending(component: "OUTPUT_\(UUID()).PDF")
        defer {
            TestPDFGenerator.cleanup(source)
            try? FileManager.default.removeItem(at: output)
        }

        let compressor = PDFCompressor()
        try await compressor.compress(
            source: source, destination: output,
            level: .lossless, quality: .good, grayscale: false, stripMetadata: false,
            progress: { _ in }
        )

        let doc = PDFDocument(url: output)
        #expect(doc?.pageCount == 2)
    }

    @Test("Very long filename works")
    func veryLongFilename() async throws {
        let longName = String(repeating: "a", count: 200) + ".pdf"
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: longName)
        let output = URL.temporaryDirectory.appending(component: "long_output_\(UUID()).pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            try? FileManager.default.removeItem(at: output)
        }

        let compressor = PDFCompressor()
        try await compressor.compress(
            source: source, destination: output,
            level: .lossless, quality: .good, grayscale: false, stripMetadata: false,
            progress: { _ in }
        )

        let doc = PDFDocument(url: output)
        #expect(doc?.pageCount == 1)
    }
}
