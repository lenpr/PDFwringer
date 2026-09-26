# Mac App Store Release

PDFwringer has a separate Mac App Store distribution path. The existing
Developer ID, notarization, and DMG targets are for downloads outside the Store
and must not be used to create the App Store build.

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

- `CFBundleShortVersionString` is the customer-facing version, such as
  `0.1.17`.
- `CFBundleVersion` is the build number. Increment it for every new build sent
  to App Store Connect. Apple permits reuse only when its processing of the
  previous upload failed; in that case, reuse the existing artifact when
  possible rather than rebuilding different code with the same identity.

Then validate the complete codebase and the unsigned archive structure:

```bash
make test
make app-store-check
```

`app-store-check` performs a credential-free Release archive, checks both
architectures, verifies the bundled privacy manifest and property lists, and
rejects quarantine attributes. Its temporary archive is removed afterward.

Commit the release inputs, then tag that exact commit with both version values:

```bash
git tag appstore-v0.1.17-build.2
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
open .build/app-store/PDFwringer-0.1.17-build.2/PDFwringer.xcarchive
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
- [ ] Universal Release archive via `make app-store-check`.
- [ ] App Store signing, provisioning, export and Organizer validation.
- [ ] Run on the minimum supported macOS 26, as well as the current macOS.
- [ ] Cold and warm Finder/Open With/Dock opens, system open/save panels,
      drag-and-drop, and Open Recent after relaunch in the sandbox.
- [ ] Cancel long operations, retry a failed save, and save over an existing
      destination without altering the source.
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
macOS 26.0; lowering that target would require a separate compatibility audit.

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

Not completed by this local validation: macOS 26 execution, Intel execution,
App Store distribution signing/provisioning, Organizer validation, TestFlight,
and the account-side submission/privacy/export-compliance responses. Complete
those gates for the actual submission candidate; no upload was performed.

## References

- [Distributing an app with Xcode](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
- [Uploading builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
- [Mac App Store provisioning profiles](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile/)
- [Privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)
