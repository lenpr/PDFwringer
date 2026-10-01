import Testing
import Foundation
import PDFKit
import CoreText

private final class InvalidRepresentationPDFDocument: PDFDocument {
    override func dataRepresentation() -> Data? {
        Data("not a PDF".utf8)
    }
}

private final class SnapshotHookPDFDocument: PDFDocument {
    let snapshot: Data
    let hook: @Sendable () -> Void
    init(snapshot: Data, hook: @escaping @Sendable () -> Void) {
        self.snapshot = snapshot
        self.hook = hook
        super.init()
    }
    override func dataRepresentation() -> Data? {
        hook()
        return snapshot
    }
}

@Suite("Utilities")
@MainActor
struct UtilityTests {

    @Test("Filesystem messages offer recovery while domain and unknown errors are preserved")
    func actionableErrorMessages() {
        let diskFull = CocoaError(.fileWriteOutOfSpace)
        #expect(PDFwringerError.userMessage(for: diskFull).contains("Free space"))
        #expect(PDFwringerError.userMessage(for: CocoaError(.fileWriteNoPermission)).contains("Choose a folder"))
        #expect(PDFwringerError.userMessage(for: CocoaError(.fileWriteVolumeReadOnly)).contains("read-only"))
        let protectionError = PDFwringerError.protectionPreservationFailed
        #expect(PDFwringerError.userMessage(for: protectionError) == protectionError.localizedDescription)
        let unknown = NSError(domain: "TestDomain", code: 1, userInfo: [NSLocalizedDescriptionKey: "Specific failure"])
        #expect(PDFwringerError.userMessage(for: unknown) == "Specific failure")
        // NSError values thrown by Foundation bridge to the same recovery path.
        let bridged = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteFileExists.rawValue)
        #expect(PDFwringerError.userMessage(for: bridged).contains("another name"))
    }

    // MARK: - Formatting

    @Test("Page tooltips reject dimensions outside integer range")
    func pageTooltipRejectsExtremeDimensions() {
        #expect(Formatting.pageTooltip(
            pageNumber: 1,
            cropBox: CGRect(x: 0, y: 0, width: 1e20, height: 1e20)
        ) == "Page 1")
        #expect(Formatting.pageTooltip(
            pageNumber: 2,
            cropBox: CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 792)
        ) == "Page 2")
    }

    @Test("Page tooltips include ordinary dimensions")
    func pageTooltipIncludesOrdinaryDimensions() {
        #expect(Formatting.pageTooltip(
            pageNumber: 3,
            cropBox: CGRect(x: 0, y: 0, width: 612.9, height: 792.1)
        ) == "Page 3 — 612 × 792 pt")
    }

    // MARK: - AtomicFileWriter

    @Test("AtomicFileWriter writes content to destination")
    func atomicWriteSuccess() throws {
        let dest = URL.temporaryDirectory.appending(component: UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: dest) }
        var replacementDirectory: URL?

        try AtomicFileWriter.write(to: dest) { tempURL in
            replacementDirectory = tempURL.deletingLastPathComponent()
            let destinationFileSystem = try FileManager.default.attributesOfFileSystem(
                forPath: dest.deletingLastPathComponent().path(percentEncoded: false)
            )[.systemNumber] as? NSNumber
            let stagingFileSystem = try FileManager.default.attributesOfFileSystem(
                forPath: tempURL.deletingLastPathComponent().path(percentEncoded: false)
            )[.systemNumber] as? NSNumber
            #expect(destinationFileSystem == stagingFileSystem)
            #expect(tempURL.pathExtension == dest.pathExtension)
            try Data("hello".utf8).write(to: tempURL)
            return true
        }

        let data = try Data(contentsOf: dest)
        #expect(String(data: data, encoding: .utf8) == "hello")
        if let replacementDirectory {
            #expect(!FileManager.default.fileExists(
                atPath: replacementDirectory.path(percentEncoded: false)
            ))
        }
    }

    @Test("AtomicFileWriter supports yielding producers")
    func atomicWriteAsyncSuccess() async throws {
        let dest = URL.temporaryDirectory.appending(component: UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: dest) }
        var replacementDirectory: URL?

        try await AtomicFileWriter.write(to: dest) { tempURL in
            replacementDirectory = tempURL.deletingLastPathComponent()
            try Data("before yield".utf8).write(to: tempURL)
            await Task.yield()
            try Data("after yield".utf8).write(to: tempURL)
            return true
        }

        #expect(try Data(contentsOf: dest) == Data("after yield".utf8))
        if let replacementDirectory {
            #expect(!FileManager.default.fileExists(
                atPath: replacementDirectory.path(percentEncoded: false)
            ))
        }
    }

    @Test("AtomicFileWriter cleans up on block returning false")
    func atomicWriteBlockFalse() {
        let dest = URL.temporaryDirectory.appending(component: UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: dest) }
        try? Data("original".utf8).write(to: dest)
        var stagedURL: URL?

        do {
            try AtomicFileWriter.write(to: dest) { tempURL in
                stagedURL = tempURL
                try Data("partial".utf8).write(to: tempURL)
                return false
            }
            Issue.record("Expected error")
        } catch let error as PDFwringerError {
            if case .cannotWriteOutput = error { } else {
                Issue.record("Expected cannotWriteOutput, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect((try? Data(contentsOf: dest)) == Data("original".utf8))
        if let stagedURL {
            #expect(!FileManager.default.fileExists(atPath: stagedURL.path(percentEncoded: false)))
            #expect(!FileManager.default.fileExists(atPath: stagedURL.deletingLastPathComponent().path(percentEncoded: false)))
        }
    }

    @Test("AtomicFileWriter cleans up on block throwing")
    func atomicWriteBlockThrows() {
        let dest = URL.temporaryDirectory.appending(component: UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: dest) }
        try? Data("original".utf8).write(to: dest)

        struct TestError: Error {}
        var stagedURL: URL?

        do {
            try AtomicFileWriter.write(to: dest) { tempURL in
                stagedURL = tempURL
                try Data("partial".utf8).write(to: tempURL)
                throw TestError()
            }
            Issue.record("Expected error")
        } catch is TestError {
            // expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect((try? Data(contentsOf: dest)) == Data("original".utf8))
        #expect(stagedURL != nil)
        if let stagedURL {
            #expect(!FileManager.default.fileExists(atPath: stagedURL.path(percentEncoded: false)))
            #expect(!FileManager.default.fileExists(atPath: stagedURL.deletingLastPathComponent().path(percentEncoded: false)))
        }
    }

    @Test("Cancelled synchronous writes preserve destinations and clean staging", arguments: [false, true])
    func synchronousWriteCancellation(existing: Bool) async throws {
        let directory = TestPDFGenerator.makeTempDirectory()
        defer { TestPDFGenerator.cleanup(directory) }
        let destination = directory.appending(component: "output.pdf")
        let original = Data("original".utf8)
        if existing { try original.write(to: destination) }
        var stagingDirectory: URL?
        let task = Task { @MainActor in
            let producer: (URL) throws -> Bool = { temporary in
                stagingDirectory = temporary.deletingLastPathComponent()
                try Data("new content".utf8).write(to: temporary)
                withUnsafeCurrentTask { $0?.cancel() }
                return true
            }
            try AtomicFileWriter.write(to: destination, using: producer)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect((try? Data(contentsOf: destination)) == (existing ? original : nil))
        let staging = try #require(stagingDirectory)
        #expect(!FileManager.default.fileExists(atPath: staging.path))
        // A cancelled attempt must not poison a subsequent save.
        try AtomicFileWriter.write(to: destination) { temporary in
            try Data("retry".utf8).write(to: temporary)
            return true
        }
        #expect(try Data(contentsOf: destination) == Data("retry".utf8))
    }

    @Test("A save rejects a destination installed during preparation", arguments: [false, true])
    func changedDestinationDuringWrite(existing: Bool) throws {
        let directory = TestPDFGenerator.makeTempDirectory()
        defer { TestPDFGenerator.cleanup(directory) }
        let destination = directory.appending(component: "output.pdf")
        if existing { try Data("original".utf8).write(to: destination) }
        var stagingDirectory: URL?
        do {
            try AtomicFileWriter.write(to: destination) { temporary in
                stagingDirectory = temporary.deletingLastPathComponent()
                try Data("our output".utf8).write(to: temporary)
                // Atomic write installs a new inode, as another saving app would.
                try Data("other app's output".utf8).write(to: destination, options: .atomic)
                return true
            }
            Issue.record("Expected the changed destination to be preserved")
        } catch let error as PDFwringerError {
            guard case .destinationChanged = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
        #expect(try Data(contentsOf: destination) == Data("other app's output".utf8))
        let staging = try #require(stagingDirectory)
        #expect(!FileManager.default.fileExists(atPath: staging.path))
    }

    @Test("AtomicFileWriter replaces an existing regular file")
    func atomicWriteReplacesExistingFile() throws {
        let dest = URL.temporaryDirectory.appending(component: UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: dest) }
        try Data("old".utf8).write(to: dest)

        try AtomicFileWriter.write(to: dest) { tempURL in
            try Data("new".utf8).write(to: tempURL)
            return true
        }

        #expect(try Data(contentsOf: dest) == Data("new".utf8))
    }

    @Test("AtomicFileWriter rejects a directory destination")
    func atomicWriteRejectsDirectory() throws {
        let destination = URL.temporaryDirectory.appending(component: UUID().uuidString)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: destination) }

        do {
            try AtomicFileWriter.write(to: destination) { tempURL in
                try Data("data".utf8).write(to: tempURL)
                return true
            }
            Issue.record("Expected cannotWriteOutput")
        } catch let error as PDFwringerError {
            guard case .cannotWriteOutput = error else {
                Issue.record("Expected cannotWriteOutput, got \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(
            atPath: destination.path(percentEncoded: false),
            isDirectory: &isDirectory
        ))
        #expect(isDirectory.boolValue)
    }

    @Test(
        "AtomicFileWriter preserves destination extension",
        arguments: ["pdf", "PDF", "png", ""]
    )
    func atomicWritePreservesExtension(fileExtension: String) throws {
        var destination = URL.temporaryDirectory.appending(component: UUID().uuidString)
        if !fileExtension.isEmpty {
            destination.appendPathExtension(fileExtension)
        }
        defer { try? FileManager.default.removeItem(at: destination) }

        try AtomicFileWriter.write(to: destination) { tempURL in
            #expect(tempURL.pathExtension == fileExtension)
            try Data("data".utf8).write(to: tempURL)
            return true
        }
        #expect(FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)))
    }

    @Test("Legacy temp cleanup removes only stale UUID-named legacy files")
    func legacyTempCleanupIsNarrowlyScoped() throws {
        let directory = TestPDFGenerator.makeTempDirectory()
        defer { TestPDFGenerator.cleanup(directory) }

        let staleFiles = ["pdf", "jpg", "jpeg", "png"].map {
            directory.appending(component: "\(UUID().uuidString).\($0)")
        }
        let recentPDF = directory.appending(component: "\(UUID().uuidString).PDF")
        let unrelatedPDF = directory.appending(component: "unrelated.pdf")
        let staleText = directory.appending(component: "\(UUID().uuidString).txt")
        let nestedPDF = directory.appending(component: "\(UUID().uuidString).pdf")
        for file in staleFiles + [recentPDF, unrelatedPDF, staleText] {
            try Data("temporary".utf8).write(to: file)
        }
        try FileManager.default.createDirectory(at: nestedPDF, withIntermediateDirectories: false)

        let staleDate = Date(timeIntervalSince1970: 1)
        for file in staleFiles + [unrelatedPDF, staleText] {
            try FileManager.default.setAttributes(
                [.modificationDate: staleDate],
                ofItemAtPath: file.path(percentEncoded: false)
            )
        }

        let removed = AtomicFileWriter.cleanupLegacyTempFiles(
            in: directory,
            olderThan: Date().addingTimeInterval(-3600)
        )

        #expect(removed == staleFiles.count)
        for file in staleFiles {
            #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        }
        #expect(FileManager.default.fileExists(atPath: recentPDF.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: unrelatedPDF.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: staleText.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: nestedPDF.path(percentEncoded: false)))
    }

    @Test("Legacy temp cleanup does not create a missing directory")
    func legacyTempCleanupDoesNotCreateDirectory() {
        let directory = URL.temporaryDirectory
            .appending(component: "missing-legacy-temp-\(UUID())")
        defer { TestPDFGenerator.cleanup(directory) }

        #expect(AtomicFileWriter.cleanupLegacyTempFiles(
            in: directory,
            olderThan: Date()
        ) == 0)
        #expect(!FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)))
    }

    @Test("Exclusive publisher truncates Unicode without splitting characters")
    func exclusivePublisherTruncatesUnicodeSafely() throws {
        let stagingDirectory = TestPDFGenerator.makeTempDirectory()
        let outputDirectory = TestPDFGenerator.makeTempDirectory()
        let staged = stagingDirectory.appending(component: "staged.jpg")
        let payload = Data("image".utf8)
        try payload.write(to: staged)
        defer {
            TestPDFGenerator.cleanup(stagingDirectory)
            TestPDFGenerator.cleanup(outputDirectory)
        }

        let generatedSuffix = "_page_001"
        let output = try #require(ExclusiveFilePublisher.publish([
            .init(
                url: staged,
                baseStem: String(repeating: "é", count: 300),
                generatedSuffix: generatedSuffix,
                pathExtension: "jpg"
            )
        ], to: outputDirectory).first)

        let protectedSuffix = generatedSuffix + ".jpg"
        #expect(output.lastPathComponent.hasSuffix(protectedSuffix))
        let prefix = output.lastPathComponent.dropLast(protectedSuffix.count)
        #expect(!prefix.isEmpty)
        #expect(prefix.allSatisfy { String($0) == "é" })
        #expect(TestPDFGenerator.fileSystemComponentLength(of: output)
            <= TestPDFGenerator.fileSystemNameLimit(in: outputDirectory))
        #expect(try Data(contentsOf: output) == payload)
    }

    @Test("Exclusive publisher rolls back earlier outputs when a later staged file is missing")
    func exclusivePublisherRollsBackPartialBatch() throws {
        let stagingDirectory = TestPDFGenerator.makeTempDirectory()
        let outputDirectory = TestPDFGenerator.makeTempDirectory()
        let firstStaged = stagingDirectory.appending(component: "first.jpg")
        let missingStaged = stagingDirectory.appending(component: "missing.jpg")
        try Data("first image".utf8).write(to: firstStaged)
        defer {
            TestPDFGenerator.cleanup(stagingDirectory)
            TestPDFGenerator.cleanup(outputDirectory)
        }

        do {
            _ = try ExclusiveFilePublisher.publish([
                .init(
                    url: firstStaged,
                    baseStem: "batch",
                    generatedSuffix: "_page_001",
                    pathExtension: "jpg"
                ),
                .init(
                    url: missingStaged,
                    baseStem: "batch",
                    generatedSuffix: "_page_002",
                    pathExtension: "jpg"
                ),
            ], to: outputDirectory)
            Issue.record("Expected the missing staged file to fail publication")
        } catch let error as PDFwringerError {
            guard case .cannotWriteOutput = error else {
                Issue.record("Expected cannotWriteOutput, got \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(!FileManager.default.fileExists(
            atPath: firstStaged.path(percentEncoded: false)
        ))
        #expect(!FileManager.default.fileExists(
            atPath: outputDirectory
                .appending(component: "batch_page_001.jpg")
                .path(percentEncoded: false)
        ))
        #expect(try FileManager.default.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: nil
        ).isEmpty)
    }

    // MARK: - DocumentSaver

    @Test("Text extraction preserves blank-page positions")
    func textExtractionPreservesPageAlignment() throws {
        let combinedURL = URL.temporaryDirectory.appending(component: UUID().uuidString + "_aligned.pdf")
        defer { TestPDFGenerator.cleanup(combinedURL) }

        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try #require(CGContext(combinedURL as CFURL, mediaBox: &mediaBox, nil))
        context.beginPage(mediaBox: &mediaBox)
        context.endPage()
        context.beginPage(mediaBox: &mediaBox)
        let text = NSAttributedString(
            string: "Page 1",
            attributes: [
                .font: NSFont.systemFont(ofSize: 48),
                .foregroundColor: NSColor.black,
            ]
        )
        context.textPosition = CGPoint(x: 100, y: 400)
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
        context.endPage()
        context.closePDF()

        let extracted = PDFAssertions.extractText(from: combinedURL)
        #expect(extracted.count == 2)
        #expect(extracted[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(extracted[1].contains("Page 1"))
    }

    @Test("DocumentSaver preserves cancellation and destination approval across the snapshot",
          arguments: [false, true])
    func documentSaverSnapshotBoundary(cancel: Bool) async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        let snapshot = try Data(contentsOf: source)
        let directory = TestPDFGenerator.makeTempDirectory()
        let output = directory.appending(component: "saved.pdf")
        let original = Data("Approved original".utf8)
        let replacement = Data("Concurrent replacement".utf8)
        try original.write(to: output)
        defer { TestPDFGenerator.cleanup(source); TestPDFGenerator.cleanup(directory) }
        let document = SnapshotHookPDFDocument(snapshot: snapshot) {
            if cancel { withUnsafeCurrentTask { $0?.cancel() } }
            else { try? replacement.write(to: output, options: .atomic) }
        }
        document.insert(PDFPage(), at: 0)
        let operation = Task { @MainActor in
            await DocumentSaver.save(document: document, source: source, to: output)
        }
        let result = await operation.value
        #expect(result.outputURL == nil)
        #expect(result.isError == !cancel)
        #expect(try Data(contentsOf: output) == (cancel ? original : replacement))
        #expect(try Data(contentsOf: source) == snapshot)
    }

    @Test("DocumentSaver publishes unsaved geometry and leaves its source intact")
    func documentSaverWorkingContent() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2)
        let bytes = try Data(contentsOf: source)
        let directory = TestPDFGenerator.makeTempDirectory()
        let output = directory.appending(component: "saved.pdf")
        defer { TestPDFGenerator.cleanup(source); TestPDFGenerator.cleanup(directory) }
        let document = try #require(PDFDocument(url: source))
        let page = try #require(document.page(at: 0))
        page.rotation = 90
        let crop = CGRect(x: 10, y: 20, width: 400, height: 500)
        page.setBounds(crop, for: .cropBox)
        let result = await DocumentSaver.save(document: document, source: source, to: output)
        #expect(!result.isError && result.outputURL == output)
        let saved = try #require(PDFDocument(url: output)?.page(at: 0))
        #expect(saved.rotation == 90 && saved.bounds(for: .cropBox) == crop)
        #expect(try Data(contentsOf: source) == bytes)
    }

    @Test("DocumentSaver refuses to replace its source document")
    func documentSaverRejectsSourceDestination() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "save-source.pdf")
        defer { TestPDFGenerator.cleanup(source) }
        let originalData = try Data(contentsOf: source)
        let workingDocument = try #require(PDFDocument(url: source)?.copy() as? PDFDocument)
        try PDFRotator().rotate(
            document: workingDocument,
            angle: .ninety,
            pageIndices: nil,
            progress: { _ in }
        )

        let result = await DocumentSaver.save(
            document: workingDocument,
            source: source,
            to: source
        )

        #expect(result.isError)
        #expect(result.outputURL == nil)
        #expect(result.message == PDFwringerError.sourceEqualsDestination.localizedDescription)
        #expect(try Data(contentsOf: source) == originalData)
    }

    @Test("DocumentSaver rejects invalid serialization without replacing destination")
    func documentSaverValidatesStagedOutput() async throws {
        let directory = TestPDFGenerator.makeTempDirectory()
        let source = directory.appending(component: "source.pdf")
        let destination = directory.appending(component: "destination.pdf")
        let originalDestination = Data("existing destination".utf8)
        try originalDestination.write(to: destination)
        defer { TestPDFGenerator.cleanup(directory) }

        let document = InvalidRepresentationPDFDocument()
        document.insert(PDFPage(), at: 0)

        let result = await DocumentSaver.save(
            document: document,
            source: source,
            to: destination
        )

        #expect(result.isError)
        #expect(result.outputURL == nil)
        #expect(try Data(contentsOf: destination) == originalDestination)
    }

    // MARK: - Formatting

    @Test("Formatting.fileSize formats bytes correctly")
    func fileSizeFormatting() {
        #expect(Formatting.fileSize(0) == "Zero KB")
        #expect(Formatting.fileSize(1024).contains("1"))
        #expect(Formatting.fileSize(1_048_576).contains("1"))
        #expect(Formatting.fileSize(1_048_576).contains("MB"))
    }

    @Test("Formatting finds disk capacity for a new destination")
    func diskCapacityForNewDestination() throws {
        let directory = TestPDFGenerator.makeTempDirectory()
        defer { TestPDFGenerator.cleanup(directory) }
        let destination = directory.appending(component: "new-output.pdf")

        #expect(!FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)))
        _ = try #require(Formatting.availableDiskSpace(at: directory))
        let destinationCapacity = try #require(Formatting.availableDiskSpace(at: destination))

        #expect(destinationCapacity > 0)
    }

    @Test("Formatting rejects non-file URLs for disk capacity")
    func diskCapacityRejectsNonFileURL() {
        #expect(Formatting.availableDiskSpace(at: URL(string: "https://example.com/out.pdf")!) == nil)
    }
}
