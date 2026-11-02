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
