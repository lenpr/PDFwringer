import Foundation
import PDFKit
import Testing

/// Reusable assertion helpers for PDF testing. These provide stronger oracles than
/// "output is valid" by checking specific invariants that operations must preserve.
@MainActor
enum PDFAssertions {

    // MARK: - Text Preservation

    /// Extracts all text from a PDF, page by page.
    static func extractText(from url: URL) -> [String] {
        guard let doc = PDFDocument(url: url) else { return [] }
        return (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }
    }

    /// Asserts that text content is preserved between source and output PDFs.
    /// Use for operations that should NOT rasterize (lossless, metadata, rotate, split, merge, crop).
    static func assertTextPreserved(
        source: URL,
        output: URL,
        operation: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let sourceText = extractText(from: source)
        let outputText = extractText(from: output)

        guard sourceText.count == outputText.count else {
            Issue.record(
                "Text preservation failed for \(operation): page count differs (source \(sourceText.count), output \(outputText.count))",
                sourceLocation: sourceLocation
            )
            return
        }

        for (i, (s, o)) in zip(sourceText, outputText).enumerated() {
            let normalizedSource = s.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedOutput = o.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedSource != normalizedOutput && !normalizedSource.isEmpty {
                Issue.record(
                    "Text preservation failed for \(operation) on page \(i+1): text differs",
                    sourceLocation: sourceLocation
                )
                return
            }
        }
    }

    /// Asserts that at least one page has extractable text (for fixtures known to have text).
    static func assertHasExtractableText(
        url: URL,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> Bool {
        let texts = extractText(from: url)
        return texts.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: - Page Geometry

    /// Captures per-page geometry for comparison.
    struct PageGeometry: Equatable, CustomStringConvertible {
        let mediaBox: CGRect
        let cropBox: CGRect
        let rotation: Int
        let pageIndex: Int

        var description: String {
            "Page \(pageIndex+1): media=\(Int(mediaBox.width))×\(Int(mediaBox.height)), crop=\(Int(cropBox.width))×\(Int(cropBox.height)), rot=\(rotation)°"
        }
    }

    /// Extracts geometry for all pages in a PDF.
    static func extractGeometry(from url: URL) -> [PageGeometry] {
        guard let doc = PDFDocument(url: url) else { return [] }
        return (0..<doc.pageCount).compactMap { i in
            guard let page = doc.page(at: i) else { return nil }
            return PageGeometry(
                mediaBox: page.bounds(for: .mediaBox),
                cropBox: page.bounds(for: .cropBox),
                rotation: page.rotation,
                pageIndex: i
            )
        }
    }

    /// Asserts that page geometry is preserved between source and output.
    /// Use for operations that should not change page dimensions or rotation.
    static func assertGeometryPreserved(
        source: URL,
        output: URL,
        operation: String,
        allowRotationChange: Bool = false,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let sourceGeom = extractGeometry(from: source)
        let outputGeom = extractGeometry(from: output)

        guard sourceGeom.count == outputGeom.count else {
            Issue.record(
                "Geometry check failed for \(operation): page count differs (source \(sourceGeom.count), output \(outputGeom.count))",
                sourceLocation: sourceLocation
            )
            return
        }

        for (s, o) in zip(sourceGeom, outputGeom) {
            let mediaMatch = abs(s.mediaBox.width - o.mediaBox.width) < 1 &&
                             abs(s.mediaBox.height - o.mediaBox.height) < 1
            let cropMatch = abs(s.cropBox.width - o.cropBox.width) < 1 &&
                            abs(s.cropBox.height - o.cropBox.height) < 1
            let rotMatch = allowRotationChange || s.rotation == o.rotation

            if !mediaMatch {
                Issue.record(
                    "Geometry failed for \(operation) on page \(s.pageIndex+1): mediaBox differs (source \(Int(s.mediaBox.width))×\(Int(s.mediaBox.height)), output \(Int(o.mediaBox.width))×\(Int(o.mediaBox.height)))",
                    sourceLocation: sourceLocation
                )
            }
            if !cropMatch {
                Issue.record(
                    "Geometry failed for \(operation) on page \(s.pageIndex+1): cropBox differs (source \(Int(s.cropBox.width))×\(Int(s.cropBox.height)), output \(Int(o.cropBox.width))×\(Int(o.cropBox.height)))",
                    sourceLocation: sourceLocation
                )
            }
            if !rotMatch {
                Issue.record(
                    "Geometry failed for \(operation) on page \(s.pageIndex+1): rotation differs (source \(s.rotation)°, output \(o.rotation)°)",
                    sourceLocation: sourceLocation
                )
            }
        }
    }

    /// Asserts rotation changed by expected amount on all pages.
    static func assertRotationChanged(
        source: URL,
        output: URL,
        expectedDelta: Int,
        pageIndices: [Int]? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let sourceGeom = extractGeometry(from: source)
        let outputGeom = extractGeometry(from: output)

        let indicesToCheck = pageIndices ?? Array(0..<sourceGeom.count)

        for i in indicesToCheck where i < sourceGeom.count && i < outputGeom.count {
            let expected = (sourceGeom[i].rotation + expectedDelta) % 360
            let actual = outputGeom[i].rotation
            if actual != expected {
                Issue.record(
                    "Rotation check failed on page \(i+1): expected \(expected)°, got \(actual)°",
                    sourceLocation: sourceLocation
                )
            }
        }
    }

    // MARK: - Annotation Counting

    /// Counts total annotations across all pages.
    static func annotationCount(in url: URL) -> Int {
        guard let doc = PDFDocument(url: url) else { return 0 }
        return (0..<doc.pageCount).reduce(0) { sum, i in
            sum + (doc.page(at: i)?.annotations.count ?? 0)
        }
    }

    // MARK: - File Safety

    /// Asserts that a source file was not modified by an operation.
    static func assertSourceUnmodified(
        url: URL,
        originalSize: Int64,
        operation: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let currentSize = (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.size] as? Int64) ?? -1
        #expect(currentSize == originalSize,
                "Source file was modified by \(operation): expected \(originalSize) bytes, got \(currentSize)",
                sourceLocation: sourceLocation)
    }
}
