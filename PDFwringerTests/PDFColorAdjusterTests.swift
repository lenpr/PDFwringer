import Testing
import PDFKit
import Foundation
import CoreGraphics

@Suite("PDFColorAdjuster")
@MainActor
struct PDFColorAdjusterTests {

    // MARK: - Identity settings

    @Test("Identity settings preserve document semantics")
    func identitySettingsPreserveDocument() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 3)
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "identity.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        let adjuster = PDFColorAdjuster()
        try await adjuster.adjust(
            source: source,
            destination: output,
            settings: .init(),
            pages: nil,
            progress: { _ in }
        )

        #expect(try Data(contentsOf: output) == Data(contentsOf: source))
        let sourceDocument = try #require(PDFDocument(url: source))
        let outputDocument = try #require(PDFDocument(url: output))
        #expect(outputDocument.pageCount == sourceDocument.pageCount)
        for index in 0..<sourceDocument.pageCount {
            #expect(outputDocument.page(at: index)?.string == sourceDocument.page(at: index)?.string)
        }
    }

    // MARK: - Non-identity settings

    @Test("Non-identity settings produces valid PDF with same page count")
    func nonIdentityProducesValidPDF() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 4)
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "adjusted.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        let adjuster = PDFColorAdjuster()
        try await adjuster.adjust(
            source: source,
            destination: output,
            settings: .init(brightness: 0.2, contrast: 1.5, saturation: 0.5),
            pages: nil,
            progress: { _ in }
        )

        let doc = PDFDocument(url: output)
        #expect(doc != nil)
        #expect(doc?.pageCount == 4)
    }

    @Test("Color adjustment suspends MainActor before reporting page progress")
    func colorAdjustmentKeepsMainActorResponsive() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "responsive_color.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "responsive_color_out.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        var mainActorHeartbeat = false
        var heartbeatAtFirstProgress: Bool?
        Task { @MainActor in mainActorHeartbeat = true }

        try await PDFColorAdjuster().adjust(
            source: source,
            destination: output,
            settings: .init(brightness: 0.1),
            pages: nil,
            dpi: 72,
            progress: { _ in
                if heartbeatAtFirstProgress == nil {
                    heartbeatAtFirstProgress = mainActorHeartbeat
                }
            }
        )

        #expect(heartbeatAtFirstProgress == true)
    }

    @Test("Specific page range only processes target pages")
    func specificPageRange() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 5)
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "partial.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        let adjuster = PDFColorAdjuster()
        try await adjuster.adjust(
            source: source,
            destination: output,
            settings: .init(brightness: 0.3, contrast: 1.0, saturation: 1.0),
            pages: [0, 2, 4],
            progress: { _ in }
        )

        let doc = PDFDocument(url: output)
        #expect(doc != nil)
        #expect(doc?.pageCount == 5)
    }

    @Test("Unselected pages preserve text, annotations, geometry, and rotation")
    func unselectedPagesPreserveSemantics() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2)
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "preserved.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        let sourceDocument = try #require(PDFDocument(url: source))
        sourceDocument.documentAttributes = [
            PDFDocumentAttribute.titleAttribute: "Semantic preservation"
        ]
        let selectedPage = try #require(sourceDocument.page(at: 0))
        let selectedAnnotation = PDFAnnotation(
            bounds: CGRect(x: 20, y: 20, width: 24, height: 24),
            forType: .text,
            withProperties: nil
        )
        selectedAnnotation.contents = "Rasterize me"
        selectedPage.addAnnotation(selectedAnnotation)

        let untouchedPage = try #require(sourceDocument.page(at: 1))
        untouchedPage.rotation = 90
        untouchedPage.setBounds(
            CGRect(x: 12, y: 18, width: 500, height: 650),
            for: .cropBox
        )
        let untouchedAnnotation = PDFAnnotation(
            bounds: CGRect(x: 30, y: 30, width: 24, height: 24),
            forType: .text,
            withProperties: nil
        )
        untouchedAnnotation.contents = "Keep me"
        untouchedPage.addAnnotation(untouchedAnnotation)
        #expect(sourceDocument.write(to: source))

        let expectedDocument = try #require(PDFDocument(url: source))
        let expectedSelected = try #require(expectedDocument.page(at: 0))
        let expectedUntouched = try #require(expectedDocument.page(at: 1))

        try await PDFColorAdjuster().adjust(
            source: source,
            destination: output,
            settings: .init(brightness: 0.2),
            pages: [0],
            dpi: 72,
            progress: { _ in }
        )

        let outputDocument = try #require(PDFDocument(url: output))
        let outputSelected = try #require(outputDocument.page(at: 0))
        let outputUntouched = try #require(outputDocument.page(at: 1))
        #expect(outputSelected.string?.isEmpty ?? true)
        #expect(!expectedSelected.annotations.isEmpty)
        #expect(outputSelected.annotations.isEmpty)
        #expect(outputUntouched.string == expectedUntouched.string)
        #expect(
            outputUntouched.annotations.compactMap(\.contents)
                == expectedUntouched.annotations.compactMap(\.contents)
        )
        #expect(outputUntouched.rotation == expectedUntouched.rotation)
        #expect(outputUntouched.bounds(for: .mediaBox) == expectedUntouched.bounds(for: .mediaBox))
        #expect(outputUntouched.bounds(for: .cropBox) == expectedUntouched.bounds(for: .cropBox))
        #expect(
            outputDocument.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
                == "Semantic preservation"
        )
    }

    // MARK: - adjustImage static method

    @Test("adjustImage with identity returns same image")
    func adjustImageIdentity() {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        defer { TestPDFGenerator.cleanup(source) }

        guard let doc = PDFRasterizer.openDocument(at: source),
              let page = doc.page(at: 1),
              let (image, _) = PDFRasterizer.render(page, dpi: 72, grayscale: false)
        else {
            Issue.record("Could not render test page")
            return
        }

        let result = PDFColorAdjuster.adjustImage(image, settings: .init())
        #expect(result === image)
    }

    @Test("adjustImage with zero saturation produces desaturated output")
    func adjustImageDesaturate() {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        defer { TestPDFGenerator.cleanup(source) }

        guard let doc = PDFRasterizer.openDocument(at: source),
              let page = doc.page(at: 1),
              let (image, _) = PDFRasterizer.render(page, dpi: 72, grayscale: false)
        else {
            Issue.record("Could not render test page")
            return
        }

        let result = PDFColorAdjuster.adjustImage(image, settings: .init(saturation: 0))
        #expect(result != nil)
        #expect(result!.width == image.width)
        #expect(result!.height == image.height)
    }

    @Test("adjustImage with extreme brightness changes dimensions are preserved")
    func adjustImageExtremeBrightness() {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        defer { TestPDFGenerator.cleanup(source) }

        guard let doc = PDFRasterizer.openDocument(at: source),
              let page = doc.page(at: 1),
              let (image, _) = PDFRasterizer.render(page, dpi: 72, grayscale: false)
        else {
            Issue.record("Could not render test page")
            return
        }

        let result = PDFColorAdjuster.adjustImage(image, settings: .init(brightness: 1.0))
        #expect(result != nil)
        #expect(result!.width == image.width)
        #expect(result!.height == image.height)
    }

    // MARK: - Error cases

    @Test("Invalid source throws cannotOpenDocument")
    func invalidSourceThrows() async throws {
        let bogus = URL.temporaryDirectory.appending(component: UUID().uuidString + "_ghost.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "out.pdf")
        defer { TestPDFGenerator.cleanup(output) }

        let adjuster = PDFColorAdjuster()
        await #expect(throws: PDFwringerError.self) {
            try await adjuster.adjust(
                source: bogus,
                destination: output,
                settings: .init(brightness: 0.5, contrast: 1.0, saturation: 1.0),
                pages: nil,
                progress: { _ in }
            )
        }
    }

    @Test("Corrupt source file throws cannotOpenDocument")
    func corruptSourceThrows() async throws {
        let corrupt = URL.temporaryDirectory.appending(component: UUID().uuidString + "_corrupt.pdf")
        try Data("not a pdf".utf8).write(to: corrupt)
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "out.pdf")
        defer {
            TestPDFGenerator.cleanup(corrupt)
            TestPDFGenerator.cleanup(output)
        }

        let adjuster = PDFColorAdjuster()
        await #expect(throws: PDFwringerError.self) {
            try await adjuster.adjust(
                source: corrupt,
                destination: output,
                settings: .init(brightness: 0.1, contrast: 1.0, saturation: 1.0),
                pages: nil,
                progress: { _ in }
            )
        }
    }

    @Test("Out-of-range page indices are rejected before writing")
    func outOfRangePageIndexThrows() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2)
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "out.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        await #expect(throws: PDFwringerError.self) {
            try await PDFColorAdjuster().adjust(
                source: source,
                destination: output,
                settings: .init(brightness: 0.1),
                pages: [2],
                progress: { _ in }
            )
        }
        #expect(!FileManager.default.fileExists(atPath: output.path(percentEncoded: false)))
    }

    @Test("Empty explicit page selection is rejected")
    func emptyPageSelectionThrows() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2)
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "out.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        await #expect(throws: PDFwringerError.self) {
            try await PDFColorAdjuster().adjust(
                source: source,
                destination: output,
                settings: .init(),
                pages: [],
                progress: { _ in }
            )
        }
        #expect(!FileManager.default.fileExists(atPath: output.path(percentEncoded: false)))
    }

    @Test("Missing page aborts without publishing partial output")
    func missingPageAborts() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2)
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "partial.pdf")
        let originalDestination = Data("existing destination".utf8)
        try originalDestination.write(to: output)
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        let document = try #require(PDFDocument(url: source))
        var removedPage = false
        await #expect(throws: PDFwringerError.self) {
            try await PDFColorAdjuster().adjust(
                document: document,
                source: source,
                destination: output,
                settings: .init(brightness: 0.1),
                pages: nil,
                progress: { progress in
                    if progress > 0, !removedPage {
                        document.removePage(at: 1)
                        removedPage = true
                    }
                }
            )
        }
        #expect(try Data(contentsOf: output) == originalDestination)
    }

    @Test("Identity adjustment saves the authoritative document after source replacement")
    func identityUsesAuthoritativeDocument() async throws {
        let authoritativeSource = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "authoritative.pdf")
        let replacedSource = TestPDFGenerator.makeRenderedPDF(pageCount: 1, filename: "replacement.pdf")
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "identity.pdf")
        defer {
            TestPDFGenerator.cleanup(authoritativeSource)
            TestPDFGenerator.cleanup(replacedSource)
            TestPDFGenerator.cleanup(output)
        }

        let document = try #require(PDFDocument(url: authoritativeSource))
        document.documentAttributes = [
            PDFDocumentAttribute.titleAttribute: "Authoritative title"
        ]
        let replacementDocument = try #require(PDFDocument(url: replacedSource))
        replacementDocument.documentAttributes = [
            PDFDocumentAttribute.titleAttribute: "Replacement title"
        ]
        #expect(replacementDocument.write(to: replacedSource))

        try await PDFColorAdjuster().adjust(
            document: document,
            source: replacedSource,
            destination: output,
            settings: .init(),
            pages: nil,
            progress: { _ in }
        )

        let outputDocument = try #require(PDFDocument(url: output))
        #expect(
            outputDocument.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
                == "Authoritative title"
        )
    }

    // MARK: - Progress

    @Test("Reports progress monotonically reaching 1.0")
    func progressReachesCompletion() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 5)
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "progress.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        var progressValues: [Double] = []
        let adjuster = PDFColorAdjuster()
        try await adjuster.adjust(
            source: source,
            destination: output,
            settings: .init(brightness: 0.1, contrast: 1.2, saturation: 0.8),
            pages: nil,
            progress: { p in progressValues.append(p) }
        )

        #expect(!progressValues.isEmpty)
        #expect(progressValues.last == 1.0)

        for i in 1..<progressValues.count {
            #expect(progressValues[i] >= progressValues[i - 1])
        }
    }

    // MARK: - Custom DPI and quality

    @Test("Higher DPI produces larger output")
    func higherDPIProducesLargerFile() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 2)
        let outputLow = TestPDFGenerator.makeTempDirectory().appending(component: "low_dpi.pdf")
        let outputHigh = TestPDFGenerator.makeTempDirectory().appending(component: "high_dpi.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputLow)
            TestPDFGenerator.cleanup(outputHigh)
        }

        let adjuster = PDFColorAdjuster()
        let settings = PDFColorAdjuster.Settings(brightness: 0.1, contrast: 1.2, saturation: 1.0)

        try await adjuster.adjust(source: source, destination: outputLow, settings: settings, pages: nil, dpi: 72, quality: 0.5, progress: { _ in })
        try await adjuster.adjust(source: source, destination: outputHigh, settings: settings, pages: nil, dpi: 300, quality: 0.9, progress: { _ in })

        let lowSize = try FileManager.default.attributesOfItem(atPath: outputLow.path(percentEncoded: false))[.size] as! Int64
        let highSize = try FileManager.default.attributesOfItem(atPath: outputHigh.path(percentEncoded: false))[.size] as! Int64

        #expect(highSize > lowSize)
    }
}
