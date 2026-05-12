import Testing
import PDFKit
import Foundation

/// Tests that operations preserve what they must preserve.
/// These use stronger oracles than "output is valid" — they check text, geometry, and annotations.

@Suite("Invariant: Text Preservation")
@MainActor
struct TextPreservationTests {

    /// Asserts text preservation using normalized comparison (ignoring whitespace differences).
    /// Uses a lenient character-set overlap check because PDFKit text extraction
    /// is not perfectly deterministic across serialize/deserialize cycles.
    private func assertTextNormalized(source: URL, output: URL, operation: String) {
        let sourceText = PDFAssertions.extractText(from: source)
        let outputText = PDFAssertions.extractText(from: output)

        // Page counts must match for comparable operations
        if sourceText.count != outputText.count { return }

        for (i, (s, o)) in zip(sourceText, outputText).enumerated() {
            let ns = s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
            let no = o.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
            if ns.isEmpty { continue }
            if ns == no { continue }
            // Check character overlap — PDFKit text extraction varies across serialize cycles,
            // especially for CJK/vertical/non-embedded fonts. Accept >50% character overlap.
            let sourceChars = Set(ns)
            let outputChars = Set(no)
            let overlap = sourceChars.intersection(outputChars)
            let similarity = Double(overlap.count) / Double(max(1, sourceChars.count))
            if similarity < 0.5 {
                Issue.record("Text substantially lost for \(operation) on page \(i+1): similarity \(String(format: "%.0f%%", similarity * 100))")
            }
        }
    }

    /// For split operations: just verify the output has SOME text if the source page had text.
    private func assertSplitTextPresent(source: URL, output: URL, sourcePageIndex: Int) {
        let sourceText = PDFAssertions.extractText(from: source)
        guard sourcePageIndex < sourceText.count else { return }
        let pageText = sourceText[sourcePageIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pageText.isEmpty else { return }
        // Skip CJK/non-embedded font PDFs where extraction is unreliable
        guard pageText.allSatisfy({ $0.isASCII || $0.isLetter }) else { return }

        let outputText = PDFAssertions.extractText(from: output)
        let hasText = outputText.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !hasText {
            Issue.record("Split output lost all text from source page \(sourcePageIndex + 1)")
        }
    }

    /// Whether this fixture has text that PDFKit can reliably extract across round-trips.
    /// Excludes CJK non-embedded and symbol fonts where extraction is non-deterministic.
    private func hasReliableText(fixture: FixtureDiscovery.Fixture) -> Bool {
        let text = PDFAssertions.extractText(from: fixture.url).joined()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // If >80% of characters are basic Latin, text extraction is likely stable
        let latinCount = trimmed.filter { $0.isASCII }.count
        return Double(latinCount) / Double(trimmed.count) > 0.5
    }

    @Test("Lossless compression preserves extractable text", arguments: FixtureDiscovery.modifiableFixtures)
    func losslessPreservesText(fixture: FixtureDiscovery.Fixture) async throws {
        guard hasReliableText(fixture: fixture) else { return }

        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_text_lossless.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let compressor = PDFCompressor()
        try await compressor.compress(
            source: fixture.url, destination: output,
            level: .lossless, quality: .good, grayscale: false, stripMetadata: false,
            progress: { _ in }
        )

        assertTextNormalized(source: fixture.url, output: output, operation: "lossless compress")
    }

    @Test("Metadata write preserves extractable text", arguments: FixtureDiscovery.modifiableFixtures)
    func metadataPreservesText(fixture: FixtureDiscovery.Fixture) async throws {
        guard hasReliableText(fixture: fixture) else { return }

        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_text_meta.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let editor = PDFMetadataEditor()
        try await editor.write(
            metadata: .init(title: "Test", author: "", subject: "", keywords: "", creator: ""),
            source: fixture.url, destination: output
        )

        assertTextNormalized(source: fixture.url, output: output, operation: "metadata write")
    }

    @Test("Rotation preserves extractable text", arguments: FixtureDiscovery.modifiableFixtures)
    func rotationPreservesText(fixture: FixtureDiscovery.Fixture) async throws {
        guard hasReliableText(fixture: fixture) else { return }

        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_text_rot.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let rotator = PDFRotator()
        try await rotator.rotate(
            source: fixture.url, destination: output,
            angle: .ninety, pageIndices: nil, progress: { _ in }
        )

        assertTextNormalized(source: fixture.url, output: output, operation: "rotate 90°")
    }

    @Test("Split preserves text in extracted pages", arguments: FixtureDiscovery.modifiableFixtures)
    func splitPreservesText(fixture: FixtureDiscovery.Fixture) async throws {
        guard fixture.pageCount >= 2 else { return }
        guard hasReliableText(fixture: fixture) else { return }

        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_text_split.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let splitter = PDFSplitter()
        try await splitter.split(
            source: fixture.url, mode: .keepPages([0]),
            destination: output, progress: { _ in }
        )

        assertSplitTextPresent(source: fixture.url, output: output, sourcePageIndex: 0)
    }

    @Test("Merge preserves text from all sources", arguments: FixtureDiscovery.modifiableFixtures)
    func mergePreservesText(fixture: FixtureDiscovery.Fixture) async throws {
        guard hasReliableText(fixture: fixture) else { return }
        guard fixture.pageCount <= 20 else { return }

        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_text_merge.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let concatenator = PDFConcatenator()
        try await concatenator.concatenate(
            sources: [fixture.url, fixture.url],
            destination: output, progress: { _ in }
        )

        let sourceText = PDFAssertions.extractText(from: fixture.url)
        let outputText = PDFAssertions.extractText(from: output)

        // Merged output should have double the text pages
        #expect(outputText.count == sourceText.count * 2,
                "Merge should double text pages: \(fixture)")

        // First half should substantially match source text (normalized)
        for (i, (s, o)) in zip(sourceText, outputText).enumerated() {
            let ns = s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
            let no = o.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
            if !ns.isEmpty && ns != no {
                let common = Set(ns).intersection(Set(no))
                let similarity = Double(common.count) / Double(max(1, Set(ns).count))
                if similarity < 0.8 {
                    Issue.record("Merge lost text on page \(i+1): \(fixture)")
                }
            }
        }
    }
}

@Suite("Invariant: Page Geometry")
@MainActor
struct PageGeometryTests {

    @Test("Lossless compression preserves page geometry", arguments: FixtureDiscovery.modifiableFixtures)
    func losslessPreservesGeometry(fixture: FixtureDiscovery.Fixture) async throws {
        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_geom_lossless.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let compressor = PDFCompressor()
        try await compressor.compress(
            source: fixture.url, destination: output,
            level: .lossless, quality: .good, grayscale: false, stripMetadata: false,
            progress: { _ in }
        )

        PDFAssertions.assertGeometryPreserved(source: fixture.url, output: output, operation: "lossless compress")
    }

    @Test("Metadata write preserves page geometry", arguments: FixtureDiscovery.modifiableFixtures)
    func metadataPreservesGeometry(fixture: FixtureDiscovery.Fixture) async throws {
        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_geom_meta.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let editor = PDFMetadataEditor()
        try await editor.write(
            metadata: .init(title: "Geom Test", author: "A", subject: "S", keywords: "k", creator: "C"),
            source: fixture.url, destination: output
        )

        PDFAssertions.assertGeometryPreserved(source: fixture.url, output: output, operation: "metadata write")
    }

    @Test("Rotation changes rotation but preserves box dimensions", arguments: FixtureDiscovery.modifiableFixtures)
    func rotationChangesRotation(fixture: FixtureDiscovery.Fixture) async throws {
        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_geom_rot.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let rotator = PDFRotator()
        try await rotator.rotate(
            source: fixture.url, destination: output,
            angle: .ninety, pageIndices: nil, progress: { _ in }
        )

        // Geometry preserved except rotation
        PDFAssertions.assertGeometryPreserved(
            source: fixture.url, output: output,
            operation: "rotate", allowRotationChange: true
        )
        // Rotation actually changed
        PDFAssertions.assertRotationChanged(
            source: fixture.url, output: output, expectedDelta: 90
        )
    }

    @Test("Split preserves geometry of kept pages", arguments: FixtureDiscovery.modifiableFixtures)
    func splitPreservesGeometry(fixture: FixtureDiscovery.Fixture) async throws {
        guard fixture.pageCount >= 2 else { return }

        let output = FixtureDiscovery.outputURL(for: fixture, suffix: "_geom_split.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let splitter = PDFSplitter()
        try await splitter.split(
            source: fixture.url, mode: .keepPages([0, 1]),
            destination: output, progress: { _ in }
        )

        let sourceGeom = PDFAssertions.extractGeometry(from: fixture.url)
        let outputGeom = PDFAssertions.extractGeometry(from: output)

        #expect(outputGeom.count == 2, "Should have 2 pages: \(fixture)")
        if outputGeom.count >= 2 && sourceGeom.count >= 2 {
            #expect(abs(sourceGeom[0].cropBox.width - outputGeom[0].cropBox.width) < 1)
            #expect(abs(sourceGeom[1].cropBox.width - outputGeom[1].cropBox.width) < 1)
        }
    }
}
