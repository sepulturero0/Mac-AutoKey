# Implementation notes

- `MacAutoKeyApp.swift`: SwiftUI window, persistent MenuBarExtra, app lifecycle cleanup.
- `MainView.swift`: two native configuration tabs, explicit shortcut key/modifier editors, sequence row add/delete/reorder, Accessibility and focus controls.
- `AppModel.swift`: coordinates commands, mutually exclusive runs, validation/autosave, errors, and per-run PID/focus checks. Settings changes stop active runs.
- `Models.swift`: typed Codable settings/actions/shortcuts, validation, UserDefaults store. Invalid changes never replace the stored valid snapshot.
- `KeyCatalog.swift`: explicit macOS virtual key codes and US ANSI character mapping; Unicode is a separate selectable mode.
- `AutomationEngines.swift`: independent single-task clicker and sequence engines; monotonic cancellation-aware suspension, state transitions, generations preventing stale task completion from overwriting a restarted run. Input emitters and safety gates are injected for meaningful tests.
- `EventEmitters.swift`: CoreGraphics/AppKit event construction, HID-stream posting for pointer mode and process-directed fixed clicks. Private source state; down/up pairs and Shift release are synchronous groups. Unicode sent per character, never through the clipboard. Allocation failures throw. Quartz posting has no delivery acknowledgment: permission preflight cannot prove a target consumed an event.
- `GlobalHotkeyManager.swift`: Carbon pressed/released hotkeys; repeat latch, per-shortcut registration errors, native cleanup. Emergency registered first and retained for invalid editor settings. No global keyboard event tap or idle event polling.
- `Permissions.swift`: supported AX trust and event-post preflight; prompt only on user request, System Settings link and manual/activation refresh.
- `TargetManager.swift`: NSWorkspace activation/session/sleep notifications, foreground process and bundle metadata. Saved target identity is bundle ID plus canonical bundle path. No polling while idle.

Swift 6 isolation is explicit: observable services, engines, UI, and emitters live on the main actor, while models are Sendable values. Event creation/posting is a bounded synchronous operation; sleeps suspend and never block the event loop. This avoids cross-thread races and leaves hotkey/Stop All processing available during waits. There are no network services, external databases, unbounded loops, or busy waits. Active timers are represented by at most one cancellable task per engine; short modifier-release checks run only at activation (maximum 3 seconds).

The permission/focus/modifier gate runs before every click/key/character. NSWorkspace notifications cancel an active run even during a long wait. A PID is fixed once the 3-second manual arming or shortcut release finishes. Application-level focus protection cannot inspect remote-session contents or distinguish windows within the same process. Events already in the system queue cannot be recalled. The clicker sleeps from the last click and never compensates for a system stall by flooding events.

Unit tests verify actual engine scheduling/state transitions with recording emitters, persisted Codable data, validation and mappings. They do not grant permissions, prove real target event consumption, or prove Citrix compatibility. Live verification and its limits are recorded separately.

`LocalVerification.swift` is an opt-in development integration launcher reached only by explicit command-line arguments. It uses isolated settings and a freshly launched disposable receiver with a fixed bundle identifier and verified bundle path/PID. It adds a pointer-in-counter safety constraint for click checks. The ordinary app performs none of these launch-time test actions. `DebugDiagnostics.swift` is compiled out of release builds and captures only its own window via `SCShareableContent.currentProcess`; it does not request broad screen-recording access. Numeric input uses retained string drafts so blank/malformed edits cannot silently run the prior numeric value.

## Version 1.1 command and focus changes

`KeyboardCommand` owns a stable UUID, name, enabled state, hotkey, entry mode, delay, and actions. Configuration schema 2 persists a command collection; decoding schema 1 migrates the original sequence losslessly. The existing UserDefaults key stays unchanged. Command IDs map to unique Carbon registration IDs; registration IDs are never reused during a process lifetime, so stale queued events cannot trigger a newly assigned command. Duplicates receive new command and action IDs. Numeric drafts are scoped to each command or action ID.

Manual runs hide the utility before the three-second countdown. Shortcut runs capture the foreground PID before waiting for modifier release and verify it again before emitting input. Workspace notifications cancel only an unavailable session or a real change away from the bound PID. Repeated activation notices for the same application are harmless. Engine failures propagate to a persistent visible message. `--permission-report` is an explicit, read-only Launch Services diagnostic and performs no automation.

## Pause lifecycle (1.3)

Each engine creates an independent `RunControl` per run. Pause cancels only the current sleep and suspends the existing task on a continuation; it preserves remaining delay and iterator position. Resume releases the continuation. Stop cancels the task, cancels its sleeper, releases any pause waiter, and invalidates its generation. There is no polling while paused. Pause remains an active owned run, so duplicate starts cannot overlap it.

A paused run retains its original foreground PID and permits configuration-window inspection. Resume rechecks permission, configuration and that exact PID; a different allowed process cannot inherit the run. Manual resumption uses a separately cancellable countdown protected by a generation token. Session lock/sleep, settings edits, Stop All, and feature replacement cancel pending resume as well as both engines.

## Fixed click position (1.5)

Configuration schema 2 gains optional fixedClickEnabled/fixedClickX/fixedClickY keys. Older files decode with the mode off and existing commands preserved. Numeric drafts support signed coordinates and block invalid starts/saves. A cancellable three-second pointer capture sends no input; cancellation is checked before publishing countdown state so a task cancelled before scheduling cannot restore stale UI.

Fixed runs snapshot their screen point and obtain the same bound PID after preparation. Before each pair, an Accessibility hit-test verifies the point belongs to that PID, with a 200 ms messaging timeout. Window geometry supplies the receiving window number and local point. Noninteractive Dock/display overlays in the window list do not determine input ownership. No screen contents, window titles, private CGEvent fields, or cursor-association APIs are used.

The public [NSEvent mouse-event factory](https://developer.apple.com/documentation/appkit/nsevent/mouseevent(with:location:modifierflags:timestamp:windownumber:context:eventnumber:clickcount:pressure:)) supplies the receiving window identity. Its CGEvent uses a flipped window-relative point for process-directed delivery; source state is explicitly private. [CGEvent.postToPid](https://developer.apple.com/documentation/coregraphics/cgevent/posttopid(_:)) sends the synchronous pair only to the verified process. It never falls back to HID posting or cursor warping. The normal pointer-following mode retains HID delivery. Since posting has no consumption acknowledgment, app-specific acceptance remains a practical limit; the integration receiver verifies actual NSButton actions and an unchanged pointer at two separate positions during a run.

## Image condition (1.6)

ImageConditionSettings is an optional schema-2 field; older settings default to disabled. Its normalized reference PNG, logical point dimensions, name, and similarity threshold persist locally with the existing configuration. File imports are size-bounded and plain/unreadable images are rejected. Screen Recording is checked with the supported CGPreflightScreenCaptureAccess API and requested only by the explicit UI button.

ImageConditionMonitor samples composited ScreenCaptureKit display crops covering the frontmost target window, without the cursor or audio. It captures visible pixels rather than a hidden window image. Captured frames remain in memory. A background ImageMatcher actor uses bounded RGB rasters, normalized luminance correlation, and color similarity with coarse/fine position search at common scales. Positive and negative results are cached for at most 200 ms measured from capture start. Matching is heuristic; recognition errors and OS capture latency remain practical limits.

The matcher decodes the reference image once per reference change and reuses resized templates and coarse/fine sample plans across frames. Sample plans are rebuilt only when the captured frame width changes. This avoids repeating PNG decode, gradient sorting, and sample-array allocation on every poll while keeping the same search scales, scoring, threshold, and polling cadence.

The clicker awaits the condition before input and rechecks cancellation, pause, and target safety after asynchronous work. Missing images produce waitingForImage and no emission; returned images resume only an armed run. Long click intervals are divided into cancellable slices so disappearance is still monitored. Pause during a capture discards its result after resume. Stop invalidates monitor generations, cancels engine tasks, and cannot be undone by a late capture. Session and Accessibility protection remains active while waiting; focus and physical modifier behavior depends on whether Image condition is enabled (see 1.6.4). Ordinary operation with Image condition disabled does not capture the screen.

The opt-in --verify-image-condition integration uses only the disposable Input Receiver, a generated marker image, and local marker-state files to show/hide that marker. It verifies real delivered clicks for image presence, disappearance, return, manual Pause/Resume, and Stop. It never modifies user references or configures a business target.

## Focus changes during image monitoring (1.6.4)

The clicker stores its target PID separately from keyboard automation. With Image condition enabled, app activation and physical modifier-key changes do not cancel the image monitor. The monitor remains bound to the original target; if that window is not on-screen (for example, after switching Spaces), the condition is treated as absent and the engine waits for it to return. Click dispatch is gated on the original target being frontmost, and is suppressed while keyboard automation runs, so a background image monitor cannot click another app. Without Image condition, focus loss still stops the run and the existing modifier-key guard remains. Session lock/sleep and permission failures continue to stop automation.

## Direct screen crop (1.6.1)

ScreenRegionPicker hides the configuration, snapshots connected screens with ScreenCaptureKit, and presents borderless crosshair selection panels. A flipped selection view maps logical screen points to each snapshot’s pixels, including Retina scaling. Only the selected crop is normalized and persisted as an ImageReference; full screen snapshots remain in memory and are discarded when selection ends. Escape, right-click, or application deactivation cancels without replacing the prior reference. Capturing stops active automation and blocks new runs until selection completes.

## Image appearance delay (1.6.2)

ImageConditionSettings.appearanceDelayMS defaults to zero when decoding older settings and accepts 0–60,000 ms. AutoClickerEngine enters waitingForImageDelay after a positive match, sleeps in at most 200 ms slices, and rechecks the image/focus/cancellation before clicking. Observed absence cancels the pending click and resets the full appearance delay. After the first click, the existing interval governs subsequent clicks until another absence. RunControl freezes the delay during Pause; Stop cancels it. The delay is ignored when no image condition is supplied. The menu bar keeps the eye symbol and uses blue while the image is absent, green as soon as it matches (including appearance delay and clicking), and orange while manually paused. Cached image identity is preserved across matching updates.
