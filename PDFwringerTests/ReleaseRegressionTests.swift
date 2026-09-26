import Foundation
import PDFKit
import Testing

@Suite("Release regressions")
@MainActor
struct ReleaseRegressionTests {
    @Test("New passwords require explicit flattening and leave existing files intact")
    func passwordRequiresConsent() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        let directory = TestPDFGenerator.makeTempDirectory()
        defer { TestPDFGenerator.cleanup(source); TestPDFGenerator.cleanup(directory) }
        let output = directory.appending(component: "existing.pdf")
        let sentinel = Data("Existing destination".utf8)
        try sentinel.write(to: output)
        do {
            try await PDFMetadataEditor().write(metadata: .empty, source: source,
                destination: output, password: "secret")
            Issue.record("Must not silently rasterize or produce legacy encryption")
        } catch PDFwringerError.passwordRequiresFlattening { }
        #expect(try Data(contentsOf: output) == sentinel)
    }

    @Test("Unsupported passwords are rejected before writing", arguments: ["🔑password", "pass\0word", String(repeating: "a", count: 33)])
    func invalidPasswords(password: String) async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        let directory = TestPDFGenerator.makeTempDirectory()
        defer { TestPDFGenerator.cleanup(source); TestPDFGenerator.cleanup(directory) }
        let output = directory.appending(component: "existing.pdf")
        let sentinel = Data("Existing destination".utf8)
        try sentinel.write(to: output)
        do {
            try await PDFMetadataEditor().write(metadata: .empty, source: source,
                destination: output, password: password, flattenAnnotations: true)
            Issue.record("Unsupported password accepted")
        } catch PDFwringerError.invalidEncryptionPassword { }
        #expect(try Data(contentsOf: output) == sentinel)
    }

    @Test("Cipher verification rejects legacy encryption and misleading plaintext")
    func cipherVerificationFailsClosed() throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        let directory = TestPDFGenerator.makeTempDirectory()
        defer { TestPDFGenerator.cleanup(source); TestPDFGenerator.cleanup(directory) }
        let output = directory.appending(component: "legacy.pdf")
        let document = try #require(PDFDocument(url: source))
        #expect(document.write(to: output, withOptions: [.ownerPasswordOption: "pw", .userPasswordOption: "pw"]))
        #expect(!PDFEncryptionPolicy.hasAES128Encryption(at: output))
        let misleading = Data("/Filter /Standard /V 4 /R 4 /Length 128 /CFM /AESV2 /Encrypt 1 0 R\nstartxref\n0\n%%EOF".utf8)
        try misleading.write(to: output)
        #expect(!PDFEncryptionPolicy.hasAES128Encryption(at: output))
        #expect(!PDFEncryptionPolicy.hasAES128Encryption(at: source))
    }

    @Test("PDF 2 metadata round-trips while embedded XMP remains explicitly outside the clearing promise")
    func metadataAndXMP() async throws {
        let directory = TestPDFGenerator.makeTempDirectory()
        defer { TestPDFGenerator.cleanup(directory) }
        let source = directory.appending(component: "pdf20-xmp.pdf")
        let changed = directory.appending(component: "changed.pdf")
        let cleared = directory.appending(component: "cleared.pdf")
        let compressed = directory.appending(component: "lossless.pdf")
        let original = pdfWithXMP()
        try original.write(to: source)
        let document = try #require(PDFDocument(url: source))
        #expect(document.pageCount == 1)
        let metadata = PDFMetadataEditor.Metadata(title: "Updated", author: "New author", subject: "Subject", keywords: "one, two", creator: "Creator")
        let editor = PDFMetadataEditor()
        try await editor.write(metadata: metadata, source: source, destination: changed)
        #expect(editor.read(from: changed) == metadata)
        #expect(PDFDocument(url: changed)?.string == document.string)
        try await editor.write(metadata: .empty, source: changed, destination: cleared)
        #expect(editor.read(from: cleared) == .empty)
        _ = try await PDFCompressor().compress(source: source, destination: compressed,
            level: .lossless, quality: .good, grayscale: false, progress: { _ in })
        for output in [changed, cleared, compressed] {
            let data = try Data(contentsOf: output)
            #expect(data.range(of: Data("PRIVATE_XMP_TEST_CREATOR".utf8)) != nil)
        }
        #expect(try Data(contentsOf: source) == original)
    }

    /// Self-contained fixture: deliberately bypass PDFKit so the input has no Info dictionary.
    private func pdfWithXMP() -> Data {
        let xmp = "<x:xmpmeta xmlns:x='adobe:ns:meta/'><rdf:RDF xmlns:rdf='http://www.w3.org/1999/02/22-rdf-syntax-ns#'><rdf:Description xmlns:xmp='http://ns.adobe.com/xap/1.0/' xmp:CreatorTool='PRIVATE_XMP_TEST_CREATOR'/></rdf:RDF></x:xmpmeta>"
        let content = "BT /F1 18 Tf 20 100 Td (Searchable fixture text) Tj ET"
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R /Metadata 6 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
            "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            "<< /Type /Metadata /Subtype /XML /Length \(xmp.utf8.count) >>\nstream\n\(xmp)\nendstream"
        ]
        var data = Data("%PDF-2.0\n".utf8)
        var offsets = [0]
        for (index, object) in objects.enumerated() {
            offsets.append(data.count)
            data.append(Data("\(index + 1) 0 obj\n\(object)\nendobj\n".utf8))
        }
        let xref = data.count
        data.append(Data("xref\n0 \(offsets.count)\n0000000000 65535 f \n".utf8))
        for offset in offsets.dropFirst() {
            data.append(Data(String(format: "%010d 00000 n \n", offset).utf8))
        }
        data.append(Data("trailer\n<< /Size \(offsets.count) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
        return data
    }
}
