# Live local acceptance checks

Status: **Local Cocoa input and native shortcut event dispatch VERIFIED through the explicit integration harness**; see TEST_RESULTS.md and evidence/local-input.json. The user also confirmed the physical-key sample output and click-counter start/stop worked. The instrumented physical-key recorder timed out; its raw results remain unchanged. Physical emergency stop and the remaining detailed manual UI checks are not separately verified. Accessibility was granted by the user. The native UI automation bridge was unavailable; no TextEdit/VoiceOver interaction is claimed.

Use a new, disposable TextEdit document (Format → Make Plain Text) for the first keyboard test. Do not use an existing user document. Alternatively, the included local NSTextView fixture gives structured results:

```sh
Scripts/build-input-receiver.sh
open '.build/Input Receiver.app'
open 'dist/Mac AutoKey.app'
```

The fixture is a separate local AppKit application, not part of the shipped utility. It records only text entered into its own empty editor and its harmless button's click timestamps in `/tmp/MacAutoKey-input-receiver.json`. It never reads another app's input. Quit it after testing.

1. Enable Accessibility for the final `dist/Mac AutoKey.app`; return and click Check Again. Turn Citrix Only off.
2. Focus a new plain text document. Invoke Command + Up once and release modifiers. Expect exactly `15\n10\n`, with at least the two configured 500 ms waits plus per-key delays. Hold the shortcut to check there is no overlapping repeat.
3. Change the shortcut to Control + Option + F9; repeat while TextEdit is focused. Record registration and real delivery separately.
4. In the fixture, position the pointer over **Click counter**. Press F6, leave it for about 3 seconds, then F6 again. Expect about 30 clicks at 100 ms. Inspect timestamps for scheduling tolerance; do not count the manual positioning click.
5. Confirm the counter stops increasing after the last queued mouse pair. Repeat with Stop All via Command + Shift + Escape and via menu while the configuration window is closed.
6. Set a sequence with a 60-second initial wait; stop during the wait. Then use a long text action and stop during typing. No subsequent character/step should occur beyond a pair already sent.
7. Start clicking or typing, then switch to another application. Input must stop before the new app receives further generated actions. Repeat with Citrix Only on and the fixture explicitly allowed; test allowed-to-allowed focus changes.
8. Set Citrix Only on with no matching target and invoke from TextEdit. Expect no generated events and an understandable block message. Capture the intended app and verify its bundle ID/path; remove it and repeat the block test.
9. Change intervals, modifiers, text mode and action order; add and remove a step. Close the window and reopen through the menu; then quit and relaunch. All valid settings should remain, with both engines stopped.
10. Test invalid intervals, duplicate shortcuts and a sequence that could trigger an unmodified activation key. Expect visible validation, preserved last valid stored settings, and emergency stop registration retained. Try a shortcut already owned by another utility and record the registration warning.
11. Deny Accessibility and try manual start. Expect guidance and no generated input. Re-enable and relaunch if needed. Test permission revocation during a run with a disposable target; no future emission should pass the permission gate.

Keep results and timestamps under `docs/TEST_RESULTS.md`. Mock-event success cannot be relabeled as live TextEdit or Citrix success.

## Version 1.1 command/start regression checks

- Add two commands with different names, hotkeys, delays, and text. While the first command is selected in the editor, focus a disposable text field and invoke the second command’s hotkey; only its content must appear.
- Duplicate a command, edit its text and delay, restart, and confirm both commands retain their independent content and shortcuts.
- Delete a command with an invalid delay draft; its invisible error must disappear and the remaining command must still save.
- From the utility window, use manual Run; it hides itself and provides three seconds to focus the target field. Verify output appears there.
- Check the saved clicker shortcut in Troubleshooting, including modifiers and Fn behavior.
- Verify permission with the normal bundled app through Launch Services; a direct Codex/terminal-launched pass is insufficient. Re-add the exact finished bundle after an ad hoc rebuild if the app reports denied.
