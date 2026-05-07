import Testing
import PDFKit
import Foundation

@Suite("PDFCropper")
@MainActor
struct PDFCropperTests {

    private let cropper = PDFCropper()

    @Test("Crop reduces page dimensions by specified insets")
    func cropReducesDimensions() {
        let url = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "crop.pdf")
        defer { TestPDFGenerator.cleanup(url) }

        let doc = PDFDocument(url: url)!
        let originalBounds = doc.page(at: 0)!.bounds(for: .cropBox)

        let result = cropper.crop(document: doc, indices: [0], top: 10, bottom: 20, left: 5, right: 15)

        let newBounds = doc.page(at: 0)!.bounds(for: .cropBox)
        #expect(result.pagesModified == 1)
        #expect(result.pagesSkipped == 0)
        #expect(abs(newBounds.width - (originalBounds.width - 20)) < 0.01)
        #expect(abs(newBounds.height - (originalBounds.height - 30)) < 0.01)
    }

    @Test("Crop skips pages where insets exceed dimensions")
    func cropSkipsOversizedInsets() {
        let url = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "oversize.pdf")
        defer { TestPDFGenerator.cleanup(url) }

        let doc = PDFDocument(url: url)!
        let bounds = doc.page(at: 0)!.bounds(for: .cropBox)

        // Use insets that clearly exceed the page height
        let result = cropper.crop(document: doc, indices: [0], top: bounds.height, bottom: 1, left: 0, right: 0)
        #expect(result.pagesModified == 0)
        #expect(result.pagesSkipped == 1)
    }

    @Test("Crop clamps negative values to zero")
    func cropClampsNegatives() {
        let url = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "neg.pdf")
        defer { TestPDFGenerator.cleanup(url) }

        let doc = PDFDocument(url: url)!
        let originalBounds = doc.page(at: 0)!.bounds(for: .cropBox)

        let result = cropper.crop(document: doc, indices: [0], top: -10, bottom: -20, left: -5, right: -15)

        let newBounds = doc.page(at: 0)!.bounds(for: .cropBox)
        #expect(result.pagesModified == 1)
        #expect(abs(newBounds.width - originalBounds.width) < 0.01)
        #expect(abs(newBounds.height - originalBounds.height) < 0.01)
    }

    @Test("Resize sets page to target size")
    func resizeSetsTargetSize() {
        let url = TestPDFGenerator.makeRenderedPDF(pageCount: 2, filename: "resize.pdf")
        defer { TestPDFGenerator.cleanup(url) }

        let doc = PDFDocument(url: url)!
        let target = CGSize(width: 595.28, height: 841.89)

        let result = cropper.resize(document: doc, indices: [0, 1], targetSize: target)

        #expect(result.pagesModified == 2)
        let bounds = doc.page(at: 0)!.bounds(for: .cropBox)
        #expect(abs(bounds.width - target.width) < 0.01)
        #expect(abs(bounds.height - target.height) < 0.01)
    }

    @Test("Resize ignores out-of-bounds indices")
    func resizeIgnoresOutOfBounds() {
        let url = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "oob.pdf")
        defer { TestPDFGenerator.cleanup(url) }

        let doc = PDFDocument(url: url)!
        let result = cropper.resize(document: doc, indices: [5, 10], targetSize: CGSize(width: 100, height: 100))
        #expect(result.pagesModified == 0)
    }

    @Test("PaperSize A4 has correct dimensions")
    func paperSizeA4() {
        let size = PaperSize.a4.size
        #expect(abs(size.width - 595.28) < 0.01)
        #expect(abs(size.height - 841.89) < 0.01)
    }

    @Test("PaperSize all cases have portrait orientation")
    func paperSizePortrait() {
        for paper in PaperSize.allCases {
            #expect(paper.size.width < paper.size.height)
        }
    }
}
