<p align="center">
  <img src="icon.png" width="128" height="128" alt="PDFwringer icon">
</p>

<h1 align="center">PDFwringer</h1>

<p align="center">
  A lightweight native macOS app for compressing, merging, splitting, rotating, and editing PDF files.<br>
  Built with SwiftUI and PDFKit — no external dependencies.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS_26+-blue?logo=apple" alt="Platform">
  <img src="https://img.shields.io/badge/swift-6.0-orange?logo=swift" alt="Swift">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</p>

---

## Features

| Feature | Description |
|---------|-------------|
| **Compress** | Lossless metadata stripping or lossy rasterization at configurable DPI/quality. Live size estimates. |
| **Merge** | Drag-and-drop reordering, alphabetical sort, add/remove files. |
| **Split / Extract** | Split every N pages, keep specific pages, or remove pages using flexible range syntax. |
| **Rotate** | Rotate all or selected pages by 90/180/270 degrees with live preview. |
| **Metadata** | Edit title, author, subject, keywords, creator. Set or remove PDF passwords. |

### Page range syntax

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
make app     # produces .build/PDFwringer.app
make run     # build + launch

# Or open PDFwringer.xcodeproj in Xcode (Cmd+B)
```

### Install

```bash
make app
cp -R .build/PDFwringer.app ~/Applications/
```

### Test

```bash
make test    # 110 tests across 9 suites
```

Uses [Swift Testing](https://developer.apple.com/documentation/testing). Tests cover the service/model/utility layers without requiring a running app. PDFs are generated programmatically — no fixture files.

---

## Architecture

MVVM with a stateless service layer. Navigation is a state machine driven by `AppState`.

```
PDFwringer/
├── Models/          Value types (CompressionLevel, JPEGQuality, PDFFileItem)
├── Services/        Stateless PDF ops (Compressor, Concatenator, Splitter, Rotator, MetadataEditor, PageRangeParser)
├── ViewModels/      @Observable classes (AppViewModel, CompressViewModel, ConcatenateViewModel, SplitViewModel)
├── Views/           SwiftUI views + NSViewRepresentable drop overlay
├── Utilities/       Error types, file dialogs, formatting helpers
└── Resources/       Asset catalog, AppIcon.icns
```

### Design decisions

- **Document-first flow** — drop/select files first, then choose an action
- **NSView drop overlay** — SwiftUI's `onDrop` is unreliable in sandboxed apps; `DropReceiverView` wraps an NSView that passes clicks through via `hitTest → nil`
- **Background size estimation** — compression options probe the first page at each setting to give instant size feedback
- **Atomic writes** — all operations write to a temp file, then `FileManager.replaceItemAt` to the destination
- **Strict concurrency** — full Swift 6 `SWIFT_STRICT_CONCURRENCY = complete`, all code `@MainActor`

---

## License

[MIT](LICENSE) — Lukas N.P. Egger
