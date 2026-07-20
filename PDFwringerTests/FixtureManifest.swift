import Foundation
import PDFKit
import Testing

/// Fixture manifest: records expected properties per fixture for precise assertion.
/// Tests validate against explicit expectations rather than just "output opens."
@MainActor
enum FixtureManifest {

    struct ExpectedProperties {
        let pageCount: Int
        let hasText: Bool
        let hasExtractableText: Bool
        let hasAnnotations: Bool
        let isEncrypted: Bool
        let allowsDocumentChanges: Bool
        let canOpen: Bool
        let category: String
        let notes: String

        init(
            pages: Int,
            text: Bool = true,
            extractableText: Bool? = nil,
            annotations: Bool = false,
            encrypted: Bool = false,
            allowsDocumentChanges: Bool = true,
            canOpen: Bool = true,
            category: String = "smoke",
            notes: String = ""
        ) {
            self.pageCount = pages
            self.hasText = text
            self.hasExtractableText = extractableText ?? text
            self.hasAnnotations = annotations
            self.isEncrypted = encrypted
            self.allowsDocumentChanges = allowsDocumentChanges
            self.canOpen = canOpen
            self.category = category
            self.notes = notes
        }
    }

    /// Known fixture properties. Update when adding new fixtures.
    static let manifest: [String: ExpectedProperties] = [
        // Smoke / basic
        "tracemonkey.pdf": .init(pages: 14, text: true, category: "smoke", notes: "PDF.js baseline, text+vector+fonts"),
        "pdf20_simple.pdf": .init(pages: 1, text: true, category: "smoke", notes: "Minimal PDF 2.0"),
        "pdf20_utf8.pdf": .init(pages: 1, text: true, category: "smoke", notes: "PDF 2.0 UTF-8 strings"),
        "pdf20_incremental.pdf": .init(pages: 1, text: true, category: "smoke", notes: "PDF 2.0 via incremental save"),
        "pdf20_offset_start.pdf": .init(pages: 1, text: true, category: "smoke", notes: "Non-zero PDF start offset"),

        // Fonts, color, images
        "rotated.pdf": .init(pages: 1, text: true, category: "fonts_color", notes: "Pre-rotated pages"),
        "vertical.pdf": .init(pages: 3, text: true, category: "fonts_color", notes: "CJK vertical writing"),
        "zapfdingbats.pdf": .init(pages: 2, text: true, annotations: true, category: "fonts_color", notes: "Standard 14 symbol font"),
        "transparent.pdf": .init(pages: 1, text: false, category: "fonts_color", notes: "Transparency/compositing"),
        "xobject_image.pdf": .init(pages: 1, text: false, category: "fonts_color", notes: "Image XObject"),
        "cmyk_image.pdf": .init(pages: 1, text: false, category: "fonts_color", notes: "CMYK color space image"),
        "pdf20_bpc_image.pdf": .init(pages: 1, text: false, extractableText: true, category: "fonts_color", notes: "Black point compensation"),

        // Annotations
        "text_widget.pdf": .init(pages: 1, annotations: true, category: "annotations", notes: "Text form widget"),
        "choice_widget.pdf": .init(pages: 1, annotations: true, category: "annotations", notes: "Dropdown/list widget"),
        "button_widget.pdf": .init(pages: 1, annotations: true, category: "annotations", notes: "Button/check/radio widget"),
        "highlight.pdf": .init(pages: 1, annotations: true, category: "annotations", notes: "Highlight markup"),
        "freetext.pdf": .init(pages: 1, annotations: true, category: "annotations", notes: "Free-text annotation"),
        "line_no_appearance.pdf": .init(pages: 1, annotations: true, category: "annotations", notes: "Missing appearance stream"),
        "fileattachment.pdf": .init(pages: 1, annotations: true, category: "annotations", notes: "File attachment annotation"),

        // Forms
        "pdflatex_forms.pdf": .init(pages: 1, text: true, annotations: true, category: "forms", notes: "LaTeX-generated form"),
        "with_attachment.pdf": .init(pages: 1, text: true, category: "forms", notes: "Embedded file attachment"),
        "irs_w9.pdf": .init(pages: 6, text: true, annotations: true, category: "forms", notes: "IRS fillable form"),

        // Security
        "password_protected.pdf": .init(pages: 1, encrypted: true, allowsDocumentChanges: false, canOpen: false, category: "security", notes: "Password: openpassword"),
        "sechandler.pdf": .init(pages: 1, text: true, extractableText: false, annotations: true, encrypted: true, category: "security", notes: "Permission-restricted, no copying or assembly allowed"),

        // Scanned
        "hubbard_ocr.pdf": .init(pages: 1, text: true, category: "scanned", notes: "Scanned with OCR text layer"),
        "hubbard_no_ocr.pdf": .init(pages: 1, text: false, category: "scanned", notes: "Scanned without OCR — image only"),
        "usgs_orthoimagery.pdf": .init(pages: 4, text: true, category: "scanned", notes: "USGS brochure with maps"),

        // Mixed
        "cropped_rotated_scaled.pdf": .init(pages: 4, text: true, annotations: true, category: "mixed", notes: "Various page box transformations"),
        "noembed_jis7.pdf": .init(pages: 1, text: true, category: "mixed", notes: "Japanese non-embedded font"),
        "pdf20_utf8_annotation.pdf": .init(pages: 1, text: true, extractableText: false, annotations: true, category: "mixed", notes: "Thai UTF-8 annotation"),
        "pdf20_output_intent.pdf": .init(pages: 2, text: true, category: "mixed", notes: "Page-level output intent"),

        // Large
        "fdsys_architecture.pdf": .init(pages: 87, text: true, category: "large", notes: "87-page government document"),

        // Quarantine (may not open cleanly)
        "poppler_fuzzed.pdf": .init(pages: 1, text: false, annotations: true, category: "quarantine", notes: "Fuzzed Poppler regression; opens in current PDFKit"),
        "ghostscript_fuzzed.pdf": .init(pages: 1, text: false, category: "quarantine", notes: "Fuzzed Ghostscript regression; opens in current PDFKit"),
        "pdfbox_regression.pdf": .init(pages: 1, text: false, category: "quarantine", notes: "PDFBox parser regression; opens in current PDFKit"),
        "redhat_regression.pdf": .init(pages: 0, text: false, canOpen: false, category: "quarantine", notes: "RedHat security regression"),
    ]

    /// Returns expected properties for a fixture, or nil if not in manifest.
    static func expected(for fixture: FixtureDiscovery.Fixture) -> ExpectedProperties? {
        manifest[fixture.filename]
    }
}

// MARK: - Manifest Validation Tests

@Suite("Fixture Manifest Validation")
@MainActor
struct FixtureManifestTests {

    @Test("All fixtures match manifest page count", arguments: FixtureDiscovery.allFixtures)
    func pageCountMatchesManifest(fixture: FixtureDiscovery.Fixture) throws {
        let expected = try #require(FixtureManifest.expected(for: fixture))
        guard expected.canOpen else { return } // Can't check page count of unopenable PDFs

        #expect(fixture.pageCount == expected.pageCount,
                "Page count mismatch for \(fixture.filename): expected \(expected.pageCount), got \(fixture.pageCount)")
    }

    @Test("Manifest openability expectations match reality", arguments: FixtureDiscovery.allFixtures)
    func openabilityMatchesManifest(fixture: FixtureDiscovery.Fixture) throws {
        let expected = try #require(FixtureManifest.expected(for: fixture))

        let canActuallyOpen = if let document = PDFDocument(url: fixture.url) {
            !document.isLocked && document.pageCount > 0
        } else {
            false
        }
        #expect(
            canActuallyOpen == expected.canOpen,
            "Openability mismatch for \(fixture.filename): expected \(expected.canOpen), got \(canActuallyOpen)"
        )
    }

    @Test("Manifest annotation expectations match reality", arguments: FixtureDiscovery.openableFixtures)
    func annotationStatusMatchesManifest(fixture: FixtureDiscovery.Fixture) throws {
        let expected = try #require(FixtureManifest.expected(for: fixture))

        let count = PDFAssertions.annotationCount(in: fixture.url)
        let hasAnnotations = count > 0
        #expect(
            hasAnnotations == expected.hasAnnotations,
            "Annotation mismatch for \(fixture.filename): expected \(expected.hasAnnotations), found \(count)"
        )
    }

    @Test("Manifest security expectations match reality", arguments: FixtureDiscovery.allFixtures)
    func securityStatusMatchesManifest(fixture: FixtureDiscovery.Fixture) throws {
        let expected = try #require(FixtureManifest.expected(for: fixture))
        guard let document = PDFDocument(url: fixture.url) else {
            #expect(!expected.canOpen, "Could not validate security properties for openable fixture \(fixture.filename)")
            return
        }

        #expect(
            document.isEncrypted == expected.isEncrypted,
            "Encryption mismatch for \(fixture.filename): expected \(expected.isEncrypted), got \(document.isEncrypted)"
        )
        #expect(
            document.allowsDocumentChanges == expected.allowsDocumentChanges,
            "Document-change permission mismatch for \(fixture.filename): expected \(expected.allowsDocumentChanges), got \(document.allowsDocumentChanges)"
        )
    }

    @Test("Manifest text expectations match reality", arguments: FixtureDiscovery.openableFixtures)
    func textStatusMatchesManifest(fixture: FixtureDiscovery.Fixture) throws {
        let expected = try #require(FixtureManifest.expected(for: fixture))
        let actual = PDFAssertions.hasExtractableText(url: fixture.url)
        #expect(
            actual == expected.hasExtractableText,
            "Extractable-text mismatch for \(fixture.filename): expected \(expected.hasExtractableText), got \(actual)"
        )
    }

    @Test("On-disk corpus exactly matches the manifest")
    func corpusMatchesManifest() {
        let discovered = Set(FixtureDiscovery.allFixtures.map { "\($0.category)/\($0.filename)" })
        let expected = Set(FixtureManifest.manifest.map { filename, properties in
            "\(properties.category)/\(filename)"
        })
        let missing = expected.subtracting(discovered).sorted()
        let unexpected = discovered.subtracting(expected).sorted()

        #expect(missing.isEmpty, "Missing fixtures: \(missing.joined(separator: ", "))")
        #expect(unexpected.isEmpty, "Unexpected fixtures: \(unexpected.joined(separator: ", "))")
    }
}
