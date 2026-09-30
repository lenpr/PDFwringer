# Release progression

## 0.2.0 (build 4) — 2026-09-30

The first downloadable release of the production hardening and compression
review work completed in September. This version replaces the May 0.1.16
download and aligns the installed app, GitHub download, Homebrew cask, and new
App Store candidate.

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
the progression visible. Their archived binaries and signed tags are preserved;
they were not separate public downloads and are not renumbered.

| Version / build | Date | Milestone | Source tag |
|---|---|---|---|
| 0.1.16 (3) | 2026-09-30 | Target-size compression and original/result review; 399 tests and Organizer validation passed | [`appstore-v0.1.16-build.3`](https://github.com/lenpr/PDFwringer/tree/appstore-v0.1.16-build.3) |
| 0.1.16 (2) | 2026-09-29 | Persistent password retry prompt and protected-document/cancellation validation; 383 tests and Organizer validation passed | [`appstore-v0.1.16-build.2`](https://github.com/lenpr/PDFwringer/tree/appstore-v0.1.16-build.2) |
| 0.1.16 (1) | 2026-09-28 | Hardened file operations, isolated PDF workers, lifecycle fixes, macOS 27/Apple silicon scope, and first signed App Store validation | [`appstore-v0.1.16-build.1`](https://github.com/lenpr/PDFwringer/tree/appstore-v0.1.16-build.1) |

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
public version, and build number. Historical evidence keeps its original identity.
