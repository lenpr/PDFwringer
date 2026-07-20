import Testing
import Foundation
import PDFKit
import CoreText

@Suite("Utilities")
@MainActor
struct UtilityTests {

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

    @Test("DocumentSaver refuses to replace its source document")
    func documentSaverRejectsSourceDestination() throws {
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

        let result = DocumentSaver.save(
            document: workingDocument,
            source: source,
            to: source
        )

        #expect(result.isError)
        #expect(result.outputURL == nil)
        #expect(result.message == PDFwringerError.sourceEqualsDestination.localizedDescription)
        #expect(try Data(contentsOf: source) == originalData)
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
