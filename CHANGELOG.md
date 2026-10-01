# Release progression

## Unreleased

- Merge assembles, writes and verifies PDFs in an isolated background worker;
  cancellation and destination-change checks prevent publishing stale results.
- Unannotated, unencrypted page reordering avoids redundant per-page
  serialization and writes in the background. Preservation-sensitive inputs keep
  the established path.
- Full-document color adjustment streams encoded pages instead of retaining a
  complete image-backed document. Partial selections preserve untouched pages.
- Color sliders reuse one current-page base image, render to the pane's display
  density and avoid repeated JPEG encoding/decoding. Rapid edits coalesce while
  stale pages, revisions and cancelled work cannot publish a preview.
- Rotate/Crop saves write and verify in the background, show a cancellable busy
  phase and prevent edits/navigation from racing publication.
- Ordinary unencrypted metadata saves write and verify in the background after
  capturing the current document; protected inputs retain their safeguards.
- Lossless preparation verifies and writes isolated snapshots in the background
  without weakening encryption or annotation-removal checks.
- Merge, reorder and color progress reserve completion for verified publication.
- A repeatable optimized benchmark and responsiveness/cancellation regressions
  track performance without collecting user data. Evidence: `PERFORMANCE_AUDIT.md`.

- Metadata/password fields keep their accessibility names after typing.
- Coral controls improve text contrast in light appearance; primary buttons and
  segmented choices retain readable white labels in both appearances.
- Failed output publication explains permission, disk-full/quota, read-only and
  missing-path problems. Permission-loss regressions verify unchanged files and
  successful retry using the reviewed result.

Native layout/recovery evidence and deferred accessibility checks are in
`UX_AUDIT.md`. Version and distributed candidates remain unchanged until the
consolidated release.

## 0.2.3 — 2026-09-30

Includes the task-flow refinements below and shows only the public version in
About, documentation, and release descriptions. The required internal build
identifier remains in signing metadata. No PDF operations or dependencies added.

## 0.2.2 — 2026-09-30

Internal candidate; these changes ship in the 0.2.3 download.

Makes existing task flows more consistent, without new PDF operations.

- Larger native Back controls respond across the whole label, including the
  chevron. Navigation stays visible above scrolling options in every tool.
- Native draggable dividers let people resize preview/list and options columns.
- Close File replaces the small opposite-side X on the tool chooser. Back returns
  to tools; Close File returns to the neutral file-selection screen.
- Merge is available alongside the other tools after opening one PDF. The PDF is
  already in the merge list, with guidance to Add Files. Back returns to the
  original document; removing the last item leaves a usable empty merge list.
- The opening screen remains focused on selecting PDFs, with no task-specific
  buttons. Opening several PDFs still starts the existing merge flow.
- Password Protection replaces the broad Security label. Add password protection
  explains and asks consent for the current image-copy requirement; ordinary
  password removal does not require flattening. The encryption safeguards remain.

Validation and distribution evidence are tracked in `APP_STORE.md`.

## 0.2.1 — 2026-09-30

Refines existing workflows after the adversarial UI/UX review. No new PDF
operations, permissions, services, or dependencies.

- Crop distinguishes pending guides, applied changes, and saved copies. Pending
  edits receive unsaved-work protection and cannot be silently omitted on Save.
- Color previews respect the chosen pages, identify updates, and recover from
  unavailable previews without displaying a stale page.
- Page navigation no longer toggles inclusion; separate checkmarks, keyboard
  selection, inline range errors, and spoken state make selection explicit.
- Compression comparison uses matching thumbnails and a stable control area.
  Prepared/cancelled feedback is neutral; saved output alone gets a success check.
- Options scroll and reflow, result messages wrap and reveal themselves, and
  headers, primary actions, warnings, progress, and Cancel behave consistently.
- Existing actions appear in the Actions menu. Page commands use Command–Option
  arrows (add Shift for first/last), preserving ordinary text caret navigation.
- Merge ordering has the same keyboard alternatives as page reordering.
- Calmer cards/landing screen, comfortable zoom controls, adaptive small accent
  text, and reduced decorative motion preserve the existing visual identity.

Validation and distribution evidence are tracked in `APP_STORE.md`.

## 0.2.0 — 2026-09-30

The first downloadable release of the production hardening and compression
review work completed in September. This version replaces the May 0.1.16
download and aligns the installed app, GitHub download, Homebrew cask, and new
App Store candidate.

All 399 tests, archive/export checks, and Xcode Organizer validation passed.
The [0.2.0 download](https://github.com/lenpr/PDFwringer/releases/tag/v0.2.0)
is signed, notarized, and stapled; Homebrew and the installed app use the same
version and build. See `APP_STORE.md` for the validation record and artifact retention policy.

- Fit under a specified file-size limit, with complete output measurement and
  explicit consent for image compression.
- Compare Original / Result before saving, preserving page and relative zoom.
- Prepare/review/save protects source and destination files until publication.
- Includes the stability, file safety, PDF permission/encryption, cancellation,
  preview lifecycle, accessibility-label, and release-process improvements from
  the milestones below.
- Apple silicon only; macOS 27.0 or later. No new permissions, services, or
  dependencies. The App Store candidate is separate from the Developer ID
  download and has not been submitted for review.

## September development milestones

These are the actual earlier build identities, recorded retrospectively to make
the progression visible. Their source tags and validation results remain the
historical record; superseded local binaries have been removed. They were not
separate public downloads and are not renumbered.

| Version | Date | Milestone | Source tag |
|---|---|---|---|
| 0.1.16 | 2026-09-30 | Target-size compression and original/result review; 399 tests and Organizer validation passed | [Source checkpoint](https://github.com/lenpr/PDFwringer/tree/appstore-v0.1.16-build.3) |
| 0.1.16 | 2026-09-29 | Persistent password retry prompt and protected-document/cancellation validation; 383 tests and Organizer validation passed | [Source checkpoint](https://github.com/lenpr/PDFwringer/tree/appstore-v0.1.16-build.2) |
| 0.1.16 | 2026-09-28 | Hardened file operations, isolated PDF workers, lifecycle fixes, macOS 27/Apple silicon scope, and first signed App Store validation | [Source checkpoint](https://github.com/lenpr/PDFwringer/tree/appstore-v0.1.16-build.1) |

## 0.1.16 — 2026-05-16

Previous public download. The original release and asset remain available as
history at [`v0.1.16`](https://github.com/lenpr/PDFwringer/releases/tag/v0.1.16).
Earlier public releases are listed on the
[GitHub releases page](https://github.com/lenpr/PDFwringer/releases).

## Version policy

`PDFwringer/Info.plist` is the source of truth for both build paths and the app's
visible version. Increment the public version for each shipped user-visible batch:
patch versions for fixes, minor versions for retained feature increments. Build
numbers increase for each new signed candidate, including rebuilds within a
public version. Tag each exact release-input commit as `v<version>` and
`appstore-v<version>-build.<build>`; do not move published tags or replace assets.

GitHub release notes and the Homebrew cask must name that same version and point
to the verified downloadable artifact. The installed Developer ID app and the
App Store export have different signing requirements, but use the same source,
public version, and build number. Historical tags and validation results keep
their original identity; retain local artifacts according to `APP_STORE.md`.
