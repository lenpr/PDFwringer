import Testing
import PDFKit
import Foundation

private final class RefusingRotationPage: PDFPage {
    override var rotation: Int {
        get { super.rotation }
        set { }
    }
}

@Suite("PDFRotator")
@MainActor
struct PDFRotatorTests {

    private let rotator = PDFRotator()

    @Test("Rotate all pages 90° changes rotation property")
    func rotateAll90() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 3)
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "out.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        try await rotator.rotate(
            source: source, destination: output,
            angle: .ninety, pageIndices: nil,
            progress: { _ in }
        )

        let result = PDFDocument(url: output)!
        for i in 0..<result.pageCount {
            #expect(result.page(at: i)!.rotation == 90)
        }
    }

    @Test("Rotate specific pages leaves others unchanged")
    func rotateSpecificPages() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 4)
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "out.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        try await rotator.rotate(
            source: source, destination: output,
            angle: .oneEighty, pageIndices: [1, 3],
            progress: { _ in }
        )

        let result = PDFDocument(url: output)!
        #expect(result.page(at: 0)!.rotation == 0)
        #expect(result.page(at: 1)!.rotation == 180)
        #expect(result.page(at: 2)!.rotation == 0)
        #expect(result.page(at: 3)!.rotation == 180)
    }

    @Test("Out-of-bounds indices are silently filtered")
    func outOfBoundsFiltered() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 3)
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "out.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        try await rotator.rotate(
            source: source, destination: output,
            angle: .ninety, pageIndices: [0, 5, 10, -1],
            progress: { _ in }
        )

        let result = PDFDocument(url: output)!
        #expect(result.page(at: 0)!.rotation == 90)
        #expect(result.page(at: 1)!.rotation == 0)
        #expect(result.page(at: 2)!.rotation == 0)
    }

    @Test("Duplicate indices rotate page multiple times")
    func duplicateIndices() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2)
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "out.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        try await rotator.rotate(
            source: source, destination: output,
            angle: .ninety, pageIndices: [0, 0],
            progress: { _ in }
        )

        let result = PDFDocument(url: output)!
        #expect(result.page(at: 0)!.rotation == 180)
    }

    @Test("270° rotation equivalent to 90° counter-clockwise")
    func rotate270() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "out.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        try await rotator.rotate(
            source: source, destination: output,
            angle: .twoSeventy, pageIndices: nil,
            progress: { _ in }
        )

        let result = PDFDocument(url: output)!
        #expect(result.page(at: 0)!.rotation == 270)
    }

    @Test("In-memory rotation refuses permission-restricted documents")
    func restrictedDocumentIsNotMutated() throws {
        let source = TestPDFGenerator.makeAssemblyRestrictedPDF()
        defer { TestPDFGenerator.cleanup(source) }
        let document = try #require(PDFDocument(url: source))
        let page = try #require(document.page(at: 0))
        let originalRotation = page.rotation
        #expect(!document.allowsDocumentAssembly)

        do {
            try rotator.rotate(
                document: document,
                angle: .ninety,
                pageIndices: nil,
                progress: { _ in }
            )
            Issue.record("Expected documentAssemblyNotAllowed")
        } catch let error as PDFwringerError {
            guard case .documentAssemblyNotAllowed = error else {
                Issue.record("Expected documentAssemblyNotAllowed, got \(error)")
                return
            }
        }

        #expect(page.rotation == originalRotation)
    }

    @Test("File rotation fails closed when document assembly is forbidden")
    func restrictedDocumentCreatesNoOutput() async throws {
        let source = TestPDFGenerator.makeAssemblyRestrictedPDF()
        let outputDirectory = TestPDFGenerator.makeTempDirectory()
        let output = outputDirectory.appending(component: "restricted-rotation.pdf")
        let originalData = try Data(contentsOf: source)
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDirectory)
        }

        do {
            try await rotator.rotate(
                source: source,
                destination: output,
                angle: .ninety,
                pageIndices: nil,
                progress: { _ in }
            )
            Issue.record("Expected documentAssemblyNotAllowed")
        } catch let error as PDFwringerError {
            guard case .documentAssemblyNotAllowed = error else {
                Issue.record("Expected documentAssemblyNotAllowed, got \(error)")
                return
            }
        }

        #expect(!FileManager.default.fileExists(atPath: output.path))
        #expect(try Data(contentsOf: source) == originalData)
    }

    @Test("Ignored PDFKit rotation setters fail and roll back earlier pages")
    func ignoredSetterFailsClosed() throws {
        let document = PDFDocument()
        let firstPage = PDFPage()
        let refusingPage = RefusingRotationPage()
        document.insert(firstPage, at: 0)
        document.insert(refusingPage, at: 1)
        #expect(document.allowsDocumentAssembly)
        var progressValues: [Double] = []

        do {
            try rotator.rotate(
                document: document,
                angle: .ninety,
                pageIndices: nil,
                progress: { progressValues.append($0) }
            )
            Issue.record("Expected documentAssemblyNotAllowed")
        } catch let error as PDFwringerError {
            guard case .documentAssemblyNotAllowed = error else {
                Issue.record("Expected documentAssemblyNotAllowed, got \(error)")
                return
            }
        }

        #expect(firstPage.rotation == 0)
        #expect(refusingPage.rotation == 0)
        #expect(progressValues == [0.5])
    }

    @Test("Rotating unreadable file throws fileNotReadable")
    func unreadableFileThrows() async {
        let bogus = URL.temporaryDirectory.appending(component: "nonexistent.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "out.pdf")
        defer { TestPDFGenerator.cleanup(output) }

        do {
            try await rotator.rotate(
                source: bogus, destination: output,
                angle: .ninety, pageIndices: nil,
                progress: { _ in }
            )
            Issue.record("Expected error")
        } catch let error as PDFwringerError {
            if case .fileNotReadable = error { } else {
                Issue.record("Expected fileNotReadable, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Progress is monotonic and reaches 1.0")
    func progressReporting() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 5)
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "out.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        var values: [Double] = []
        try await rotator.rotate(
            source: source, destination: output,
            angle: .ninety, pageIndices: nil,
            progress: { values.append($0) }
        )

        #expect(!values.isEmpty)
        #expect(values.last == 1.0)
        for i in 1..<values.count {
            #expect(values[i] >= values[i - 1])
        }
    }
}
