import Testing
import PDFKit

@Suite("SourceEqualsDestination")
@MainActor
struct SourceEqualsDestinationTests {

    @Test("PDFCompressor rejects source == destination")
    func compressorGuard() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2)
        defer { TestPDFGenerator.cleanup(source) }

        let compressor = PDFCompressor()
        await #expect(throws: PDFwringerError.self) {
            try await compressor.compress(
                source: source, destination: source,
                level: .lossless, quality: .good, grayscale: false, stripMetadata: false,
                progress: { _ in }
            )
        }
    }

    @Test("PDFConcatenator rejects destination in source list")
    func concatenatorGuard() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2)
        defer { TestPDFGenerator.cleanup(source) }

        let concatenator = PDFConcatenator()
        await #expect(throws: PDFwringerError.self) {
            try await concatenator.concatenate(
                sources: [source],
                destination: source,
                progress: { _ in }
            )
        }
    }

    @Test("PDFSplitter keepPages rejects source == destination")
    func splitterKeepGuard() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 3)
        defer { TestPDFGenerator.cleanup(source) }

        let splitter = PDFSplitter()
        await #expect(throws: PDFwringerError.self) {
            try await splitter.split(
                source: source, mode: .keepPages([0, 1]),
                destination: source, progress: { _ in }
            )
        }
    }

    @Test("PDFSplitter removePages rejects source == destination")
    func splitterRemoveGuard() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 3)
        defer { TestPDFGenerator.cleanup(source) }

        let splitter = PDFSplitter()
        await #expect(throws: PDFwringerError.self) {
            try await splitter.split(
                source: source, mode: .removePages([0]),
                destination: source, progress: { _ in }
            )
        }
    }

    @Test("PDFRotator rejects source == destination")
    func rotatorGuard() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2)
        defer { TestPDFGenerator.cleanup(source) }

        let rotator = PDFRotator()
        await #expect(throws: PDFwringerError.self) {
            try await rotator.rotate(
                source: source, destination: source,
                angle: .ninety, pageIndices: nil, progress: { _ in }
            )
        }
    }

    @Test("PDFMetadataEditor rejects source == destination")
    func metadataGuard() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        defer { TestPDFGenerator.cleanup(source) }

        let editor = PDFMetadataEditor()
        await #expect(throws: PDFwringerError.self) {
            try await editor.write(
                metadata: .empty, source: source, destination: source
            )
        }
    }

    @Test("PDFColorAdjuster rejects source == destination")
    func colorAdjusterGuard() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        defer { TestPDFGenerator.cleanup(source) }

        let adjuster = PDFColorAdjuster()
        await #expect(throws: PDFwringerError.self) {
            try await adjuster.adjust(
                source: source, destination: source,
                settings: .init(brightness: 0.5, contrast: 1, saturation: 1),
                pages: nil, progress: { _ in }
            )
        }
    }
}
