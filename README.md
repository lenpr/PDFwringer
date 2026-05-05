# PDFwringer

A lightweight macOS app for compressing, merging, and splitting PDF files. Native SwiftUI with no external dependencies.

<!-- ![PDFwringer screenshot](docs/screenshot.png) -->

## Features

### Compress
- **Lossless mode** — strips metadata while preserving text, annotations, and links
- **Rasterize mode** — re-renders pages as JPEG at configurable DPI (300/150/72) for maximum size reduction
- Adjustable JPEG quality, optional grayscale conversion
- Live size estimates before committing

### Concatenate
- Drag-and-drop file list with reordering
- Sort alphabetically (A-Z / Z-A)
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
make run     # build + launch
make clean   # remove build artifacts
```

## Architecture

The app follows MVVM with a service layer:

```
PDFwringer/
├── Models/          # Data types (CompressionLevel, JPEGQuality, PDFFileItem)
├── Services/        # PDF operations (Compressor, Concatenator, Splitter, PageRangeParser)
├── ViewModels/      # UI state + orchestration per feature tab
├── Views/           # SwiftUI views including reusable PDFDropZone
├── Utilities/       # Error types, file dialog helpers
└── Resources/       # Asset catalog
```

All PDF processing uses Apple's PDFKit and CoreGraphics — no third-party libraries.

## License

[MIT](LICENSE) — Lukas N.P. Egger
