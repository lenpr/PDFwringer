# Performance and responsiveness audit

2026-09-30. Production source reviewed at `6a88146`; installed application: PDFwringer 0.2.3. The original analysis is preserved below; the implementation follow-up records unreleased changes and measured results.

## Assessment (original baseline)

The application is already compact and uses sensible foundations: native PDFKit previews, optimized arm64 builds, a lazy thumbnail strip, bounded image caching, isolated raster workers, cooperative cancellation, and one reused Core Image context. A rewrite, another PDF engine, or a general processing framework is not justified.

The largest opportunity is to remove long uninterrupted work from the interface thread. Several operations do render in the background, but return to MainActor for page serialization, output assembly, writing, and validation. Being declared `async` does not make those synchronous sections responsive. A fast progress bar cannot compensate for a final write that prevents the interface from responding for several seconds.

There are also opportunities to do less work. Reorder serializes and reconstructs every page before copying it. Color adjustment constructs and retains an image-backed PDFPage for every adjusted page, then serializes the entire output. Preview rendering uses a fixed print-like resolution and repeats work when settings change. These deserve attention before startup micro-optimizations.

## Implemented performance batch — unreleased, 2026-09-30

The first three increments and ordinary saves, unencrypted metadata writing and lossless preparation in item 4
are implemented. Item 9 now reserves completion for verified publication in
merge, reorder, and all color-output paths. Item 10 has an optional optimized
`make benchmark-performance` lane plus large-document responsiveness and
cancellation regressions. No dependencies, PDF tools, settings, permissions or
release identities changed.

Merge opens, assembles, writes and verifies its PDFKit graph in an isolated
background worker. Its progress callbacks return to MainActor; cancellation
reaches the worker and is checked before publication. Destination identity is
captured before preparation. The success message uses the actual output page
count and captured inputs.

Unannotated, unencrypted reorder operations take one authoritative Data snapshot,
then copy pages and write/verify the output in an isolated worker. The corpus
exposed PDFKit differences when whole-document snapshots include annotations;
those documents, and encrypted inputs, retain the established per-page isolation
path. Both paths capture destination approval before preparation and report 100%
only after publication. The initial snapshot and annotation scan still run on
MainActor; this improvement does not eliminate every possible complex-input
pause.

Full-document color adjustment streams one encoded page at a time into a PDF
context. It retains the existing render resolution, JPEG quality, crop/rotation
handling and modeled title/author/subject/keywords/creator metadata. The derived
PDF receives new writer timestamps; custom document-info fields are not copied.
Partial page selections retain the existing vector-page preservation path and
its final synchronous writer. Identity settings retain their preservation paths.

Ordinary unencrypted metadata output retains the existing normalization snapshot
of current in-memory content, then applies metadata, writes, verifies and commits
in a worker. The snapshot itself remains synchronous. Protected metadata saves retain their existing writer path. Lossless preparation
now verifies its serialized snapshot, writes bytes, and verifies the file in an
isolated worker with the same protection/annotation requirements. Authoritative
copying, metadata/annotation edits and serialization still run on MainActor, as
does final prepared-compression validation when saving a reviewed result. Their
protection and preservation policies have not been relaxed.
Rotate/Crop saves now capture destination approval before their snapshot and
write/verify in an isolated worker using value-only protection expectations.
Both task flows show the existing save phase with a Cancel control, disable
editing and Back, reject repeated saves and guard navigation/drop/close while
saving. Cancellation keeps the working copy dirty; only a published output
clears it. The initial snapshot remains on MainActor.

The new corpus comparison runs every reorder fixture against the established
serialization path, checking non-whitespace text, page geometry, annotation
contents/bounds and form values. It tolerates only inferred whitespace changes
and 0.001-point annotation rounding. Existing PDFKit normalization of some form
values and nonzero origins is not a promise of exact source equivalence; native
form/appearance fidelity remains a release-review concern. Working-copy edits,
source isolation, changed destinations and cancellation are covered separately.

The measured service gains below are headless optimized results on the same
machine and inputs as the original audit. They measure elapsed time, MainActor
heartbeat delay and whole-process peak RSS across three iterations per operation.
They do not establish cold launch time, native animation quality, GPU memory or
Store-installed behavior. Merge memory is essentially unchanged. No leak claim
is inferred from peak RSS.

| Operation | Median time, before → after | Max MainActor delay, before → after | Process peak RSS, before → after |
|---|---:|---:|---:|
| Merge 10 × 87 pages | 5,142.7 → 4,843.0 ms | 5,284.3 → 2.6 ms | 645.7 → 657.6 MiB |
| Reorder 400 pages | 7,708.7 → 2,406.1 ms | 4,236.9 → 77.3 ms | 527.8 → 133.2 MiB |
| Adjust all 400 pages | 22,228.4 → 14,599.5 ms | 6,622.0 → 59.7 ms | 1,352.3 → 153.0 MiB |
| Metadata, 2,000 pages | 947.6 → 937.4 ms | 982.0 → 335.0 ms | 442.7 → 445.1 MiB |
| Ordinary save, 2,000 pages | 502.9 → 494.5 ms | 498.2 → 336.8 ms | 379.0 → 376.9 MiB |
| Lossless API, 2,000 pages | 782.7 → 675.2 ms | 811.6 → 365.9 ms | 485.6 → 401.5 MiB |

Merge/reorder/metadata measurements use the complete worker changes; color,
ordinary save and lossless were measured again after the final refinements.
Lossless timings cover the direct service API; the reviewed compression flow
also performs its existing synchronous final validation at publication. The
unchanged medium-compression control measured 12,974 ms, 57 ms maximum delay,
and 114 MiB peak RSS. Variability in unchanged code illustrates why throughput
claims should use broad bounds and repeated native measurements. No startup
improvement is claimed in this batch.


Final verification: 420 tests passed (349 fast, 62 corpus, 9 performance),
optimized app build, strict bundle-signature verification and unsigned App Store
archive structure check passed. Native interactive checks and VoiceOver
remain deferred; the installed app and signed 0.2.3 candidates remain unchanged
until the consolidated release. Remaining snapshot/protected-writer work and complex-page
preview reuse are the next increments, before optional scheduling and
animation refinements.

## How the baseline was measured

- Apple M2 Pro, 12 CPU cores, 32 GiB RAM, macOS 27.0, build 26A428; Swift 6.4.
- An optimized harness compiled the actual services, models, utilities, and view models with `-O -whole-module-optimization`, Swift 6, strict concurrency, and the arm64 macOS 27 target. These were not timings from a debug build.
- **217 baseline executions across 73 input/operation combinations**: three executions per combination, except one cancellation probe. An additional six executions compared two temporary implementation experiments; three short probes broke down working-copy costs.
- Real checksum-verified fixtures: `tracemonkey.pdf` (14 pages, 1,016,315 bytes), `fdsys_architecture.pdf` (87 pages), and `usgs_orthoimagery.pdf` (4 image-heavy pages). The 400- and 2,000-page stress documents repeat copied tracemonkey pages: 16,791,894 and 83,374,914 bytes respectively. Repeated content is a deterministic stress test, not a representative distribution of every customer's documents.
- Operations ran sequentially. Compilation and profiling were excluded from baseline timing. Other applications remained in use; the machine was not rebooted, filesystem caches were not purged, and thermal/power conditions were not controlled. The results establish priorities on this machine, not universal product promises.
- Each operation ran with a MainActor task scheduled to wake every 5 ms. “Interface delay” below means the largest observed wake-up lateness, after subtracting those 5 ms, over the three executions. It includes scheduling noise and the short observation tail; it is **not a measured frame rate or a complete mouse-to-paint latency**. Long multi-second gaps nevertheless identify serious blocking reliably.
- “Peak memory” is the harness process's maximum resident set size, across its three executions. It includes framework allocations, source documents, and any allocator/cache retention. It is not the installed app's idle memory or a count of bytes belonging exclusively to the operation.
- Source documents were opened before timing operations other than `open`. `open` measures PDF construction, page count, and first-page bounds; it excludes file-panel interaction, recent-bookmark work, and visible PDFView drawing. Color-preview timing includes the existing 100 ms debounce and waiting for the published preview. Thumbnail timing covers completing up to 12 requested thumbnails, not displaying the first one.
- Merge cases concatenate **ten copies** of the named input. Thus the 87-page input produces an 870-page output. Split cases create one output per page. Compression cases include prepare and commit, using Good quality and color output. Export cases use 150 DPI. Ordinary saves measure `DocumentSaver`; rotate/crop/resize measure in-memory mutations.

Apple describes interaction delays around 50–100 ms as perceptible and recommends keeping interface work short. Animation frame budgets are tighter still. These provide a useful direction, but three executions cannot establish a statistically meaningful p95/p99. [Apple: improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness), [understanding user interface responsiveness](https://developer.apple.com/documentation/xcode/understanding-user-interface-responsiveness).

## Baseline that matters most

Times are median elapsed time and worst observed interface delay. A long elapsed time is acceptable for real document processing if the interface continues responding.

| Existing operation | Median elapsed | Worst interface delay | Peak memory |
|---|---:|---:|---:|
| Open local 14-page PDF, excluding visible preview | 0.3 ms | 1.3 ms | 17 MiB |
| Open local 2,000-page PDF, excluding visible preview | 3.4 ms | 35.5 ms | 20 MiB |
| First 12 vector thumbnails, 14-page input | 278 ms | 50.5 ms | 40 MiB |
| All 4 image-heavy thumbnails | 1.05 s | 204 ms | 58 MiB |
| Color preview, ordinary vector page | 149 ms | 15 ms | 79 MiB |
| Color preview, image-heavy page | 424 ms | 160 ms | 114 MiB |
| Merge ten 14-page PDFs | 1.23 s | **1.23 s** | 80 MiB |
| Merge ten 87-page PDFs | 5.14 s | **5.28 s** | 646 MiB |
| Reorder 400 pages | 7.71 s | **4.24 s** | 528 MiB |
| Adjust colors on 400 pages | 22.23 s | **6.62 s** | **1,352 MiB** |
| Medium raster compression, 400 pages | 14.82 s | 91 ms | 114 MiB |
| High raster compression, 400 pages | 27.62 s | 222 ms | 192 MiB |
| Split 400 pages into individual files | 7.24 s | 100 ms | 62 MiB |
| Save ordinary 2,000-page document | 503 ms | **498 ms** | 379 MiB |
| Save metadata on 2,000-page document | 948 ms | **982 ms** | 443 MiB |
| Enter rotate/crop working copy, 2,000 pages | 214 ms | **213 ms** | 92 MiB |
| Lossless compression, 2,000 pages | 783 ms | **812 ms** | 486 MiB |

The cancellation probe requested cancellation after roughly 100 ms of high raster compression on 400 pages. It completed about 1.7 ms after the request and published nothing. This is encouraging for that run; it does not certify cancellation during a complex page, final serialization, or a slow-volume write.

### Startup

One App Launch Instruments recording used the actual installed, signed app. The recorded system-interface initialization began at 450.5 ms on the trace timeline; initial frame rendering ended at 875.2 ms. That observable initialization-to-frame interval is approximately **425 ms**. Initial-frame rendering itself took 18.9 ms; one AppKit scene-creation interval took 197.5 ms; `applicationDidFinishLaunching` took 2.3 ms.

This is a **single instrumented process launch**, not a cold-boot benchmark or a Finder-click-to-interactive measurement. The recording origin is not a reliable substitute for the user's launch gesture. Consequently, neither 425 ms nor 875 ms should be advertised as a complete launch-time guarantee. The recording reported a profiler sampling-period warning; the lifecycle intervals were exported successfully. Instrumentation ended its target process at the time limit; that is not an application crash.

The current evidence does not identify a large startup bottleneck in our launch callback. Recent-bookmark resolution and legacy cleanup remain plausible tail-latency risks on unavailable/slow volumes; they were not tested with those conditions. Warm/cold launch, first visible PDF frame, idle memory, and scrolling/resize frame rates need dedicated native measurements before making stronger claims. [Apple: reducing launch time](https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time).

## Experiments: substantial gains without a rewrite

These experiments were confined to disposable harness sources. **The app's implementation was not changed.** Their ordinary page-count/readability and existing publication checks ran, but encrypted files, annotation/form behavior, visual fidelity, cancellation, sandbox access, and production UI progress handling were not comprehensively requalified.

| Experiment | Current source | Temporary variant | Interpretation |
|---|---:|---:|---|
| Merge 870 pages: worst interface delay | 5,284 ms | **3.9 ms** | Constructing/using worker-owned PDFKit objects off MainActor removed the freeze. |
| Merge 870 pages: median elapsed | 5,143 ms | 5,047 ms | Similar throughput; the meaningful gain is responsiveness. |
| Merge 870 pages: peak resident memory | 646 MiB | 663 MiB | No memory improvement demonstrated. |
| Reorder 400 pages: median elapsed | 7,709 ms | **2,381 ms** | Copying pages directly instead of serializing/reopening every page was about 69% faster. |
| Reorder 400 pages: peak resident memory | 528 MiB | **125 MiB** | About 76% lower peak memory in this test. |
| Reorder 400 pages: worst interface delay | 4,237 ms | 2,342 ms | Simpler copying helps, but final serialization still needs attention. |

A separate one-second stack sample during the existing 870-page merge placed all 665 sampled main-thread stacks beneath `PDFConcatenator.concatenate` → `AtomicFileWriter.write` → `PDFDocument.writeToURL`. Most descended into PDFPage/Core Graphics content processing. This corroborates the heartbeat: the final PDFKit write is the blocking phase, rather than the view's progress display.

The 2,000-page working-copy breakdown was also revealing: `PDFDocument.copy()` took about **1.7 ms**; eagerly retrieving and comparing source/copy page identities took **201–210 ms**. Preserve that safety check, but schedule its work in bounded batches instead of replacing PDFKit copying or abandoning isolation checks.

## Prioritized backlog (original findings; implementation status above)

Effort estimates are relative: small means a localized change, medium means a service-path change with substantive regression verification. They are not delivery commitments.

### 1. Move merge processing off the interface thread

**Impact: very high. Effort: medium. Evidence: measured and prototyped.**

[PDFConcatenator.swift](PDFwringer/Services/PDFConcatenator.swift:73) yields during insertion but performs its final write and verification synchronously on MainActor. Merge inputs are URLs, so an isolated worker can open and own its own PDFDocuments without transferring the authoritative preview documents between actors. Keep sequential input handling and the current identity, permission, staging, verification, and exclusive-publication guarantees. Send only value progress/results back to the view model, with stale-operation guards and bounded progress updates.

The prototype removes seconds of blocking with similar total processing time. It does not make PDFKit's internal write cooperatively interruptible: Cancel must respond visually immediately, then publication must remain suppressed if cancellation arrives while the writer is finishing.

### 2. Delete the redundant reorder serialization round trip

**Impact: very high. Effort: small for the simplification; medium for completing responsive saving. Evidence: measured and prototyped.**

[PDFPageReorderer.swift](PDFwringer/Services/PDFPageReorderer.swift:30) serializes each page, opens a new single-page document, then copies the reconstructed page. Test direct page copying under MainActor instead, maintaining independent page objects and all page-order/protection policies. It dramatically reduced throughput cost and peak memory on the stress document.

Requalify source immutability, annotations, forms, rotation/crop boxes, text, and owner-restricted/unlocked inputs before adoption. Final output serialization at line 43 still blocks; do not describe the direct-copy change alone as solving responsiveness. Avoid introducing a parallel page-reorder engine.

### 3. Bound color-adjustment output memory and eliminate its final freeze

**Impact: very high. Effort: medium. Evidence: measured bottleneck; proposed remedy not prototyped.**

[PDFColorAdjuster.swift](PDFwringer/Services/PDFColorAdjuster.swift:175) converts each encoded JPEG into NSImage/PDFPage and retains all those pages in an output PDFDocument. The final `outputDocument.write` at line 203 is synchronous. This is the worst measured memory/latency combination: 1.32 GiB peak resident memory and a 6.6-second interface gap on 400 pages.

The first color-save execution in that process reached 890 MiB; the second and third raised the process high-water mark to 1,071 and 1,352 MiB. This warrants native memory investigation, but does not by itself prove a leak: the headless harness does not reproduce AppKit's event-loop lifetime, and allocator/framework cache retention contributes to resident memory.

For the all-pages-adjusted case, evaluate the existing compressor's page-by-page CGContext/JPEG assembly pattern instead of retaining image-backed PDFPages. For mixed selections, preserve untouched vector pages and their existing behavior; do not obtain speed by rasterizing extra pages. A compact single-page encoded-PDF representation is another candidate, but requires profiling rather than assuming it is cheaper.

Preserve metadata, geometry, explicit protection-removal disclosures, annotation appearances, atomic publication, and cancellation. Verify memory stays bounded as page count grows. Do not silently reduce saved DPI or JPEG quality.

### 4. Make ordinary, metadata, and lossless saves responsive

**Impact: high. Effort: medium. Evidence: measured.**

[DocumentSaver](PDFwringer/Utilities/PDFwringerError.swift:355), [normal metadata writing](PDFwringer/Services/PDFMetadataEditor.swift:182), and [lossless compression](PDFwringer/Services/PDFCompressor.swift:286) serialize/write/verify synchronously. Even an 83 MB input creates roughly 0.5–1 second of blocking. Rotate and Crop call DocumentSaver directly from button handlers and do not have a visible asynchronous save phase.

Move value-only file I/O and worker-owned output validation off MainActor, then address the serialization itself. Moving `Data.write` alone is insufficient when `dataRepresentation()` is the expensive section. Authoritative PDFKit objects must remain on MainActor. A worker must reconstruct from immutable content or independently open a permitted source; passing `document.copy()` into a detached task is not an acceptable shortcut.

Prefer a small async extension of the existing save path, retaining one publication policy. Protect in-memory unlocks and edits from accidental disk reopen or serialization changes. Keep cancellation and close/quit guarding accurate throughout the save.

### 5. Reduce complex-page snapshot work on MainActor

**Impact: high for scans and complex PDFs. Effort: medium. Evidence: measured.**

[ThumbnailCache](PDFwringer/Utilities/ThumbnailCache.swift:50), [color previews](PDFwringer/ViewModels/ColorAdjustViewModel.swift:89), and raster/export paths serialize a PDFPage before handing Data to a worker. This keeps actor ownership safe, but one image-heavy page snapshot took about **130 ms**, before rendering began. Debouncing, yielding between pages, and prioritizing workers cannot interrupt that synchronous call.

First reuse a valid snapshot of the current page when only color settings change. Key it to document identity/revision and page geometry, invalidate correctly, and keep the cache small and in memory. Then prototype worker-owned read-only document access for eligible workflows. A whole-document immutable snapshot can avoid repeated page serialization, but may itself block and duplicate substantial memory. Encrypted/unlocked documents and edited working copies need an explicit safe path; retain the present per-page fallback where necessary.

The stress-only `snapshot-all` probe took 3.71 seconds without yielding. That probe is **not an existing app flow**; it illustrates why eagerly snapshotting an entire thumbnail list would be a regression.

### 6. Make color sliders reuse work and render only the necessary preview pixels

**Impact: high for perceived speed. Effort: small to medium. Evidence: stage timings plus code.**

[ColorAdjustViewModel](PDFwringer/ViewModels/ColorAdjustViewModel.swift:80) waits 100 ms for every preview request, serializes the page, renders it at 150 DPI, filters it, JPEG-encodes it, and reconstructs NSImage. A letter page becomes **2,103,750 pixels** regardless of how small the preview pane is.

Use the preview's displayed size and backing scale to choose a bounded resolution; keep saved output quality unchanged. Retain one unadjusted current-page render so slider changes apply only the filter. Preserve single-flight execution and latest-request publication. Avoid repeating identical requests, including several individual change handlers when a preset changes brightness, contrast, and saturation together.

Use the debounce for continuous slider changes; initial page display and discrete preset activation can have a shorter/direct path. Maintain a correctly identified preview while updates finish and avoid briefly presenting the previous page as the current one. Geometry-stable placeholders should match the actual page aspect ratio instead of the current fixed A-series ratio.

Warm vector-page stage costs were approximately 6–8 ms snapshot, 10–11 ms render, 5–8 ms filter, and 9 ms JPEG encode. First Core Image use added 183 ms in a separate process; it already happens off MainActor. The image-heavy page still spent about 130 ms snapshotting and 146 ms rendering. Caching and smaller previews can help, but no numerical speedup is promised until measured. Keep the existing reused CIContext. [Apple: Core Image processing guidance](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/CoreImaging/ci_tasks/ci_tasks.html).

### 7. Prioritize useful thumbnails and optional estimates

**Impact: medium to high on navigation. Effort: small to medium. Evidence: code and measured completion times.**

[ThumbnailCache](PDFwringer/Utilities/ThumbnailCache.swift:40) serializes requests behind one task tail. This prevents allocation storms, but a newly requested visible/current page can wait behind previously requested pages. Leaving the screen cancels the cache; moving a cell offscreen does not remove just that queued request. Give the current/visible pages priority, discard obsolete queued work, and retain single-flight rendering. Do not expand to an unbounded parallel renderer.

Every thumbnail completion increments one shared generation. [The strip](PDFwringer/Views/PageThumbnailStripView.swift:67) and [reorder rows](PDFwringer/Views/ReorderPagesView.swift:31) observe it; reorder also rebuilds an enumerated array. Profile native view-update cost before adding per-cell observation or changing List. Avoid reconstructing all page metadata for every completion when measurement confirms it matters. The existing LazyHStack is already the correct starting point. [Apple: performant scrollable stacks](https://developer.apple.com/documentation/swiftui/creating-performant-scrollable-stacks/).

[Exact compression estimates](PDFwringer/Services/PDFCompressor.swift:231) render six DPI/color combinations and perform 24 JPEG encodes before publishing all estimates. They took 117–946 ms in the fixture probes and up to 184 MiB peak resident memory. The app already supplies instant heuristics. Probe the selected setting first, defer unused combinations, and pause optional work while preparing/saving. Keep cancellation, the 100 MB eager-read limit, and generation guards. This is an efficiency opportunity, not a measured interface freeze: the estimator heartbeat stayed responsive.

### 8. Batch large-document validation and page mutations

**Impact: medium; low implementation complexity. Effort: small to medium. Evidence: measured breakdown.**

[AppViewModel.makeWorkingCopy](PDFwringer/ViewModels/AppViewModel.swift:453) eagerly validates every source/copy page identity before navigation. On 2,000 pages, copying was cheap but this loop cost about 203 ms. Validate in bounded MainActor batches with cancellation and state-generation checks. Keep the all-page isolation guarantee before editing becomes available.

In-memory rotate, crop, and resize loops each reached around 100 ms on the same stress document. Apply mutations in bounded batches where worthwhile, preserving current rollback/unsaved-change behavior. Small documents should remain immediate; do not introduce visible progress UI for operations that ordinarily finish within a few milliseconds.

### 9. Make feedback match the real processing phases

**Impact: high to perceived polish; depends on removing blocking first. Effort: small. Evidence: code.**

Several page loops report progress 1.0 before the final PDF write and verification. That can leave a 100% bar displayed while the app is blocked and the file does not yet exist. Keep completion reserved for verified publication. Reuse the existing status area for clear preparation/writing/verification phases, with an indeterminate final phase where a percentage would be invented. Avoid speculative time-remaining estimates.

File-list intake already runs off MainActor, but has no clear in-progress presentation. Add timely feedback within the existing landing/file-list flow only when intake actually takes long enough to notice. Preserve neutral Select Files wording, latest-intake behavior, and prompt cancellation. Single-file open/bookmark updates still run synchronously; off-volume/iCloud/network tail behavior needs measurement before changing that path.

The navigation animations use 300 ms springs; thumbnail scroll animations use 200 ms. Once native frame traces are available, evaluate a consistent, shorter transition around 150–200 ms and avoid animating expensive PDF layout unnecessarily. Keep page/viewport continuity and Reduce Motion. This is refinement of existing interactions, not a new mode or control.

### 10. Establish performance gates that catch interface freezes

**Impact: very high for retaining improvements. Effort: small to medium. Evidence: test coverage gap.**

[PerformanceAndLifecycleTests](PDFwringerTests/PerformanceAndLifecycleTests.swift:12) uses a coarse 30-second throughput bound. Those tests can pass even with seconds of interface blocking. Keep them as broad safeguards, but add a small optimized benchmark lane covering ordinary vector PDFs, complex image pages, large page counts, merge, reorder, and color output. Record phase duration, maximum MainActor gaps, peak memory, and cancellation-to-cleanup time separately.

Add privacy-safe local signposts around intake, first visible preview, snapshots, render/filter/encode, serialization, verification, and publication. Existing category loggers and total operation durations can be retained. Log counts, settings, and elapsed times; avoid filenames, paths, PDF text, metadata contents, and passwords. No analytics service is needed.

Pair service measurements with native App Launch, SwiftUI/animation, memory, and interaction traces. Include slow destinations, large scanned PDFs, rapid navigation, repeated open/close cycles, cancelled operations, and memory pressure. Correctness checks must still cover source preservation, annotations/forms, passwords, output fidelity, and no-clobber writes. [Apple: improving performance](https://developer.apple.com/documentation/xcode/improving-your-app-s-performance), [SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance).

## Lower-priority refinements

- Defer recent-bookmark resolution and legacy temporary-file migration off the startup critical path; batch recent updates when opening many files. [BookmarkManager](PDFwringer/Utilities/BookmarkManager.swift:19) repeatedly resolves up to ten entries for each newly opened file. Consider noninteractive/nonmounting resolution where appropriate, preserving stale-bookmark migration and access balancing. Unavailable-volume behavior is currently unmeasured; no startup saving is claimed. Remove the one-release legacy cleanup only after its migration window is confirmed complete. [Apple: noninteractive bookmark resolution](https://developer.apple.com/documentation/foundation/nsurl/bookmarkresolutionoptions/withoutui).
- Move [exported image Data writes](PDFwringer/Services/PDFImageExporter.swift:189) off MainActor; separately profile large batch publication. Disk speed may dominate on external/network destinations. Preserve destination-volume staging and rollback rather than publishing pages early.
- Add an explicit per-page byte/pixel ceiling where exposed resolution and memory pressure warrant one. The UI exports at most 300 DPI, but the exporter service accepts 2,400 DPI; the A3 cap scales with DPI and therefore does not impose a fixed memory ceiling. Color output accumulation is the measured current concern. Do not lower selected quality or reject normal documents merely to satisfy an arbitrary memory number.
- If measurements justify it, reuse a bounded thumbnail/snapshot cache across read-only tool transitions. Rotation and crop require independent working documents and geometry invalidation. A global document cache, disk preview cache, or persistent document history would add privacy/lifecycle complexity and is not justified here.
- Investigate the TIFF/JPEG handoff only after eliminating larger costs. Encoded bytes are a safe actor boundary; removing encoding by sharing unsafe PDFKit or mutable AppKit objects would be a poor trade.

## What to deliberately leave alone

- **The architecture and native PDF viewer.** MVVM and the current service boundaries are adequate. There is no evidence for replacing SwiftUI, building a custom PDF renderer, adding dependencies, or wrapping every operation in a new framework.
- **Sequential page rendering and bounded caches.** More simultaneous raster jobs could reduce elapsed time but increase peak memory, CPU contention, battery use, and cancellation complexity. First remove redundant work and final main-thread writes.
- **PDF output safety.** Keep actor isolation, protection checks, page/annotation verification, source/destination identity guards, same-volume staging, no-clobber publication, and rollback. Expensive validation should be scheduled safely rather than deleted.
- **Saved document quality.** Smaller previews are appropriate; silent reductions of export DPI or fidelity are not. Lossless and raster compression have different semantics and should remain explicit.
- **The reused Core Image context, lazy strip, native window controls, and release optimization flags.** These are already sensible. Do not prewarm the whole graphics stack during app launch solely to move a delay somewhere else.
- **The neutral landing screen and current feature set.** Faster feedback, predictable progress, and continuity can improve delight without new tools, onboarding screens, settings, background services, or cloud processing.

## Acceptance targets and missing native evidence

These are proposed engineering goals, not measured guarantees. Establish repeatable baselines per device/input before enforcing them:

| Experience | Proposed acceptance criterion |
|---|---|
| Ordinary button/keyboard action | Visible acknowledgement within roughly 50–100 ms; no unexplained stalls |
| Long PDF operation | MainActor work normally in short slices; eliminate all measured multi-second gaps and investigate repeated gaps above 50 ms |
| Smooth scrolling/divider/zoom | Measure real frames at the display's refresh rate; aim for short view updates rather than treating the 100 ms hang threshold as an animation budget |
| Initial preview | Measure open request → first correctly identified visible page; separate local, unavailable-volume, encrypted, and complex-page cases |
| Color sliders | Fast latest-setting feedback on ordinary pages; bounded cached render; no stale-page flashes or overlapping render allocations |
| Cancellation | Immediate acknowledgement; bounded completion/cleanup after the current uninterruptible library call; no output published after cancellation |
| Color output memory | Does not grow in proportion to retained decoded page bitmaps; compare 20/100/400-page runs rather than enforcing one universal RSS cap |
| Repeated workflows | No sustained memory growth after warm-up across repeated open/tool/back/close cycles; no accumulated temporary outputs |
| Launch | Repeat warm/cold installed-app measurements; retain the current lean landing path and defer optional work |

Not measured in this batch: end-to-end mouse/key-to-visible-response latency, native PDFView first-page paint, frame pacing during resize/zoom/scroll, idle app footprint, sustained memory retention, energy use, slow/removable/network destinations, iCloud materialization, reboot-cold caches, and performance inside the final App Store/TestFlight installation. VoiceOver remains deferred at the user's request. No system accessibility settings were changed.

## Recommended increments

1. Add minimal phase/heartbeat measurement and make the merge worker responsive; requalify progress, cancellation, sandbox access, and atomic publication.
2. Simplify reorder copying, prove content/source preservation across the corpus, and remove its final serialization freeze.
3. Bound color-output memory; optimize the existing preview's current-page render and invalidate it correctly.
4. Make ordinary/metadata/lossless saving asynchronous safely; batch large-document verification and mutation work.
5. Refine thumbnail priority, estimate scheduling, truthful progress, and transition timing against native traces.

Perform these as small measured changes. Keep one consolidated release update after verification. The top ten backlog entries above are the proposed order of work; none require new product functionality.

## Full measured baseline

Milliseconds throughout. Peak RSS is MiB. Three executions per row except cancellation. `snapshot-all` is a deliberately uninterrupted stress probe, not an existing user workflow; `color-stages` excludes the UI debounce and measures the page snapshot/render/filter/encode chain. The full table preserves these measurements after disposable harnesses and generated documents are removed.

| Input | Operation | Median ms | Min–max ms | Max interface delay ms | Peak RSS MiB |
|---|---|---:|---:|---:|---:|
| tracemonkey.pdf | open | 0.3 | 0.2–4.3 | 1.3 | 17.0 |
| tracemonkey.pdf | copy | 0.5 | 0.5–1.7 | 1.3 | 17.7 |
| tracemonkey.pdf | serialize | 8.0 | 8.0–13.8 | 8.8 | 22.1 |
| tracemonkey.pdf | snapshot | 7.6 | 6.7–14.3 | 9.3 | 19.8 |
| tracemonkey.pdf | thumbnail | 277.8 | 277.7–301.8 | 50.5 | 40.0 |
| tracemonkey.pdf | color-stages | 34.0 | 32.5–223.0 | 2.9 | 77.1 |
| tracemonkey.pdf | color-preview | 148.6 | 144.2–201.9 | 15.0 | 78.8 |
| tracemonkey.pdf | estimate | 234.0 | 232.6–256.0 | 1.3 | 62.1 |
| tracemonkey.pdf | lossless | 39.8 | 39.0–64.1 | 59.1 | 24.6 |
| tracemonkey.pdf | medium | 543.4 | 526.3–574.3 | 66.5 | 74.6 |
| tracemonkey.pdf | high | 1059.9 | 1016.8–1071.2 | 76.1 | 162.2 |
| tracemonkey.pdf | save | 21.4 | 19.1–22.8 | 17.8 | 22.5 |
| tracemonkey.pdf | rotate | 0.3 | 0.3–0.4 | 1.3 | 17.5 |
| tracemonkey.pdf | merge | 1231.8 | 1221.6–1239.7 | 1233.2 | 80.3 |
| tracemonkey.pdf | split | 279.9 | 260.0–288.1 | 66.8 | 29.3 |
| tracemonkey.pdf | reorder | 301.1 | 297.9–303.9 | 145.0 | 47.3 |
| tracemonkey.pdf | color-save | 826.2 | 783.3–883.1 | 256.5 | 160.6 |
| fdsys_architecture.pdf | open | 1.0 | 0.8–6.3 | 1.4 | 17.8 |
| fdsys_architecture.pdf | copy | 3.4 | 3.1–3.9 | 1.3 | 20.6 |
| fdsys_architecture.pdf | serialize | 32.0 | 29.7–32.5 | 27.5 | 29.6 |
| fdsys_architecture.pdf | thumbnail | 121.3 | 120.0–136.8 | 13.9 | 41.5 |
| fdsys_architecture.pdf | color-preview | 147.3 | 128.8–179.8 | 27.0 | 81.7 |
| fdsys_architecture.pdf | estimate | 116.7 | 116.1–125.7 | 1.4 | 56.6 |
| fdsys_architecture.pdf | lossless | 86.1 | 82.3–90.7 | 85.8 | 33.5 |
| fdsys_architecture.pdf | medium | 2330.2 | 2319.0–2339.1 | 40.8 | 181.0 |
| fdsys_architecture.pdf | save | 57.4 | 49.2–57.6 | 52.6 | 31.5 |
| fdsys_architecture.pdf | merge | 5142.7 | 5136.9–5315.0 | 5284.3 | 645.7 |
| fdsys_architecture.pdf | split | 1283.0 | 1233.5–1423.0 | 53.6 | 81.4 |
| fdsys_architecture.pdf | reorder | 1062.8 | 1042.5–1068.3 | 475.0 | 183.2 |
| fdsys_architecture.pdf | color-save | 4289.2 | 3899.4–4345.8 | 1495.6 | 397.8 |
| usgs_orthoimagery.pdf | open | 4.2 | 3.9–6.2 | 1.3 | 18.7 |
| usgs_orthoimagery.pdf | copy | 0.3 | 0.3–0.4 | 1.3 | 18.8 |
| usgs_orthoimagery.pdf | snapshot | 130.2 | 129.7–142.8 | 137.8 | 33.7 |
| usgs_orthoimagery.pdf | thumbnail | 1048.9 | 900.4–1083.3 | 203.7 | 58.3 |
| usgs_orthoimagery.pdf | color-stages | 293.0 | 291.0–423.4 | 137.7 | 116.0 |
| usgs_orthoimagery.pdf | color-preview | 424.0 | 404.1–474.7 | 159.5 | 113.5 |
| usgs_orthoimagery.pdf | estimate | 945.6 | 942.0–979.1 | 2.2 | 183.6 |
| usgs_orthoimagery.pdf | lossless | 64.7 | 63.1–76.3 | 71.4 | 24.5 |
| usgs_orthoimagery.pdf | medium | 1128.7 | 1115.9–1157.5 | 169.1 | 139.3 |
| usgs_orthoimagery.pdf | high | 1791.6 | 1749.3–1824.5 | 204.7 | 275.5 |
| usgs_orthoimagery.pdf | color-save | 1249.7 | 1229.2–1344.7 | 166.5 | 156.7 |
| vector-400.pdf | open | 0.9 | 0.8–3.9 | 1.3 | 17.6 |
| vector-400.pdf | copy | 23.3 | 23.0–24.2 | 19.2 | 32.1 |
| vector-400.pdf | serialize | 72.6 | 72.3–79.6 | 74.6 | 114.4 |
| vector-400.pdf | snapshot-all | 3714.0 | 3712.6–3763.4 | 3758.4 | 66.0 |
| vector-400.pdf | thumbnail | 279.9 | 275.2–302.9 | 52.7 | 40.0 |
| vector-400.pdf | color-preview | 136.2 | 132.4–228.8 | 8.6 | 78.7 |
| vector-400.pdf | estimate | 233.4 | 231.4–242.8 | 1.4 | 77.7 |
| vector-400.pdf | lossless | 182.0 | 142.7–265.7 | 260.7 | 116.6 |
| vector-400.pdf | medium | 14824.4 | 14226.9–15086.1 | 91.2 | 113.8 |
| vector-400.pdf | high | 27623.1 | 27410.5–28124.9 | 221.5 | 191.8 |
| vector-400.pdf | save | 104.5 | 95.2–116.0 | 111.0 | 109.3 |
| vector-400.pdf | rotate | 10.3 | 10.2–11.2 | 6.3 | 27.8 |
| vector-400.pdf | reorder | 7708.7 | 7688.1–8046.1 | 4236.9 | 527.8 |
| vector-400.pdf | color-save | 22228.4 | 22176.6–22531.8 | 6622.0 | 1352.3 |
| vector-400.pdf | cancel | 123.9 | 123.9–123.9 | 43.2 | 104.0 |
| vector-2000.pdf | open | 3.4 | 2.8–40.5 | 35.5 | 19.7 |
| vector-2000.pdf | copy | 214.3 | 213.3–217.8 | 212.8 | 92.0 |
| vector-2000.pdf | serialize | 343.9 | 343.3–354.9 | 349.9 | 328.3 |
| vector-2000.pdf | snapshot | 5.6 | 5.4–7.6 | 2.6 | 23.3 |
| vector-2000.pdf | thumbnail | 273.0 | 270.9–277.9 | 49.3 | 41.2 |
| vector-2000.pdf | save | 502.9 | 497.5–503.2 | 498.2 | 379.0 |
| vector-2000.pdf | rotate | 101.9 | 100.7–106.7 | 101.8 | 70.4 |
| vector-2000.pdf | lossless | 782.7 | 765.7–816.5 | 811.6 | 485.6 |
| tracemonkey.pdf | metadata | 25.6 | 25.3–30.0 | 25.0 | 24.5 |
| tracemonkey.pdf | flatten | 1047.2 | 1037.5–1060.7 | 76.9 | 152.1 |
| tracemonkey.pdf | export-jpeg | 447.3 | 433.3–465.9 | 56.2 | 58.5 |
| tracemonkey.pdf | export-png | 609.9 | 604.1–651.8 | 69.6 | 60.0 |
| tracemonkey.pdf | intake-20 | 2.9 | 2.9–3.2 | 1.3 | 17.3 |
| vector-400.pdf | split | 7238.3 | 7235.8–7411.3 | 99.7 | 62.4 |
| vector-2000.pdf | metadata | 947.6 | 945.9–987.0 | 982.0 | 442.7 |
| vector-2000.pdf | crop | 104.2 | 101.8–107.7 | 102.8 | 70.9 |
| vector-2000.pdf | resize | 103.7 | 103.6–108.7 | 103.9 | 70.0 |
