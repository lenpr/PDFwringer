# Bug and stability sweep — 2026-10-01

Reviewed source `1c5d8fc` after the performance batches. This is a targeted broad
code review of lifecycle, concurrency, output safety, malformed inputs, PDF
preservation and UI state. It is not a new signed-candidate certification or an
exhaustive proof of all PDFKit behavior. No new tools, dependencies or permissions.

## Confirmed findings and small fixes

1. **Discard-dialog reentrancy could replace unsaved work.** The modal confirmation
   runs a nested AppKit event loop. File panels already prevented a second open,
   close or navigation event, but the discard confirmation did not. A regression
   injects Start Over, single-file Open and multiple-file intake while the user is
   deciding, declines the outer confirmation, and requires the original editor
   and dirty state to survive. The same gate now rejects nested navigation and
   blocks batch intake before it can queue work during that decision.
2. **Extreme split sizes could trap on integer overflow.** Ceiling division used
   `pageCount + n - 1`, which overflows for `Int.max` even on a tiny PDF. Chunk
   sizing is bounded to the document and division/end calculations avoid
   overflowing additions. Large positive sizes retain the existing one-file
   behavior; nonpositive sizes retain the established one-page normalization.
3. **Invalid color-page indices could crash while describing the error.** Both
   service overloads converted an invalid index to a page number with `index + 1`.
   `Int.max` trapped before the intended rejection. They now use a bounded,
   generic range error; extreme indices must throw without changing an existing
   destination or publishing any output.

## Other angles reviewed

- **Cancellation/concurrency:** detached worker ownership, cancellation forwarding,
  awaiting actual completion before staging cleanup, single-flight estimates and
  preview/thumbnail queues, stale generation/source checks, edit rollback and
  operation navigation guards. No PDFKit reference transfer added.
- **File safety:** source/destination alias checks, captured destination identity,
  same-volume staging, exclusive batch rename, collision naming and rollback
  that checks published-entry identity. Existing overwrite/cancellation/race
  tests remain the gate. Filesystem check/publication cannot be described as
  protection against every hostile external process changing directory entries.
- **Preservation/privacy:** protected-output verification, permissions, authoritative
  in-memory snapshots, annotation-sensitive fallbacks, explicit rasterization
  consent, private file/error logging and security-scope balancing. Existing XMP
  clearing limits and flattening losses remain documented, rather than widening
  the promise.
- **State/UI/lifecycle:** cold/warm Finder opens, password retry/cancel, tool entry,
  Back/Close/Quit, busy state, file-panel nested loops and discard nested loops.
  Native preview notification filtering and teardown retain their regression
  coverage. VoiceOver remains deferred; no disruptive native UI automation in
  this sweep.

## Deliberately unchanged and remaining limits

Keep PDFKit isolation, atomic/exclusive publication, existing permission policy,
conservative protected/annotated paths and explicit destructive-operation consent.
Do not refactor functioning service layers merely to remove a little repetition.
MainActor PDFKit copying/serialization and noninterruptible framework/filesystem
calls remain bounded only by the underlying operation. Native frame profiling,
slow/network/iCloud inputs and final Store-installed QA remain release evidence
work; this review does not claim those are completed. Versions and distribution
remain unchanged for the consolidated release.

Validation results are recorded in `APP_STORE.md` after the fixes are verified.

## Source-recovery follow-up — 2026-10-01

Review of `44def18` confirmed that the Compress/Split convenience source loaders
could reject a missing, corrupt or locked replacement while retaining an old
success/error message or completed progress. Split also retained the previous
operation's error category after a later successful source change. This affects
view-model reuse/noninteractive callers; production views normally receive an
already-loaded document. Failed interactive Open intentionally preserves the
current workspace and was not changed.

The loaders now clear feedback tied to the previous source on rejection, and
successful source changes reset progress/retry categories. The regression first
saves a real reviewed compression result, then exercises all three invalid input
classes and valid-source recovery. Split uses a real validation error before
replacement. Before the fix the cases failed; after the fix the output must stay
readable, old feedback must be absent, and valid-source processing must recover.
No PDF output algorithm, permission or navigation behavior changed.

## Completion and publication follow-up — 2026-10-01

Review of `3d055b7` found raster compression, annotation/password flattening and
the direct rotation writer reporting 100% inside their final page loop, before
closing, verifying and publishing the PDF. A regression reproduced this in all
four cases by trying to read the destination from the completion callback. These
writers now reserve completion for successful publication. Compression
preparation similarly reserves completion for a validated retained candidate;
the chosen destination remains untouched until Save Result.

A concurrent-replacement regression also showed that direct rotation captured
the destination identity only after its yielding page edits. A replacement
arriving during that work could therefore be overwritten. Rotation now runs
inside the existing atomic-write boundary, capturing the identity before editing
and rechecking source/destination separation before writing. This does not change
the interactive in-memory rotation path.

Regressions require exactly one completion signal with a readable output, no
completion on rejected publication, preservation of a concurrent destination,
and cancellation at the last pre-publication step. Lossless and raster review
preparation must also reject cancellation before readiness without reporting
completion or changing existing files. No new output modes or permissions added.

## Bounded source-read follow-up — 2026-10-01

Review of `ae0c370` examined source reads, cancellation/error recovery, malformed
geometry and page selections, working-copy mutations, merge ownership and
reused view-model state. One concrete resource-limit gap was found: optional
compression probes checked file size, then used an unbounded `Data(contentsOf:)`.
A source growing or being replaced after that check could exceed the intended
100 MB eager-read limit. This was identified from the code; no timing-dependent
filesystem race is claimed as a deterministic reproduction.

The existing intake reader now lives beside the raster source loader, and both
callers reuse it. Chunked reads enforce the byte limit independently of the
earlier size check and check cancellation before and after each read. The opened
descriptor is validated as a regular file; nonblocking open avoids waiting for a
pipe substituted before that validation. Regular-file symlinks remain supported.
Open errors preserve the established missing-file/permission guidance. Larger
intake sources retain their existing URL-backed fallback; oversized optional
probes retain heuristic estimates.

Tests cover exact limits at zero, one byte and either side of a 1 MiB chunk
boundary, one-byte growth beyond each limit, regular-file aliases, cancelled
reads, denied access and missing files. A pipe fixture is also rejected; the
previous optional probe already rejected that fixture, so this is preserved
behavior rather than a newly reproduced PDF-opening bug. The source-byte limit
does not imply a total process-memory bound or make framework/filesystem calls
interruptible. No new PDF operation, permission, dependency or UI flow.
