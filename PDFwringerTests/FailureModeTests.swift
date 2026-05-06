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
