# UI and UX release refinement backlog

Reviewed 2026-09-30 against 0.2.0 (4). The initial review was analysis only. The user subsequently authorized
implementation of the high-value fixes; the implementation record follows. No additional PDF operations, services, accounts, or modes are proposed.

## Scope and confidence

Three independent agents reviewed visual consistency, workflow correctness, and
accessibility/platform interaction. The primary reviewer inspected the installed
app's landing screen, document chooser, crop, compression, color adjustment,
export, and split screens, using the existing public tracemonkey.pdf test fixture.
All existing workflow views, shared controls, related view models, navigation,
and command definitions received source review.

Live inspection confirmed the unsolicited A4 crop guide on a Letter document,
compression accessibility labels omitting visible estimates/warnings, and split
fields lacking distinct spoken names. Export exposes individually named format
and resolution choices without a named group in the inspected accessibility tree.
The app was returned to its landing screen; no PDF outputs were written.

This was not a complete VoiceOver certification or an end-to-end execution of
every operation. Small-window clipping, light-appearance contrast, Escape
precedence, focus restoration, and text-caret shortcut interference need targeted
runtime verification. Attempts to resize the native window did not establish an
exact 650×420 test; layout risks below are derived from actual view structure,
not claimed as observed clipping. Failure-state findings are source-confirmed
paths, not newly reproduced PDF rendering failures.

Apple's current [button guidance](https://developer.apple.com/design/human-interface-guidelines/buttons)
supports consistent native interaction states and accessible controls; its
[feedback guidance](https://developer.apple.com/design/human-interface-guidelines/feedback)
supports integrated status feedback with interruption proportional to importance.
The recommendations below are project-specific judgments grounded in code.

Effort: **S** = a localized refinement; **M** = coordinated view/state changes
plus focused regression checks. Rankings reflect impact, reach, and effort,
not estimates of App Review rejection probability.

## Priority A — resolve misleading interactions before visual lock

### 1. Make crop's pending edits impossible to silently overlook — M

Typing margins or changing paper size updates the guide, but Save serializes only
the already-applied working document. A person can see their intended change,
press Save, and get an unchanged copy. Three prominent buttons do not explain
this distinction. Merely typed settings also do not call the dirty callback.

**Refinement:** retain the existing apply-then-save model; label the buttons
“Apply Crop” and “Apply Page Size,” distinguish pending guides from applied
content, and prevent Save from silently ignoring pending inputs. Do not implicitly
apply both operations, or repeatedly crop when saving. Clarify whether pending
settings are discarded when leaving.

**Acceptance:** enter a margin, then Save or leave without applying; the outcome
is explicit. Apply, inspect, and Save produces the inspected working document.

Evidence: [CropOptionsView.swift:34](/Users/D068138/Development/private/PDFwringer/PDFwringer/Views/CropOptionsView.swift:34),
[apply controls:122](/Users/D068138/Development/private/PDFwringer/PDFwringer/Views/CropOptionsView.swift:122),
[save:273](/Users/D068138/Development/private/PDFwringer/PDFwringer/Views/CropOptionsView.swift:273).

### 2. Make color preview respect the chosen page subset — M

Color preview always renders the current page with adjustment settings. Save
uses the selected subset. An excluded page can look adjusted even though it
will remain unchanged, and changing selection does not refresh the preview.

**Refinement:** display the original appearance for excluded pages, update on
selection changes, and keep current-page inspection distinct from output scope.

**Acceptance:** adjust only page 2, inspect page 1, and confirm its preview and
saved appearance agree. Repeat after selecting/deselecting the current page.

Evidence: [ColorAdjustOptionsView.swift:121](/Users/D068138/Development/private/PDFwringer/PDFwringer/Views/ColorAdjustOptionsView.swift:121)
versus [selected save indices:126](/Users/D068138/Development/private/PDFwringer/PDFwringer/Views/ColorAdjustOptionsView.swift:126).

### 3. Stop failed color previews from showing the wrong page indefinitely — M

Previous preview imagery remains while a new page renders. Missing page data
returns early and rendering failures are swallowed. A failed replacement can
leave old-page imagery indefinitely; an initial failure can leave a spinner.

**Refinement:** associate imagery with page/settings, show a restrained updating
state, and replace failures with “Preview unavailable.” Preserve cancellation
and generation guards. Avoid presenting stale imagery as the current page.

**Acceptance:** failed initial/replacement previews settle into a truthful state;
rapid page/slider changes never publish a stale result.

Evidence: [ColorAdjustViewModel.swift:79](/Users/D068138/Development/private/PDFwringer/PDFwringer/ViewModels/ColorAdjustViewModel.swift:79),
[suppressed error:107](/Users/D068138/Development/private/PDFwringer/PDFwringer/ViewModels/ColorAdjustViewModel.swift:107),
[preview presentation:167](/Users/D068138/Development/private/PDFwringer/PDFwringer/Views/ColorAdjustOptionsView.swift:167).

### 4. Distinguish prepared, saved, cancelled, and warning feedback — S

ResultMessageView maps every non-error message to a green success check. This
includes unsaved compression preparation, cancellation, and partially skipped
crops. Unattainable target compression is already marked as an error. Later edits can leave earlier “Saved” messages
visible. Crop can retain an older output URL beside a new partial-crop message.

**Refinement:** retain one shared component with a small presentation distinction:
neutral preparation/cancellation, warning for incomplete outcomes, green for
saved output, red for errors. Clear or qualify old messages/output links when
editing resumes. Prepared output should plainly say it has not been saved.

**Acceptance:** every status matches whether a file exists and whether current
edits were saved; Finder always refers to the output described by the message.

Evidence: [ResultMessageView.swift:10](/Users/D068138/Development/private/PDFwringer/PDFwringer/Views/ResultMessageView.swift:10),
[CompressViewModel.swift:291](/Users/D068138/Development/private/PDFwringer/PDFwringer/ViewModels/CompressViewModel.swift:291),
[CropOptionsView.swift:237](/Users/D068138/Development/private/PDFwringer/PDFwringer/Views/CropOptionsView.swift:237).

### 5. Make all tools comfortable in short/narrow windows — M

The declared minimum is 650×420. Crop, Rotate, Merge, and Reorder use fixed
options stacks; other tools scroll. Additional selection fields, warnings, and
results increase height. Crop's four 50-point fields and button share one row;
Rotate's mutation controls and Save share another crowded row.

**Refinement:** reuse the existing scrolling treatment; arrange margins in a
compact 2×2 layout and separate rotation controls from the primary save action.
Reflow long result messages/actions. Also constrain overly wide form content so
labels, choices, and action buttons do not become disconnected in large windows.

**Acceptance:** minimum, default, and enlarged windows keep controls, errors,
Cancel, and primary actions reachable, including protected PDFs and long names.

Evidence: [ContentView.swift:233](/Users/D068138/Development/private/PDFwringer/PDFwringer/ContentView.swift:233),
[CropOptionsView.swift:64](/Users/D068138/Development/private/PDFwringer/PDFwringer/Views/CropOptionsView.swift:64),
[RotateOptionsView.swift:44](/Users/D068138/Development/private/PDFwringer/PDFwringer/Views/RotateOptionsView.swift:44),
[MergeOptionsView.swift:125](/Users/D068138/Development/private/PDFwringer/PDFwringer/Views/MergeOptionsView.swift:125),
[ReorderPagesView.swift:107](/Users/D068138/Development/private/PDFwringer/PDFwringer/Views/ReorderPagesView.swift:107).

### 6. Explain invalid page ranges before asking for a destination — S/M

Shared selection suppresses parsing failures into an empty set. Several tools
only shake the field, so users cannot identify the reason. Export opens its
folder chooser before checking selection validity.

**Refinement:** expose the existing parser's readable explanation adjacent to
the field, distinguish no selection from invalid input, and validate before
opening a file/folder panel. Retain thumbnail/text synchronization.

**Acceptance:** malformed/out-of-bounds ranges have specific readable and spoken
feedback; no destination chooser opens for an invalid operation.

Evidence: [PageRangeParser.swift:81](/Users/D068138/Development/private/PDFwringer/PDFwringer/Services/PageRangeParser.swift:81),
[PageSelectionView.swift:24](/Users/D068138/Development/private/PDFwringer/PDFwringer/Views/PageSelectionView.swift:24),
[ExportImagesOptionsView.swift:157](/Users/D068138/Development/private/PDFwringer/PDFwringer/Views/ExportImagesOptionsView.swift:157).

## Priority B — highest-leverage consistency and delight

| Rank | Refinement | Why / smallest useful change | Effort | Evidence |
|---|---|---|---|---|
| 7 | Honest crop guides | Default A4 creates an unexplained outline on entry; crop and resize guides can coexist. Show only the actively edited pending operation; suppress unsolicited resize guides. | S/M | CropOptionsView.swift:17,185; CropPreviewPanel.swift:23 |
| 8 | Separate page inspection from selection | A plain thumbnail click both navigates and toggles inclusion. Inspecting a selected page can exclude it. Give the existing two actions distinct, discoverable interactions; preserve keyboard equivalents. | M | PageThumbnailStripView.swift:104,146,167 |
| 9 | Keep comparison visually coherent | Large Result preview still uses Original thumbnails/popover imagery. Follow the active document where practical, or explicitly identify source-only navigation imagery. Reserve stable space for Compare so preparation does not abruptly shrink the preview. Avoid another parallel cache implementation. | S/M | CompressOptionsView.swift:20,30,36; PageThumbnailStripView.swift:118 |
| 10 | Consistent primary/secondary action hierarchy | Crop has three prominent actions, Split has three competing export actions, Rotate mixes edits and Save. Keep Save/Export strongest; make Apply controls secondary. Clarify Save Copy versus publication, and label prepared Cancel as discard where appropriate. | S | CropOptionsView.swift:122,150,162; SplitOptionsView.swift:71,89,107; RotateOptionsView.swift:66 |
| 11 | Readable, compact consequence notices | Flattening losses use tiny tertiary text while incidental headings receive more weight. Keep all material loss/protection disclosures, group them beside their triggering controls, and foreground the immediate consequence. | S | MetadataOptionsView.swift:91,124; CompressOptionsView.swift:88; CropOptionsView.swift:154 |
| 12 | Complete spoken control identity | Name export groups, crop paper size, and split keep/remove fields distinctly. Merge removal labels should identify the file. Compression choices should speak estimated size and larger-than-original warnings; thumbnail state should include both Current and Selected. | S | ExportImagesOptionsView.swift:79,93; CropOptionsView.swift:136; SplitOptionsView.swift:86,104; MergeOptionsView.swift:65; CompressOptionsView.swift:164; PageThumbnailStripView.swift:103 |
| 13 | Predictable keyboard/focus behavior | Back and prepared Cancel compete for Escape; processing Cancel lacks that shortcut. Verify normal arrow/caret behavior in fields and focus after navigation. Align Actions menu with existing card operations, including Reorder/Export, while preserving established shortcuts. | S/M | OptionsHeaderView.swift:15; CompressOptionsView.swift:262,281; PDFwringerApp.swift:60,88 |
| 14 | Calmer action chooser | Eight shadowed cards and generous gaps consume vertical space. Tighten card padding/gaps slightly and reduce repeated shadows/hover lift; retain icons, titles, descriptions, and established order. | S | DocumentView.swift:43; ActionCardView.swift:37–47 |
| 15 | Visible replacement-drop feedback | Workflow drop receivers update isDropTargeted without displaying it. Reuse a quiet border around the actual accepting preview column. Avoid implying the whole window accepts drops. | S | DocumentView.swift:20,34; CropOptionsView.swift:26,56; LandingView.swift:43 |
| 16 | Clear, reachable progress and results | Name the current operation/attempt stage alongside existing progress. Keep Cancel discoverable and reveal new feedback without unnecessarily stealing focus or moving the document. Wrap long result actions beneath the message in tight widths. | S/M | CompressOptionsView.swift:277; SplitOptionsView.swift:115; ResultMessageView.swift:26 |
| 17 | Comfortable preview controls | Tiny plain zoom symbols have labels but no per-control help or generous hit areas. Add modest padding, native focus/hover feedback, and concise tooltips. Keep the compact floating toolbar. | S | PDFPreviewView.swift:197–215 |
| 18 | Calm motion and readable accent text | Honor Reduce Motion for slides, shimmer, pulse, and bounce; delete the page-count bounce. Measure small coral text in light appearance and Increase Contrast; use an adaptive foreground where needed rather than changing the brand everywhere. | S | LandingView.swift:17,67; DocumentView.swift:55; PageThumbnailStripView.swift:91,197; CompressOptionsView.swift:183; PDFwringerError.swift:330 |

## Priority C — finishing touches after interaction fixes

19. **Consistent headers and long names — S.** Merge duplicates a smaller Back
control. Reuse the existing header pattern, unify page/file-size punctuation,
and expose full filenames/path through help. Avoid extra permanent text.
Evidence: OptionsHeaderView.swift:11,22; MergeOptionsView.swift:127;
DocumentView.swift:47.

20. **Plain desktop language and number formatting — S.** “Tap thumbnails”
should be “Click”; explain CW/CCW and Hi-Con/B&W through clear labels/help;
use locale-aware adjustment values as already done for target/crop input.
Explain disabled password creation next to its flattening dependency.
Evidence: PageSelectionView.swift:36; RotateOptionsView.swift:67;
ColorAdjustOptionsView.swift:201,207; MetadataOptionsView.swift:124.

21. **Cleaner landing composition — S.** Reduce the oversized blurred icon's
visual dominance and increase secondary-instruction readability. “Choose files
or press ⌘O” describes the actual interaction more precisely than “click to
select,” which can imply the whole empty area is clickable. Preserve the
simple drop-first composition. Evidence: LandingView.swift:24,79.

## Flow coverage and intended outcome

| Existing flow | Main refinement | Preserve |
|---|---|---|
| Landing / file intake | Clear selection copy, restrained backdrop, visible drop targeting | Native chooser and drop-first simplicity |
| Document overview | Compact cards, readable names, matching menu order | Preview beside understandable operation choices |
| Compression | Truthful preparation state, consistent comparison imagery, stage feedback | Exact prepared bytes, explicit image-compression consent, viewport preservation |
| Split / extract / remove | Distinct fields, explicit output action names, balanced hierarchy | Separate existing operations and native destinations |
| Merge | Reachable options, file-specific labels, verify keyboard ordering | Ordered list and drag ordering; fail-closed intake |
| Rotate | Roomy controls, clear direction names, selection errors | Immediate working-copy preview and explicit Save |
| Crop / resize | Pending/apply/save clarity and honest guides | Independent crop/resize actions, source untouched |
| Color adjustment | Scope-correct preview and honest unavailable state | Direct sliders, existing presets and Reset |
| Metadata / protection | Readable warnings, explain dependencies, stale-status cleanup | Conservative protection behavior and explicit flattening |
| Image export | Validate first, named choices and stage feedback | Existing formats/resolutions and folder destination |
| Reorder | Reachable options, clear feedback, unchanged keyboard alternatives | Existing Move Earlier/Later and drag interaction |

## Deliberately leave alone

- The two-column document/options model, coral identity, native controls, and
  modest rounded surfaces. No redesign or new navigation framework is needed.
- Exact-output Prepare → Review → Save Result and preservation of page/zoom/pan.
- Native open/save panels, source protection, cancellation, and unsaved-work guards.
- Explicit loss/protection caveats. Improve their hierarchy; do not hide them to
  make the screen appear cleaner.
- Existing Finder reveal, retry, selectable status text, and status announcements.
- Reorder's existing non-drag interactions and thumbnail keyboard support.
- The feature set. No onboarding tour, dashboard, new presets, cloud integration,
  operation chaining, history system, or celebratory animation is justified here.

## Suggested bounded increments

1. **Trust:** items 1–4, plus honest crop guides and stale output-link cleanup.
2. **Reachability:** items 5–6, then control names and keyboard verification.
3. **Consistency:** comparison imagery, selection interaction, action hierarchy,
   warning presentation, and command parity.
4. **Visual finish:** card density, drop feedback, control targets, motion/contrast,
   headers/copy, and landing composition.

Do not combine these into a rewrite. Validate each touched workflow with minimum
and default window sizes, keyboard/VoiceOver, light/dark appearance, long names,
protected inputs, cancellation, failed operations, and resumed editing after Save.
Use focused tests for behavioral changes; use native visual inspection for spacing
and appearance. Then create one new signed candidate and repeat the release gates.

## Implementation — 0.2.1 (build 5)

Implemented the high-value interaction, accessibility, consistency, and visual
refinements above. Crop blocks saving pending inputs and guards navigation; color
preview honors selection and exposes unavailable/updating states. Navigation and
inclusion are separate thumbnail actions, with both states exposed to assistive
technology. Result styling follows actual publication, old output links clear on
editing, and options/results reflow and scroll. Keyboard commands, labels, merge
ordering alternatives, disclosure typography, hit targets, drop feedback, motion,
card density, filenames, locale formatting, and landing composition were refined
without adding PDF operations or dependencies.

Regression suite: 402 passing tests (335 fast, 61 corpus, 6 performance). Native
checks confirmed pending crop Save does not open a chooser or write output; Back
prompts and Keep Editing preserves the draft. Thumbnail inspection preserves
inclusion and speaks Current plus Selected; invalid ranges show their parser
reason. Left Arrow edits the range text without changing the current page.
Compression choices speak measured estimates and larger-than-original warnings.
Preparation leaves the destination untouched and exposes a neutral receipt;
Command-S publishes and changes it to saved feedback. Metadata save feedback
remains visible and clears when the fields are edited.

Exact 650×420 sizing and a complete VoiceOver/Increase Contrast certification
remain explicit final QA gates; do not infer them from the source/layout fixes.
See `APP_STORE.md` for signed candidate and distribution evidence.

## Task-flow follow-up — 0.2.2 (build 6)

User feedback exposed the Back chevron's inadequate hit target, fixed pane widths,
ambiguous Security wording, and the lack of Merge entry from a single PDF. This
increment uses one repeatable navigation pattern: pinned, full-button Back to the
tool chooser, and pinned Close File from the chooser to neutral file selection.
All ten two-column screens now use Apple's native
[HSplitView](https://developer.apple.com/documentation/SwiftUI/HSplitView), preserving
reachable minimum widths while permitting divider adjustment.

Merge joins the existing tool chooser and Actions menu. A single opened PDF starts
its list; Add Files explains the next step. Back keeps the original document and
its active file access. Removing the last file keeps the list open. Failed intake,
discard refusal, and running-operation gates preserve their previous guarantees.
The landing screen retains only neutral file selection; no Merge button or note.

Password Protection names the actual operation. New password creation is reachable
directly, but first explains and asks consent for an image-based copy, including
loss of text selection, links, editable annotations/forms, accessibility tags, and
signatures. The app's current safe writer requires this path; PDF files do not
inherently require flattening to use a password. No weaker writer or new encryption
dependency was introduced. Removal and retention still use the existing ordinary
save path. Original inputs remain unchanged.

All 406 tests passed, with focused merge-return/security-scope regressions. Native
checks confirmed the neutral landing screen, one-PDF Merge entry and return,
empty-list recovery, discard protection, Back-chevron clicks, loaded-preview
divider dragging, and password consent/cancellation. Exact minimum-window and
complete assistive-technology certification remain final QA gates. Validation
evidence and remaining release gates are in `APP_STORE.md`.
