# PDFwringer

A lightweight macOS app for compressing, merging, and splitting PDF files. Native SwiftUI with no external dependencies.

## Features

### Compress
- **Lossless mode** — strips metadata while preserving text, annotations, and links
- **Rasterize mode** — re-renders pages as JPEG at configurable DPI (300/150/72) for maximum size reduction
- Adjustable JPEG quality, optional grayscale conversion
- Live size estimates before committing

### Merge
- Drag-and-drop file list with manual reordering (up/down buttons)
- Sort alphabetically (A→Z / Z→A)
- Add/remove individual files
- Progress reporting for large merges

### Split / Extract
- **Split every N pages** — creates numbered output files
- **Keep pages** — extract specific pages by range
- **Remove pages** — drop specific pages from the document

#### Page range syntax

| Input | Meaning |
|-------|---------|
| `3` | Page 3 |
| `1,5,10` | Pages 1, 5, and 10 |
| `3-6` | Pages 3 through 6 |
| `6-3` | Pages 6 through 3 (reversed) |
| `-3` | From the start through page 3 |
| `8-` | From page 8 to the end |
| `1, 3-5, 8-` | Mixed (comma-separated) |

Duplicates are allowed. User order is preserved.

## Requirements

- macOS 26.0+
- Apple Silicon (arm64)

## Building

### Xcode

Open `PDFwringer.xcodeproj` and build the `PDFwringer` scheme (Cmd+B).

### Command line

```bash
make build   # compiles to .build/PDFwringer
make app     # build + create .app bundle at .build/PDFwringer.app
make run     # build + launch (bare executable)
make test    # compile + run all tests
make clean   # remove build artifacts
```

### App bundle

`make app` produces a proper macOS `.app` bundle at `.build/PDFwringer.app` with an Info.plist and app icon. This is the recommended way to distribute or install the app — double-clicking the bundle launches it like any native app (no Terminal window).

## Testing

```bash
make test
```

Uses Swift Testing (`import Testing`, `@Test`, `#expect`). Tests cover the service/model/utility layers without requiring SwiftUI or a running app. Test PDFs are generated programmatically — no fixture files needed.

Test suites: `PageRangeParserTests`, `PDFCompressorTests`, `PDFConcatenatorTests`, `PDFSplitterTests`.

## Architecture

The app follows MVVM with a service layer. A top-level `AppState` enum drives navigation as a state machine (landing → singleFile/multiFile → action screen → back).

```
PDFwringer/
├── Models/          # Value types: CompressionLevel, JPEGQuality, PDFFileItem
├── Services/        # Stateless PDF operations: PDFCompressor, PDFConcatenator, PDFSplitter, PageRangeParser
├── ViewModels/      # @Observable classes: AppViewModel (navigation), CompressViewModel, ConcatenateViewModel, SplitViewModel
├── Views/           # SwiftUI views + DropReceiverView (NSViewRepresentable for reliable sandboxed drag-and-drop)
├── Utilities/       # PDFwringerError, FileDialogHelper, Formatting
└── Resources/       # Asset catalog, AppIcon.icns
```

All PDF processing uses Apple's PDFKit and CoreGraphics — no third-party libraries.

### Key design decisions

- **Document-first flow**: Users drop or select files first, then choose an action. Navigation is driven by `AppState` in `AppViewModel`.
- **NSView drop overlay**: SwiftUI's built-in `onDrop` is unreliable in sandboxed apps. `DropReceiverView` wraps an `NSView` that registers for file URL drags while returning `nil` from `hitTest` so clicks pass through.
- **Background size estimation**: `CompressViewModel` probes the first page at every compression setting in the background, then extrapolates to give instant feedback as users toggle options.
- **Atomic writes**: All services write to a temp file first, then atomically replace the destination via `FileManager.replaceItemAt`.

## License

[MIT](LICENSE) — Lukas N.P. Egger
