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
        return (0..<doc.pageCount).map { doc.page(at: $0)?.string ?? "" }
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

        guard !sourceText.isEmpty, !outputText.isEmpty,
              sourceText.count == outputText.count else {
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

    /// Returns whether at least one page has extractable text.
    static func hasExtractableText(url: URL) -> Bool {
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
            "Page \(pageIndex+1): media=\(mediaBox), crop=\(cropBox), rot=\(rotation)°"
        }
    }

    /// Extracts geometry for all pages in a PDF.
    static func extractGeometry(from url: URL) -> [PageGeometry] {
        guard let doc = PDFDocument(url: url) else { return [] }
        return extractGeometry(from: doc)
    }

    /// Extracts geometry from an already-open document, including unsaved edits.
    static func extractGeometry(from document: PDFDocument) -> [PageGeometry] {
        (0..<document.pageCount).compactMap { i in
            guard let page = document.page(at: i) else { return nil }
            return PageGeometry(
                mediaBox: page.bounds(for: .mediaBox),
                cropBox: page.bounds(for: .cropBox),
                rotation: page.rotation,
                pageIndex: i
            )
        }
    }

    /// Returns whether the origins and sizes of two rectangles match within tolerance.
    static func rectanglesMatch(
        _ lhs: CGRect,
        _ rhs: CGRect,
        tolerance: CGFloat = 1
    ) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < tolerance &&
        abs(lhs.origin.y - rhs.origin.y) < tolerance &&
        abs(lhs.size.width - rhs.size.width) < tolerance &&
        abs(lhs.size.height - rhs.size.height) < tolerance
    }

    /// Compares page boxes in page-relative coordinates. PDFKit may legally
    /// normalize a nonzero media-box origin while shifting every other box by
    /// the same amount during serialization.
    static func pageBoxesMatch(
        _ lhs: PageGeometry,
        _ rhs: PageGeometry,
        tolerance: CGFloat = 1
    ) -> Bool {
        rectanglesMatch(
            relativeBox(lhs.mediaBox, mediaBox: lhs.mediaBox),
            relativeBox(rhs.mediaBox, mediaBox: rhs.mediaBox),
            tolerance: tolerance
        ) && rectanglesMatch(
            relativeBox(lhs.cropBox, mediaBox: lhs.mediaBox),
            relativeBox(rhs.cropBox, mediaBox: rhs.mediaBox),
            tolerance: tolerance
        )
    }

    private static func relativeBox(_ box: CGRect, mediaBox: CGRect) -> CGRect {
        box.offsetBy(dx: -mediaBox.minX, dy: -mediaBox.minY)
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

        guard !sourceGeom.isEmpty, !outputGeom.isEmpty,
              sourceGeom.count == outputGeom.count else {
            Issue.record(
                "Geometry check failed for \(operation): page count differs (source \(sourceGeom.count), output \(outputGeom.count))",
                sourceLocation: sourceLocation
            )
            return
        }

        for (s, o) in zip(sourceGeom, outputGeom) {
            let sourceMedia = relativeBox(s.mediaBox, mediaBox: s.mediaBox)
            let outputMedia = relativeBox(o.mediaBox, mediaBox: o.mediaBox)
            let sourceCrop = relativeBox(s.cropBox, mediaBox: s.mediaBox)
            let outputCrop = relativeBox(o.cropBox, mediaBox: o.mediaBox)
            let mediaMatch = rectanglesMatch(sourceMedia, outputMedia)
            let cropMatch = rectanglesMatch(sourceCrop, outputCrop)
            let rotMatch = allowRotationChange || s.rotation == o.rotation

            if !mediaMatch {
                Issue.record(
                    "Geometry failed for \(operation) on page \(s.pageIndex+1): mediaBox size differs (source \(s.mediaBox), output \(o.mediaBox))",
                    sourceLocation: sourceLocation
                )
            }
            if !cropMatch {
                Issue.record(
                    "Geometry failed for \(operation) on page \(s.pageIndex+1): page-relative cropBox differs (source \(sourceCrop), output \(outputCrop))",
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
        guard !sourceGeom.isEmpty,
              sourceGeom.count == outputGeom.count,
              !indicesToCheck.isEmpty,
              indicesToCheck.allSatisfy({ sourceGeom.indices.contains($0) }) else {
            Issue.record(
                "Rotation check failed: source/output geometry is missing, mismatched, or the selection is invalid",
                sourceLocation: sourceLocation
            )
            return
        }

        for i in indicesToCheck {
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
        originalData: Data,
        operation: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let currentData = try? Data(contentsOf: url)
        #expect(
            currentData == originalData,
            "Source file contents were modified by \(operation)",
            sourceLocation: sourceLocation
        )
    }
}
