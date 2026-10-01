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

    @Test("A later source failure preserves the existing destination")
    func laterSourceFailurePreservesDestination() async throws {
        let first = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "first.pdf")
        let second = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "second.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "merged.pdf")
        let originalDestination = Data("existing destination".utf8)
        try originalDestination.write(to: output)
        defer {
            TestPDFGenerator.cleanup(first)
            TestPDFGenerator.cleanup(second)
            TestPDFGenerator.cleanup(output)
        }

        var replacementError: Error?
        var replacedSecondSource = false
        await #expect(throws: PDFwringerError.self) {
            try await PDFConcatenator().concatenate(
                sources: [first, second],
                destination: output,
                progress: { value in
                    guard value >= 0.5, !replacedSecondSource else { return }
                    replacedSecondSource = true
                    do {
                        try Data("not a PDF".utf8).write(to: second, options: .atomic)
                    } catch {
                        replacementError = error
                    }
                }
            )
        }

        #expect(replacementError == nil)
        #expect(try Data(contentsOf: output) == originalDestination)
    }

    @Test("Completion means the merged file is already published")
    func completionFollowsPublication() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 3)
        let directory = TestPDFGenerator.makeTempDirectory()
        let output = directory.appending(component: "merged.pdf")
        defer { TestPDFGenerator.cleanup(source); TestPDFGenerator.cleanup(directory) }
        var publishedAtCompletion = false
        try await PDFConcatenator().concatenate(sources: [source, source], destination: output) { value in
            #expect(Thread.isMainThread)
            if value == 1 {
                publishedAtCompletion = PDFDocument(url: output)?.pageCount == 6
            }
        }
        #expect(publishedAtCompletion)
    }

    @Test("An external destination change during merge is preserved", arguments: [false, true])
    func destinationChanges(existing: Bool) async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2)
        let directory = TestPDFGenerator.makeTempDirectory()
        let output = directory.appending(component: "merged.pdf")
        defer { TestPDFGenerator.cleanup(source); TestPDFGenerator.cleanup(directory) }
        if existing { try Data("previous destination".utf8).write(to: output) }
        let externalBytes = Data("externally replaced destination".utf8)
        var didReplace = false
        do {
            try await PDFConcatenator().concatenate(sources: [source, source], destination: output) { value in
                guard !didReplace, value < 1 else { return }
                do {
                    try externalBytes.write(to: output, options: .atomic)
                    didReplace = true
                } catch { Issue.record("Could not simulate destination replacement: \(error)") }
            }
            Issue.record("Expected destinationChanged")
        } catch PDFwringerError.destinationChanged { }
        #expect(didReplace)
        #expect(try Data(contentsOf: output) == externalBytes)
    }

    @Test("Cancellation after assembly reaches the worker and preserves existing output")
    func cancelBeforeWriting() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 3)
        let directory = TestPDFGenerator.makeTempDirectory()
        let output = directory.appending(component: "merged.pdf")
        defer { TestPDFGenerator.cleanup(source); TestPDFGenerator.cleanup(directory) }
        let original = Data("existing destination".utf8)
        try original.write(to: output)
        var operation: Task<PDFConcatenator.Result, Error>?
        var sawCompletion = false
        operation = Task {
            try await PDFConcatenator().concatenate(sources: [source], destination: output) { value in
                if value >= 0.99, value < 1 { operation?.cancel() }
                if value == 1 { sawCompletion = true }
            }
        }
        do { _ = try await operation?.value; Issue.record("Expected cancellation") }
        catch is CancellationError { }
        #expect(!sawCompletion)
        #expect(try Data(contentsOf: output) == original)
    }
}
