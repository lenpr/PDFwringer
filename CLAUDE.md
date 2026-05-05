# CLAUDE.md

## Build

```bash
make build      # swiftc → .build/PDFwringer (arm64, macOS 26)
make app        # build + .app bundle at .build/PDFwringer.app
make run        # build + launch (bare executable, needs Terminal)
make clean      # rm -rf .build
```

Or open `PDFwringer.xcodeproj` in Xcode and build the PDFwringer scheme.

No Swift Package Manager — the project uses an Xcode project with a parallel Makefile for CLI builds.

## Tests

```bash
make test       # compile + run all tests via Swift Testing
```

Uses Swift Testing (`import Testing`, `@Test`, `#expect`). Tests compile the Services/Models/Utilities layer without SwiftUI.

Test suites cover: `PageRangeParser`, `PDFConcatenator`, `PDFSplitter`, `PDFCompressor`. Tests generate PDFs programmatically — no fixture files needed.

## Architecture

MVVM with a service layer. All code is `@MainActor`.

```
Models/       → Value types: CompressionLevel, JPEGQuality, PDFFileItem
Services/     → Stateless PDF operations: PDFCompressor, PDFConcatenator, PDFSplitter, PageRangeParser
ViewModels/   → @Observable classes: AppViewModel, CompressViewModel, ConcatenateViewModel, SplitViewModel
Views/        → SwiftUI views + DropReceiverView (NSViewRepresentable drop overlay)
Utilities/    → PDFwringerError, FileDialogHelper, Formatting (shared formatBytes)
Resources/    → Asset catalog, AppIcon.icns
```

### Navigation model

`AppState` (in `AppViewModel.swift`) is the top-level state machine:

```
landing → singleFile / multiFile → compressing / splitting / merging → (back)
```

`ContentView` switches on `AppState` to render the correct view. `AppViewModel` owns state transitions (handleDrop, goBack, startOver, selectCompress/Split/Merge).

`AppState` has custom `Equatable` because `PDFDocument` doesn't conform — equality checks compare URLs/item IDs only.

## Key conventions

- **Concurrency**: All service methods are `async throws` with cooperative cancellation (`Task.checkCancellation()`). Progress reported via `(Double) -> Void` closure (range 0.0–1.0).
- **Sandbox**: App is sandboxed with `com.apple.security.files.user-selected.read-write`. File access uses `NSSavePanel`/`NSOpenPanel` — never raw path construction.
- **PDF reading**: `PDFCompressor.openPDF(at:)` reads file data into memory first (works around CGPDFDocument sandbox restrictions). Other services use `PDFDocument(url:)`.
- **Temp files**: Operations write to `URL.temporaryDirectory` then atomically replace the destination via `FileManager.replaceItemAt(_:withItemAt:)`.
- **State management**: ViewModels use `@Observable` (Observation framework). Views own their VM via `@State`.
- **Drop handling**: `DropReceiverView` wraps `DropNSView` (NSView subclass) for reliable drag-and-drop in sandbox. Returns `nil` from `hitTest` so SwiftUI buttons underneath remain clickable.
- **File items**: `PDFFileItem.from(url:)` / `.from(urls:)` is the single factory for creating items from URLs (filters PDFs, creates bookmarks, reads page count).
- **Formatting**: `Formatting.fileSize(_:)` is the shared byte-formatting utility used throughout the app.

## Compression dual-engine

- **Lossless** (`CompressionLevel.lossless`): Strips document-level metadata, re-serializes via PDFKit. When `stripMetadata: true`, also removes all page annotations (links, highlights, etc.).
- **Rasterize** (`CompressionLevel.high/medium/low`): Renders each page to a bitmap at target DPI, encodes as JPEG, assembles new PDF via CGContext. Flattens all content.

## App bundle

`make app` creates `.build/PDFwringer.app` with proper `Info.plist` (bundle ID, icon reference, activation). The `init()` in `PDFwringerApp` also sets `.regular` activation policy so the app works correctly when launched as a bare executable via `make run`.
