import Testing
import PDFKit
import Foundation

@MainActor
private func expectPermissionsDenied(
    _ operation: () async throws -> Void
) async {
    do {
        try await operation()
        Issue.record("Expected documentPermissionsDenied")
    } catch PDFwringerError.documentPermissionsDenied {
        // Expected.
    } catch {
        Issue.record("Expected documentPermissionsDenied, got \(error)")
    }
}

@Suite("Failure Modes")
@MainActor
struct FailureModeTests {

    // MARK: - Locked PDF handling

    @Test("Concatenator throws documentIsLocked for locked PDF")
    func concatenatorLockedPDF() async throws {
        let normal = TestPDFGenerator.makeRenderedPDF(pageCount: 2)
        let locked = makeLockedPDF()
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "out.pdf")
        defer {
            TestPDFGenerator.cleanup(normal)
            TestPDFGenerator.cleanup(locked)
            TestPDFGenerator.cleanup(output)
        }

        let concatenator = PDFConcatenator()
        do {
            try await concatenator.concatenate(
                sources: [normal, locked],
                destination: output,
                progress: { _ in }
            )
            Issue.record("Expected error")
        } catch let error as PDFwringerError {
            if case .documentIsLocked = error { } else {
                Issue.record("Expected documentIsLocked, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Splitter throws documentIsLocked for locked PDF")
    func splitterLockedPDF() async throws {
        let locked = makeLockedPDF()
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "out.pdf")
        defer {
            TestPDFGenerator.cleanup(locked)
            TestPDFGenerator.cleanup(output)
        }

        let splitter = PDFSplitter()
        do {
            _ = try await splitter.split(
                source: locked,
                mode: .keepPages([0]),
                destination: output,
                progress: { _ in }
            )
            Issue.record("Expected error")
        } catch let error as PDFwringerError {
            if case .documentIsLocked = error { } else {
                Issue.record("Expected documentIsLocked, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Rotator throws documentIsLocked for locked PDF")
    func rotatorLockedPDF() async throws {
        let locked = makeLockedPDF()
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "out.pdf")
        defer {
            TestPDFGenerator.cleanup(locked)
            TestPDFGenerator.cleanup(output)
        }

        let rotator = PDFRotator()
        do {
            try await rotator.rotate(
                source: locked,
                destination: output,
                angle: .ninety,
                pageIndices: nil,
                progress: { _ in }
            )
            Issue.record("Expected error")
        } catch let error as PDFwringerError {
            if case .documentIsLocked = error { } else {
                Issue.record("Expected documentIsLocked, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Encrypted PDF permission enforcement

    @Test("Derived and mutating workflows honor PDF permissions")
    func restrictedWorkflowsFailClosed() async throws {
        let source = TestPDFGenerator.makePermissionRestrictedPDF(
            permissions: 0,
            filename: "fully-restricted.pdf"
        )
        let outputDirectory = TestPDFGenerator.makeTempDirectory()
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(outputDirectory)
        }

        let document = try #require(PDFDocument(url: source))
        #expect(document.isEncrypted)
        #expect(!document.isLocked)
        #expect(!document.allowsCopying)
        #expect(!document.allowsDocumentChanges)
        #expect(!document.allowsDocumentAssembly)

        await expectPermissionsDenied {
            _ = try await PDFCompressor().compress(
                document: document,
                source: source,
                destination: outputDirectory.appending(component: "lossless.pdf"),
                level: .lossless,
                quality: .good,
                grayscale: false,
                progress: { _ in }
            )
        }
        await expectPermissionsDenied {
            _ = try await PDFCompressor().compress(
                document: document,
                source: source,
                destination: outputDirectory.appending(component: "raster.pdf"),
                level: .medium,
                quality: .good,
                grayscale: false,
                progress: { _ in }
            )
        }
        await expectPermissionsDenied {
            _ = try await PDFConcatenator().concatenate(
                sources: [source],
                destination: outputDirectory.appending(component: "merged.pdf"),
                progress: { _ in }
            )
        }
        await expectPermissionsDenied {
            _ = try await PDFSplitter().split(
                document: document,
                source: source,
                mode: .keepPages([0]),
                destination: outputDirectory.appending(component: "extracted.pdf"),
                progress: { _ in }
            )
        }
        await expectPermissionsDenied {
            _ = try await PDFImageExporter().exportPages(
                document: document,
                source: source,
                outputDirectory: outputDirectory,
                options: .init(format: .png, dpi: 72),
                pageIndices: nil,
                progress: { _ in }
            )
        }
        await expectPermissionsDenied {
            try await PDFColorAdjuster().adjust(
                document: document,
                source: source,
                destination: outputDirectory.appending(component: "adjusted.pdf"),
                settings: .init(brightness: 0.1),
                pages: nil,
                dpi: 72,
                progress: { _ in }
            )
        }
        await expectPermissionsDenied {
            try await PDFMetadataEditor().write(
                metadata: .empty,
                document: document,
                source: source,
                destination: outputDirectory.appending(component: "metadata.pdf")
            )
        }
        await expectPermissionsDenied {
            try await PDFMetadataEditor().write(
                metadata: .empty,
                document: document,
                source: source,
                destination: outputDirectory.appending(component: "flattened.pdf"),
                flattenAnnotations: true
            )
        }
        await expectPermissionsDenied {
            _ = try PDFCropper().crop(
                document: document,
                indices: [0],
                top: 1,
                bottom: 1,
                left: 1,
                right: 1
            )
        }
        await expectPermissionsDenied {
            _ = try PDFRotator().rotate(
                document: document,
                angle: .ninety,
                pageIndices: nil,
                progress: { _ in }
            )
        }

        let outputs = try FileManager.default.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: nil
        )
        #expect(outputs.isEmpty)
    }

    @Test("Permission requirements distinguish copying from modification")
    func permissionRequirementsAreSpecific() async throws {
        let source = TestPDFGenerator.makePermissionRestrictedPDF(
            permissions: PDFAccessPermissions.allowsContentCopying.rawValue,
            filename: "copy-only.pdf"
        )
        defer { TestPDFGenerator.cleanup(source) }

        let document = try #require(PDFDocument(url: source))
        #expect(document.allowsCopying)
        #expect(!document.allowsDocumentChanges)
        #expect(!document.allowsDocumentAssembly)
        try PDFPermissionPolicy.require(.copyContent, for: document)
        await expectPermissionsDenied {
            try PDFPermissionPolicy.require(.changeDocument, for: document)
        }
        await expectPermissionsDenied {
            try PDFPermissionPolicy.require(.assembleDocument, for: document)
        }
    }

    // MARK: - Corrupt/invalid files in merge

    @Test("Concatenator rejects a corrupt selected file without publishing")
    func concatenatorCorruptFile() async throws {
        let valid = TestPDFGenerator.makeRenderedPDF(pageCount: 2)
        let corrupt = URL.temporaryDirectory.appending(component: UUID().uuidString + "_corrupt.pdf")
        try Data("not a pdf".utf8).write(to: corrupt)
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "merged.pdf")
        defer {
            TestPDFGenerator.cleanup(valid)
            TestPDFGenerator.cleanup(corrupt)
            TestPDFGenerator.cleanup(output)
        }

        let concatenator = PDFConcatenator()
        await #expect(throws: PDFwringerError.self) {
            try await concatenator.concatenate(
                sources: [valid, corrupt],
                destination: output,
                progress: { _ in }
            )
        }
        #expect(!FileManager.default.fileExists(atPath: output.path(percentEncoded: false)))
    }

    @Test("Concatenator with all corrupt files throws cannotOpenDocument")
    func concatenatorAllCorrupt() async throws {
        let corrupt1 = URL.temporaryDirectory.appending(component: UUID().uuidString + "_bad1.pdf")
        let corrupt2 = URL.temporaryDirectory.appending(component: UUID().uuidString + "_bad2.pdf")
        try Data("nope".utf8).write(to: corrupt1)
        try Data("also nope".utf8).write(to: corrupt2)
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "out.pdf")
        defer {
            TestPDFGenerator.cleanup(corrupt1)
            TestPDFGenerator.cleanup(corrupt2)
            TestPDFGenerator.cleanup(output)
        }

        let concatenator = PDFConcatenator()
        do {
            try await concatenator.concatenate(
                sources: [corrupt1, corrupt2],
                destination: output,
                progress: { _ in }
            )
            Issue.record("Expected error")
        } catch let error as PDFwringerError {
            if case .cannotOpenDocument = error { } else {
                Issue.record("Expected cannotOpenDocument, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Write failures

    @Test("Metadata write to unwritable destination throws")
    func metadataWriteFailure() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        let unwritable = URL(filePath: "/nonexistent_dir/output.pdf")
        defer { TestPDFGenerator.cleanup(source) }

        let editor = PDFMetadataEditor()
        do {
            try await editor.write(metadata: .empty, source: source, destination: unwritable)
            Issue.record("Expected error")
        } catch let error as PDFwringerError {
            guard case .cannotWriteOutput = error else {
                Issue.record("Expected cannotWriteOutput, got \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Splitter rejects an entirely out-of-range page selection")
    func splitterOutOfRange() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 3)
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "out.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        do {
            _ = try await PDFSplitter().split(
                source: source,
                mode: .keepPages([10, 20, 30]),
                destination: output,
                progress: { _ in }
            )
            Issue.record("Expected invalidPageRange")
        } catch let error as PDFwringerError {
            guard case .invalidPageRange(let detail) = error else {
                Issue.record("Expected invalidPageRange, got \(error)")
                return
            }
            #expect(detail == "no valid pages in range")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(!FileManager.default.fileExists(atPath: output.path(percentEncoded: false)))
    }

    // MARK: - AppViewModel error state

    @Test("loadSingleFile with corrupt file shows error")
    func appViewModelCorruptFile() {
        let corrupt = URL.temporaryDirectory.appending(component: UUID().uuidString + "_bad.pdf")
        try! Data("garbage".utf8).write(to: corrupt)
        defer { TestPDFGenerator.cleanup(corrupt) }

        let vm = AppViewModel()
        vm.loadSingleFile(corrupt)

        #expect(vm.showErrorAlert == true)
        #expect(vm.errorMessage.contains("bad"))
        #expect(vm.isLanding)
    }

    // MARK: - Drag-and-drop edge cases

    @Test("Multiple invalid PDFs finish with an error and no workflow")
    func multipleInvalidFiles() async {
        let corrupt1 = URL.temporaryDirectory.appending(component: UUID().uuidString + "_bad1.pdf")
        let corrupt2 = URL.temporaryDirectory.appending(component: UUID().uuidString + "_bad2.pdf")
        try! Data("garbage".utf8).write(to: corrupt1)
        try! Data("garbage".utf8).write(to: corrupt2)
        defer {
            TestPDFGenerator.cleanup(corrupt1)
            TestPDFGenerator.cleanup(corrupt2)
        }

        let vm = AppViewModel()
        let intake = vm.loadMultipleFiles([corrupt1, corrupt2])
        await intake.value

        #expect(vm.showErrorAlert)
        #expect(vm.errorMessage == PDFwringerError.cannotOpenDocument.localizedDescription)
        #expect(vm.isLanding)
    }

    @Test("handleDrop with zero-byte file ignores it")
    func handleDropZeroByteFile() {
        let empty = URL.temporaryDirectory.appending(component: UUID().uuidString + "_empty.pdf")
        try! Data().write(to: empty)
        defer { TestPDFGenerator.cleanup(empty) }

        let vm = AppViewModel()
        vm.handleDrop([empty])

        // Zero-byte file can't be loaded as PDF → error
        #expect(vm.showErrorAlert)
        #expect(vm.isLanding)
    }

    @Test("handleDrop with mix of valid and invalid drops valid only")
    func handleDropMixedValidity() async throws {
        let valid = TestPDFGenerator.makeRenderedPDF(pageCount: 2, filename: "valid_mix.pdf")
        let corrupt = URL.temporaryDirectory.appending(component: UUID().uuidString + "_corrupt.pdf")
        try! Data("not a pdf".utf8).write(to: corrupt)
        defer {
            TestPDFGenerator.cleanup(valid)
            TestPDFGenerator.cleanup(corrupt)
        }

        let vm = AppViewModel()
        vm.handleDrop([valid, corrupt])

        // Wait for async loadMultipleFiles to complete
        for _ in 0..<100 {
            if case .landing = vm.state {
                try await Task.sleep(for: .milliseconds(50))
            } else { break }
        }

        // Routing happens after validation, so the one readable PDF opens normally.
        if case .singleFile(let loadedURL, let document) = vm.state {
            #expect(loadedURL == valid)
            #expect(document.pageCount == 2)
        } else {
            Issue.record("Expected singleFile state, got \(vm.state)")
        }
    }

    @Test("handleDrop with non-PDF extension files is ignored")
    func handleDropNonPDFExtension() {
        let txt = URL.temporaryDirectory.appending(component: UUID().uuidString + "_file.txt")
        try! Data("hello".utf8).write(to: txt)
        defer { TestPDFGenerator.cleanup(txt) }

        let vm = AppViewModel()
        vm.handleDrop([txt])

        #expect(vm.isLanding)
    }

    @Test("PDFFileItem.from filters out non-loadable URLs")
    func fileItemFromFiltersCorrupt() {
        let valid = TestPDFGenerator.makeRenderedPDF(pageCount: 2)
        let corrupt = URL.temporaryDirectory.appending(component: UUID().uuidString + "_corrupt.pdf")
        try! Data("junk".utf8).write(to: corrupt)
        defer {
            TestPDFGenerator.cleanup(valid)
            TestPDFGenerator.cleanup(corrupt)
        }

        let items = PDFFileItem.from(urls: [valid, corrupt])
        #expect(items.count == 1)
    }

    // MARK: - Helpers

    private func makeLockedPDF() -> URL {
        let doc = PDFDocument()
        doc.insert(PDFPage(), at: 0)
        let url = URL.temporaryDirectory.appending(component: UUID().uuidString + "_locked.pdf")
        doc.write(to: url, withOptions: [
            .ownerPasswordOption: "owner123",
            .userPasswordOption: "user123"
        ])
        return url
    }
}
