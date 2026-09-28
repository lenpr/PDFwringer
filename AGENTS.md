# AGENTS.md

## Build

```bash
make build      # swiftc → .build/PDFwringer (arm64, macOS 27)
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

Uses Swift Testing (`import Testing`, `@Test`, `#expect`). Tests compile the Services/Models/Utilities/ViewModels layer without SwiftUI.

Test suites cover: `PageRangeParser`, `PDFConcatenator`, `PDFSplitter`, `PDFCompressor`, `PDFRotator`, `PDFCropper`, `PDFMetadataEditor`, `PDFColorAdjuster`, `PDFImageExporter`, `PDFImageConverter`, `AppViewModel`, `CompressViewModel`, `SplitViewModel`, `ConcatenateViewModel`, `PDFFileItem`, `SourceEqualsDestination`, `FailureModeTests`, `UtilityTests`, end-to-end workflows, fixture-based integration tests, and property/invariant tests. Tests generate PDFs programmatically — no fixture files needed for the fast lane.
The fast lane also compiles `Views/PDFPreviewView.swift` to test native PDF
navigation and teardown. `make test` additionally verifies and runs the external
fixture corpus and performance tests. Run test and archive builds sequentially.

## Architecture

MVVM with a service layer. UI state and authoritative PDFKit documents are
`@MainActor`. Background workers reconstruct isolated pages from `Data`; PDFKit
reference objects must not be shared across actors. File-list intake and optional
compression estimates also run off MainActor.

```
Models/       → Value types: CompressionLevel, JPEGQuality, PDFFileItem, PaperSize, ColorPreset
Services/     → Stateless PDF operations: PDFCompressor, PDFConcatenator, PDFSplitter, PDFRotator, PDFCropper, PDFColorAdjuster, PDFMetadataEditor, PDFImageExporter, PDFImageConverter, PageRangeParser
ViewModels/   → @Observable classes: AppViewModel, CompressViewModel, ConcatenateViewModel, SplitViewModel, ColorAdjustViewModel
Views/        → SwiftUI views + shared components: OptionsHeaderView, PageSelectionView, PDFPreviewView, CropPreviewPanel, PageThumbnailStripView, DropReceiverView, ResultMessageView, ActionCardView, ColorAdjustOptionsView
Utilities/    → PDFwringerError, FileDialogHelper, BookmarkManager, Formatting, AtomicFileWriter, Log, Color.coral (all in PDFwringerError.swift except BookmarkManager)
Resources/    → Asset catalog, AppIcon.icns
```

### Navigation model

`AppState` (in `AppViewModel.swift`) is the top-level state machine:

```
landing → singleFile / multiFile → compressing / splitting / rotating / editingMetadata / cropping / adjustingColor / merging / exportingImages / reorderingPages → (back)
```

`ContentView` switches on `AppState` to render the correct view. `AppViewModel` owns state transitions (handleDrop, goBack, startOver, selectCompress/Split/Merge/Rotate/Metadata/Crop/AdjustColor/ExportImages/ReorderPages).

`AppState` has custom `Equatable` because `PDFDocument` doesn't conform — equality checks compare URLs/item IDs only.

## Key conventions

- **Concurrency**: Most service methods are `async throws` with cooperative cancellation (`Task.checkCancellation()`). Progress reported via `(Double) -> Void` closure (range 0.0–1.0). `PDFMetadataEditor.write()` is `async throws` with optional progress (needed for flatten which rasterizes pages). `PDFCompressor.compressFirstPage` is `nonisolated` for background estimation.
- **Cancellation**: All ViewModels store an `operationTask: Task<Void, Never>?` and expose a `cancel()` method. Views show a Cancel button alongside progress indicators. Services check `Task.checkCancellation()` per page iteration, so cancellation takes effect within one page.
- **Source/dest guard**: Services use `FileSystemIdentity.requireDistinct` to reject source/destination aliases, including symbolic links, hard links, and case aliases, with `PDFwringerError.sourceEqualsDestination`. Plain URL equality is insufficient.
- **Sandbox**: App is sandboxed with `com.apple.security.files.user-selected.read-write`. File access uses `NSSavePanel`/`NSOpenPanel` — never raw path construction.
- **PDF reading**: `PDFCompressor.openPDF(at:)` reads file data into memory first (works around CGPDFDocument sandbox restrictions). Other services use `PDFDocument(url:)`.
- **Temp files**: Single-file saves stage in an item replacement directory on the destination volume. Batch outputs also stage on the destination volume and publish through `ExclusiveFilePublisher`. Do not revert to cross-volume temporary files or check-then-move publication.
- **State management**: ViewModels use `@Observable` (Observation framework). Views own their VM via `@State`.
- **Drop handling**: `DropReceiverView` wraps `DropNSView` (NSView subclass) for reliable drag-and-drop in sandbox. Returns `nil` from `hitTest` so SwiftUI buttons underneath remain clickable.
- **File items**: `PDFFileItem.from(url:)` constructs one readable, unlocked PDF item. Async `.load(urls:)` ignores non-PDF URLs but rejects an entire batch if any selected PDF is unreadable, missing, or locked. Never silently omit a PDF from a merge selection. Struct is `Sendable`.
- **Formatting**: `Formatting.fileSize(_:)` is the shared byte-formatting utility. `Formatting.triggerShake(_:)` provides the shared invalid-input shake animation.
- **Atomic writes**: `AtomicFileWriter` (in `PDFwringerError.swift`) checks cancellation before publication. Existing destinations use `FileManager.replaceItemAt` after an identity check; new destinations use exclusive rename to avoid overwriting a file that appeared during preparation. Staging is cleaned up on failure. The old `temporaryDirectory/PDFwringer` path is only used for legacy cleanup.
- **Logging**: `Log` enum (in `PDFwringerError.swift`) provides structured `os.Logger` instances per category (compress, merge, split, rotate, metadata).
- **Thumbnails**: `ThumbnailCache` is `@MainActor @Observable` with a generation counter for SwiftUI refresh. Page snapshots are deferred until after view construction, and each cache permits one snapshot/render at a time, including across cancellation. Authoritative PDF access stays on MainActor; isolated rendering is detached. Native PDF preview updates must cancel stale queued navigation and refresh coordinator bindings.

## Compression dual-engine

- **Lossless** (`CompressionLevel.lossless`): Clears standard document-info fields and re-serializes via PDFKit; embedded XMP and other identifying content can remain. Optional annotation removal is limited to supported types and must verify that no annotations remain in the serialized output. Forms, signatures, redactions, and unsupported annotations fail closed. Existing protection must survive serialization or the write is rejected.
- **Rasterize** (`CompressionLevel.high/medium/low`): Renders each page to a bitmap at target DPI, encodes as JPEG, assembles new PDF via CGContext. Flattens all content. Oversized pages (where point dimensions exceed A3 at the target DPI — common in scanned PDFs and iPhone photos) are automatically capped to prevent bitmap inflation.
- **Size estimation**: `CompressViewModel` provides instant heuristic estimates (based on page dimensions × DPI × JPEG ratio) shown with "~" prefix, then replaces them with real first-page estimates computed in a background task.

## Annotation flattening

`PDFMetadataEditor` supports flattening annotations via the `flattenAnnotations` parameter. When enabled, each page is rasterized at 300 DPI (JPEG quality 0.92) using `page.draw(with:to:)` which renders annotation appearances into the bitmap. The result is a visually identical PDF where annotations are burned into the page content and are no longer editable. Text selectability, accessibility tags, interactive forms, links, and digital signatures are lost. New password creation requires this explicit flattening path and verifies AES-128 output before publication; ordinary saves only retain existing protection or remove it explicitly. The operation is async with progress reporting and cancellation support.

## App bundle

`make app` creates `.build/PDFwringer.app` with proper `Info.plist` (bundle ID, icon reference, activation) and ad-hoc codesigning. `make release` adds `-O -whole-module-optimization` for distribution builds. `make sign` codesigns with a Developer ID certificate and hardened runtime (clears extended attributes before signing). `make notarize` submits to Apple's notary service and staples the ticket. `make dmg` wraps the app in a notarized disk image with an Applications symlink for drag-to-install UX. The `init()` in `PDFwringerApp` also sets `.regular` activation policy so the app works correctly when launched as a bare executable via `make run`.

Both Makefile and Xcode builds support Apple silicon only (macOS 27.0+). See
`APP_STORE.md` for the separate App Store archive/export path and outstanding
release gates; a passing ad-hoc build is not App Store signing validation.
