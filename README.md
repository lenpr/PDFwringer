<p align="center">
  <img src="icon.png" width="256" height="256" alt="PDFwringer icon">
</p>

<h1 align="center">PDFwringer</h1>

<p align="center">
  <strong>Wring every last byte out of your PDFs.</strong><br><br>
  A lightweight native macOS app for compressing, merging, splitting, rotating, cropping, color-adjusting, watermarking, and editing PDF files.<br>
  Built entirely with SwiftUI and PDFKit — zero external dependencies, zero network calls, zero data collection.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS_26+-blue?logo=apple" alt="Platform">
  <img src="https://img.shields.io/badge/swift-6.0-orange?logo=swift" alt="Swift">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</p>

<p align="center">
  <img src="screenshots/action-picker.png" width="720" alt="PDFwringer — action picker">
</p>

---

## Why PDFwringer?

Most PDF tools are either bloated Electron apps, subscription-gated web services, or privacy nightmares that upload your documents to someone else's server. PDFwringer is different:

- **Fully offline** — your files never leave your machine
- **Native performance** — instant launches, no runtime overhead
- **Drop and done** — drag a PDF in, pick an action, save the result
- **Sandboxed** — only touches files you explicitly select

---

## Features

### Compress

Squeeze bloated PDFs down to size. Choose lossless metadata stripping for a quick trim, or lossy rasterization at configurable DPI (72-300) and JPEG quality for dramatic reductions. Live size estimates let you compare options *before* committing — no guesswork. Oversized pages (common in scanned PDFs and iPhone photos) are automatically capped to prevent file inflation.

<p align="center">
  <img src="screenshots/compress.png" width="720" alt="Compression options with live size estimates">
</p>

### Merge

Combine multiple PDFs into one. Drag-and-drop files in, reorder them freely, sort alphabetically, and merge with a single click.

### Split / Extract

Pull out exactly the pages you need. Split every N pages, keep specific pages, or remove unwanted ones — all using intuitive range syntax (`1, 3-5, 8-`). Perfect for extracting chapters, removing blank pages, or breaking a monolithic PDF into manageable pieces.

<p align="center">
  <img src="screenshots/split.png" width="720" alt="Split and extract pages">
</p>

### Rotate Pages

Fix sideways scans and upside-down pages. Rotate all or selected pages by 90° CW, 180°, or 90° CCW with a live preview showing exactly what you'll get.

<p align="center">
  <img src="screenshots/rotate.png" width="720" alt="Rotate pages">
</p>

### Crop / Resize

Trim excess whitespace or resize pages to standard paper sizes (A4, Letter, A5, Legal). Crop and resize are independent — trim margins without resizing, resize without cropping, or both at once. Portrait/landscape toggle included.

### Adjust Colors

Fine-tune brightness, contrast, and saturation with real-time preview. Named presets (Vivid, Muted, B&W, High Contrast) get you 90% of the way with one click — then dial in the rest manually if needed.

### Edit Metadata

View and edit title, author, subject, keywords, and creator. Set or remove password protection. Flatten annotations to permanently burn highlights, comments, and form fields into the page content — useful for sharing documents without editable markup.

<p align="center">
  <img src="screenshots/metadata.png" width="720" alt="Edit PDF metadata">
</p>

### Add Page Numbers

Add page numbers at any of six positions (top/bottom, left/center/right). Configure starting number, font size, color, and optional prefix/suffix. Live preview shows exactly where numbers will land. Numbers are rendered directly into page content — visible in all PDF viewers.

### Add Watermark

Overlay semi-transparent text like DRAFT, CONFIDENTIAL, or any custom text across pages. Full control over font size, color, opacity, rotation angle, and position. Useful for marking documents as unofficial or internal without altering the underlying content.

### Export as Images

Export selected pages as JPEG or PNG files at configurable DPI (72/150/300). JPEG quality slider for size control. Exports to a directory with automatic filename numbering.

### Reorder Pages

Drag pages in a sidebar list to rearrange their order. Quick-actions for reversing page order or resetting to original. Saves the reordered document to a new file.

### Image to PDF

Drop image files (JPG, PNG, TIFF, HEIC) directly into the app to convert them into a PDF. Each image becomes one page, auto-scaled to fit reasonable dimensions.

---

## Page Range Syntax

Used in Split / Extract, Rotate, and Crop operations:

| Input | Meaning |
|-------|---------|
| `3` | Page 3 |
| `1,5,10` | Pages 1, 5, and 10 |
| `3-6` | Pages 3 through 6 |
| `6-3` | Pages 6 through 3 (reversed) |
| `-3` | From the start through page 3 |
| `8-` | From page 8 to the end |
| `1, 3-5, 8-` | Mixed (comma-separated) |

---

## Getting Started

### Requirements

- macOS 26.0+ (Tahoe)
- Apple Silicon (arm64)

### Build & Run

```bash
# Command line — from zero to running in seconds
make app       # produces .build/PDFwringer.app (ad-hoc codesigned)
make release   # optimized build (-O) + app bundle
make dmg       # app + drag-to-install disk image (.build/PDFwringer.dmg)
make run       # build + launch immediately

# Or open PDFwringer.xcodeproj in Xcode (Cmd+B)
```

### Install

```bash
make app
cp -R .build/PDFwringer.app ~/Applications/
# That's it. No brew, no npm, no pip.
```

### Test

```bash
make test       # 259 tests across 41 suites
make test-fast  # 143 unit tests in ~2 seconds (no fixtures needed)
```

Uses [Swift Testing](https://developer.apple.com/documentation/testing). Tests cover services, models, utilities, and view models. A real-world PDF fixture corpus (36 files) exercises all operations against diverse document types. PDFs are also generated programmatically for unit tests — no setup needed.

---

## Distribution

### Code Signing & Notarization

The Makefile includes targets for signing and notarizing with a Developer ID certificate:

```bash
make sign       # build + sign with hardened runtime (Developer ID)
make notarize   # sign + submit to Apple + staple notarization ticket
make dmg        # full pipeline: release build + signed DMG + notarize
```

Prerequisites:
- A "Developer ID Application" certificate installed in your keychain
- A notarytool keychain profile (set up once via `xcrun notarytool store-credentials`)
- Update `SIGN_IDENTITY` and `NOTARY_PROFILE` in the Makefile for your team

The app is sandboxed with `com.apple.security.files.user-selected.read-write` entitlement — no additional entitlements are needed for hardened runtime unless accessing protected resources.

### Privacy

See [PRIVACY.md](PRIVACY.md). The app makes no network requests and collects no data.

---

## Architecture

MVVM with a stateless service layer. Navigation is a state machine driven by `AppState`.

```
PDFwringer/
├── Models/          Value types (CompressionLevel, JPEGQuality, PDFFileItem, PaperSize)
├── Services/        Stateless PDF ops (Compressor, Concatenator, Splitter, Rotator, Cropper, ColorAdjuster, MetadataEditor, PageRangeParser)
├── ViewModels/      @Observable classes (AppViewModel, CompressViewModel, ConcatenateViewModel, SplitViewModel)
├── Views/           SwiftUI views, shared components (OptionsHeaderView, PageSelectionView, PDFPreviewView, CropPreviewPanel)
├── Utilities/       Error types, file dialogs, formatting helpers, Color.coral
└── Resources/       Asset catalog, AppIcon.icns
```

### Design Decisions

- **Document-first flow** — drop/select files first, then choose an action
- **NSView drop overlay** — SwiftUI's `onDrop` is unreliable in sandboxed apps; `DropReceiverView` wraps an NSView that passes clicks through via `hitTest → nil`
- **Background size estimation** — compression options probe the first page at each setting to give instant size feedback
- **Atomic writes** — all operations write to a temp file, then `FileManager.replaceItemAt` to the destination
- **Strict concurrency** — full Swift 6 `SWIFT_STRICT_CONCURRENCY = complete`, all code `@MainActor`

---

## License

[MIT](LICENSE) — do whatever you want with it. Lukas N.P. Egger
