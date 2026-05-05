import Testing
import PDFKit

@Suite("PDFSplitter")
@MainActor
struct PDFSplitterTests {

    // MARK: - Split every N pages

    @Test("Split 10-page PDF every 3 pages produces 4 files")
    func splitEveryThree() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 10, filename: "ten.pdf")
        let outputDir = TestPDFGenerator.makeTempDirectory()
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDir)
        }

        let splitter = PDFSplitter()
        let outputs = try await splitter.split(
            source: source,
            mode: .splitEveryN(3),
            destination: outputDir,
            progress: { _ in }
        )

        #expect(outputs.count == 4)

        // First 3 chunks have 3 pages each, last has 1
        let pageCounts = outputs.map { PDFDocument(url: $0)?.pageCount ?? 0 }
        #expect(pageCounts == [3, 3, 3, 1])
    }

    @Test("Split every 1 page produces N single-page files")
    func splitEverySinglePage() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 4, filename: "four.pdf")
        let outputDir = TestPDFGenerator.makeTempDirectory()
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDir)
        }

        let splitter = PDFSplitter()
        let outputs = try await splitter.split(
            source: source,
            mode: .splitEveryN(1),
            destination: outputDir,
            progress: { _ in }
        )

        #expect(outputs.count == 4)
        for url in outputs {
            let doc = PDFDocument(url: url)
            #expect(doc?.pageCount == 1)
        }
    }

    @Test("Split with N larger than page count produces single file")
    func splitNLargerThanTotal() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 3, filename: "small.pdf")
        let outputDir = TestPDFGenerator.makeTempDirectory()
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDir)
        }

        let splitter = PDFSplitter()
        let outputs = try await splitter.split(
            source: source,
            mode: .splitEveryN(100),
            destination: outputDir,
            progress: { _ in }
        )

        #expect(outputs.count == 1)
        #expect(PDFDocument(url: outputs[0])?.pageCount == 3)
    }

    // MARK: - Keep pages

    @Test("Keep specific pages extracts correct subset")
    func keepPages() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 8, filename: "eight.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "extracted.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        let splitter = PDFSplitter()
        let outputs = try await splitter.split(
            source: source,
            mode: .keepPages([0, 2, 4, 6]), // 0-based indices
            destination: output,
            progress: { _ in }
        )

        #expect(outputs.count == 1)
        #expect(PDFDocument(url: outputs[0])?.pageCount == 4)
    }

    @Test("Keep single page")
    func keepSinglePage() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 5, filename: "five.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "single.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        let splitter = PDFSplitter()
        let outputs = try await splitter.split(
            source: source,
            mode: .keepPages([3]),
            destination: output,
            progress: { _ in }
        )

        #expect(outputs.count == 1)
        #expect(PDFDocument(url: outputs[0])?.pageCount == 1)
    }

    @Test("Keep pages with empty list throws")
    func keepEmptyListThrows() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 5, filename: "five.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "nope.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        let splitter = PDFSplitter()
        await #expect(throws: PDFwringerError.self) {
            try await splitter.split(
                source: source,
                mode: .keepPages([]),
                destination: output,
                progress: { _ in }
            )
        }
    }

    // MARK: - Remove pages

    @Test("Remove pages produces PDF without those pages")
    func removePages() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 6, filename: "six.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "trimmed.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        let splitter = PDFSplitter()
        let outputs = try await splitter.split(
            source: source,
            mode: .removePages([1, 3, 5]), // remove pages 2, 4, 6 (0-based)
            destination: output,
            progress: { _ in }
        )

        #expect(outputs.count == 1)
        #expect(PDFDocument(url: outputs[0])?.pageCount == 3)
    }

    @Test("Remove all pages leaves empty set which throws")
    func removeAllPagesThrows() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2, filename: "two.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "empty.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        let splitter = PDFSplitter()
        await #expect(throws: PDFwringerError.self) {
            try await splitter.split(
                source: source,
                mode: .removePages([0, 1]),
                destination: output,
                progress: { _ in }
            )
        }
    }

    // MARK: - Error cases

    @Test("Invalid source URL throws cannotOpenDocument")
    func invalidSourceThrows() async throws {
        let bogus = URL.temporaryDirectory.appending(component: "nonexistent.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "out.pdf")
        defer { TestPDFGenerator.cleanup(output) }

        let splitter = PDFSplitter()
        await #expect(throws: PDFwringerError.self) {
            try await splitter.split(
                source: bogus,
                mode: .splitEveryN(1),
                destination: output,
                progress: { _ in }
            )
        }
    }

    @Test("Reports progress monotonically")
    func reportsProgress() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 6, filename: "six.pdf")
        let outputDir = TestPDFGenerator.makeTempDirectory()
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDir)
        }

        var progressValues: [Double] = []
        let splitter = PDFSplitter()
        _ = try await splitter.split(
            source: source,
            mode: .splitEveryN(2),
            destination: outputDir,
            progress: { p in progressValues.append(p) }
        )

        #expect(!progressValues.isEmpty)
        #expect(progressValues.last == 1.0)
        // Verify monotonically non-decreasing
        for i in 1..<progressValues.count {
            #expect(progressValues[i] >= progressValues[i - 1])
        }
    }
}
