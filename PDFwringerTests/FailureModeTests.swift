import Testing
import PDFKit
import Foundation

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

    // MARK: - Corrupt/invalid files in merge

    @Test("Concatenator reports corrupt file in skippedFiles")
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
        let result = try await concatenator.concatenate(
            sources: [valid, corrupt],
            destination: output,
            progress: { _ in }
        )

        #expect(result.skippedFiles.count == 1)
        #expect(result.skippedFiles[0].contains("corrupt"))
        #expect(result.outputPageCount == 2)
    }

    @Test("Concatenator with all corrupt files throws emptyFileList")
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
            if case .emptyFileList = error { } else {
                Issue.record("Expected emptyFileList, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Write failures

    @Test("Metadata write to unwritable destination throws")
    func metadataWriteFailure() throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 1)
        let unwritable = URL(filePath: "/nonexistent_dir/output.pdf")
        defer { TestPDFGenerator.cleanup(source) }

        let editor = PDFMetadataEditor()
        #expect(throws: (any Error).self) {
            try editor.write(metadata: .empty, source: source, destination: unwritable)
        }
    }

    @Test("Splitter with all out-of-range pages produces minimal output or fails")
    func splitterOutOfRange() async throws {
        let source = TestPDFGenerator.makeRenderedPDF(pageCount: 3)
        let output = TestPDFGenerator.makeTempDirectory().appending(component: "out.pdf")
        defer {
            TestPDFGenerator.cleanup(source)
            TestPDFGenerator.cleanup(output)
        }

        let splitter = PDFSplitter()
        do {
            let results = try await splitter.split(
                source: source,
                mode: .keepPages([10, 20, 30]),
                destination: output,
                progress: { _ in }
            )
            // PDFKit always writes at least 1 page; verify no requested pages made it
            if let doc = PDFDocument(url: results[0]) {
                #expect(doc.pageCount <= 1)
            }
        } catch {
            // Throwing is acceptable
        }
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
        #expect(vm.state == .landing)
    }

    // MARK: - Drag-and-drop edge cases

    @Test("handleDrop with all invalid files shows error")
    func handleDropAllInvalid() {
        let corrupt1 = URL.temporaryDirectory.appending(component: UUID().uuidString + "_bad1.pdf")
        let corrupt2 = URL.temporaryDirectory.appending(component: UUID().uuidString + "_bad2.pdf")
        try! Data("garbage".utf8).write(to: corrupt1)
        try! Data("garbage".utf8).write(to: corrupt2)
        defer {
            TestPDFGenerator.cleanup(corrupt1)
            TestPDFGenerator.cleanup(corrupt2)
        }

        let vm = AppViewModel()
        vm.handleDrop([corrupt1, corrupt2])

        // Multiple corrupt files → multiFile state with empty items list filtered out,
        // or single corrupt file → error alert
        // Since PDFFileItem.from(urls:) filters out non-loadable PDFs, the result is empty
        #expect(vm.state == .landing)
    }

    @Test("handleDrop with zero-byte file ignores it")
    func handleDropZeroByteFile() {
        let empty = URL.temporaryDirectory.appending(component: UUID().uuidString + "_empty.pdf")
        try! Data().write(to: empty)
        defer { TestPDFGenerator.cleanup(empty) }

        let vm = AppViewModel()
        vm.handleDrop([empty])

        // Zero-byte file can't be loaded as PDF → error
        #expect(vm.showErrorAlert == true || vm.state == .landing)
    }

    @Test("handleDrop with mix of valid and invalid drops valid only")
    func handleDropMixedValidity() {
        let valid = TestPDFGenerator.makeRenderedPDF(pageCount: 2)
        let corrupt = URL.temporaryDirectory.appending(component: UUID().uuidString + "_bad.pdf")
        try! Data("not a pdf".utf8).write(to: corrupt)
        defer {
            TestPDFGenerator.cleanup(valid)
            TestPDFGenerator.cleanup(corrupt)
        }

        let vm = AppViewModel()
        vm.handleDrop([valid, corrupt])

        // With 2 URLs, handleDrop calls loadMultipleFiles which uses PDFFileItem.from(urls:)
        // which filters out the corrupt one — should result in multiFile with 1 item,
        // or since only 1 valid, could be singleFile
        if case .multiFile(let items) = vm.state {
            #expect(items.count == 1)
        } else if case .singleFile = vm.state {
            // Also acceptable — implementation may special-case single valid result
        } else {
            Issue.record("Expected multiFile or singleFile state, got \(vm.state)")
        }
    }

    @Test("handleDrop with non-PDF extension files is ignored")
    func handleDropNonPDFExtension() {
        let txt = URL.temporaryDirectory.appending(component: UUID().uuidString + "_file.txt")
        try! Data("hello".utf8).write(to: txt)
        defer { TestPDFGenerator.cleanup(txt) }

        let vm = AppViewModel()
        vm.handleDrop([txt])

        #expect(vm.state == .landing)
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
