import Testing
import PDFKit
import Foundation

private final class MissingExportPagePDFDocument: PDFDocument {
    var inaccessiblePageIndex: Int?

    override func page(at index: Int) -> PDFPage? {
        if index == inaccessiblePageIndex { return nil }
        return super.page(at: index)
    }
}

private func exportFilename(
    source: URL,
    pageNumber: Int,
    suffix: Int? = nil,
    extension fileExtension: String = "jpg"
) -> String {
    let baseName = source.deletingPathExtension().lastPathComponent
    let suffixText = suffix.map { "_\($0)" } ?? ""
    return String(format: "%@_page_%03d%@.%@", baseName, pageNumber, suffixText, fileExtension)
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

    @Test("Image export suspends MainActor before reporting page progress")
    func exportKeepsMainActorResponsive() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "responsive_export.pdf")
        let outputDir = TestPDFGenerator.makeTempDirectory()
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDir)
        }

        var mainActorHeartbeat = false
        var heartbeatAtFirstProgress: Bool?
        Task { @MainActor in mainActorHeartbeat = true }

        _ = try await PDFImageExporter().exportPages(
            source: source,
            outputDirectory: outputDir,
            options: .init(format: .jpeg, dpi: 72, quality: 0.8),
            pageIndices: nil,
            progress: { _ in
                if heartbeatAtFirstProgress == nil {
                    heartbeatAtFirstProgress = mainActorHeartbeat
                }
            }
        )

        #expect(heartbeatAtFirstProgress == true)
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

    @Test("Deduplicates selected pages while preserving first-seen order")
    func deduplicatesPagesStably() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 3, filename: "export_duplicate.pdf")
        let outputDir = TestPDFGenerator.makeTempDirectory()
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDir)
        }

        var progressValues: [Double] = []
        let outputs = try await PDFImageExporter().exportPages(
            source: source,
            outputDirectory: outputDir,
            options: .init(format: .jpeg, dpi: 72, quality: 0.8),
            pageIndices: [2, 0, 2, 1, 0],
            progress: { progressValues.append($0) }
        )

        #expect(outputs.map(\.lastPathComponent) == [
            exportFilename(source: source, pageNumber: 3),
            exportFilename(source: source, pageNumber: 1),
            exportFilename(source: source, pageNumber: 2),
        ])
        #expect(progressValues.count == 3)
        #expect(progressValues.last == 1)
    }

    @Test("Duplicate selections count once toward the export limit")
    func appliesLimitAfterDeduplication() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "export_limit.pdf")
        let outputDir = TestPDFGenerator.makeTempDirectory()
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDir)
        }

        let outputs = try await PDFImageExporter().exportPages(
            source: source,
            outputDirectory: outputDir,
            options: .init(format: .jpeg, dpi: 72, quality: 0.8),
            pageIndices: Array(repeating: 0, count: 5_001),
            progress: { _ in }
        )

        #expect(outputs.count == 1)
    }

    @Test("Uses a suffix instead of overwriting an existing export")
    func suffixesExistingExport() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "export_existing.pdf")
        let outputDir = TestPDFGenerator.makeTempDirectory()
        let existingName = exportFilename(source: source, pageNumber: 1)
        let existing = outputDir.appending(component: existingName)
        let originalData = Data("original".utf8)
        try originalData.write(to: existing)
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDir)
        }

        let outputs = try await PDFImageExporter().exportPages(
            source: source,
            outputDirectory: outputDir,
            options: .init(format: .jpeg, dpi: 72, quality: 0.8),
            pageIndices: nil,
            progress: { _ in }
        )

        #expect(try Data(contentsOf: existing) == originalData)
        #expect(outputs.map(\.lastPathComponent) == [
            exportFilename(source: source, pageNumber: 1, suffix: 1),
        ])
        #expect(try FileManager.default.contentsOfDirectory(atPath: outputDir.path).count == 2)
    }

    @Test("Uses the lowest available suffix")
    func usesLowestAvailableSuffix() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "export_suffix.pdf")
        let outputDir = TestPDFGenerator.makeTempDirectory()
        let sentinel = Data("existing".utf8)
        let canonical = outputDir.appending(
            component: exportFilename(source: source, pageNumber: 1)
        )
        let firstSuffix = outputDir.appending(
            component: exportFilename(source: source, pageNumber: 1, suffix: 1)
        )
        try sentinel.write(to: canonical)
        try sentinel.write(to: firstSuffix)
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDir)
        }

        let outputs = try await PDFImageExporter().exportPages(
            source: source,
            outputDirectory: outputDir,
            options: .init(format: .jpeg, dpi: 72, quality: 0.8),
            pageIndices: nil,
            progress: { _ in }
        )

        #expect(outputs.map(\.lastPathComponent) == [
            exportFilename(source: source, pageNumber: 1, suffix: 2),
        ])
        #expect(try Data(contentsOf: canonical) == sentinel)
        #expect(try Data(contentsOf: firstSuffix) == sentinel)
    }

    @Test("Resolves each batch collision independently")
    func resolvesMixedBatchCollisions() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2, filename: "export_mixed.pdf")
        let outputDir = TestPDFGenerator.makeTempDirectory()
        let existing = outputDir.appending(
            component: exportFilename(source: source, pageNumber: 1)
        )
        let sentinel = Data("existing".utf8)
        try sentinel.write(to: existing)
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDir)
        }

        let outputs = try await PDFImageExporter().exportPages(
            source: source,
            outputDirectory: outputDir,
            options: .init(format: .jpeg, dpi: 72, quality: 0.8),
            pageIndices: nil,
            progress: { _ in }
        )

        #expect(outputs.map(\.lastPathComponent) == [
            exportFilename(source: source, pageNumber: 1, suffix: 1),
            exportFilename(source: source, pageNumber: 2),
        ])
        #expect(try Data(contentsOf: existing) == sentinel)
    }

    @Test("Handles a collision created after rendering")
    func handlesLateCollision() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "export_late.pdf")
        let outputDir = TestPDFGenerator.makeTempDirectory()
        let canonical = outputDir.appending(
            component: exportFilename(source: source, pageNumber: 1)
        )
        let sentinel = Data("late collision".utf8)
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDir)
        }

        var createdCollision = false
        let outputs = try await PDFImageExporter().exportPages(
            source: source,
            outputDirectory: outputDir,
            options: .init(format: .jpeg, dpi: 72, quality: 0.8),
            pageIndices: nil,
            progress: { value in
                if value == 1, !createdCollision {
                    try! sentinel.write(to: canonical)
                    createdCollision = true
                }
            }
        )

        #expect(outputs.map(\.lastPathComponent) == [
            exportFilename(source: source, pageNumber: 1, suffix: 1),
        ])
        #expect(try Data(contentsOf: canonical) == sentinel)
    }

    @Test("Treats a colliding directory as occupied")
    func preservesCollidingDirectory() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "export_directory.pdf")
        let outputDir = TestPDFGenerator.makeTempDirectory()
        let collision = outputDir.appending(
            component: exportFilename(source: source, pageNumber: 1)
        )
        try FileManager.default.createDirectory(at: collision, withIntermediateDirectories: false)
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDir)
        }

        let outputs = try await PDFImageExporter().exportPages(
            source: source,
            outputDirectory: outputDir,
            options: .init(format: .jpeg, dpi: 72, quality: 0.8),
            pageIndices: nil,
            progress: { _ in }
        )

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: collision.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(outputs.map(\.lastPathComponent) == [
            exportFilename(source: source, pageNumber: 1, suffix: 1),
        ])
    }

    @Test("Rendering failure leaves the output directory unchanged")
    func renderingFailureCreatesNoExports() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2, filename: "export_failure.pdf")
        let data = try Data(contentsOf: source)
        let document = try #require(MissingExportPagePDFDocument(data: data))
        document.inaccessiblePageIndex = 1
        let outputDir = TestPDFGenerator.makeTempDirectory()
        let existing = outputDir.appending(component: "sentinel.txt")
        let sentinel = Data("existing".utf8)
        try sentinel.write(to: existing)
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDir)
        }

        await #expect(throws: PDFwringerError.self) {
            _ = try await PDFImageExporter().exportPages(
                document: document,
                source: source,
                outputDirectory: outputDir,
                options: .init(format: .jpeg, dpi: 72, quality: 0.8),
                pageIndices: nil,
                progress: { _ in }
            )
        }

        #expect(try Data(contentsOf: existing) == sentinel)
        #expect(try FileManager.default.contentsOfDirectory(atPath: outputDir.path) == ["sentinel.txt"])
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
