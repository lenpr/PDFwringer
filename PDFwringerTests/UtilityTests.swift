import Testing
import Foundation

@Suite("Utilities")
@MainActor
struct UtilityTests {

    // MARK: - AtomicFileWriter

    @Test("AtomicFileWriter writes content to destination")
    func atomicWriteSuccess() throws {
        let dest = URL.temporaryDirectory.appending(component: UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: dest) }

        try AtomicFileWriter.write(to: dest) { tempURL in
            try Data("hello".utf8).write(to: tempURL)
            return true
        }

        let data = try Data(contentsOf: dest)
        #expect(String(data: data, encoding: .utf8) == "hello")
    }

    @Test("AtomicFileWriter cleans up on block returning false")
    func atomicWriteBlockFalse() {
        let dest = URL.temporaryDirectory.appending(component: UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: dest) }

        do {
            try AtomicFileWriter.write(to: dest) { tempURL in
                try Data("data".utf8).write(to: tempURL)
                return false
            }
            Issue.record("Expected error")
        } catch let error as PDFwringerError {
            if case .cannotWriteOutput = error { } else {
                Issue.record("Expected cannotWriteOutput, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(!FileManager.default.fileExists(atPath: dest.path(percentEncoded: false)))
    }

    @Test("AtomicFileWriter cleans up on block throwing")
    func atomicWriteBlockThrows() {
        let dest = URL.temporaryDirectory.appending(component: UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: dest) }

        struct TestError: Error {}

        do {
            try AtomicFileWriter.write(to: dest) { _ in
                throw TestError()
            }
            Issue.record("Expected error")
        } catch is TestError {
            // expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(!FileManager.default.fileExists(atPath: dest.path(percentEncoded: false)))
    }

    // MARK: - Formatting

    @Test("Formatting.fileSize formats bytes correctly")
    func fileSizeFormatting() {
        #expect(Formatting.fileSize(0) == "Zero KB")
        #expect(Formatting.fileSize(1024).contains("1"))
        #expect(Formatting.fileSize(1_048_576).contains("1"))
        #expect(Formatting.fileSize(1_048_576).contains("MB"))
    }
}
