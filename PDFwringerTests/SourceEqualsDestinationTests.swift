import Testing
import PDFKit

@MainActor
private func expectSourceEqualsDestination(
    _ operation: () async throws -> Void
) async {
    do {
        try await operation()
        Issue.record("Expected sourceEqualsDestination")
    } catch PDFwringerError.sourceEqualsDestination {
        // Expected.
    } catch {
        Issue.record("Expected sourceEqualsDestination, got \(error)")
    }
}

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
                level: .lossless, quality: .good, grayscale: false,
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

    @Test("Filesystem identity recognizes links and case aliases")
    func filesystemIdentityAliases() throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "identity.pdf")
        let hardLink = source.deletingLastPathComponent()
            .appending(component: "\(UUID().uuidString)-hard-link.pdf")
        let symbolicLink = source.deletingLastPathComponent()
            .appending(component: "\(UUID().uuidString)-symbolic-link.pdf")
        let unrelated = source.deletingLastPathComponent()
            .appending(component: "\(UUID().uuidString)-missing.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(hardLink)
            TestPDFGenerator.cleanup(symbolicLink)
        }

        try FileManager.default.linkItem(at: source, to: hardLink)
        try FileManager.default.createSymbolicLink(at: symbolicLink, withDestinationURL: source)

        #expect(FileSystemIdentity.representsSameFile(source, hardLink))
        #expect(FileSystemIdentity.representsSameFile(source, symbolicLink))
        #expect(!FileSystemIdentity.representsSameFile(source, unrelated))

        let caseAlias = source.deletingLastPathComponent()
            .appending(component: source.lastPathComponent.swapCase())
        if FileManager.default.fileExists(atPath: caseAlias.path(percentEncoded: false)) {
            #expect(FileSystemIdentity.representsSameFile(source, caseAlias))
        }
    }

    @Test("All single-file writers reject a hard-link destination alias")
    func allWritersRejectHardLinkAlias() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2, filename: "source.pdf")
        let destination = source.deletingLastPathComponent()
            .appending(component: "\(UUID().uuidString)-alias.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(destination)
        }
        try FileManager.default.linkItem(at: source, to: destination)

        await expectSourceEqualsDestination {
            _ = try await PDFCompressor().compress(
                source: source,
                destination: destination,
                level: .lossless,
                quality: .good,
                grayscale: false,
                progress: { _ in }
            )
        }
        await expectSourceEqualsDestination {
            _ = try await PDFConcatenator().concatenate(
                sources: [source],
                destination: destination,
                progress: { _ in }
            )
        }
        await expectSourceEqualsDestination {
            _ = try await PDFSplitter().split(
                source: source,
                mode: .keepPages([0]),
                destination: destination,
                progress: { _ in }
            )
        }
        await expectSourceEqualsDestination {
            try await PDFRotator().rotate(
                source: source,
                destination: destination,
                angle: .ninety,
                pageIndices: nil,
                progress: { _ in }
            )
        }
        await expectSourceEqualsDestination {
            try await PDFMetadataEditor().write(
                metadata: .empty,
                source: source,
                destination: destination
            )
        }
        await expectSourceEqualsDestination {
            try await PDFColorAdjuster().adjust(
                source: source,
                destination: destination,
                settings: .init(brightness: 0.1, contrast: 1, saturation: 1),
                pages: nil,
                progress: { _ in }
            )
        }
        await expectSourceEqualsDestination {
            let document = try #require(PDFDocument(url: source))
            try await PDFPageReorderer().reorder(
                document: document,
                source: source,
                destination: destination,
                pageOrder: [1, 0],
                progress: { _ in }
            )
        }

        let document = try #require(PDFDocument(url: source))
        let saveResult = DocumentSaver.save(document: document, source: source, to: destination)
        #expect(saveResult.isError)
        #expect(saveResult.outputURL == nil)
        #expect(saveResult.message == PDFwringerError.sourceEqualsDestination.localizedDescription)
    }
}

private extension String {
    func swapCase() -> String {
        map { character in
            let value = String(character)
            return value == value.uppercased() ? value.lowercased() : value.uppercased()
        }.joined()
    }
}
