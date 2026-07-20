import AppKit
import Foundation
import PDFKit
import Testing

@Suite("Encrypted document workflows")
@MainActor
struct EncryptedWorkflowTests {
    private static let password = "correct horse battery staple"
    private static let bookmarkDefaultsKey = "com.pdfwringer.recentBookmarks"

    @Test("Successful unlock enters the document and records it as recent")
    func appViewModelUnlocksAndRecordsRecentDocument() throws {
        let source = try makeEncryptedPDF(pageCount: 2, filename: "unlock.pdf")
        let previousBookmarks = UserDefaults.standard.object(forKey: Self.bookmarkDefaultsKey)
        defer {
            restoreBookmarks(previousBookmarks)
            TestPDFGenerator.cleanup(source)
        }

        let viewModel = AppViewModel()
        viewModel.loadSingleFile(source)

        #expect(viewModel.isLanding)
        #expect(viewModel.showPasswordPrompt)

        viewModel.passwordText = Self.password
        viewModel.unlockDocument()

        guard case .singleFile(let loadedURL, let document) = viewModel.state else {
            Issue.record("Expected successful unlock to enter the single-file state")
            return
        }

        #expect(loadedURL == source)
        #expect(!document.isLocked)
        #expect(document.pageCount == 2)
        #expect(viewModel.currentFileSize > 0)
        #expect(viewModel.passwordText.isEmpty)
        #expect(!viewModel.wrongPasswordAttempt)
        #expect(!viewModel.showPasswordPrompt)
        #expect(viewModel.recentDocuments.contains {
            $0.standardizedFileURL == source.standardizedFileURL
        })
        #expect(NSDocumentController.shared.recentDocumentURLs.contains {
            $0.standardizedFileURL == source.standardizedFileURL
        })

        viewModel.selectCompress()
        guard case .compressing(_, let actionDocument) = viewModel.state else {
            Issue.record("Expected compression state")
            return
        }
        #expect(actionDocument === document)
    }

    @Test("Metadata can replace encryption with a new password")
    func metadataReencryptsUnlockedDocument() async throws {
        let source = try makeEncryptedPDF(pageCount: 2, filename: "metadata-reencrypt.pdf")
        let outputDirectory = TestPDFGenerator.makeTempDirectory()
        let output = outputDirectory.appending(component: "metadata-reencrypted.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDirectory)
        }

        let document = try unlockedDocument(at: source)
        try await PDFMetadataEditor().write(
            metadata: .empty,
            document: document,
            source: source,
            destination: output,
            password: "replacement-password"
        )

        let lockedOutput = try #require(PDFDocument(url: output))
        #expect(lockedOutput.isEncrypted)
        #expect(lockedOutput.isLocked)
        #expect(!lockedOutput.unlock(withPassword: Self.password))

        let reopenedOutput = try #require(PDFDocument(url: output))
        #expect(reopenedOutput.unlock(withPassword: "replacement-password"))
        #expect(reopenedOutput.pageCount == 2)
        assertSourceIsStillLocked(source)
    }

    @Test("Mutable editors isolate unlocked encrypted documents")
    func mutableEditorsUseEncryptedWorkingCopies() throws {
        let source = try makeEncryptedPDF(pageCount: 2, filename: "working-copy.pdf")
        defer { TestPDFGenerator.cleanup(source) }

        let viewModel = AppViewModel()
        viewModel.loadSingleFile(source)
        viewModel.passwordText = Self.password
        viewModel.unlockDocument()
        guard case .singleFile(_, let sourceDocument) = viewModel.state else {
            Issue.record("Expected unlocked single-file state")
            return
        }
        let originalBounds = try #require(sourceDocument.page(at: 0)).bounds(for: .cropBox)

        viewModel.selectRotate()
        guard case .rotating(_, let retainedSource, let rotationCopy) = viewModel.state else {
            Issue.record("Expected rotating state")
            return
        }
        #expect(retainedSource === sourceDocument)
        #expect(rotationCopy !== sourceDocument)
        #expect(rotationCopy.isEncrypted)
        #expect(!rotationCopy.isLocked)
        #expect(rotationCopy.accessPermissions == sourceDocument.accessPermissions)
        #expect(rotationCopy.page(at: 0) !== sourceDocument.page(at: 0))
        try PDFRotator().rotate(
            document: rotationCopy,
            angle: .ninety,
            pageIndices: [0],
            progress: { _ in }
        )
        #expect(rotationCopy.page(at: 0)?.rotation == 90)
        #expect(sourceDocument.page(at: 0)?.rotation == 0)
        viewModel.goBack()

        viewModel.selectCrop()
        guard case .cropping(_, let cropSource, let cropCopy) = viewModel.state else {
            Issue.record("Expected cropping state")
            return
        }
        #expect(cropSource === sourceDocument)
        #expect(cropCopy !== sourceDocument)
        #expect(cropCopy.isEncrypted)
        #expect(!cropCopy.isLocked)
        #expect(cropCopy.accessPermissions == sourceDocument.accessPermissions)
        _ = PDFCropper().crop(
            document: cropCopy,
            indices: [0],
            top: 10,
            bottom: 10,
            left: 10,
            right: 10
        )
        #expect(cropCopy.page(at: 0)?.bounds(for: .cropBox) != originalBounds)
        #expect(sourceDocument.page(at: 0)?.bounds(for: .cropBox) == originalBounds)
        viewModel.goBack()

        guard case .singleFile(_, let restoredDocument) = viewModel.state else {
            Issue.record("Expected single-file state after discard")
            return
        }
        #expect(restoredDocument === sourceDocument)
        #expect(!viewModel.hasUnsavedChanges)
        assertSourceIsStillLocked(source)
    }

    @Test("Lossless compression preserves source encryption")
    func losslessCompressionPreservesEncryption() async throws {
        let source = try makeEncryptedPDF(pageCount: 2, filename: "lossless.pdf")
        let outputDirectory = TestPDFGenerator.makeTempDirectory()
        let output = outputDirectory.appending(component: "lossless-output.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDirectory)
        }

        let document = try unlockedDocument(at: source)
        _ = try await PDFCompressor().compress(
            document: document,
            source: source,
            destination: output,
            level: .lossless,
            quality: .good,
            grayscale: false,
            stripMetadata: false,
            progress: { _ in }
        )

        let outputDocument = try #require(PDFDocument(url: output))
        #expect(outputDocument.isEncrypted)
        #expect(outputDocument.isLocked)
        #expect(outputDocument.unlock(withPassword: Self.password))
        #expect(outputDocument.pageCount == 2)
        assertSourceIsStillLocked(source)
    }

    @Test("Metadata reads and writes from the unlocked document")
    func metadataUsesUnlockedDocument() async throws {
        let source = try makeEncryptedPDF(pageCount: 2, filename: "metadata.pdf")
        let outputDirectory = TestPDFGenerator.makeTempDirectory()
        let output = outputDirectory.appending(component: "metadata-output.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDirectory)
        }

        let document = try unlockedDocument(at: source)
        let editor = PDFMetadataEditor()

        let originalMetadata = editor.read(from: document)
        #expect(originalMetadata.title == "Encrypted fixture")
        #expect(originalMetadata.author == "PDFwringer Tests")

        let updatedMetadata = PDFMetadataEditor.Metadata(
            title: "Updated while unlocked",
            author: "Integration Test",
            subject: "Encrypted workflow",
            keywords: "locked, unlocked",
            creator: "PDFwringer"
        )
        try await editor.write(
            metadata: updatedMetadata,
            document: document,
            source: source,
            destination: output,
            removeProtection: true
        )

        let writtenDocument = try #require(PDFDocument(url: output))
        #expect(!writtenDocument.isLocked)
        #expect(writtenDocument.pageCount == 2)
        #expect(editor.read(from: writtenDocument) == updatedMetadata)
        assertSourceIsStillLocked(source)
    }

    @Test("Raster compression uses the unlocked document")
    func compressionUsesUnlockedDocument() async throws {
        let source = try makeEncryptedPDF(pageCount: 2, filename: "compress.pdf")
        let outputDirectory = TestPDFGenerator.makeTempDirectory()
        let output = outputDirectory.appending(component: "compressed.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDirectory)
        }

        let document = try unlockedDocument(at: source)
        let result = try await PDFCompressor().compress(
            document: document,
            source: source,
            destination: output,
            level: .low,
            quality: .moderate,
            grayscale: false,
            stripMetadata: false,
            progress: { _ in }
        )

        #expect(result.outputSize > 0)
        let outputDocument = try #require(PDFDocument(url: output))
        #expect(outputDocument.pageCount == 2)
        #expect(!outputDocument.isEncrypted)
        assertSourceIsStillLocked(source)
    }

    @Test("Page extraction uses the unlocked document")
    func splittingUsesUnlockedDocument() async throws {
        let source = try makeEncryptedPDF(pageCount: 3, filename: "split.pdf")
        let outputDirectory = TestPDFGenerator.makeTempDirectory()
        let output = outputDirectory.appending(component: "extracted.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDirectory)
        }

        let document = try unlockedDocument(at: source)
        let outputs = try await PDFSplitter().split(
            document: document,
            source: source,
            mode: .keepPages([1]),
            destination: output,
            progress: { _ in }
        )

        #expect(outputs == [output])
        let outputDocument = try #require(PDFDocument(url: output))
        #expect(outputDocument.pageCount == 1)
        #expect(!outputDocument.isEncrypted)
        assertSourceIsStillLocked(source)
    }

    @Test("Color adjustment uses the unlocked document")
    func colorAdjustmentUsesUnlockedDocument() async throws {
        let source = try makeEncryptedPDF(pageCount: 1, filename: "color.pdf")
        let outputDirectory = TestPDFGenerator.makeTempDirectory()
        let output = outputDirectory.appending(component: "adjusted.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDirectory)
        }

        let document = try unlockedDocument(at: source)
        try await PDFColorAdjuster().adjust(
            document: document,
            source: source,
            destination: output,
            settings: .init(brightness: 0.1, contrast: 1.1, saturation: 0.9),
            pages: nil,
            dpi: 72,
            quality: 0.8,
            progress: { _ in }
        )

        let outputDocument = try #require(PDFDocument(url: output))
        #expect(outputDocument.pageCount == 1)
        #expect(!outputDocument.isEncrypted)
        assertSourceIsStillLocked(source)
    }

    @Test("Image export uses the unlocked document")
    func imageExportUsesUnlockedDocument() async throws {
        let source = try makeEncryptedPDF(pageCount: 2, filename: "export.pdf")
        let outputDirectory = TestPDFGenerator.makeTempDirectory()
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDirectory)
        }

        let document = try unlockedDocument(at: source)
        let outputs = try await PDFImageExporter().exportPages(
            document: document,
            source: source,
            outputDirectory: outputDirectory,
            options: .init(format: .jpeg, dpi: 72, quality: 0.8),
            pageIndices: [1],
            progress: { _ in }
        )

        #expect(outputs.count == 1)
        let output = try #require(outputs.first)
        let image = try Data(contentsOf: output)
        #expect(!image.isEmpty)
        assertSourceIsStillLocked(source)
    }

    @Test("Rotation preserves encryption for an unlocked document")
    func rotationUsesUnlockedDocument() throws {
        let source = try makeEncryptedPDF(pageCount: 2, filename: "rotate.pdf")
        let outputDirectory = TestPDFGenerator.makeTempDirectory()
        let output = outputDirectory.appending(component: "rotated.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDirectory)
        }

        let document = try unlockedDocument(at: source)
        #expect(document.allowsDocumentAssembly)
        try PDFRotator().rotate(
            document: document,
            angle: .ninety,
            pageIndices: [0],
            progress: { _ in }
        )

        let saveResult = DocumentSaver.save(document: document, source: source, to: output)
        #expect(!saveResult.isError)

        let lockedOutput = try #require(PDFDocument(url: output))
        #expect(lockedOutput.isEncrypted)
        #expect(lockedOutput.isLocked)
        #expect(lockedOutput.unlock(withPassword: Self.password))
        #expect(lockedOutput.page(at: 0)?.rotation == 90)
        #expect(lockedOutput.page(at: 1)?.rotation == 0)
        assertSourceIsStillLocked(source)
    }

    private func makeEncryptedPDF(pageCount: Int, filename: String) throws -> URL {
        let plain = TestPDFGenerator.makeRenderedPDF(pageCount: pageCount, filename: "plain-\(filename)")
        defer { TestPDFGenerator.cleanup(plain) }

        guard let document = PDFDocument(url: plain) else {
            throw FixtureError.cannotOpenPlainDocument
        }
        let attributes: [PDFDocumentAttribute: Any] = [
            .titleAttribute: "Encrypted fixture",
            .authorAttribute: "PDFwringer Tests"
        ]
        document.documentAttributes = attributes

        let encrypted = URL.temporaryDirectory.appending(component: UUID().uuidString + "_" + filename)
        let options: [PDFDocumentWriteOption: Any] = [
            .ownerPasswordOption: Self.password,
            .userPasswordOption: Self.password
        ]
        guard document.write(to: encrypted, withOptions: options) else {
            throw FixtureError.cannotEncryptDocument
        }
        return encrypted
    }

    private func unlockedDocument(at url: URL) throws -> PDFDocument {
        let document = try #require(PDFDocument(url: url))
        #expect(document.isLocked)
        try #require(document.unlock(withPassword: Self.password))
        #expect(!document.isLocked)
        return document
    }

    private func assertSourceIsStillLocked(_ url: URL) {
        let sourceOnDisk = PDFDocument(url: url)
        #expect(sourceOnDisk?.isEncrypted == true)
        #expect(sourceOnDisk?.isLocked == true)
    }

    private func restoreBookmarks(_ previousValue: Any?) {
        if let previousValue {
            UserDefaults.standard.set(previousValue, forKey: Self.bookmarkDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.bookmarkDefaultsKey)
        }
    }

    private enum FixtureError: Error {
        case cannotOpenPlainDocument
        case cannotEncryptDocument
    }
}
