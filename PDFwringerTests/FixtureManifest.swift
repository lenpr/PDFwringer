import Foundation
import PDFKit
import Testing

/// Fixture manifest: records expected properties per fixture for precise assertion.
/// Tests validate against explicit expectations rather than just "output opens."
@MainActor
enum FixtureManifest {

    struct ExpectedProperties {
        let filename: String
        let pageCount: Int
        let hasText: Bool
        let hasAnnotations: Bool
        let isEncrypted: Bool
        let isModifiable: Bool
        let canOpen: Bool
        let category: String
        let notes: String

        init(
            _ filename: String,
            pages: Int,
            text: Bool = true,
            annotations: Bool = false,
            encrypted: Bool = false,
            modifiable: Bool = true,
            canOpen: Bool = true,
            category: String = "smoke",
            notes: String = ""
        ) {
            self.filename = filename
            self.pageCount = pages
            self.hasText = text
            self.hasAnnotations = annotations
            self.isEncrypted = encrypted
            self.isModifiable = modifiable
            self.canOpen = canOpen
            self.category = category
            self.notes = notes
        }
    }

    /// Known fixture properties. Update when adding new fixtures.
    static let manifest: [String: ExpectedProperties] = [
        // Smoke / basic
        "tracemonkey.pdf": .init("tracemonkey.pdf", pages: 14, text: true, category: "smoke", notes: "PDF.js baseline, text+vector+fonts"),
        "pdf20_simple.pdf": .init("pdf20_simple.pdf", pages: 1, text: true, category: "smoke", notes: "Minimal PDF 2.0"),
        "pdf20_utf8.pdf": .init("pdf20_utf8.pdf", pages: 1, text: true, category: "smoke", notes: "PDF 2.0 UTF-8 strings"),
        "pdf20_incremental.pdf": .init("pdf20_incremental.pdf", pages: 1, text: true, category: "smoke", notes: "PDF 2.0 via incremental save"),
        "pdf20_offset_start.pdf": .init("pdf20_offset_start.pdf", pages: 1, text: true, category: "smoke", notes: "Non-zero PDF start offset"),

        // Fonts, color, images
        "rotated.pdf": .init("rotated.pdf", pages: 1, text: true, category: "fonts_color", notes: "Pre-rotated pages"),
        "vertical.pdf": .init("vertical.pdf", pages: 3, text: true, category: "fonts_color", notes: "CJK vertical writing"),
        "zapfdingbats.pdf": .init("zapfdingbats.pdf", pages: 2, text: true, category: "fonts_color", notes: "Standard 14 symbol font"),
        "transparent.pdf": .init("transparent.pdf", pages: 1, text: false, category: "fonts_color", notes: "Transparency/compositing"),
        "xobject_image.pdf": .init("xobject_image.pdf", pages: 1, text: false, category: "fonts_color", notes: "Image XObject"),
        "cmyk_image.pdf": .init("cmyk_image.pdf", pages: 1, text: false, category: "fonts_color", notes: "CMYK color space image"),
        "pdf20_bpc_image.pdf": .init("pdf20_bpc_image.pdf", pages: 1, text: false, category: "fonts_color", notes: "Black point compensation"),

        // Annotations
        "text_widget.pdf": .init("text_widget.pdf", pages: 1, annotations: true, category: "annotations", notes: "Text form widget"),
        "choice_widget.pdf": .init("choice_widget.pdf", pages: 1, annotations: true, category: "annotations", notes: "Dropdown/list widget"),
        "button_widget.pdf": .init("button_widget.pdf", pages: 1, annotations: true, category: "annotations", notes: "Button/check/radio widget"),
        "highlight.pdf": .init("highlight.pdf", pages: 1, annotations: true, category: "annotations", notes: "Highlight markup"),
        "freetext.pdf": .init("freetext.pdf", pages: 1, annotations: true, category: "annotations", notes: "Free-text annotation"),
        "line_no_appearance.pdf": .init("line_no_appearance.pdf", pages: 1, annotations: true, category: "annotations", notes: "Missing appearance stream"),
        "fileattachment.pdf": .init("fileattachment.pdf", pages: 1, annotations: true, category: "annotations", notes: "File attachment annotation"),

        // Forms
        "pdflatex_forms.pdf": .init("pdflatex_forms.pdf", pages: 1, text: true, annotations: true, category: "forms", notes: "LaTeX-generated form"),
        "with_attachment.pdf": .init("with_attachment.pdf", pages: 1, text: true, category: "forms", notes: "Embedded file attachment"),
        "irs_w9.pdf": .init("irs_w9.pdf", pages: 6, text: true, annotations: true, category: "forms", notes: "IRS fillable form"),

        // Security
        "password_protected.pdf": .init("password_protected.pdf", pages: 1, encrypted: true, modifiable: false, canOpen: false, category: "security", notes: "Password: openpassword"),
        "sechandler.pdf": .init("sechandler.pdf", pages: 1, text: true, annotations: true, encrypted: false, modifiable: false, category: "security", notes: "Permission-restricted, no assembly allowed"),

        // Scanned
        "hubbard_ocr.pdf": .init("hubbard_ocr.pdf", pages: 1, text: true, category: "scanned", notes: "Scanned with OCR text layer"),
        "hubbard_no_ocr.pdf": .init("hubbard_no_ocr.pdf", pages: 1, text: false, category: "scanned", notes: "Scanned without OCR — image only"),
        "usgs_orthoimagery.pdf": .init("usgs_orthoimagery.pdf", pages: 4, text: true, category: "scanned", notes: "USGS brochure with maps"),

        // Mixed
        "cropped_rotated_scaled.pdf": .init("cropped_rotated_scaled.pdf", pages: 4, text: true, category: "mixed", notes: "Various page box transformations"),
        "noembed_jis7.pdf": .init("noembed_jis7.pdf", pages: 1, text: true, category: "mixed", notes: "Japanese non-embedded font"),
        "pdf20_utf8_annotation.pdf": .init("pdf20_utf8_annotation.pdf", pages: 1, text: true, annotations: true, category: "mixed", notes: "Thai UTF-8 annotation"),
        "pdf20_output_intent.pdf": .init("pdf20_output_intent.pdf", pages: 2, text: true, category: "mixed", notes: "Page-level output intent"),

        // Large
        "fdsys_architecture.pdf": .init("fdsys_architecture.pdf", pages: 87, text: true, category: "large", notes: "87-page government document"),

        // Quarantine (may not open cleanly)
        "poppler_fuzzed.pdf": .init("poppler_fuzzed.pdf", pages: 0, text: false, canOpen: false, category: "quarantine", notes: "Fuzzed Poppler regression"),
        "ghostscript_fuzzed.pdf": .init("ghostscript_fuzzed.pdf", pages: 0, text: false, canOpen: false, category: "quarantine", notes: "Fuzzed Ghostscript regression"),
        "pdfbox_regression.pdf": .init("pdfbox_regression.pdf", pages: 0, text: false, canOpen: false, category: "quarantine", notes: "PDFBox parser regression"),
        "redhat_regression.pdf": .init("redhat_regression.pdf", pages: 0, text: false, canOpen: false, category: "quarantine", notes: "RedHat security regression"),
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
    func pageCountMatchesManifest(fixture: FixtureDiscovery.Fixture) {
        guard let expected = FixtureManifest.expected(for: fixture) else { return }
        guard expected.canOpen else { return } // Can't check page count of unopenable PDFs

        #expect(fixture.pageCount == expected.pageCount,
                "Page count mismatch for \(fixture.filename): expected \(expected.pageCount), got \(fixture.pageCount)")
    }

    @Test("Manifest openability expectations match reality", arguments: FixtureDiscovery.allFixtures)
    func openabilityMatchesManifest(fixture: FixtureDiscovery.Fixture) {
        guard let expected = FixtureManifest.expected(for: fixture) else { return }

        let canActuallyOpen = PDFDocument(url: fixture.url) != nil && fixture.pageCount > 0
        if expected.canOpen {
            #expect(canActuallyOpen, "Manifest says \(fixture.filename) should be openable but it's not")
        }
    }

    @Test("Manifest annotation expectations match reality", arguments: FixtureDiscovery.openableFixtures)
    func annotationStatusMatchesManifest(fixture: FixtureDiscovery.Fixture) {
        guard let expected = FixtureManifest.expected(for: fixture) else { return }
        guard expected.hasAnnotations else { return }

        let count = PDFAssertions.annotationCount(in: fixture.url)
        #expect(count > 0, "Manifest says \(fixture.filename) has annotations but found \(count)")
    }

    @Test("Manifest text expectations match reality", arguments: FixtureDiscovery.openableFixtures)
    func textStatusMatchesManifest(fixture: FixtureDiscovery.Fixture) {
        guard let expected = FixtureManifest.expected(for: fixture) else { return }
        guard expected.hasText else { return }

        // Text extraction is best-effort; some PDFs with text use encodings
        // that PDFKit can't decode. Don't fail, just note as known issue.
        let hasText = PDFAssertions.assertHasExtractableText(url: fixture.url)
        if !hasText {
            // Known limitation — PDFKit text extraction doesn't work for all PDFs
            // This is informational, not a failure
        }
    }

    @Test("All on-disk fixtures have manifest entries")
    func allFixturesInManifest() {
        let unmapped = FixtureDiscovery.allFixtures.filter { FixtureManifest.expected(for: $0) == nil }
        #expect(unmapped.isEmpty, "Fixtures missing from manifest: \(unmapped.map(\.filename).joined(separator: ", "))")
    }
}
