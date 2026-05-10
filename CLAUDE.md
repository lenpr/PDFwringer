# CLAUDE.md

## Build

```bash
make build      # swiftc → .build/PDFwringer (arm64, macOS 26)
make app        # build + .app bundle at .build/PDFwringer.app (ad-hoc codesigned)
make release    # optimized build (-O -whole-module-optimization) + app bundle
make sign       # release + codesign with Developer ID (hardened runtime)
make notarize   # sign + submit to Apple notary service + staple ticket
make dmg        # release + notarized .dmg with drag-to-install layout
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

Test suites cover: `PageRangeParser`, `PDFConcatenator`, `PDFSplitter`, `PDFCompressor`, `PDFRotator`, `PDFCropper`, `PDFMetadataEditor`, `AppViewModel`, `PDFFileItem`, `FailureModeTests`, `UtilityTests`, end-to-end workflows. Tests generate PDFs programmatically — no fixture files needed.

## Architecture

MVVM with a service layer. All code is `@MainActor`.

```
Models/       → Value types: CompressionLevel, JPEGQuality, PDFFileItem, PaperSize
Services/     → Stateless PDF operations: PDFCompressor, PDFConcatenator, PDFSplitter, PDFRotator, PDFCropper, PDFColorAdjuster, PDFMetadataEditor, PageRangeParser
ViewModels/   → @Observable classes: AppViewModel, CompressViewModel, ConcatenateViewModel, SplitViewModel
Views/        → SwiftUI views + shared components: OptionsHeaderView, PageSelectionView, PDFPreviewView, CropPreviewPanel, PageThumbnailStripView, DropReceiverView, ResultMessageView, ActionCardView, ColorAdjustOptionsView
Utilities/    → PDFwringerError, FileDialogHelper, Formatting, AtomicFileWriter, Log, Color.coral (all in PDFwringerError.swift)
Resources/    → Asset catalog, AppIcon.icns
```

### Navigation model

`AppState` (in `AppViewModel.swift`) is the top-level state machine:

```
landing → singleFile / multiFile → compressing / splitting / rotating / editingMetadata / cropping / adjustingColor / merging → (back)
```

`ContentView` switches on `AppState` to render the correct view. `AppViewModel` owns state transitions (handleDrop, goBack, startOver, selectCompress/Split/Merge/Rotate/Metadata/Crop/AdjustColor).

`AppState` has custom `Equatable` because `PDFDocument` doesn't conform — equality checks compare URLs/item IDs only.

## Key conventions

- **Concurrency**: Most service methods are `async throws` with cooperative cancellation (`Task.checkCancellation()`). Progress reported via `(Double) -> Void` closure (range 0.0–1.0). `PDFMetadataEditor.write()` is `async throws` with optional progress (needed for flatten which rasterizes pages). `PDFCompressor.compressFirstPage` is `nonisolated` for background estimation.
- **Source/dest guard**: All services that take both source and destination URLs guard against `source == destination` at the top, throwing `PDFwringerError.sourceEqualsDestination`.
- **Sandbox**: App is sandboxed with `com.apple.security.files.user-selected.read-write`. File access uses `NSSavePanel`/`NSOpenPanel` — never raw path construction.
- **PDF reading**: `PDFCompressor.openPDF(at:)` reads file data into memory first (works around CGPDFDocument sandbox restrictions). Other services use `PDFDocument(url:)`.
- **Temp files**: Operations write to `URL.temporaryDirectory` then atomically replace the destination via `FileManager.replaceItemAt(_:withItemAt:)`.
- **State management**: ViewModels use `@Observable` (Observation framework). Views own their VM via `@State`.
- **Drop handling**: `DropReceiverView` wraps `DropNSView` (NSView subclass) for reliable drag-and-drop in sandbox. Returns `nil` from `hitTest` so SwiftUI buttons underneath remain clickable.
- **File items**: `PDFFileItem.from(url:)` / `.from(urls:)` is the single factory for creating items from URLs (filters PDFs, reads page count). Struct is `Sendable`.
- **Formatting**: `Formatting.fileSize(_:)` is the shared byte-formatting utility. `Formatting.triggerShake(_:)` provides the shared invalid-input shake animation.
- **Atomic writes**: `AtomicFileWriter` (in `PDFwringerError.swift`) writes to a temp file in a dedicated subdirectory (`URL.temporaryDirectory/PDFwringer/`), then uses `FileManager.replaceItemAt` for safe destination replacement. Cleans up on failure. All services use this consistently.
- **Logging**: `Log` enum (in `PDFwringerError.swift`) provides structured `os.Logger` instances per category (compress, merge, split, rotate, metadata).
- **Thumbnails**: `ThumbnailCache` is `@MainActor @Observable` with a generation counter for SwiftUI refresh. PDF access stays on MainActor; only bitmap rendering is detached.

## Compression dual-engine

- **Lossless** (`CompressionLevel.lossless`): Strips document-level metadata, re-serializes via PDFKit. When `stripMetadata: true`, also removes all page annotations (links, highlights, etc.).
- **Rasterize** (`CompressionLevel.high/medium/low`): Renders each page to a bitmap at target DPI, encodes as JPEG, assembles new PDF via CGContext. Flattens all content. Oversized pages (where point dimensions exceed A3 at the target DPI — common in scanned PDFs and iPhone photos) are automatically capped to prevent bitmap inflation.
- **Size estimation**: `CompressViewModel` provides instant heuristic estimates (based on page dimensions × DPI × JPEG ratio) shown with "~" prefix, then replaces them with real first-page estimates computed in a background task.

## Annotation flattening

`PDFMetadataEditor` supports flattening annotations via the `flattenAnnotations` parameter. When enabled, each page is rasterized at 300 DPI (JPEG quality 0.92) using `page.draw(with:to:)` which renders annotation appearances into the bitmap. The result is a visually identical PDF where annotations are burned into the page content and are no longer editable. Text selectability is lost. The operation is async with progress reporting and cancellation support.

## App bundle

`make app` creates `.build/PDFwringer.app` with proper `Info.plist` (bundle ID, icon reference, activation) and ad-hoc codesigning. `make release` adds `-O -whole-module-optimization` for distribution builds. `make sign` codesigns with a Developer ID certificate and hardened runtime (copies to `/tmp` first to avoid iCloud Drive xattr issues). `make notarize` submits to Apple's notary service and staples the ticket. `make dmg` wraps the app in a notarized disk image with an Applications symlink and Finder layout (icon view, app on left, Applications on right) for drag-to-install UX. The `init()` in `PDFwringerApp` also sets `.regular` activation policy so the app works correctly when launched as a bare executable via `make run`.
