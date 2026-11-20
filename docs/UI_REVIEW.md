# Native UI finish review

Reviewed 2026-11-02. Independent Impeccable finish reviewer; native macOS conventions and the user's minimalist SwiftUI brief govern this review.

## Initial review

Disposition: **fix**.

- P1: Numeric fields bound directly to integers could retain a previous valid value when the displayed draft was unparsable, without setting a configuration error.
- P2: Press Key rows placed reorder/delete buttons earlier than text and delay rows, making the action columns inconsistent.

## Fix scoring

Disposition: **ship**, scoped to the two findings above.

- **P1 resolved:** All numeric fields now use string draft bindings. AppModel preserves invalid drafts, reports parsing/range errors, blocks preflight and automation shortcut registration, and saves valid configuration only. Correction restores registration; deleting a delay step removes its draft error. Reviewed NumericDraftTests covering malformed, blank, fractional, out-of-range and overflow values, last-valid persistence, denied starts, multiple drafts, and step deletion. The implementation agent reports 20 tests passing in four suites; the reviewer did not rerun them.
- **P2 resolved:** The refreshed keyboard capture visibly aligns reorder/delete buttons across every displayed action type. Press Key uses an expanding value region.

Both refreshed ScreenCaptureKit own-window captures are valid: `.impeccable/review/clicker-light.png` and `.impeccable/review/keyboard-dark.png`, 1520 × 1600 pixels. No regression introduced by the fix batch was identified in these captures or the targeted source inspection.

## Scope and limits

This scoring pass covers the two original findings, not a fresh whole-app audit. No live UI interactions, VoiceOver navigation, receiver input delivery, global shortcut operation, or Citrix session behavior were exercised by this reviewer. The updated previews show Accessibility access granted; that state is not evidence of successful input delivery. Live receiver integration remained in progress when this verdict was written. The initial review also did not capture long sequences or the minimum window size. The native SwiftUI surface was judged directly; no web-only detector ran.

## Version 1.1 follow-up

The implementation agent inspected the native keyboard-command capture `.impeccable/review/keyboard-dark-v1.1.png`. It shows the command picker, Add Command, Duplicate, Delete, name/enabled controls, independent hotkey and timing, and ordered editable actions. A follow-up source adjustment aligns the editor at the top and changes granted-permission copy to readiness text. This follow-up is not an independent whole-app audit. Real command routing and manual target restoration subsequently passed the normal-launch integration command (17 required checks); see TEST_RESULTS.md.

## Version 1.2 usability review

The implementation agent reviewed native captures of the clicker in light mode, keyboard commands in dark mode, an empty command list at minimum width, and the separate Settings window. The captures use isolated preview settings, disable global shortcuts, and send no input. Evidence: `.impeccable/review/clicker-light-v1.2.png`, `keyboard-dark-v1.2.png`, `keyboard-empty-min-v1.2.png`, and `settings-light-v1.2.png`.

The command sidebar, fixed run bar, named modifiers, direct Add Step choices, interval presets, typing-options disclosure, and empty-state next action are visible. The final fix batch corrected singular step counts, inactive sidebar text contrast, missing disabled-run explanations, and Settings presentation. Settings uses a native independent window; its capture process exited normally. Runtime errors can be dismissed while configuration errors stay visible.

The native macOS design takes precedence over the context helper’s web classification; its recognized platform list omits macOS. No web detector was run against SwiftUI. The existing design metadata sidecar was reported stale and was not regenerated as unrelated maintenance. This is a scoped self-review, not a new independent audit or a VoiceOver/hardware-platform test.

## Version 1.3 status indicators

The implementation agent inspected native running (light) and paused (dark) captures; stopped was also captured. Labeled status pills and matching command-row dots communicate green Running, amber Paused, gray Stopped, blue Starting, and red Error. Paused runs expose Resume and Stop in the fixed run bar; the menu bar offers Pause/Resume while keeping the target focused. Preview runs contain only a delay and cannot emit input. Native live integration separately verifies actual pause/resume delivery and target protection. No additional visual redesign or motion was introduced.

## Version 1.4 fullscreen layout

Scoped self-review of native fullscreen Keyboard Commands (dark), native fullscreen Auto Clicker (light), and Keyboard Commands at the 860 × 650 minimum content size. The fullscreen capture reports `nativeFullscreen: true` at 1512 × 949 window points. The workspace is centered with bounded widths, the editor no longer stretches with the display, and command-management and run controls stay visible. The final confirmation narrows the clicker shell to 940 pt so its run controls stay close to its settings. Evidence: `.impeccable/review/fullscreen-keyboard-v1.4.png`, `fullscreen-clicker-v1.4.png`, and `minimum-keyboard-v1.4.png`. Captures use isolated preview settings, disable global shortcuts, and emit no input. No external monitor or Intel hardware was tested.

## Version 1.5 fixed click position

Scoped self-review of Fixed click position enabled at the minimum content size (dark) and in native fullscreen (light), plus mode off at the default window size (light). Evidence: `.impeccable/review/fixed-position-minimum-v1.5.png`, `fixed-position-fullscreen-v1.5.png`, and `pointer-mode-v1.5.png`. The new switch appears immediately after the clicker introduction, with labeled X/Y fields, a Pick Position button, helper text, and the selected coordinates in the fixed run bar. Mode off disables its fields and picker. Content scrolls in shorter windows; the run controls stay visible. These own-window previews use isolated settings and emit no input. Model tests cover cancellation and invalid coordinate drafts, while live integration separately checks pointer-free delivery. No new independent audit, external display test, or VoiceOver session was performed.

## Version 1.6 image condition

Scoped native self-review inspected the enabled image condition at 860 × 650 content points (light) and Waiting for image in native fullscreen (dark). The reference preview/name, chooser, similarity threshold, local-processing explanation, waiting label, and fixed Stop control are visible without horizontal clipping. Evidence: `.impeccable/review/image-condition-min-v1.6.png` and `image-condition-waiting-v1.6.png`. The waiting fixture uses a constant-false condition and emits no input. The separate fixture integration checks the real matcher and delivered clicks. The first waiting screenshot was captured before the preview form settled and was replaced by the confirmed active waiting capture. No screen contents outside the app were captured for visual UI review.

## Version 1.6.1 direct capture

Scoped native review inspected the normal dark app with Image condition enabled. Capture Area and Import Image, similarity, permission status, and fixed Start/Stop controls remain visible and readable; lower click settings scroll. Capture Area opens the crosshair selection overlay with the configuration hidden. Returning from a user selection shows the reference preview, Captured screen area name, and success notice, with automation stopped. The generated-marker development run separately verified exact crop dimensions and Escape preservation. User screen/reference contents were not exported as review artifacts.

## Version 1.6.2 image appearance delay

Native light minimum-size preview (860 × 650 content points) shows the reference, Capture Area/Import Image, similarity, the labeled delay field, and 2 seconds preset without horizontal clipping. Extended guidance and click settings scroll beneath the fixed Start/Stop controls. Evidence: .impeccable/review/image-delay-min-v1.6.2.png/json. The preview uses isolated settings with hotkeys disabled and emits no input. A blue Waiting to click state and menu clock distinguish the configured delay from active green clicking.

## Version 1.6.3 steady image-condition icon

The menu-bar icon keeps the eye symbol and uses blue while the image is absent, green as soon as it matches (including the configured appearance delay), and orange during manual Pause. Resume returns to the appropriate waiting or matched color. The detailed window status and tooltip remain state-specific. The existing ClickerStatusItem refresh observer checks image identity before assignment, preventing unnecessary menu-bar image replacements during similarity updates.
