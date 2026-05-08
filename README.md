<p align="center">
  <img src="icon.png" width="128" height="128" alt="PDFwringer icon">
</p>

<h1 align="center">PDFwringer</h1>

<p align="center">
  A lightweight native macOS app for compressing, merging, splitting, rotating, cropping, color-adjusting, and editing PDF files.<br>
  Built with SwiftUI and PDFKit — no external dependencies.
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

## Features

### Compress

Reduce file size with lossless metadata stripping or lossy rasterization at configurable DPI (72–300) and JPEG quality. Live size estimates let you compare options before committing. Optional grayscale conversion and metadata stripping.

<p align="center">
  <img src="screenshots/compress.png" width="720" alt="Compression options with live size estimates">
</p>

### Merge

Drag-and-drop multiple PDFs, reorder them freely, sort alphabetically, and combine into a single file.

### Split / Extract

Split a document every N pages, keep only specific pages, or remove unwanted pages — all using flexible range syntax (`1, 3-5, 8-`).

<p align="center">
  <img src="screenshots/split.png" width="720" alt="Split and extract pages">
</p>

### Rotate Pages

Rotate all or selected pages by 90° CW, 180°, or 90° CCW with a live preview.

<p align="center">
  <img src="screenshots/rotate.png" width="720" alt="Rotate pages">
</p>

### Crop / Resize

Trim margins from any edge or resize pages to standard paper sizes (A4, Letter, A5, Legal) with portrait/landscape toggle. Operations are independent — crop without resizing or vice versa. Apply to all pages or a specific range.

### Adjust Colors

Tweak brightness, contrast, and saturation with a live preview. Includes named presets (Vivid, Muted, B&W, High Contrast) and a Reset button. Apply to all pages or a specific range.

### Edit Metadata

View and edit title, author, subject, keywords, and creator. Set or remove password protection. Flatten annotations to burn highlights, comments, and form fields permanently into the page content.

<p align="center">
  <img src="screenshots/metadata.png" width="720" alt="Edit PDF metadata">
</p>

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

### Build

```bash
# Command line
make app       # produces .build/PDFwringer.app (ad-hoc codesigned)
make release   # optimized build (-O) + app bundle
make dmg       # app + drag-to-install disk image (.build/PDFwringer.dmg)
make run       # build + launch

# Or open PDFwringer.xcodeproj in Xcode (Cmd+B)
```

### Install

```bash
make app
cp -R .build/PDFwringer.app ~/Applications/
```

### Test

```bash
make test    # 148 tests across 13 suites
```

Uses [Swift Testing](https://developer.apple.com/documentation/testing). Tests cover the service/model/utility layers without requiring a running app. PDFs are generated programmatically — no fixture files.

---

## Distribution

### Code Signing & Notarization

To distribute outside the App Store, sign and notarize the app bundle:

```bash
# 1. Build the app
make app

# 2. Sign with hardened runtime
codesign --force --options runtime \
  --entitlements PDFwringer/PDFwringer.entitlements \
  --sign "Developer ID Application: Your Name (TEAM_ID)" \
  .build/PDFwringer.app

# 3. Create a zip for notarization
ditto -c -k --keepParent .build/PDFwringer.app PDFwringer.zip

# 4. Submit for notarization
xcrun notarytool submit PDFwringer.zip \
  --apple-id your@email.com \
  --team-id TEAM_ID \
  --password @keychain:notarytool-password \
  --wait

# 5. Staple the ticket
xcrun stapler staple .build/PDFwringer.app
```

The app is already sandboxed with `com.apple.security.files.user-selected.read-write` entitlement — no additional entitlements are needed for hardened runtime unless accessing protected resources.

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

[MIT](LICENSE) — Lukas N.P. Egger
