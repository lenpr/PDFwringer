# CLAUDE.md

## Build

```bash
make build      # swiftc → .build/PDFwringer (arm64, macOS 26)
make run        # build + launch
make clean      # rm -rf .build
```

Or open `PDFwringer.xcodeproj` in Xcode and build the PDFwringer scheme.

No Swift Package Manager — the project uses an Xcode project with a parallel Makefile for CLI builds.

## Tests

Run via Xcode (Cmd+U) on the `PDFwringerTests` target. Uses Swift Testing (`import Testing`, `@Test`, `#expect`).

Only `PageRangeParser` has unit tests currently.

## Architecture

MVVM with a service layer. All code is `@MainActor`.

```
Models/       → Value types: CompressionLevel, JPEGQuality, PDFFileItem
Services/     → Stateless PDF operations: PDFCompressor, PDFConcatenator, PDFSplitter, PageRangeParser
ViewModels/   → @Observable classes: CompressViewModel, ConcatenateViewModel, SplitViewModel
Views/        → SwiftUI: CompressView, ConcatenateView, SplitView, PDFDropZone
Utilities/    → PDFwringerError (LocalizedError enum), FileDialogHelper (NSSavePanel/NSOpenPanel)
```

## Key conventions

- **Concurrency**: All service methods are `async throws` with cooperative cancellation (`Task.checkCancellation()`). Progress reported via closure.
- **Sandbox**: App is sandboxed with `com.apple.security.files.user-selected.read-write`. File access uses `NSSavePanel`/`NSOpenPanel` — never raw path construction.
- **PDF reading**: `PDFCompressor.openPDF(at:)` reads file data into memory first (works around CGPDFDocument sandbox restrictions). Other services use `PDFDocument(url:)`.
- **Temp files**: Operations write to `URL.temporaryDirectory` then atomically replace the destination via `FileManager.replaceItemAt(_:withItemAt:)`.
- **State management**: ViewModels use `@Observable` (Observation framework). Views own their VM via `@State`.
- **Drop handling**: Custom `DropNSView` (NSView subclass) for reliable drag-and-drop in sandbox — SwiftUI's built-in `onDrop` can be unreliable with sandboxed file URLs.

## Compression dual-engine

- **Lossless** (`CompressionLevel.lossless`): Strips metadata/attributes, re-serializes via PDFKit. Preserves text, links, annotations.
- **Rasterize** (`CompressionLevel.high/medium/low`): Renders each page to a bitmap at target DPI, encodes as JPEG, assembles new PDF via CGContext. Flattens all content.
