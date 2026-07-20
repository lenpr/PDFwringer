# CLAUDE.md

## Build

```bash
make build      # swiftc → .build/PDFwringer (arm64, macOS 26)
make app        # sandboxed/hardened .app bundle (ad-hoc codesigned)
make release    # optimized build (-O -whole-module-optimization) + app bundle
make sign       # release + codesign with Developer ID (hardened runtime)
make notarize   # sign + submit to Apple notary service + staple ticket
make dmg        # signed app + signed/notarized drag-to-install .dmg
make run        # build + launch the sandboxed app bundle
make clean      # rm -rf .build
```

Or open `PDFwringer.xcodeproj` in Xcode and build the PDFwringer scheme.

No Swift Package Manager — the project uses an Xcode project with a parallel Makefile for CLI builds.

## Tests

```bash
make test          # compile + run all tests; requires the external PDF corpus
make test-fast     # generated unit, workflow, and safety tests; no setup
make test-corpus   # fixture, invariant, visual, and performance tests
make verify-fixtures # validate corpus completeness and checksums
```

Uses Swift Testing (`import Testing`, `@Test`, `#expect`). Tests compile the Services/Models/Utilities/ViewModels layer without SwiftUI.

Test suites cover: `PageRangeParser`, `PDFConcatenator`, `PDFSplitter`, `PDFCompressor`, `PDFRotator`, `PDFCropper`, `PDFMetadataEditor`, `PDFColorAdjuster`, `PDFImageExporter`, `AppViewModel`, `CompressViewModel`, `SplitViewModel`, `ConcatenateViewModel`, `PDFFileItem`, `SourceEqualsDestination`, `FailureModeTests`, `UtilityTests`, end-to-end workflows, fixture-based integration tests, and property/invariant tests. Tests generate PDFs programmatically — no fixture files needed for the fast lane.

## Architecture

MVVM with a service layer. UI state and authoritative `PDFDocument` ownership are `@MainActor`; CPU-heavy per-page rendering uses isolated worker documents.

```
Models/       → Value types: CompressionLevel, JPEGQuality, PDFFileItem, PaperSize, ColorPreset
Services/     → Stateless PDF operations plus PDFPageWorker for isolated per-page rendering
ViewModels/   → @Observable classes: AppViewModel, CompressViewModel, ConcatenateViewModel, SplitViewModel, ColorAdjustViewModel
Views/        → SwiftUI views + shared components: OptionsHeaderView, PageSelectionView, PDFPreviewView, CropPreviewPanel, PageThumbnailStripView, DropReceiverView, ResultMessageView, ActionCardView, ColorAdjustOptionsView
Utilities/    → PDFwringerError, FileDialogHelper, BookmarkManager, Formatting, AtomicFileWriter, Log, Color.coral (all in PDFwringerError.swift except BookmarkManager)
Resources/    → Asset catalog, AppIcon.icns
```

### Navigation model

`AppState` (in `AppViewModel.swift`) is the top-level state machine:

```
landing → singleFile → compressing / splitting / rotating / editingMetadata / cropping / adjustingColor / exportingImages / reorderingPages → (back)
        → merging → (back)
```

`ContentView` switches on `AppState` to render the correct view. `AppViewModel` owns state transitions (handleDrop, goBack, startOver, selectCompress/Split/Rotate/Metadata/Crop/AdjustColor/ExportImages/ReorderPages). Multiple PDFs open directly in the merge editor.

## Key conventions

- **Concurrency**: Most service methods are `async throws` with cooperative cancellation (`Task.checkCancellation()`). Progress is reported via a `(Double) -> Void` closure (range 0.0–1.0). Raster workflows snapshot a page to `Data` on `MainActor`; `PDFPageWorker` reconstructs a private one-page document and renders/encodes it in a detached task, so PDFKit reference types never cross actor boundaries. `PDFCompressor.estimateFirstPageSizes` is `nonisolated` for background estimation.
- **Cancellation**: Operation ViewModels store an `operationTask: Task<Void, Never>?` and expose a `cancel()` method. `AppViewModel` owns one background file-intake task and invalidates it whenever newer input or navigation supersedes it. Views show a Cancel button alongside progress indicators. Services check `Task.checkCancellation()` per page iteration, so cancellation takes effect within one page.
- **Source/dest guard**: All services that take both source and destination URLs guard against `source == destination` at the top, throwing `PDFwringerError.sourceEqualsDestination`.
- **Sandbox**: App is sandboxed with `com.apple.security.files.user-selected.read-write`. File access uses `NSSavePanel`/`NSOpenPanel` — never raw path construction. Open Recent stores security-scoped bookmark data without a separate plaintext path and balances access for the lifetime of the active document.
- **PDF reading**: `PDFCompressor.openPDF(at:)` reads file data into memory first (works around CGPDFDocument sandbox restrictions). Other services use `PDFDocument(url:)`.
- **Temp files**: Operations write to `URL.temporaryDirectory` then atomically replace the destination via `FileManager.replaceItemAt(_:withItemAt:)`.
- **State management**: ViewModels use `@Observable` (Observation framework). Views own their VM via `@State`.
- **Drop handling**: `DropReceiverView` wraps `DropNSView` (NSView subclass) for reliable drag-and-drop in sandbox. Returns `nil` from `hitTest` so SwiftUI buttons underneath remain clickable. Multi-file intake validates PDFs off MainActor, then routes zero/one/many readable files to error/single-file/merge state respectively.
- **File items**: `PDFFileItem.from(url:)` / `.from(urls:)` is the single factory for creating items from URLs (filters PDFs, reads page count). Struct is `Sendable`.
- **Formatting**: `Formatting.fileSize(_:)` is the shared byte-formatting utility. `Formatting.triggerShake(_:)` provides the shared invalid-input shake animation.
- **Atomic writes**: `AtomicFileWriter` (in `PDFwringerError.swift`) writes to a temp file in a dedicated subdirectory (`URL.temporaryDirectory/PDFwringer/`), then uses `FileManager.replaceItemAt` for safe destination replacement. Cleans up on failure. All services use this consistently.
- **Logging**: `Log` enum (in `PDFwringerError.swift`) provides structured `os.Logger` instances per category (compress, merge, split, rotate, metadata).
- **Thumbnails**: `ThumbnailCache` is `@MainActor @Observable` with a generation counter for SwiftUI refresh. It snapshots the authoritative page on `MainActor`, renders a worker-local page off actor, and constructs the cached `NSImage` back on `MainActor`.

## Compression dual-engine

- **Lossless** (`CompressionLevel.lossless`): Strips document-level metadata, re-serializes via PDFKit. When `stripMetadata: true`, also removes all page annotations (links, highlights, etc.).
- **Rasterize** (`CompressionLevel.high/medium/low`): Renders each page to a bitmap at target DPI, encodes as JPEG, assembles new PDF via CGContext. Flattens all content. Oversized pages (where point dimensions exceed A3 at the target DPI — common in scanned PDFs and iPhone photos) are automatically capped to prevent bitmap inflation.
- **Size estimation**: `CompressViewModel` provides instant heuristic estimates (based on page dimensions × DPI × JPEG ratio) shown with a "~" prefix, then replaces them with a batched first-page probe. The batch opens the source once and renders once per DPI/color combination before encoding all JPEG qualities.

## Annotation flattening

`PDFMetadataEditor` supports flattening annotations via the `flattenAnnotations` parameter. When enabled, each page is snapshotted and rasterized at 300 DPI (JPEG quality 0.92) on an isolated worker using `page.draw(with:to:)`, which renders annotation appearances into the bitmap. The result is a visually identical PDF where annotations are burned into the page content and are no longer editable. Text selectability is lost. The operation is async with progress reporting and cancellation support.

## App bundle

`make app` creates `.build/PDFwringer.app` with a proper `Info.plist`, sandbox entitlements, hardened runtime, and an ad-hoc signature. `make release` forces an optimized ad-hoc bundle without requiring credentials. `make sign` replaces that signature with a timestamped Developer ID signature. `make notarize` submits and staples the standalone app, while `make dmg` packages the signed app with an Applications symlink, signs the disk image, and notarizes/staples the final DMG. `SIGN_IDENTITY` and `NOTARY_PROFILE` can be overridden on the command line or through the environment.
