import Testing
import Foundation
import PDFKit

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

    // MARK: - DocumentSaver

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
}
