import Testing
import PDFKit
import Foundation

@Suite("PDFMetadataEditor")
@MainActor
struct PDFMetadataEditorTests {

    private let editor = PDFMetadataEditor()

    @Test("Read metadata from PDF with attributes")
    func readMetadata() {
        let url = makePDFWithMetadata(title: "Test Title", author: "Author Name")
        defer { TestPDFGenerator.cleanup(url) }

        let meta = editor.read(from: url)
        #expect(meta.title == "Test Title")
        #expect(meta.author == "Author Name")
    }

    @Test("Read from PDF with no metadata returns empty fields")
    func readEmptyMetadata() {
        let url = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        defer { TestPDFGenerator.cleanup(url) }

        let meta = editor.read(from: url)
        #expect(meta.title == "")
        #expect(meta.author == "")
        #expect(meta.subject == "")
        #expect(meta.keywords == "")
        #expect(meta.creator == "")
    }

    @Test("Write and read back metadata round-trip")
    func writeReadRoundTrip() throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2)
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "meta.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        let newMeta = PDFMetadataEditor.Metadata(
            title: "My Doc",
            author: "Jane",
            subject: "Testing",
            keywords: "swift, pdf, test",
            creator: "PDFwringer"
        )

        try editor.write(metadata: newMeta, source: source, destination: output)

        let readBack = editor.read(from: output)
        #expect(readBack.title == "My Doc")
        #expect(readBack.author == "Jane")
        #expect(readBack.subject == "Testing")
        #expect(readBack.creator == "PDFwringer")
        #expect(readBack.keywords.contains("swift"))
        #expect(readBack.keywords.contains("pdf"))
        #expect(readBack.keywords.contains("test"))
    }

    @Test("Write empty fields clears existing metadata")
    func writeEmptyClears() throws {
        let source = makePDFWithMetadata(title: "Old Title", author: "Old Author")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "cleared.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        try editor.write(metadata: .empty, source: source, destination: output)

        let readBack = editor.read(from: output)
        #expect(readBack.title == "")
        #expect(readBack.author == "")
    }

    @Test("Write preserves page count")
    func writePreservesPages() throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 5)
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "pages.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        let meta = PDFMetadataEditor.Metadata(
            title: "Titled", author: "", subject: "", keywords: "", creator: ""
        )
        try editor.write(metadata: meta, source: source, destination: output)

        let doc = PDFDocument(url: output)
        #expect(doc?.pageCount == 5)
    }

    @Test("Write to unreadable source throws")
    func writeUnreadableThrows() {
        let bogus = URL.temporaryDirectory.appending(component: "nope.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "out.pdf")
        defer { TestPDFGenerator.cleanup(output) }

        do {
            try editor.write(metadata: .empty, source: bogus, destination: output)
            Issue.record("Expected error")
        } catch let error as PDFwringerError {
            if case .fileNotReadable = error { } else {
                Issue.record("Expected fileNotReadable, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Keywords are split by comma and trimmed")
    func keywordsParsing() throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "kw.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        let meta = PDFMetadataEditor.Metadata(
            title: "", author: "", subject: "",
            keywords: " alpha , beta,  gamma ",
            creator: ""
        )
        try editor.write(metadata: meta, source: source, destination: output)

        let readBack = editor.read(from: output)
        #expect(readBack.keywords.contains("alpha"))
        #expect(readBack.keywords.contains("beta"))
        #expect(readBack.keywords.contains("gamma"))
    }

    // MARK: - Encryption

    @Test("Write with password produces encrypted document")
    func writeWithPassword() throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "encrypted.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        let meta = PDFMetadataEditor.Metadata(
            title: "Secret", author: "", subject: "", keywords: "", creator: ""
        )
        try editor.write(metadata: meta, source: source, destination: output, password: "test123")

        let doc = PDFDocument(url: output)
        #expect(doc != nil)
        #expect(doc!.isEncrypted == true)
        #expect(doc!.isLocked == true)
    }

    @Test("Write without password from source produces unencrypted document")
    func writeWithoutPassword() throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "plain.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        try editor.write(metadata: .empty, source: source, destination: output, password: nil)

        let doc = PDFDocument(url: output)
        #expect(doc != nil)
        #expect(doc!.isEncrypted == false)
    }

    @Test("Encrypted document can be unlocked and read")
    func encryptedRoundTrip() throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2)
        let encrypted = TestPDFGenerator.makeTempDirectory().appending(component: "enc.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(encrypted)
        }

        let meta = PDFMetadataEditor.Metadata(
            title: "Locked Doc", author: "Author", subject: "", keywords: "", creator: ""
        )
        try editor.write(metadata: meta, source: source, destination: encrypted, password: "pw")

        let doc = PDFDocument(url: encrypted)!
        #expect(doc.isLocked == true)
        #expect(doc.unlock(withPassword: "pw") == true)
        #expect(doc.pageCount == 2)
    }

    // MARK: - Flatten annotations

    @Test("Flatten annotations produces valid output with same page count")
    func flattenAnnotations() throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 3)
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "flattened.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        let meta = PDFMetadataEditor.Metadata(
            title: "Flattened", author: "", subject: "", keywords: "", creator: ""
        )
        try editor.write(metadata: meta, source: source, destination: output, flattenAnnotations: true)

        let doc = PDFDocument(url: output)
        #expect(doc != nil)
        #expect(doc?.pageCount == 3)

        let readBack = editor.read(from: output)
        #expect(readBack.title == "Flattened")
    }

    // MARK: - Helpers

    private func makePDFWithMetadata(title: String, author: String) -> URL {
        let doc = PDFDocument()
        doc.insert(PDFPage(), at: 0)
        var attrs: [PDFDocumentAttribute: Any] = [:]
        attrs[.titleAttribute] = title
        attrs[.authorAttribute] = author
        doc.documentAttributes = attrs

        let url = URL.temporaryDirectory.appending(component: UUID().uuidString + "_meta.pdf")
        doc.write(to: url)
        return url
    }
}
