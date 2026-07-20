import Foundation
import PDFKit
import AppKit
import Testing

@Suite("PDFPageReorderer")
@MainActor
struct PDFPageReordererTests {
    private let reorderer = PDFPageReorderer()

    private func makeDistinctPagePDF() -> URL {
        let url = URL.temporaryDirectory.appending(component: "\(UUID()).pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 300, height: 400)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            fatalError("Cannot create reorder fixture")
        }
        let colors = [NSColor.red, .green, .blue]
        for (index, color) in colors.enumerated() {
            mediaBox.size = CGSize(
                width: CGFloat(300 + index * 20),
                height: CGFloat(400 + index * 20)
            )
            context.beginPage(mediaBox: &mediaBox)
            context.setFillColor(color.cgColor)
            context.fill(mediaBox)
            context.endPage()
        }
        context.closePDF()
        return url
    }

    private func dominantChannel(of page: PDFPage) throws -> Int {
        let rendered = try #require(PDFRasterizer.render(page, dpi: 72, grayscale: false)?.image)
        let bitmap = NSBitmapImageRep(cgImage: rendered)
        let color = try #require(bitmap.colorAt(x: rendered.width / 2, y: rendered.height / 2))
            .usingColorSpace(.deviceRGB)
        let components = [color?.redComponent ?? 0, color?.greenComponent ?? 0, color?.blueComponent ?? 0]
        return try #require(components.enumerated().max(by: { $0.element < $1.element })?.offset)
    }

    @Test("Reorders every page and preserves the source")
    func reordersPages() async throws {
        let source = makeDistinctPagePDF()
        let directory = TestPDFGenerator.makeTempDirectory()
        let output = directory.appending(component: "reordered.pdf")
        let sourceData = try Data(contentsOf: source)
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(directory)
        }

        let document = try #require(PDFDocument(url: source))
        document.documentAttributes = [PDFDocumentAttribute.titleAttribute: "Reorder Test"]
        var progressValues: [Double] = []
        try await reorderer.reorder(
            document: document,
            source: source,
            destination: output,
            pageOrder: [2, 0, 1],
            progress: { progressValues.append($0) }
        )

        let result = try #require(PDFDocument(url: output))
        let channels = try (0..<result.pageCount).map {
            try dominantChannel(of: #require(result.page(at: $0)))
        }
        #expect(channels == [2, 0, 1])
        let sizes = try (0..<result.pageCount).map {
            try #require(result.page(at: $0)).bounds(for: .mediaBox).size
        }
        #expect(sizes == [CGSize(width: 340, height: 440), CGSize(width: 300, height: 400), CGSize(width: 320, height: 420)])
        #expect(result.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == "Reorder Test")
        #expect(progressValues.count == 3)
        #expect(progressValues.last == 1)
        #expect(try Data(contentsOf: source) == sourceData)
    }

    @Test("Rejects incomplete, duplicate, and out-of-range page orders")
    func rejectsInvalidOrders() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 3)
        let directory = TestPDFGenerator.makeTempDirectory()
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(directory)
        }
        let document = try #require(PDFDocument(url: source))

        for (index, order) in [[], [0, 1], [0, 0, 2], [0, 1, 3]].enumerated() {
            let output = directory.appending(component: "invalid-\(index).pdf")
            do {
                try await reorderer.reorder(
                    document: document,
                    source: source,
                    destination: output,
                    pageOrder: order,
                    progress: { _ in }
                )
                Issue.record("Expected invalidPageOrder for \(order)")
            } catch PDFwringerError.invalidPageOrder {
                // Expected.
            } catch {
                Issue.record("Expected invalidPageOrder, got \(error)")
            }
            #expect(!FileManager.default.fileExists(atPath: output.path))
        }
    }

    @Test("Refuses permission-restricted documents")
    func refusesRestrictedDocument() async throws {
        let source = TestPDFGenerator.makeAssemblyRestrictedPDF()
        let directory = TestPDFGenerator.makeTempDirectory()
        let output = directory.appending(component: "restricted.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(directory)
        }
        let document = try #require(PDFDocument(url: source))

        do {
            try await reorderer.reorder(
                document: document,
                source: source,
                destination: output,
                pageOrder: [0],
                progress: { _ in }
            )
            Issue.record("Expected documentPermissionsDenied")
        } catch PDFwringerError.documentPermissionsDenied {
            // Expected.
        } catch {
            Issue.record("Expected documentPermissionsDenied, got \(error)")
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }
}
