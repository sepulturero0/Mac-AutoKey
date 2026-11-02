# Citrix Workspace manual acceptance checklist

Current remote-session status: **NOT VERIFIED**. A Citrix Workspace installation alone is not a test session. Do not mark this checklist PASS using mocks or local TextEdit results.

Record macOS version, Mac architecture, app build/signing identity, Citrix Workspace version, remote OS/app, local keyboard layout, remote keyboard layout, keyboard synchronization/input mode, and relevant administrator restrictions. Record only non-sensitive test content.

Use a disposable remote plain text document and a harmless click counter or empty area. Avoid remote forms with business effects.

| Check | Procedure | Expected | Result |
|---|---|---|---|
| Permission | Grant Accessibility to the exact built app | Trust and event-post access shown granted | NOT VERIFIED |
| Actual viewer identity | Capture while the remote window is foreground | Actual viewer bundle ID and canonical bundle path saved | NOT VERIFIED |
| Focus gate | Citrix Only on; invoke in a non-allowed local app | No input; visible blocked status | NOT VERIFIED |
| Left clicks | F6, 100 ms, pointer over harmless remote counter | Repeated left clicks at pointer; no movement | NOT VERIFIED |
| Click interval | Compare counter/event timestamps over ≥3 seconds | About 10 clicks/second; no catch-up bursts | NOT VERIFIED |
| Click stop | Toggle F6 again | No future repetitions beyond already-queued pair | NOT VERIFIED |
| Numeric keys / Enter | Run physical sample sequence in remote text document | `15`, newline, `10`, final newline, correct order | NOT VERIFIED |
| Per-key timing | Test 60 ms, then 100–200 ms if needed | No dropped/merged input | NOT VERIFIED |
| Unicode alternative | Test `15`, then non-ASCII text using Unicode mode | Record accepted, partial, or rejected honestly | NOT VERIFIED |
| Shortcut | Invoke ⌘Up with remote window focused | Sequence once; no autorepeat overlap | NOT VERIFIED |
| Alternative shortcut | Try ⌃⌥F9 / ⌃⌥F8 | Registration and delivery both verified | NOT VERIFIED |
| Focus loss | Switch to local app during clicks, text, and long wait | Stop immediately; no input in new app | NOT VERIFIED |
| Allowed-to-allowed switch | Switch to another allowed application | Original run stops; requires new activation | NOT VERIFIED |
| Emergency stop | ⌘⇧Escape during click, text, and 60-second wait | Both engines stop; no stranded modifiers/buttons | NOT VERIFIED |
| Window closed | Close configuration; use hotkeys and menu Stop All | App remains in menu; shortcuts work | NOT VERIFIED |
| Session lock/disconnect | Lock/sleep; separately disconnect remote session | Local lock/sleep stops. Record client-specific disconnect behavior | NOT VERIFIED |

Citrix can handle physical and Unicode events differently by client version, desktop vs published-app mode, layout synchronization, input capture, and administrator policy. Synthetic events may be rejected. Registration success does not guarantee delivery through Citrix. A Citrix error/disconnect screen inside the same viewer process is not distinguishable from a remote app by this application-level focus guard. Do not depend on it to detect remote disconnects or a switch between windows owned by the same viewer.

No code injection, binary modification, TCC modification, or enterprise policy bypass is part of this app or checklist.
