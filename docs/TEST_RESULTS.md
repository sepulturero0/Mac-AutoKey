# Build and verification results

Date: 2026-11-02. Host: Apple Silicon, macOS 26.6.2 (25G83), Apple Swift 6.3.3, Command Line Tools. Full Xcode is not installed.

Permission reports retain the measured flags and version; local home-directory paths are redacted in the public copies.

## Version 1.5 fixed click position

**PASS — 40 automated tests in 12 suites:** [unit-tests-v1.5.txt](evidence/unit-tests-v1.5.txt). New tests cover older-settings compatibility, coordinate persistence/negative values/range errors, invalid drafts and recovery, cancellation before the picker task starts, fixed-position routing through the bound PID/window, no fallback on target failure, pause/resume continuity, and stopping without later input.

**PASS — 27 live local-input checks on the final universal app through Launch Services:** [local-input-v1.5.json](evidence/local-input-v1.5.json). Six new checks verify the real three-second position picker, NSButton actions at the saved screen point while the pointer is elsewhere, unchanged pointer coordinates at two locations during one run, fixed-click pause/resume/stop, and rejection of the wrong target/off-display positions. The final run delivered 5 fixed clicks before its first pause. Receiver event evidence includes the actual receiving window and local coordinates. Existing manual start, hotkey, Unicode/common-key delivery, focus loss and cancellation checks also pass.

**PASS — application identity and preservation:** [permission report](evidence/permissions-launchservices-v1.5.json) reports both Accessibility and event-posting access true for version 1.5.0. All pre-existing settings, including the two user commands and Option+F6 clicker shortcut, match the backup. The only newly stored keys are disabled fixed-position defaults; integration settings remain isolated.

**PASS — UI and delivery:** native own-window review covers enabled mode at minimum size/dark and fullscreen/light, plus disabled mode at default size. See [UI_REVIEW.md](UI_REVIEW.md). Optimized arm64/x86_64 universal build, strict signature verification, plist/project parsing, and ZIP integrity pass; [checksums](evidence/SHA256.txt). Local behavior was tested on this host only. Other apps may reject process-directed input; Citrix, external displays and Intel hardware remain unverified. Fixed mode never falls back to moving the cursor.

## Version 1.4 fullscreen layout

**PASS — native fullscreen and minimum-size layout:** own-window captures verify full native macOS fullscreen (`nativeFullscreen: true`, 1512 × 949 window points) for Keyboard Commands in dark mode and Auto Clicker in light mode, plus Keyboard Commands at 860 × 650 content points. The centered workspace bounds header/footer width, caps editor width, and leaves command-management and Run controls visible. See [UI_REVIEW.md](UI_REVIEW.md) and `.impeccable/review/*-v1.4.png`. No input is emitted by layout previews.

**PASS — 32 automated tests in 10 suites:** [unit-tests-v1.4.txt](evidence/unit-tests-v1.4.txt). **PASS — 21 live local-input checks:** [local-input-v1.4.json](evidence/local-input-v1.4.json), exercising the final universal app through Launch Services. Both permission checks are true after refreshing the existing Mac AutoKey grant for the new ad hoc signature: [permission evidence](evidence/permissions-launchservices-v1.4.json). The two-command user configuration matches its pre-update backup exactly.

**PASS — delivery:** version 1.4.0, arm64 + x86_64 universal build, strict signature verification, project/plist parsing, and ZIP integrity. Checksums: [SHA256.txt](evidence/SHA256.txt). No external monitor, Intel hardware, or Citrix session was exercised.

## Version 1.3 status and pause update

**PASS — 32 automated tests in 10 suites:** [unit-tests-v1.3.txt](evidence/unit-tests-v1.3.txt). Added pause/resume coverage checks no events while paused, no duplicate starts, exact character continuation, remaining-delay preservation, stopping a paused task, safe restart, pending-resume cancellation/generation isolation, direct-engine stop, and session lock cancellation. Workspace-notification tests are grouped serially because they broadcast process-wide notifications.

**PASS — 21 live local-input checks on the final bundled build:** [local-input-v1.3.json](evidence/local-input-v1.3.json). New checks verify actual click pause/resume, keyboard continuation with exactly `123456`, rejection of resume into a different foreground process, and Stop All during pause. Existing hotkey, Unicode/common-key delivery, focus protection and cancellation checks also pass. The final run delivered 11 measured clicks with approximately 121–142 ms intervals for a 100 ms setting, within the acceptance tolerance; OS/event delivery timing is not a hard real-time guarantee.

**PASS — normal app identity:** Accessibility and event-posting checks were both true through Launch Services after refreshing the completed bundle’s grant in System Settings; [permission evidence](evidence/permissions-launchservices-v1.3.json). Saved configuration matched its pre-update backup exactly (two user commands). Integration used isolated settings and disposable receivers only.

**PASS — native status captures:** `.impeccable/review/status-stopped-v1.3.png`, `status-running-v1.3.png`, and `status-paused-v1.3.png` show labeled gray, green, and amber status indicators, matching sidebar state and pause/resume controls. Running/paused captures use opt-in delay-only preview runs, which cannot emit input. Color is never the sole state cue. Starting is blue and errors are red. Menu actions are wired to the same tested model; physical hardware pause/menu interaction and Citrix remain unverified.

**PASS — build/package:** optimized arm64 and x86_64 builds, universal merge, strict code-signature verification, project/plist parsing, and ZIP integrity. Version 1.3.0 is at `dist/Mac AutoKey.app`. The ZIP and executable checksums are in `docs/evidence/SHA256.txt`.

The typing-cancellation receiver check now waits 100 ms after Stop before comparing two stable snapshots, allowing already-posted Quartz events to drain. Engine unit tests separately assert that no events are emitted after Stop. This removes the immediate-receipt assumption documented in the 1.2 first attempt; the app still cannot retract a system event already queued.

## Version 1.2 usability update

**Build PASS:** Swift 6 debug and optimized arm64/x86_64 universal builds, strict code-signature verification, Xcode/Info.plist parsing, and ZIP integrity. The app is delivered at `dist/Mac AutoKey.app`, version 1.2.0.

**Automated tests PASS:** 27 tests in seven suites; [unit-tests-v1.2.txt](evidence/unit-tests-v1.2.txt). Two added command-recovery tests verify exact restoration of content/order/selection/storage and safe shortcut reassignment when the old shortcut was reused.

**Live input PASS on repeat:** all 17 required checks passed through Launch Services on the final 1.2 binary; [local-input-v1.2.json](evidence/local-input-v1.2.json). Both permission checks were true after replacing the old Accessibility entry with the completed 1.2 bundle; [permission evidence](evidence/permissions-launchservices-v1.2.json). Actual delivered clicks, independent keyboard-command hotkeys, manual target restoration, background operation, focus-loss stop, and cancellation were exercised in the disposable receiver. The final click run delivered 13 clicks with approximately 96–119 ms intervals for a 100 ms setting.

The first attempt passed 16 of 17 checks; its strict typing-stability assertion observed the receiver text change between the immediate stop snapshot and the later snapshot, ending at three characters. It is retained in [local-input-v1.2-first-attempt.json](evidence/local-input-v1.2-first-attempt.json). An unchanged-binary repeat passed. This is consistent with a previously posted event reaching the receiver after the stop snapshot, but that cause was not instrumented and is not claimed as proven. Unit cancellation tests passed. As documented in the README, Stop cannot retract a Quartz event already queued by macOS.

**UI reviewed:** native light/dark captures, minimum-width empty state, fixed run controls with scrollable steps, sidebar navigation, and the independent Settings window. Captures use isolated preview data and disable shortcuts. Settings capture exited normally after the final change. See [UI_REVIEW.md](UI_REVIEW.md). Full interactive VoiceOver and physical Intel/macOS 14 checks remain unverified.

**User data preserved:** after live tests, the saved configuration matched its pre-update backup exactly. The removed sample command remained absent. Tests used isolated settings and never targeted existing user documents or Citrix.

The following sections retain earlier version 1.1 investigation and validation history; current evidence is the version 1.2 section above. Citrix remains **NOT VERIFIED**.

## Build

- **PASS** — Swift 6 debug compilation and Swift Testing runner.
- **PASS** — optimized `arm64` and `x86_64` builds, combined with `lipo` into a universal macOS 14+ application.
- **PASS** — local ad hoc code signing and `codesign --verify --strict`.
- **PASS** — Xcode project and Info.plist parse with `plutil`; shared build/test scheme included.
- **NOT VERIFIED** — `xcodebuild`/Xcode IDE execution because only Command Line Tools are installed. The same Swift sources compile through SwiftPM; project-file parsing alone is not an Xcode build.
- **NOT VERIFIED** — execution on physical Intel hardware or macOS 14. The binary includes both architectures and targets macOS 14, but runtime checks took place on this Apple Silicon/macOS 26 host.

Reproduce with `Scripts/test.sh` and `Scripts/build-app.sh --universal`. The script builds each architecture separately, so it does not require the full-Xcode `xcbuild` multi-architecture builder.

## Version 1.1 automated tests: 25 passed, 0 failures

Six suites; full log: [unit-tests.txt](evidence/unit-tests.txt). Existing engine, event construction, persistence, numeric-draft, and session tests remain passing. Four additional tests cover lossless v1 settings migration, multiple-command persistence and stable UUID routing, cross-command shortcut conflicts/self-trigger rejection, and independent command duplication/deletion/drafts.

## Permission investigation — actual launch identity

The user reported that local automation did not work despite an enabled permission entry. The saved clicker shortcut was Option+F6, rather than bare F6; Citrix Only was off. A read-only diagnostic from the bundled version 1.1 app launched using Launch Services returned **Accessibility false and event posting false**. The same binary launched directly by Codex returned both true. Evidence: [normal launch before grant](evidence/permissions-launchservices-before-grant.json), [terminal launch](evidence/permissions-terminal.json).

This establishes that the old terminal-launched integration pass did not establish the normally launched app's permission grant. Local ad hoc rebuilding can invalidate an existing permission identity. The user subsequently clarified that the new bundle had not yet been added and explicitly asked the agent to do it. Through System Settings, the old Mac AutoKey entry was removed and the exact `dist/Mac AutoKey.app` version 1.1.0 bundle was selected and added. Its switch showed On. After restarting through Launch Services, both permission checks returned **true**; see [normal launch after grant](evidence/permissions-launchservices-after-grant.json). No TCC database was modified or security policy weakened. The live verification script now launches through Launch Services and writes temporary reports outside Documents, so it tests the app's own identity and requires no Documents access grant.

Version 1.1 also hides the configuration window before a manual countdown, verifies the original foreground PID after shortcut-modifier release, ignores duplicate activation notices for the same target, and displays failed starts prominently. These changes address target/start failure paths separately from the verified permission failure.

## Version 1.1 live local input

**PASS — all 17 required live checks**, launched through macOS Launch Services after granting the actual bundled application. Evidence: [local-input.json](evidence/local-input.json). No registration warnings occurred.

- The original command produced exactly `15\n10\n` in a standard local Cocoa text field.
- The second independent command’s own Control+Option+F9 hotkey produced exactly `222\n`, while the first command remained selected in the editor.
- A manual start from the focused configuration window hid the utility, restored the disposable editor, and delivered that command’s content correctly.
- Duplicate workspace activation notification for the same foreground target did not cancel clicking.
- Real delivered clicks numbered 13; intervals were approximately 98–113 ms for a configured 100 ms interval. Toggle and emergency shortcuts stopped input.
- Common navigation keys, Unicode text, background operation with the window closed, genuine target PID changes, and cancellation during delay/typing all passed.

These are real Quartz event delivery and Carbon shortcut dispatch checks against a separate disposable application. Shortcut events were generated by the test driver; they are not labeled as newly observed physical hardware keypresses. The user’s four saved commands were preserved because integration uses isolated UserDefaults settings.

Historical version 1.0 terminal-launched input results are retained in [local-input-v1.0.json](evidence/local-input-v1.0.json). They demonstrate local event delivery under that launch's responsibility, not the normal app's current permission state. Citrix remains **NOT VERIFIED**.

## Physical hotkeys

**PASS — user-confirmed sample output and click-counter start/stop.** On 2026-11-02, in response to the physical-key checklist, the user confirmed: “Yes — text and counter worked.” This supports the observed sample sequence output and clicker start/stop in the local receiver. Physical emergency-stop behavior was not separately confirmed.

**Recorder limitation:** the two-minute attempt and ten-minute retry timed out without recording the expected initial activation. Their raw reports remain unchanged: [physical-hotkeys-first-attempt.json](evidence/physical-hotkeys-first-attempt.json) and [physical-hotkeys.json](evidence/physical-hotkeys.json). The later human confirmation is separate evidence, not an automated recorder pass or a timing measurement. Both test processes stopped and exited safely. A future instrumented check can be run with `Scripts/verify-local-input.sh --physical-hotkeys`.

## UI, lifecycle and permissions

- **PASS at reviewed scope** — valid own-window captures of Auto Clicker in light mode and Keyboard Automation in dark mode (version 1.0); version 1.1 command management was also captured and inspected. An independent review scored invalid numeric draft handling and row-button alignment resolved; see [UI_REVIEW.md](UI_REVIEW.md).
- **PASS** — denied permission is displayed safely. Version 1.1 normal-launch permission checks are documented above; terminal-launched success alone is insufficient evidence.
- **PASS** — app stays alive when its configuration window closes. Menu bar status and Stop All are implemented through the same model.
- **PASS** — initial launch and repeat isolated verification launch. Launch paths were fixed so closed-window restoration does not prevent verification from starting.
- **OBSERVED** — the idle app sampled at 0.0% CPU, around 115 MB resident memory, with threads sleeping in native event loops. This is a spot observation, not a benchmark or leak proof.
- **NOT VERIFIED** — interactive VoiceOver navigation, full UI edit/relaunch checklist, permission revocation while actively sending events, and physical sleep/lock tests. These remain in [LOCAL_TEST_CHECKLIST.md](LOCAL_TEST_CHECKLIST.md).

Earlier native UI automation attempts timed out or reported a closed pipe. In the version 1.1 permission fix, native System Settings controls became available and were used to add the exact new bundle. Own-window captures and the explicit integration command provide the remaining local evidence. The first NSView cache captures were invalid and were replaced; only the current ScreenCaptureKit own-window captures were reviewed.

## Citrix

**NOT VERIFIED.** Citrix Workspace is installed and helper processes were present, but no active remote desktop session was used. Do not infer remote compatibility from local event delivery. Follow [CITRIX_TEST_CHECKLIST.md](CITRIX_TEST_CHECKLIST.md) for real remote number/Enter/click delivery, shortcut capture, Unicode vs physical keys, layout synchronization, and focus-loss behavior. No policy bypass or Citrix modification was attempted.
