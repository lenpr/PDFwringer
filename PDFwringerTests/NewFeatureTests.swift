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

    @Test("Rejects an out-of-range page without creating files")
    func rejectsInvalidPageAtomically() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2, filename: "export_invalid.pdf")
        let outputDir = TestPDFGenerator.makeTempDirectory()
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDir)
        }

        do {
            _ = try await PDFImageExporter().exportPages(
                source: source,
                outputDirectory: outputDir,
                options: .init(format: .jpeg, dpi: 72, quality: 0.8),
                pageIndices: [0, 2],
                progress: { _ in }
            )
            Issue.record("Expected invalidPageRange")
        } catch let error as PDFwringerError {
            guard case .invalidPageRange = error else {
                Issue.record("Expected invalidPageRange, got \(error)")
                return
            }
        }

        #expect(try FileManager.default.contentsOfDirectory(atPath: outputDir.path).isEmpty)
    }

    @Test("Rejects duplicate pages without creating files")
    func rejectsDuplicatePagesAtomically() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2, filename: "export_duplicate.pdf")
        let outputDir = TestPDFGenerator.makeTempDirectory()
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDir)
        }

        do {
            _ = try await PDFImageExporter().exportPages(
                source: source,
                outputDirectory: outputDir,
                options: .init(format: .jpeg, dpi: 72, quality: 0.8),
                pageIndices: [0, 0],
                progress: { _ in }
            )
            Issue.record("Expected invalidPageRange")
        } catch let error as PDFwringerError {
            guard case .invalidPageRange = error else {
                Issue.record("Expected invalidPageRange, got \(error)")
                return
            }
        }

        #expect(try FileManager.default.contentsOfDirectory(atPath: outputDir.path).isEmpty)
    }

    @Test("Does not overwrite an existing export")
    func rejectsExistingExport() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "export_existing.pdf")
        let outputDir = TestPDFGenerator.makeTempDirectory()
        let existingName = source.deletingPathExtension().lastPathComponent + "_page_001.jpg"
        let existing = outputDir.appending(component: existingName)
        let originalData = Data("original".utf8)
        try originalData.write(to: existing)
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDir)
        }

        do {
            _ = try await PDFImageExporter().exportPages(
                source: source,
                outputDirectory: outputDir,
                options: .init(format: .jpeg, dpi: 72, quality: 0.8),
                pageIndices: nil,
                progress: { _ in }
            )
            Issue.record("Expected cannotWriteOutput")
        } catch let error as PDFwringerError {
            guard case .cannotWriteOutput = error else {
                Issue.record("Expected cannotWriteOutput, got \(error)")
                return
            }
        }

        #expect(try Data(contentsOf: existing) == originalData)
        #expect(try FileManager.default.contentsOfDirectory(atPath: outputDir.path).count == 1)
    }

    @Test("Rejects unsafe image options without trapping", arguments: [
        PDFImageExporter.Options(format: .jpeg, dpi: .infinity, quality: 0.8),
        PDFImageExporter.Options(format: .jpeg, dpi: .nan, quality: 0.8),
        PDFImageExporter.Options(format: .jpeg, dpi: 150, quality: .infinity),
        PDFImageExporter.Options(format: .jpeg, dpi: 150, quality: -0.1),
    ])
    func rejectsUnsafeOptions(options: PDFImageExporter.Options) async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "unsafe_options.pdf")
        let outputDir = TestPDFGenerator.makeTempDirectory()
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDir)
        }

        await #expect(throws: PDFwringerError.self) {
            _ = try await PDFImageExporter().exportPages(
                source: source,
                outputDirectory: outputDir,
                options: options,
                pageIndices: nil,
                progress: { _ in }
            )
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outputDir.path).isEmpty)
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
        let ctx = try #require(CGContext(data: nil, width: 200, height: 300, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(ctx.makeImage())
        let data = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        try (data as Data).write(to: imageURL)

        let converter = PDFImageConverter()
        try await converter.convert(images: [imageURL], destination: output, progress: { _ in })

        let doc = PDFDocument(url: output)
        #expect(doc != nil)
        #expect(doc?.pageCount == 1)
    }

    @Test("Corrupt input fails without replacing destination")
    func corruptInputFailsClosed() async throws {
        let validImage = URL.temporaryDirectory.appending(component: "valid_\(UUID()).png")
        let corruptImage = URL.temporaryDirectory.appending(component: "corrupt_\(UUID()).png")
        let output = URL.temporaryDirectory.appending(component: "converted_\(UUID()).pdf")
        let originalData = Data("original destination".utf8)
        defer {
            try? FileManager.default.removeItem(at: validImage)
            try? FileManager.default.removeItem(at: corruptImage)
            try? FileManager.default.removeItem(at: output)
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil,
            width: 20,
            height: 20,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try #require(context.makeImage())
        let encoded = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            encoded,
            "public.png" as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
        try (encoded as Data).write(to: validImage)
        try Data("not an image".utf8).write(to: corruptImage)
        try originalData.write(to: output)

        do {
            try await PDFImageConverter().convert(
                images: [validImage, corruptImage],
                destination: output,
                progress: { _ in }
            )
            Issue.record("Expected corrupt input to fail")
        } catch let error as PDFwringerError {
            guard case .fileNotReadable(let filename) = error else {
                Issue.record("Expected fileNotReadable, got \(error)")
                return
            }
            #expect(filename == corruptImage.lastPathComponent)
        }

        #expect(try Data(contentsOf: output) == originalData)
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
