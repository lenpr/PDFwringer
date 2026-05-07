import Testing
import PDFKit

@Suite("PDFFileItem")
struct PDFFileItemTests {

    @Test("from(url:) creates item for valid PDF")
    func fromValidPDF() {
        let url = TestPDFGenerator.makeRenderedPDF(pageCount: 3, filename: "item.pdf")
        defer { TestPDFGenerator.cleanup(url) }

        let item = PDFFileItem.from(url: url)
        #expect(item != nil)
        #expect(item?.pageCount == 3)
        #expect(item?.filename.hasSuffix("item.pdf") == true)
        #expect(item?.url == url)
    }

    @Test("from(url:) returns nil for non-PDF extension")
    func fromNonPDF() {
        let url = URL.temporaryDirectory.appending(component: "notes.txt")
        try! "text".write(to: url, atomically: true, encoding: .utf8)
        defer { TestPDFGenerator.cleanup(url) }

        let item = PDFFileItem.from(url: url)
        #expect(item == nil)
    }

    @Test("from(url:) returns nil for corrupt PDF (0 pages)")
    func fromCorruptPDF() {
        let url = URL.temporaryDirectory.appending(component: "bad.pdf")
        try! "not a real pdf".write(to: url, atomically: true, encoding: .utf8)
        defer { TestPDFGenerator.cleanup(url) }

        let item = PDFFileItem.from(url: url)
        #expect(item == nil)
    }

    @Test("from(urls:) filters to valid PDFs only")
    func fromMultipleURLs() {
        let pdf1 = TestPDFGenerator.makeRenderedPDF(pageCount: 2, filename: "one.pdf")
        let pdf2 = TestPDFGenerator.makeRenderedPDF(pageCount: 4, filename: "two.pdf")
        let txt = URL.temporaryDirectory.appending(component: "skip.txt")
        try! "skip".write(to: txt, atomically: true, encoding: .utf8)
        defer {
            TestPDFGenerator.cleanup(pdf1)
            TestPDFGenerator.cleanup(pdf2)
            TestPDFGenerator.cleanup(txt)
        }

        let items = PDFFileItem.from(urls: [pdf1, txt, pdf2])
        #expect(items.count == 2)
        #expect(items[0].pageCount == 2)
        #expect(items[1].pageCount == 4)
    }

    @Test("from(urls:) preserves input order")
    func preservesOrder() {
        let pdf1 = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "z_last.pdf")
        let pdf2 = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "a_first.pdf")
        defer {
            TestPDFGenerator.cleanup(pdf1)
            TestPDFGenerator.cleanup(pdf2)
        }

        let items = PDFFileItem.from(urls: [pdf1, pdf2])
        #expect(items[0].filename.contains("z_last"))
        #expect(items[1].filename.contains("a_first"))
    }

    @Test("Each item gets a unique ID")
    func uniqueIDs() {
        let url = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "dup.pdf")
        defer { TestPDFGenerator.cleanup(url) }

        let item1 = PDFFileItem.from(url: url)!
        let item2 = PDFFileItem.from(url: url)!
        #expect(item1.id != item2.id)
    }
}
