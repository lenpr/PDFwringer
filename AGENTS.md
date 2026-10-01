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
`make benchmark-performance` runs an optional optimized timing, MainActor-delay
and peak-memory benchmark with generated inputs and automatic output cleanup.
Run it without concurrent tests/builds for comparable measurements.
`make benchmark-preview` compares uncached, cached and pane-sized color previews
on verified vector/scanned inputs, including first-render, warm-filter timing
and the optional immutable-source snapshot path.
It is headless publication timing, not native mouse-to-paint latency.
`make benchmark-thumbnails` measures a newly preferred page behind older queued
requests, plus complete-queue timing, heartbeat delay and process peak memory.
`make benchmark-remaining` measures reviewed compression publication, displayed
estimate work and single-file intake. Large edit/entry modes are also included
in `benchmark-performance`. All benchmarks run sequentially, separate from builds/tests.

## Architecture

MVVM with a service layer. UI state and authoritative PDFKit documents are
`@MainActor`. Background workers reconstruct isolated pages from `Data`; PDFKit
reference objects must not be shared across actors. File-list intake and optional
compression estimates also run off MainActor. Merge workers open and own their
PDFKit documents. Unannotated, unencrypted reordering and ordinary unencrypted
metadata saves reconstruct isolated documents from a whole-document Data
snapshot; preservation-sensitive inputs keep the established MainActor path.
Lossless preparation verification and byte writes run in an isolated worker;
reviewed-result validation/publication also run in a worker. Authoritative
copying/serialization remain on MainActor. Protected metadata and partial-color
byte writes/verification use isolated snapshots without sharing PDFKit references.
Large Rotate/Crop entry validates copy isolation in batches; page mutations yield
and restore original rotations/bounds on cancellation before releasing busy state.
Rotate/Crop output writers also verify isolated snapshots using value-only
protection expectations; editing and navigation are guarded during saves.
Full-document color output streams one encoded page at a time, while partial
selections retain untouched PDF pages.

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
- **PDF reading**: Single-file intake reads immutable bytes in cancellable worker chunks capped at 100 MB, then constructs the authoritative PDFDocument on MainActor from those exact bytes. Larger sources keep URL-backed loading. Unencrypted read-only color/thumbnail snapshots may reconstruct isolated pages from those bytes, with annotation/geometry/revision safeguards; edited working copies and protected inputs keep authoritative snapshots. Never reopen a mutable file to substitute for the loaded document. Recent-file grants stay held until cancelled reads actually finish. `PDFCompressor.openPDF(at:)` reads file data into memory first (CGPDFDocument sandbox workaround); other service loaders use `PDFDocument(url:)`.
- **Temp files**: Single-file saves stage in an item replacement directory on the destination volume. Batch outputs also stage on the destination volume and publish through `ExclusiveFilePublisher`. Do not revert to cross-volume temporary files or check-then-move publication.
- **State management**: ViewModels use `@Observable` (Observation framework). Views own their VM via `@State`.
- **Drop handling**: `DropReceiverView` wraps `DropNSView` (NSView subclass) for reliable drag-and-drop in sandbox. Returns `nil` from `hitTest` so SwiftUI buttons underneath remain clickable.
- **File items**: `PDFFileItem.from(url:)` constructs one readable, unlocked PDF item. Async `.load(urls:)` ignores non-PDF URLs but rejects an entire batch if any selected PDF is unreadable, missing, or locked. Never silently omit a PDF from a merge selection. Struct is `Sendable`.
- **Formatting**: `Formatting.fileSize(_:)` is the shared byte-formatting utility. `Formatting.triggerShake(_:)` provides the shared invalid-input shake animation.
- **Atomic writes**: `AtomicFileWriter` (in `PDFwringerError.swift`) checks cancellation before publication. Existing destinations use `FileManager.replaceItemAt` after an identity check; new destinations use exclusive rename to avoid overwriting a file that appeared during preparation. Staging is cleaned up on failure. The old `temporaryDirectory/PDFwringer` path is only used for legacy cleanup.
- **Logging**: `Log` enum (in `PDFwringerError.swift`) provides structured `os.Logger` instances per category (compress, merge, split, rotate, metadata).
- **Thumbnails**: `ThumbnailCache` is `@MainActor @Observable` with a generation counter for SwiftUI refresh. Page snapshots are deferred until after view construction. A single render task drains a reorderable queue, favoring the latest preferred page; disappearing cells discard their queued size-specific requests. Each cache permits one snapshot/render at a time, including across cancellation. Document/revision/page geometry are checked before snapshotting and before cache publication. Authoritative PDF access stays on MainActor; isolated rendering is detached. Native PDF preview updates must cancel stale queued navigation and refresh coordinator bindings.
- **Color previews**: One current-page unadjusted `CGImage` is retained, with a weak source-document reference. Cache reuse requires an explicit content revision; advance it for any content/annotation edits. Unrevisioned callers always snapshot afresh. Page identity, rotation, crop/media bounds and pixel budget also invalidate reuse. The read-only color editor supplies a stable revision and a display-density-aware pane budget. Base preparation/filtering remains single-flight; cancellation discards the cache, saving pauses previews, and stale generations cannot publish. Immutable `CGImage` uses SDK Sendable conformance; authoritative PDFKit/AppKit objects never cross actors. Saved-output resolution and encoding are independent of preview sizing.

## Compression dual-engine

- **Lossless** (`CompressionLevel.lossless`): Clears standard document-info fields and re-serializes via PDFKit; embedded XMP and other identifying content can remain. Optional annotation removal is limited to supported types and must verify that no annotations remain in the serialized output. Forms, signatures, redactions, and unsupported annotations fail closed. Existing protection must survive serialization or the write is rejected.
- **Rasterize** (`CompressionLevel.high/medium/low`): Renders each page to a bitmap at target DPI, encodes as JPEG, assembles new PDF via CGContext. Flattens all content. Oversized pages (where point dimensions exceed A3 at the target DPI — common in scanned PDFs and iPhone photos) are automatically capped to prevent bitmap inflation.
- **Size estimation**: `CompressViewModel` provides instant heuristic estimates (based on page dimensions × DPI × JPEG ratio) shown with "~" prefix, then replaces them with real first-page estimates computed in a background task. The UI probes only displayed quality/color settings after a short debounce, pauses during Target Size/preparation/review, and retains a cancelled worker slot until completion to avoid overlap.
- **Prepare/review/save**: Both compression modes retain one `PreparedCompression` on the chosen destination volume. Original/result comparison uses that exact output; only Save Result publishes it. Settings/source changes and preparation cancellation discard it. Publication is async and busy-guarded; failed/cancelled publication retains the candidate for retry. Capture destination identity at preparation and recheck it at publication. Locked lossless outputs retain protection and disable result comparison.
- **Target size**: `CompressionTarget` strictly parses localized decimal MB (0.1–1,000; 1 MB = 1,000,000 bytes). Try lossless, then 300/150/72 DPI at Good quality only with explicit raster consent. At most four sequential complete attempts; only validated oversized results permit fallback. Success means measured bytes strictly below the limit. Errors and cancellation publish nothing.

## Annotation flattening

`PDFMetadataEditor` supports flattening annotations via the `flattenAnnotations` parameter. When enabled, each page is rasterized at 300 DPI (JPEG quality 0.92) using `page.draw(with:to:)` which renders annotation appearances into the bitmap. The result is a visually identical PDF where annotations are burned into the page content and are no longer editable. Text selectability, accessibility tags, interactive forms, links, and digital signatures are lost. New password creation requires this explicit flattening path and verifies AES-128 output before publication; ordinary saves only retain existing protection or remove it explicitly. The operation is async with progress reporting and cancellation support.

## App bundle

`make app` creates `.build/PDFwringer.app` with proper `Info.plist` (bundle ID, icon reference, activation) and ad-hoc codesigning. `make release` adds `-O -whole-module-optimization` for distribution builds. `make sign` codesigns with a Developer ID certificate and hardened runtime (clears extended attributes before signing). `make notarize` submits to Apple's notary service and staples the ticket. `make dmg` wraps the app in a notarized disk image with an Applications symlink for drag-to-install UX. The `init()` in `PDFwringerApp` also sets `.regular` activation policy so the app works correctly when launched as a bare executable via `make run`.

Both Makefile and Xcode builds support Apple silicon only (macOS 27.0+). See
`APP_STORE.md` for the separate App Store archive/export path and outstanding
release gates; a passing ad-hoc build is not App Store signing validation.

## Release identity

`PDFwringer/Info.plist` is the shared version/build source for both build paths.
Follow `CHANGELOG.md`: bump the visible version for each shipped user-visible
batch and the build number for every new signed candidate. Keep source, installed
app, GitHub download, Homebrew cask and App Store candidate aligned. Preserve
immutable source tags and record validation results under their actual identities.

## Artifact cleanup

After each completed batch, remove disposable test apps/PDFs, temporary scripts
and logs, expanded packages, duplicate downloads, `.build` (`make clean`), and
project-specific Derived Data. Preserve source, the external fixture corpus,
installed-app settings and receipts, and published GitHub assets.

Keep one canonical current archive with its dSYMs in Xcode's archive folder.
Store the current App Store package and essential validation/checksum/notarization
evidence in `../PDFwringer-release-evidence/current/`. Before pruning a superseded candidate,
verify that the new archive, package, symbols, and evidence are safely retained.
Older symbols may remain in `../PDFwringer-release-evidence/symbols/` only when
their UUID matches a publicly shipped executable needed for crash diagnosis.
Use temporary directories with cleanup on success and failure; do not create
increment-specific backup folders or leave obsolete local binaries behind.
