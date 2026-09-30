# Compression: target size and original/result comparison

Design prepared on 2026-09-29. **Not implemented.** The current validated release
candidate remains `0.1.16 (2)` at `df32247`.

Only these two increments are in scope. The other brainstormed ideas are dropped.

## Product goal

Help someone get a PDF below an upload limit and inspect the actual result before
publishing it. Keep this inside the existing Compress screen, using the current
PDFKit/Core Graphics engines. No extra top-level action or general workflow system.

The promises are deliberately narrow:

- A successful target-size result is measured from the complete output file.
- The comparison displays the exact prepared PDF that will be saved.
- Neither the source nor an existing destination changes during preparation.
- Rasterization requires an explicit choice and retains the current disclosures.
- The app can report that a limit is unattainable; it does not silently lower
  quality further or save an oversized file as a successful target result.

## One shared interaction

1. Open the existing Compress screen. Choose **Manual** or **Fit under…**.
2. Configure the operation. Manual retains the existing level/quality controls.
   Fit under shows a limit and an **Allow image-based compression** checkbox,
   initially off for each new source.
3. Select **Prepare…**. A native save panel chooses the eventual filename and
   destination. Its title/prompt explain that preparation does not save the file;
   final publication requires **Save Result**.
4. Prepare the complete candidate with progress and Cancel. Keep settings fixed
   during the operation. Show the actual result size and chosen compression level.
5. Review it using **Original / Result** above the existing preview. Use the same
   page, zoom and visible region when switching. Show which version is visible.
6. Select **Save Result** to publish the prepared bytes to the selected destination.
   Cancel discards the candidate. A changed destination causes an actionable error
   and leaves that destination intact.

Selecting the destination early is intentional: the project already stages saves
on that volume and protects the destination identity during asynchronous work.
Retain that protection throughout the review instead of introducing a second
cross-volume save path. Display the chosen output filename during review, with
the full destination available as help text.

Use one prepare/review/save path for both modes. This adds an explicit review step
to manual compression rather than maintaining parallel implementations that can
drift. Opening the save panel and approving its location never overwrites a file.

## Increment 1: Fit under…

### Controls and interpretation

- Start with one numeric MB field, default 10 MB. Avoid separate controls that
  duplicate the same setting.
- Accept localized decimal input within a documented range, proposed
  0.1–1,000 MB. Reject empty, malformed, non-finite, zero, negative and overflowing
  values. Convert using decimal arithmetic; 1 MB means 1,000,000 bytes.
- **Under** means the final byte count is strictly less than the limit. A file
  exactly at the limit does not qualify.
- Keep color unless the user explicitly selects the existing grayscale option.
  Do not change color automatically to meet a target.
- Existing size estimates remain estimates. They may inform the display, but
  cannot decide success or authorize saving.

### Bounded candidate policy

If the original already meets the limit, explain that compression is unnecessary
and leave both files untouched. The user can still choose Manual to compress it.

Otherwise try lossless rewriting first, with annotation removal off. Keep the
existing explanation that standard document-info fields are cleared and that
this is not a privacy sanitizer. If the actual output fits, stop and retain it.

If lossless output is too large:

- With image-based compression off, stop and explain that the limit could not be
  met while retaining page content. Offer the existing explicit checkbox, not an
  automatic switch.
- With it on, try three existing raster presets in a fixed order: 300 DPI/Good,
  150 DPI/Good, then 72 DPI/Good. Respect the user's grayscale choice. Stop at the
  first complete output that fits.

That is at most **four complete attempts**, including lossless, run sequentially.
Discard an oversized candidate before the next attempt. Do not add binary search,
continuous quality tuning, parallel trials, or claims of globally optimal quality.
The result is the first qualifying preset in this documented order.

An operation/validation failure is an error, not an oversized candidate. Preserve
the existing fail-closed rules for permissions, malformed PDFs, unsafe annotation
removal and protection preservation. Do not silently bypass such a failure by
trying a different engine. The user may explicitly choose an appropriate manual
operation after reading the error.

If none fits, report **“Couldn't get below [limit] with these settings.”** Include
the smallest measured size for context, discard the temporary output, and offer
editing the limit or returning to Manual. Do not publish an oversized fallback.

The image-based option must disclose before preparation that searchable text,
accessibility tags, links, forms and digital signatures are not preserved, and
that an encrypted input produces an unprotected raster copy. Do not retain the
consent across new source documents.

## Increment 2: Original / Result

### First version

Use a single preview with a keyboard-accessible segmented toggle. This works in
the existing narrow layout and keeps the same viewing area for both versions.
Do not add a split-screen mode, draggable reveal divider, image-difference heatmap
or automatic quality score.

Reuse the page thumbnail navigation and native PDF preview. Keep zoom controls.
Compare complete generated output, not an approximation made from current sliders
or a first-page size estimate. Preparing again replaces the previous result.

The shared viewport records page index, fit/manual zoom and the visible anchor.
Map the anchor through displayed crop/rotation geometry when changing documents;
do not pass a source page or PDFDestination to the result document. Preserve the
visible region for cropped pages, non-zero crop origins and 90°/270° rotations.
Cancel stale queued navigation and ignore events from a previously displayed PDF.

Changing settings invalidates and discards the prepared result, disables Save
Result, and returns the preview to Original. Never label an old candidate as the
result of newly selected settings. Saving publishes the prepared bytes without
recompressing them.

### Protected and restricted documents

Comparison is available for raster results and lossless results that can be opened
for display. An encrypted lossless result may reopen locked; show **“Comparison
unavailable for this protected result”** and keep the original preview accessible.
Do not remove protection, retain a password, or add another password-entry workflow
just to enable comparison in this first version. Saving that result still requires
all existing protection checks to pass.

Keep existing PDF permission checks. Comparison must not create an unrestricted
derivative as a workaround for a restriction.

## Changes grounded in the current code

- `PDFCompressor.swift`: separate output preparation from final publication.
  Reuse the existing lossless/raster implementations, output validation, page
  limits, disk checks and cancellation. Add a small bounded target policy; avoid
  copying the raster loop into another service.
- `PDFwringerError.swift` / `AtomicFileWriter`: expose the minimum lifecycle needed
  to retain a prepared, destination-volume staged file until commit or discard.
  Reuse the existing destination-identity check and exclusive publication. Have
  one owner responsible for cleanup; do not duplicate those mechanisms in the VM.
- `CompressViewModel.swift`: own the mode, validated limit, snapshotted settings,
  selected destination and at most one prepared candidate. Preparation and saving
  share a single-operation guard. Use generations to suppress stale completions.
- `CompressOptionsView.swift`: integrate the mode, disclosures, prepare/review/save
  controls and comparison toggle in the existing screen. Preserve drop handling.
- `PDFPreviewView.swift`: add narrowly scoped viewport preservation for comparison.
  Keep the default behavior of other preview callers unchanged. Preserve teardown
  and stale-navigation protections.
- `FileDialogHelper.swift`: allow a preparation-specific save-panel title/prompt
  while retaining its existing modal workflow guard.
- `ContentView.swift` / existing close guards: treat a prepared, unsaved result as
  unsaved work. Back, replacement Open/drop, Close and Quit use the existing discard
  confirmation. Cancel deliberately discards it; successful save clears the flag.

Authoritative PDFKit objects remain on MainActor. Detached work receives Data and
reconstructs isolated pages. Render one page at a time and one candidate at a time;
cancel optional estimates while preparing. Clean up candidate files on settings
changes, cancellation, discard, replacement, errors and successful publication.

## Implementation order

1. Refactor preparation/publication with regression coverage and no UI changes.
2. Add the bounded target policy and its service/view-model tests.
3. Integrate the shared prepare/review/save flow and matched-viewport comparison.
4. Run the full tests and native checks, update documentation, increment the build
   number, and archive/export/validate a new candidate. Preserve build 2 as history.

Do not install or publish an unfinished build. The installed app and App Store
candidate remain unchanged while this design is reviewed.

## Acceptance and verification

- Test original already under limit, lossless success, explicit raster consent,
  success at each raster preset, exactly-at-limit output, and no qualifying output.
  Use measured outputs from generated fixtures rather than brittle fixed PDF sizes.
- Verify the attempt bound and fixed order, cancellation between and during
  attempts, and that permission/validation errors do not become silent fallbacks.
- Test localized/invalid/extreme input and conversions at byte boundaries.
- Verify source identity guards, late destination replacement/creation, failed
  publication, save retry, cleanup and unchanged source/existing-output checksums.
- Verify the saved bytes match the reviewed candidate, not a second encoding.
- Test settings/source changes while work is pending; stale results must never
  enable Save or replace the current comparison.
- Exercise page switching, zoom, pan, fit, cropped and rotated pages, small windows,
  rapid toggling, queued navigation and view teardown against real native PDFViews.
- Test encrypted input, retained lossless protection, the locked-result limitation
  and the disclosed unprotected raster result without storing passwords.
- Run the existing full `make test` and App Store archive check sequentially.
  Native-check keyboard/VoiceOver labels, Cancel, save-panel cancellation, unsaved
  result discard prompts, overwrite and destination changes for the new build.

No unrelated product functionality is included in this plan.
