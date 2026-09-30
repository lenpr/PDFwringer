# Mac App Store Release

PDFwringer has a separate Mac App Store distribution path. The existing
Developer ID, notarization, and DMG targets are for downloads outside the Store
and must not be used to create the App Store build.

The app requires macOS 27.0 or later on Apple silicon. Build with Xcode 27.

## Current candidate: 0.2.0 (build 4) — 2026-09-30

This version consolidates the September hardening and compression increments
under a new visible version. `PDFwringer/Info.plist` contains version `0.2.0`
and build `4`; the implementation is unchanged from validated build 3. Source
commit `b4e79d0` is tagged `v0.2.0` and `appstore-v0.2.0-build.4`.

All 399 tests passed again (332 fast, 61 corpus, 6 performance), along with the
unsigned archive check, signed archive, App Store export, strict signatures, and
Xcode Organizer validation. Organizer reported: “Your app successfully passed
all validation checks.” The export contains an Apple Distribution-signed arm64
app, macOS 27 minimum, sandbox/user-selected read-write/app-scoped bookmarks,
and no debugging entitlement. Its Mac App Store installer signature was verified.
Package SHA-256:
`002d40a48b5d325071b2fe97df44bed1b7c7f118c994357b02295daf9bb8cbab`.

The [GitHub 0.2.0 release](https://github.com/lenpr/PDFwringer/releases/tag/v0.2.0)
provides the separately Developer ID-signed app in a signed, notarized, stapled
DMG. Both the app and DMG passed notarization; the downloaded GitHub asset matches
SHA-256 `42f2fc513cda7f64e9beb327dd5c33a9d3a910cdfbea7e84d31b8e79c86d5beb`.
The Homebrew cask points to that version/checksum and requires Apple silicon and
macOS 27.0+. Homebrew upgraded the local receipt and installed app to `0.2.0`;
the installed About panel visibly shows `Version 0.2.0 (4)`. Strict signature and
Gatekeeper checks passed. The installed executable matches the download exactly
and shares the archive UUID `0FFC18EC-47AF-3411-8EFB-230440893920`.

Evidence is preserved outside `.build` in
`../PDFwringer-release-evidence/appstore-0.2.0-build.4-b4e79d0/` and
`../PDFwringer-release-evidence/download-0.2.0-build.4-b4e79d0/`.
Earlier evidence below retains its original identity; see `CHANGELOG.md` for
the progression. The App Store candidate has not been submitted for review.
Account-side listing/privacy/compliance responses, the complete accessibility
pass, and Store/TestFlight-installed checks remain submission gates.

## Build 3 compression implementation — 2026-09-30

Build `0.1.16 (3)` implements only the two increments retained in
`COMPRESSION_PLAN.md`: target-size compression and comparison of the original
with the exact prepared result. Both manual and target modes use Prepare, review,
then Save Result. Image-based target attempts require explicit consent. Limits
use decimal MB and success requires the measured complete file to be strictly
below the requested limit. No permissions, entitlements, services, or network
dependencies were added.

Full validation passed: 332 fast tests, 61 checksum-verified corpus tests, and
6 performance tests (399 total). New tests cover localized byte boundaries,
every bounded compression attempt, permission errors, cancellation, exact-byte
publication, destination changes, candidate cleanup, stale results, retained
encryption, and rotated/cropped-page viewport preservation.

Native checks in the development-signed implementation build passed: already-small
input, unattainable lossless target, explicit raster consent, page/zoom comparison,
unsaved-result navigation with Keep Editing, settings invalidation, native
overwrite selection, refusal of a destination replaced during review, cancellation
of a prepared result, and Command-S publication. The saved output independently
reopened with two pages and 82,314 bytes, below its 100,000-byte limit. The existing
destination remained unchanged during preparation and a concurrent replacement
remained intact after a refused save. Testing found and fixed a retry action that
needed to reopen destination selection after that failure.

The unsigned App Store archive structure check passed, including arm64-only code,
bundle version, privacy manifest, icon, and release symbols.
Candidate `0.1.16 (3)`, source `1962331`, tagged `appstore-v0.1.16-build.3`, also
passed the signed archive, App Store export, strict app-signature checks, and Xcode
Organizer validation. Organizer reported: “Your app successfully passed all
validation checks.” The exported package contains an Apple Distribution-signed
arm64 app with the macOS 27 minimum, sandbox, user-selected read/write and
app-scoped bookmarks, and no debugging entitlement. Its Mac App Store installer
signature was verified. Package SHA-256:
`b7a35dd065de3d348fbb148697333e062b01b243dff3e215e2a4c77176e69498`.

The exact development-signed archive app additionally passed native manual
prepare/review/save, destination-change refusal, corrected Try Again destination
selection, and save-panel cancellation retaining the candidate. Reselecting a
new destination and Command-S saved the result successfully.

Evidence is preserved outside `.build` in
`../PDFwringer-release-evidence/appstore-0.1.16-build.3-1962331/`.
Build 2's results below are historical. Remaining submission gates include the
account-side listing/privacy/compliance responses and the complete
accessibility/layout and distribution-installed interaction pass. No App Store
review submission or publication was performed.

The same archive's app was separately signed with Developer ID, accepted by
Apple notarization, stapled, and installed at `/Applications/PDFwringer.app`.
Strict signature verification and Gatekeeper assessment passed. Its executable
UUID matches the archive. Native installed-app launch, Open, Compress, target
preflight and return to the landing screen passed. This local installation does
not certify a Store/TestFlight-installed copy. Evidence is retained in
`../PDFwringer-release-evidence/local-install-0.1.16-build.3-1962331/`.

## Signed candidate validation — 2026-09-28

Candidate `0.1.16 (1)`, source commit `55093a9`, tagged
`appstore-v0.1.16-build.1`, passed the actual App Store signing/export path:

- Xcode automatic provisioning created a signed Apple silicon archive.
- App Store Connect export produced a package with an Apple Distribution-signed
  app and a Mac App Store installer signature. Strict signature verification passed.
- The exported app requires macOS 27.0 and retains the sandbox, user-selected
  read/write, and app-scoped bookmark entitlements, without debugging access.
- Xcode Organizer reported: “Your app successfully passed all validation checks.”
- The App Store Connect record now exists for `PDFwringer`, bundle ID and SKU
  `com.pdfwringer.app`, primary language English (United States). Xcode initially
  reported an error after record creation; repeating validation succeeded.

The archive, dSYMs, exported package, SHA-256, and validation logs are retained
outside `.build` in `../PDFwringer-release-evidence/appstore-0.1.16-build.1-55093a9/`.
No app was submitted for review or published. Signed-candidate interaction tests
and the App Store Connect listing, privacy, and compliance responses remain.
The older unsigned-validation entries below are historical; their signing and
Organizer limitations have been resolved for this candidate only.

## Signed archive interaction checks — 2026-09-29

Tested the preserved Apple Development-signed archive app for commit `55093a9`
on macOS 27. These checks do not certify an App Store-installed or
TestFlight-delivered copy.

Passed native launch/Open, unsaved metadata protection for Close and Quit,
Keep Editing preserving the edit, Quit while the save panel is active,
save-panel cancellation and retry, and successful metadata saving. The output
was independently reopened and verified to contain three pages and the expected
title; the source SHA-256 remained unchanged. Quit after saving exited without
a discard prompt. Relaunch and Open Recent reopened the fixture successfully.

Evidence and the disposable saved PDF are retained alongside the signed archive
as `native-smoke-20260929.json` and `signed-smoke-output-20260929.pdf`.
Remaining native checks include Finder/Dock replacement while a save panel is
active, drag-and-drop, save failure/overwrite, long-operation cancellation,
protected PDFs, and the full accessibility/layout pass. No code changes were
needed for the checks completed here.

## Protected-document validation and prompt fix — 2026-09-29

Native testing of build 1 found that an incorrect opening password dismissed
its SwiftUI alert without retry guidance. The prompt now uses a persistent sheet:
incorrect attempts clear the input, show the error, and retain keyboard focus;
Return retries, and Cancel/Escape clears pending password state.

Verified in the rebuilt Apple Development-signed app: repeated incorrect attempts,
correct-password retry, and Escape preserving the current document. All 316 fast
tests passed, including retry/cancellation state coverage. Native tests on build 1
also verified ordinary saves retaining existing protection, incorrect verification
passwords publishing no output, explicit removal producing an unencrypted copy,
and explicit flattening producing AES-128 output. Outputs were independently
reopened, tested with wrong/correct passwords, and checked for page count and the
AESV2/128-bit security dictionary. The protected source checksum remained unchanged.

In the rebuilt app, a 200-page flattening operation was cancelled at about 20%
while targeting an existing disposable output. Both source and destination retained
their original SHA-256. The earlier attempt finished before the cancellation click;
it was repeated against a restored destination and observed to report “Cancelled.”

Build 2 includes the prompt fix and supersedes build 1 as the release candidate.
Full validation passed: 316 fast tests, 61 checksum-verified corpus tests, and
6 performance tests (383 total), plus the unsigned App Store archive check.
Its signing/export and Organizer result are recorded separately below.

## Build 2 signed candidate validation — 2026-09-29

Candidate `0.1.16 (2)`, source commit `df32247`, tagged
`appstore-v0.1.16-build.2`, passed automatic provisioning, signed archive,
App Store export, and Xcode Organizer validation. Organizer reported:
“Your app successfully passed all validation checks.”

Independent checks of the exported package confirmed the Apple Distribution app
signature, Mac App Store installer signature, arm64-only executable, macOS 27.0
minimum, sandbox, user-selected read/write and app-scoped bookmarks, with no
debugging entitlement. The package SHA-256 is
`efe2bfee9cff3ba964debcea4c99b86380268d8888251e03ae64e51f717030a1`.

The archive, dSYMs, package, signatures, test/build/validation logs, and synthetic
protected-document fixtures are retained outside `.build` in
`../PDFwringer-release-evidence/appstore-0.1.16-build.2-df32247/`.
The native password and cancellation evidence is recorded in
`native-protected-workflows-20260929.json`. The earlier interaction-check list
is historical: protected PDFs and long-operation cancellation are now covered.
Finder/Dock replacement during a save panel, drag-and-drop, save failure/overwrite,
the full accessibility/layout pass, and an App Store-installed or TestFlight copy
remain unverified. No review submission or publication was performed.

## One-time account setup

These steps require the app owner and cannot be stored in the repository:

1. Join the Apple Developer Program and accept the current agreements in App
   Store Connect.
2. Register `com.pdfwringer.app` as an explicit App ID. Confirm this identifier
   before the first upload; Apple does not let you change it after uploading a
   build.
3. Create the macOS app record in App Store Connect with the same bundle ID.
4. Sign in to the Apple Developer account in Xcode. Automatic signing will
   manage the App Store distribution certificate and provisioning profile.
5. Record the ten-character Team ID. Pass it as `APP_STORE_TEAM_ID`; no team,
   certificate, profile, or credential is committed to source control.

## Prepare a release

Update both values in `PDFwringer/Info.plist` before every Store release:

- `CFBundleShortVersionString` is the customer-facing version. Increment it for
  each shipped user-visible batch, using a patch for fixes and a minor version
  for retained feature increments (see `CHANGELOG.md`).
- `CFBundleVersion` is the build number. Increment it for every new build sent
  to App Store Connect. Apple permits reuse only when its processing of the
  previous upload failed; in that case, reuse the existing artifact when
  possible rather than rebuilding different code with the same identity.

Then validate the complete codebase and the unsigned archive structure:

```bash
make test
make app-store-check
```

`app-store-check` performs a credential-free Release archive, requires exactly
the Apple silicon (`arm64`) architecture, verifies the bundled privacy manifest
and property lists, and rejects quarantine attributes. Its temporary archive is removed afterward.

Commit the release inputs, then tag that exact commit with both version values:

```bash
git tag appstore-v0.2.0-build.4
```

The archive target refuses a dirty input tree or a mismatched tag. The separate
tag namespace allows multiple Store builds without colliding with the existing
`v<version>` tags used by Developer ID releases.

## Archive and export

Create the signed archive after Xcode has access to the Apple Developer team:

```bash
make app-store-archive APP_STORE_TEAM_ID=XXXXXXXXXX
make app-store-export APP_STORE_TEAM_ID=XXXXXXXXXX
```

Artifacts use a version-and-build-specific directory under `.build/app-store/`.
Both commands refuse to overwrite an existing artifact. The export options use
App Store Connect distribution and automatic signing, preserve the checked-in
version/build values, and include symbols.

Neither command uploads anything. Validate the archive and explicitly upload it
with Xcode Organizer, or upload the exported package with Transporter. Because
the archive is kept under `.build/app-store/` instead of Xcode's default archive
directory, open or double-click the `.xcarchive` first, for example:

```bash
open .build/app-store/PDFwringer-0.2.0-build.4/PDFwringer.xcarchive
```

Store builds are signed locally by Xcode with the team's App Store distribution
assets, then delivered through App Store Connect. They are not submitted to
`notarytool` or wrapped in the Developer ID DMG.

## Privacy and encryption

`PDFwringer/PrivacyInfo.xcprivacy` records the implementation audited for this
release:

- no tracking, tracking domains, or collected data;
- app-only preferences and security-scoped bookmark storage;
- disk-space checks used to fail visibly before an output write;
- file metadata for app-container temporary files and user-selected files.

The matching App Store Connect privacy response is **Data Not Collected**.
Use the public `PRIVACY.md` page as the required privacy-policy URL. Re-audit
both declarations before submission if networking, analytics, advertising, or
third-party SDKs are ever added.

PDFwringer can password-protect PDFs, but the implementation uses only Apple's
PDFKit/Core Graphics encryption. Apple still requires an export-compliance
determination for cryptography provided by the operating system, and App Store
Connect's questionnaire determines whether documentation is required for the
intended territories. `ITSAppUsesNonExemptEncryption` is intentionally absent
until that answer is confirmed. If App Store Connect determines that the
current use is exempt and needs no documentation, add the key with a Boolean
`false` value to avoid answering the same question for each upload. If it asks
for documentation, follow Apple's review process and use the value Apple
provides. Revisit the determination if any cryptography implementation or
dependency changes.

## Content and password behavior to describe accurately

- Lossless compression clears standard document-info fields. Editing or clearing
  those fields does **not** remove embedded XMP, attachments, identifying page
  content, or all other metadata. Do not market this as a privacy sanitizer.
- Raster compression, color adjustment, and annotation flattening turn affected
  pages into images. Searchable text, accessibility tags, interactive fields,
  links, and digital signatures are not preserved. This is disclosed before save;
  do not describe raster output as an archival format.
- New passwords are available only with explicit annotation flattening. The
  Core Graphics output must verify as AES-128 before it replaces a destination.
  The supported password format is 1–32 printable ASCII characters. The ordinary
  PDFKit password writer is deliberately not used because it creates legacy RC4.
- Ordinary metadata saves retain existing protection. A document that required
  unlocking requires its current password again to verify the staged result.
  Removing protection is an explicit choice. Derived outputs (split, merge,
  reordered pages, rasterized compression, color changes, and exported images)
  disclose that the new copy is not password-protected.
- Existing protected PDFs may use older encryption; retaining their protection
  does not upgrade it. Do not claim all saved PDFs use AES.

## Known framework limitations and release gates

The checked corpus contains reproducible PDFKit serialization limitations:
`cmyk_image.pdf` cannot be safely rewritten by lossless compression or ordinary
metadata editing; annotation removal from `highlight.pdf` and `zapfdingbats.pdf`
can leave annotations in the serialized result. Rewriting `sechandler.pdf` can
silently remove its existing owner restrictions. These operations must reject the
write and leave both source and any existing destination intact. Corpus tests
exercise these exact rejection cases rather than skipping the files. Other
unexpected failures still fail the suite. Explicit rasterization remains a
separate user choice, never an automatic fallback.

Before an actual submission, record results for the exact signed candidate:

- [ ] Full `make test` (fast, checksum-verified corpus, performance/lifecycle).
- [ ] Apple silicon Release archive via `make app-store-check`.
- [ ] App Store signing, provisioning, export and Organizer validation.
- [ ] Run the exact candidate on macOS 27, the minimum supported OS.
- [ ] Cold and warm Finder/Open With/Dock opens, system open/save panels,
      drag-and-drop, and Open Recent after relaunch in the sandbox.
- [ ] Cancel long operations, retry a failed save, and save over an existing
      destination without altering the source.
- [ ] While a save/output-folder panel is open, attempt Finder Open and Quit;
      the current workflow must remain intact. Cancel the panel and verify that
      opening another document works again.
- [ ] Reject and accept unsaved-work prompts for Back, replacement Open/drop,
      Start Over, native Close, and Quit; verify saved work does not prompt.
- [ ] Keyboard navigation, VoiceOver, narrow windows and light/dark appearances;
      disclosures and the action buttons must remain reachable by scrolling.
- [ ] Password-protected input, retained protection, explicit deprotection and
      verified AES output, including an incorrect verification password.

The local implementation checks do not replace these candidate-specific gates.
No App Store account, certificate/profile, export-compliance answer, or
minimum-OS test result should be inferred from an unsigned archive passing.
Keep exported archives and symbols outside `.build` before running `make clean`.

## App Store Connect checklist

Beyond the binary and product media, complete the following in App Store
Connect:

- app name, SKU, primary language, productivity category, description, and
  keywords;
- support URL, privacy-policy URL, copyright, and App Review contact/notes;
- age-rating questionnaire, content-rights answer, pricing, and territories;
- app privacy response and export-compliance response;
- current agreements, tax/banking details when applicable, and DSA trader
  status for EU distribution.

The current app has no login, server dependency, in-app purchase, temporary
sandbox exception, or review account to configure. Its deployment target is
macOS 27.0 on Apple silicon; Intel Macs are not supported. Lowering that target
would require a separate compatibility audit.

## Local verification — 2026-09-25

Verified on Apple silicon, macOS 27.0 (26A428), Xcode 27.0 (27A266a):

- `make test`: 295 fast tests, 61 corpus tests across the checksum-verified
  36-file corpus, and 6 performance tests passed. Parameterized corpus tests
  include the explicit safe-rejection cases described above.
- `make release`: optimized sandboxed app built successfully; strict code-signing
  verification passed with the intended sandbox, user-selected read/write, and
  app-scoped bookmark entitlements. This local smoke build was ad-hoc signed.
- `make app-store-check`: the unsigned universal Release archive passed its
  architecture, bundle, privacy-manifest, and configuration checks. Xcode emitted
  local CoreSimulator/CoreDevice version warnings; the macOS archive succeeded.
- Native UI smoke checks passed for system Open/Save panels, metadata saving,
  cancelling native Close and Quit with unsaved edits, quitting after a save
  without a discard prompt, and cold Finder Open With into the optimized build.
  Automated lifecycle tests cover queued cold and warm open events and rejected
  navigation, replacement Open/drop, Start Over, Close, and Quit.

One preview lifecycle test exceeded its five-second deadline while an Xcode
archive compiled concurrently. The complete test run passed when run separately,
with no assertion or timeout relaxed. Run test and archive validation sequentially
as shown above to avoid competing with the timing-sensitive checks.

Outstanding under the current support scope: App Store distribution
signing/provisioning, Organizer validation, TestFlight,
and the account-side submission/privacy/export-compliance responses. Complete
those gates for the actual submission candidate; no upload was performed.

## Apple silicon scope and local verification — 2026-09-27

The supported hardware scope is now Apple silicon only. Both Xcode build
configurations explicitly use `arm64`, matching the Makefile default. The
unsigned archive check and signed archive target reject binaries with any other
architecture. The earlier universal-archive result above is historical; Intel
execution is no longer a release gate.

On Apple silicon with macOS 27.0 (26A428):

- Full `make test` passed: 300 fast tests, 61 checksum-verified corpus tests,
  and 6 performance tests. These test the service/model/viewmodel layers and
  do not substitute for testing the signed app through its UI.
- `make app-store-check` passed with an Apple silicon-only Release archive,
  including bundle metadata, privacy manifest, icon, and release symbols.
- `make release` passed. The optimized app contains only `arm64` code; strict
  ad-hoc signature verification passed with sandbox, user-selected read/write,
  and app-scoped bookmark entitlements intact.

App Store signing/provisioning, export, Organizer validation, and the
candidate-specific native UI checks remain release gates.
The available local signing identity is Developer ID, not an App Store
distribution identity. No release tag, upload, or notarization was performed.

## Follow-up hardening verification — 2026-09-27

Validated source commit `96c1390` on the same Apple silicon/macOS 27 environment:

- Full `make test`: 307 fast tests, 61 checksum-verified corpus tests, and
  6 performance tests passed.
- `make release` and strict signature verification passed. This optimized local
  app is ad-hoc signed, sandboxed, and Apple silicon only.
- `make app-store-check` passed for the unsigned Release archive.
- Live UI checks confirmed Tab/Space thumbnail activation, the accessible
  Show Preview action, selected-page movement using Option–Up Arrow, and the
  accessible Move Later button. Boundary button state and restoration of the
  original page order were also verified. This is not a complete VoiceOver or
  minimum-OS certification.
- Regression tests now cover cancelled synchronous saves, staging cleanup,
  successful retries, destinations replaced during preparation, and rejection
  of unreadable/missing/locked PDFs without accepting a partial merge list.
- The preview lifecycle test now waits for operation completion and retains its
  image/settings assertions, with a one-minute framework timeout for hangs.
  It no longer mistakes time spent on other concurrent tests for render failure.

Local evidence is retained outside `.build`, in the sibling directory
`PDFwringer-release-evidence/2026-09-27-96c1390/`: test/build/archive logs, the
optimized local app, and an `evidence.json` containing the source revision,
platform/toolchain, architecture, and binary SHA-256. `make clean` does not
remove this directory. The unsigned check archive is temporary and is not kept;
retain the actual signed distribution archive and its dSYMs at release time.

Remaining release gates: actual App Store signing/provisioning and Organizer
validation, candidate-specific UI/accessibility checks, and the account-side
submission responses. No upload was performed.

## Final local verification — recorded 2026-09-28

Validated source commit `c5a76f4` after native preview navigation, thumbnail
concurrency, and crop-geometry hardening:

- Full `make test`: 313 fast tests, 61 corpus tests, and 6 performance tests
  passed (380 total). The external fixture checksums passed.
- Optimized `make release`, strict ad-hoc signature verification, and the
  Apple silicon-only unsigned `make app-store-check` all passed.
- Native preview regression tests cover superseded navigation, document/binding
  replacement, and teardown. A 24-request thumbnail regression measured 24
  simultaneous snapshots before the fix and one afterward.
- Crop/resize tests reject non-finite origins, overflowing rectangle edges, and
  non-finite crop controls without mutating the affected page.

Logs, the optimized local app, platform/toolchain details, source revision, and
binary SHA-256 are preserved outside `.build` in the sibling directory
`PDFwringer-release-evidence/2026-09-28-c5a76f4/`.

This remains local validation on macOS 27. The App Store distribution
signing/provisioning, Organizer, and candidate-specific manual release gates
above are still outstanding. No release upload or notarization was performed.

## References

- [Distributing an app with Xcode](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
- [Uploading builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
- [Mac App Store provisioning profiles](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile/)
- [Privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)

## Signed save rejection and retry — 2026-09-29

On the development-signed archive for `55093a9`, selecting the source PDF in
Save and accepting the system Replace prompt was rejected by the app with the
source/destination error. The source SHA-256 remained unchanged. Try Again
successfully replaced a separate disposable output; independent PDFKit checks
confirmed three pages and the updated title. No code changes were needed.
Further native testing was stopped at the usage-budget threshold.
