import Testing
import PDFKit
import Foundation

@Suite("PDFPageNumberer")
@MainActor
struct PDFPageNumbererTests {

    @Test("Adds page numbers to all pages and preserves page count")
    func addsNumbersToAllPages() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 5, filename: "numberer_all.pdf")
        let output = URL.temporaryDirectory.appending(component: "numbered_\(UUID()).pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            try? FileManager.default.removeItem(at: output)
        }

        let numberer = PDFPageNumberer()
        try await numberer.addPageNumbers(
            source: source, destination: output,
            options: .init(), pageIndices: nil,
            progress: { _ in }
        )

        let doc = PDFDocument(url: output)
        #expect(doc != nil)
        #expect(doc?.pageCount == 5)
    }

    @Test("Numbers only selected pages")
    func numbersSelectedPages() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 5, filename: "numberer_select.pdf")
        let output = URL.temporaryDirectory.appending(component: "numbered_sel_\(UUID()).pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            try? FileManager.default.removeItem(at: output)
        }

        let numberer = PDFPageNumberer()
        try await numberer.addPageNumbers(
            source: source, destination: output,
            options: .init(), pageIndices: [0, 2, 4],
            progress: { _ in }
        )

        let doc = PDFDocument(url: output)
        #expect(doc?.pageCount == 5)
    }

    @Test("Rejects source equals destination")
    func rejectsSourceEqualsDestination() async {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "numberer_sameurl.pdf")
        defer { TestPDFGenerator.cleanup(source) }

        let numberer = PDFPageNumberer()
        await #expect(throws: PDFwringerError.self) {
            try await numberer.addPageNumbers(
                source: source, destination: source,
                options: .init(), pageIndices: nil,
                progress: { _ in }
            )
        }
    }

    @Test("Reports progress reaching 1.0")
    func reportsProgress() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 3, filename: "numberer_prog.pdf")
        let output = URL.temporaryDirectory.appending(component: "numbered_prog_\(UUID()).pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            try? FileManager.default.removeItem(at: output)
        }

        var lastProgress: Double = 0
        let numberer = PDFPageNumberer()
        try await numberer.addPageNumbers(
            source: source, destination: output,
            options: .init(), pageIndices: nil,
            progress: { p in lastProgress = p }
        )

        #expect(abs(lastProgress - 1.0) < 0.01)
    }
}

@Suite("PDFWatermarker")
@MainActor
struct PDFWatermarkerTests {

    @Test("Adds watermark and preserves page count")
    func addsWatermark() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 3, filename: "watermark_basic.pdf")
        let output = URL.temporaryDirectory.appending(component: "watermarked_\(UUID()).pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            try? FileManager.default.removeItem(at: output)
        }

        let watermarker = PDFWatermarker()
        try await watermarker.addWatermark(
            source: source, destination: output,
            options: .init(text: "DRAFT"),
            pageIndices: nil,
            progress: { _ in }
        )

        let doc = PDFDocument(url: output)
        #expect(doc != nil)
        #expect(doc?.pageCount == 3)
    }

    @Test("Watermarks only selected pages")
    func watermarksSelectedPages() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 4, filename: "watermark_select.pdf")
        let output = URL.temporaryDirectory.appending(component: "watermarked_sel_\(UUID()).pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            try? FileManager.default.removeItem(at: output)
        }

        let watermarker = PDFWatermarker()
        try await watermarker.addWatermark(
            source: source, destination: output,
            options: .init(text: "CONFIDENTIAL"),
            pageIndices: [0, 2],
            progress: { _ in }
        )

        let doc = PDFDocument(url: output)
        #expect(doc?.pageCount == 4)
    }

    @Test("Empty text does nothing")
    func emptyTextNoOp() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "watermark_empty.pdf")
        let output = URL.temporaryDirectory.appending(component: "watermarked_empty_\(UUID()).pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            try? FileManager.default.removeItem(at: output)
        }

        let watermarker = PDFWatermarker()
        try await watermarker.addWatermark(
            source: source, destination: output,
            options: .init(text: ""),
            pageIndices: nil,
            progress: { _ in }
        )

        // Empty text should not create an output
        let exists = FileManager.default.fileExists(atPath: output.path(percentEncoded: false))
        #expect(!exists)
    }

    @Test("Rejects source equals destination")
    func rejectsSourceEqualsDestination() async {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "watermark_sameurl.pdf")
        defer { TestPDFGenerator.cleanup(source) }

        let watermarker = PDFWatermarker()
        await #expect(throws: PDFwringerError.self) {
            try await watermarker.addWatermark(
                source: source, destination: source,
                options: .init(text: "TEST"),
                pageIndices: nil,
                progress: { _ in }
            )
        }
    }
}

@Suite("PDFImageExporter")
@MainActor
struct PDFImageExporterTests {

    @Test("Exports all pages as JPEG files")
    func exportsAllPagesJPEG() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 3, filename: "export_jpeg.pdf")
        let outputDir = TestPDFGenerator.makeTempDirectory()
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDir)
        }

        let exporter = PDFImageExporter()
        let outputs = try await exporter.exportPages(
            source: source, outputDirectory: outputDir,
            options: .init(format: .jpeg, dpi: 72, quality: 0.8),
            pageIndices: nil,
            progress: { _ in }
        )

        #expect(outputs.count == 3)
        for url in outputs {
            #expect(url.pathExtension == "jpg")
            let data = try Data(contentsOf: url)
            #expect(data.count > 0)
        }
    }

    @Test("Exports selected pages as PNG")
    func exportsSelectedPNG() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 5, filename: "export_png.pdf")
        let outputDir = TestPDFGenerator.makeTempDirectory()
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDir)
        }

        let exporter = PDFImageExporter()
        let outputs = try await exporter.exportPages(
            source: source, outputDirectory: outputDir,
            options: .init(format: .png, dpi: 150, quality: 1.0),
            pageIndices: [0, 4],
            progress: { _ in }
        )

        #expect(outputs.count == 2)
        for url in outputs {
            #expect(url.pathExtension == "png")
        }
    }
}

@Suite("PDFImageConverter")
@MainActor
struct PDFImageConverterTests {

    @Test("Converts image to single-page PDF")
    func convertsImageToPDF() async throws {
        // Create a test image
        let imageURL = URL.temporaryDirectory.appending(component: "test_image_\(UUID()).png")
        let output = URL.temporaryDirectory.appending(component: "converted_\(UUID()).pdf")
        defer {
            try? FileManager.default.removeItem(at: imageURL)
            try? FileManager.default.removeItem(at: output)
        }

        // Create a simple PNG image
        let size = CGSize(width: 200, height: 300)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: 200, height: 300, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = ctx.makeImage() else { return }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        try (data as Data).write(to: imageURL)

        let converter = PDFImageConverter()
        try await converter.convert(images: [imageURL], destination: output, progress: { _ in })

        let doc = PDFDocument(url: output)
        #expect(doc != nil)
        #expect(doc?.pageCount == 1)
    }

    @Test("isImageFile correctly identifies image extensions")
    func identifiesImageFiles() {
        #expect(PDFImageConverter.isImageFile(URL(fileURLWithPath: "/test.jpg")) == true)
        #expect(PDFImageConverter.isImageFile(URL(fileURLWithPath: "/test.png")) == true)
        #expect(PDFImageConverter.isImageFile(URL(fileURLWithPath: "/test.heic")) == true)
        #expect(PDFImageConverter.isImageFile(URL(fileURLWithPath: "/test.pdf")) == false)
        #expect(PDFImageConverter.isImageFile(URL(fileURLWithPath: "/test.txt")) == false)
    }
}
