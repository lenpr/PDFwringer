import Testing
import PDFKit
import Foundation

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
