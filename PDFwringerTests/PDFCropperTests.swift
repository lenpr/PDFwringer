import Testing
import PDFKit
import Foundation

@Suite("PDFCropper")
@MainActor
struct PDFCropperTests {

    private let cropper = PDFCropper()

    @Test("Crop reduces page dimensions by specified insets")
    func cropReducesDimensions() throws {
        let url = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "crop.pdf")
        defer { TestPDFGenerator.cleanup(url) }

        let doc = PDFDocument(url: url)!
        let originalBounds = doc.page(at: 0)!.bounds(for: .cropBox)

        let result = try cropper.crop(document: doc, indices: [0], top: 10, bottom: 20, left: 5, right: 15)

        let newBounds = doc.page(at: 0)!.bounds(for: .cropBox)
        #expect(result.pagesModified == 1)
        #expect(result.pagesSkipped == 0)
        #expect(abs(newBounds.width - (originalBounds.width - 20)) < 0.01)
        #expect(abs(newBounds.height - (originalBounds.height - 30)) < 0.01)
    }

    @Test("Display-edge crop geometry follows page rotation")
    func cropGeometryFollowsRotation() throws {
        let bounds = CGRect(x: 100, y: 200, width: 400, height: 600)
        let expected: [Int: CGRect] = [
            0: CGRect(x: 130, y: 220, width: 330, height: 570),
            90: CGRect(x: 110, y: 230, width: 370, height: 530),
            180: CGRect(x: 140, y: 210, width: 330, height: 570),
            270: CGRect(x: 120, y: 240, width: 370, height: 530)
        ]

        for rotation in [0, 90, 180, 270] {
            let calculated = PDFCropGeometry.cropBounds(
                in: bounds,
                rotation: rotation,
                top: 10,
                bottom: 20,
                left: 30,
                right: 40
            )
            #expect(calculated == expected[rotation])

            let document = PDFDocument()
            let page = PDFPage()
            page.setBounds(bounds, for: .mediaBox)
            page.setBounds(bounds, for: .cropBox)
            page.rotation = rotation
            document.insert(page, at: 0)
            _ = try cropper.crop(
                document: document,
                indices: [0],
                top: 10,
                bottom: 20,
                left: 30,
                right: 40
            )
            #expect(page.bounds(for: .cropBox) == expected[rotation])
            #expect(page.rotation == rotation)
        }
    }

    @Test("Crop skips pages where insets exceed dimensions")
    func cropSkipsOversizedInsets() throws {
        let url = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "oversize.pdf")
        defer { TestPDFGenerator.cleanup(url) }

        let doc = PDFDocument(url: url)!
        let bounds = doc.page(at: 0)!.bounds(for: .cropBox)

        // Use insets that clearly exceed the page height
        let result = try cropper.crop(document: doc, indices: [0], top: bounds.height, bottom: 1, left: 0, right: 0)
        #expect(result.pagesModified == 0)
        #expect(result.pagesSkipped == 1)
    }

    @Test("Crop clamps negative values to zero")
    func cropClampsNegatives() throws {
        let url = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "neg.pdf")
        defer { TestPDFGenerator.cleanup(url) }

        let doc = PDFDocument(url: url)!
        let originalBounds = doc.page(at: 0)!.bounds(for: .cropBox)

        let result = try cropper.crop(document: doc, indices: [0], top: -10, bottom: -20, left: -5, right: -15)

        let newBounds = doc.page(at: 0)!.bounds(for: .cropBox)
        #expect(result.pagesModified == 1)
        #expect(abs(newBounds.width - originalBounds.width) < 0.01)
        #expect(abs(newBounds.height - originalBounds.height) < 0.01)
    }

    @Test("Resize sets page to target size")
    func resizeSetsTargetSize() throws {
        let url = TestPDFGenerator.makeRenderedPDF(pageCount: 2, filename: "resize.pdf")
        defer { TestPDFGenerator.cleanup(url) }

        let doc = PDFDocument(url: url)!
        let target = CGSize(width: 595.28, height: 841.89)

        let result = try cropper.resize(document: doc, indices: [0, 1], targetSize: target)

        #expect(result.pagesModified == 2)
        let bounds = doc.page(at: 0)!.bounds(for: .cropBox)
        #expect(abs(bounds.width - target.width) < 0.01)
        #expect(abs(bounds.height - target.height) < 0.01)
    }

    @Test("Resize centers display-oriented bounds on rotated pages")
    func resizeCentersRotatedBounds() throws {
        let original = CGRect(x: 100, y: 200, width: 400, height: 600)
        let displayTarget = CGSize(width: 240, height: 320)

        for rotation in [0, 90, 180, 270] {
            let expectedSize = rotation == 90 || rotation == 270
                ? CGSize(width: 320, height: 240)
                : displayTarget
            let expected = CGRect(
                x: original.midX - expectedSize.width / 2,
                y: original.midY - expectedSize.height / 2,
                width: expectedSize.width,
                height: expectedSize.height
            )
            #expect(PDFCropGeometry.resizeBounds(
                in: original,
                rotation: rotation,
                displayTargetSize: displayTarget
            ) == expected)

            let document = PDFDocument()
            let page = PDFPage()
            page.setBounds(original, for: .mediaBox)
            page.setBounds(original, for: .cropBox)
            page.rotation = rotation
            document.insert(page, at: 0)
            _ = try cropper.resize(
                document: document,
                indices: [0],
                targetSize: displayTarget
            )
            #expect(page.bounds(for: .mediaBox) == expected)
            #expect(page.bounds(for: .cropBox) == expected)
            #expect(page.rotation == rotation)
        }
    }

    @Test("Resize ignores out-of-bounds indices")
    func resizeIgnoresOutOfBounds() throws {
        let url = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "oob.pdf")
        defer { TestPDFGenerator.cleanup(url) }

        let doc = PDFDocument(url: url)!
        let result = try cropper.resize(document: doc, indices: [5, 10], targetSize: CGSize(width: 100, height: 100))
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
