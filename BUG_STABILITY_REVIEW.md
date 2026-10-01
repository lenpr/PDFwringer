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
