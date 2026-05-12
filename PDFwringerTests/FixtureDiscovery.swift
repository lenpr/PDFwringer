import Foundation
import PDFKit

/// Discovers and categorizes PDF fixture files for integration testing.
/// Fixtures are located relative to this source file at `Fixtures/`.
enum FixtureDiscovery {

    /// A discovered PDF fixture with metadata for parameterized testing.
    struct Fixture: Sendable, CustomStringConvertible {
        let url: URL
        let filename: String
        let category: String
        let fileSize: Int64
        let pageCount: Int

        var description: String { "\(category)/\(filename)" }

        var isSmall: Bool { fileSize < 100_000 }
        var isLarge: Bool { fileSize > 5_000_000 }
        var isMultipage: Bool { pageCount > 10 }
    }

    /// Root directory containing all fixture PDFs.
    static let fixturesDirectory: URL = {
        // Derive from this file's compile-time path
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile.deletingLastPathComponent().appending(component: "Fixtures")
    }()

    /// Returns true if there are any fixture PDFs available for testing.
    static var hasFixtures: Bool {
        !allFixtures.isEmpty
    }

    /// All discovered PDF fixtures, recursively found in the Fixtures directory.
    /// Cached after first access within a test run.
    static let allFixtures: [Fixture] = {
        discover()
    }()

    /// Fixtures filtered by category subdirectory name.
    static func fixtures(in category: String) -> [Fixture] {
        allFixtures.filter { $0.category == category }
    }

    /// Fixtures that can be opened successfully (valid, not locked).
    static let openableFixtures: [Fixture] = {
        allFixtures.filter { fixture in
            guard let doc = PDFDocument(url: fixture.url) else { return false }
            return !doc.isLocked && doc.pageCount > 0
        }
    }()

    /// Fixtures that can be opened AND modified (no permission restrictions).
    /// Use this for tests that rotate, strip annotations, or otherwise mutate content.
    static let modifiableFixtures: [Fixture] = {
        allFixtures.filter { fixture in
            guard let doc = PDFDocument(url: fixture.url) else { return false }
            guard !doc.isLocked && doc.pageCount > 0 else { return false }
            // Check if the PDF allows modifications
            return doc.allowsCopying && doc.allowsCommenting
        }
    }()

    /// Fixtures that are password-protected or otherwise locked.
    static let lockedFixtures: [Fixture] = {
        allFixtures.filter { fixture in
            guard let doc = PDFDocument(url: fixture.url) else { return false }
            return doc.isLocked
        }
    }()

    /// Fixtures that cannot be opened at all (corrupt, not valid PDF).
    static let corruptFixtures: [Fixture] = {
        allFixtures.filter { PDFDocument(url: $0.url) == nil }
    }()

    // MARK: - Discovery

    private static func discover() -> [Fixture] {
        let fm = FileManager.default
        let root = fixturesDirectory

        guard fm.fileExists(atPath: root.path(percentEncoded: false)) else { return [] }

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var fixtures: [Fixture] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "pdf" else { continue }

            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }

            let fileSize = Int64(values?.fileSize ?? 0)

            // Determine category from immediate parent directory
            let parent = fileURL.deletingLastPathComponent()
            let category: String
            if parent.standardizedFileURL == root.standardizedFileURL {
                category = "root"
            } else {
                category = parent.lastPathComponent
            }

            // Try to get page count (0 if can't open)
            let pageCount: Int
            if let doc = PDFDocument(url: fileURL) {
                pageCount = doc.isLocked ? 0 : doc.pageCount
            } else {
                pageCount = 0
            }

            fixtures.append(Fixture(
                url: fileURL,
                filename: fileURL.lastPathComponent,
                category: category,
                fileSize: fileSize,
                pageCount: pageCount
            ))
        }

        return fixtures.sorted { $0.filename < $1.filename }
    }

    // MARK: - Test Helpers

    /// Creates a temporary output URL for fixture test results.
    static func outputURL(for fixture: Fixture, suffix: String) -> URL {
        let dir = URL.temporaryDirectory.appending(component: "PDFwringer_fixture_tests")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = fixture.url.deletingPathExtension().lastPathComponent + suffix
        return dir.appending(component: name)
    }

    /// Cleans up all fixture test output files.
    static func cleanupOutputs() {
        let dir = URL.temporaryDirectory.appending(component: "PDFwringer_fixture_tests")
        try? FileManager.default.removeItem(at: dir)
    }

    /// Validates that a PDF at the given URL is readable with the expected page count.
    @MainActor
    static func validateOutput(at url: URL, expectedPages: Int? = nil) -> (valid: Bool, pageCount: Int) {
        guard let doc = PDFDocument(url: url) else { return (false, 0) }
        guard !doc.isLocked else { return (false, 0) }
        let pages = doc.pageCount
        if let expected = expectedPages {
            return (pages == expected, pages)
        }
        return (pages > 0, pages)
    }
}
