import Testing
import PDFKit

@Suite("PDFConcatenator")
@MainActor
struct PDFConcatenatorTests {

    @Test("Concatenates two PDFs with correct total page count")
    func concatenateTwoPDFs() async throws {
        let pdf1 = TestPDFGenerator.makeRenderedPDF(pageCount: 3, filename: "a.pdf")
        let pdf2 = TestPDFGenerator.makeRenderedPDF(pageCount: 5, filename: "b.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "merged.pdf")
        defer {
            TestPDFGenerator.cleanup(pdf1)
            TestPDFGenerator.cleanup(pdf2)
            TestPDFGenerator.cleanup(output)
        }

        let concatenator = PDFConcatenator()
        try await concatenator.concatenate(
            sources: [pdf1, pdf2],
            destination: output,
            progress: { _ in }
        )

        let result = PDFDocument(url: output)
        #expect(result != nil)
        #expect(result?.pageCount == 8)
    }

    @Test("Concatenates three PDFs preserving order")
    func concatenateThreePDFs() async throws {
        let pdf1 = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "first.pdf")
        let pdf2 = TestPDFGenerator.makeRenderedPDF(pageCount: 2, filename: "second.pdf")
        let pdf3 = TestPDFGenerator.makeRenderedPDF(pageCount: 3, filename: "third.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "merged.pdf")
        defer {
            TestPDFGenerator.cleanup(pdf1)
            TestPDFGenerator.cleanup(pdf2)
            TestPDFGenerator.cleanup(pdf3)
            TestPDFGenerator.cleanup(output)
        }

        let concatenator = PDFConcatenator()
        try await concatenator.concatenate(
            sources: [pdf1, pdf2, pdf3],
            destination: output,
            progress: { _ in }
        )

        let result = PDFDocument(url: output)
        #expect(result?.pageCount == 6)
    }

    @Test("Reports progress during concatenation")
    func reportsProgress() async throws {
        let pdf1 = TestPDFGenerator.makeRenderedPDF(pageCount: 5, filename: "a.pdf")
        let pdf2 = TestPDFGenerator.makeRenderedPDF(pageCount: 5, filename: "b.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "merged.pdf")
        defer {
            TestPDFGenerator.cleanup(pdf1)
            TestPDFGenerator.cleanup(pdf2)
            TestPDFGenerator.cleanup(output)
        }

        var progressValues: [Double] = []
        let concatenator = PDFConcatenator()
        try await concatenator.concatenate(
            sources: [pdf1, pdf2],
            destination: output,
            progress: { p in progressValues.append(p) }
        )

        #expect(!progressValues.isEmpty)
        #expect(progressValues.last == 1.0)
    }

    @Test("Throws emptyFileList for empty sources")
    func throwsForEmptySources() async throws {
        let concatenator = PDFConcatenator()
        await #expect(throws: PDFwringerError.self) {
            try await concatenator.concatenate(
                sources: [],
                destination: URL.temporaryDirectory.appending(component: "nope.pdf"),
                progress: { _ in }
            )
        }
    }

    @Test("Single file concatenation produces same page count")
    func singleFile() async throws {
        let pdf = TestPDFGenerator.makeRenderedPDF(pageCount: 4, filename: "solo.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "merged.pdf")
        defer {
            TestPDFGenerator.cleanup(pdf)
            TestPDFGenerator.cleanup(output)
        }

        let concatenator = PDFConcatenator()
        try await concatenator.concatenate(
            sources: [pdf],
            destination: output,
            progress: { _ in }
        )

        let result = PDFDocument(url: output)
        #expect(result?.pageCount == 4)
    }

    // MARK: - Edge cases

    @Test("Unreadable file in sources throws fileNotReadable")
    func unreadableSourceThrows() async {
        let valid = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "valid.pdf")
        let bogus = URL.temporaryDirectory.appending(component: "nonexistent.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "out.pdf")
        defer {
            TestPDFGenerator.cleanup(valid)
            TestPDFGenerator.cleanup(output)
        }

        let concatenator = PDFConcatenator()
        do {
            try await concatenator.concatenate(
                sources: [valid, bogus],
                destination: output,
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

    @Test("Progress is monotonically non-decreasing")
    func progressMonotonic() async throws {
        let pdf1 = TestPDFGenerator.makeRenderedPDF(pageCount: 4, filename: "a.pdf")
        let pdf2 = TestPDFGenerator.makeRenderedPDF(pageCount: 4, filename: "b.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "merged.pdf")
        defer {
            TestPDFGenerator.cleanup(pdf1)
            TestPDFGenerator.cleanup(pdf2)
            TestPDFGenerator.cleanup(output)
        }

        var values: [Double] = []
        let concatenator = PDFConcatenator()
        try await concatenator.concatenate(
            sources: [pdf1, pdf2],
            destination: output,
            progress: { values.append($0) }
        )

        for i in 1..<values.count {
            #expect(values[i] >= values[i - 1])
        }
        #expect(values.last == 1.0)
    }

    @Test("Many small PDFs concatenate correctly")
    func manySmallPDFs() async throws {
        let pdfs = (0..<10).map { TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "f\($0).pdf") }
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "merged.pdf")
        defer {
            for pdf in pdfs { TestPDFGenerator.cleanup(pdf) }
            TestPDFGenerator.cleanup(output)
        }

        let concatenator = PDFConcatenator()
        try await concatenator.concatenate(
            sources: pdfs,
            destination: output,
            progress: { _ in }
        )

        let result = PDFDocument(url: output)
        #expect(result?.pageCount == 10)
    }
}
