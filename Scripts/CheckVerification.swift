import Foundation
import Darwin

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let report = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
let physical = report["mode"] as? String == "human physical hotkey integration"
let required = physical
    ? ["physicalSequenceHotkeyPassed", "physicalClickTogglePassed", "physicalEmergencyPassed", "backgroundWithWindowClosedPassed", "finished"]
    : ["clickPauseResumePassed", "keyboardPauseResumePassed", "pausedResumeRejectsWrongTargetPassed", "stopWhilePausedPassed", "independentCommandHotkeyPassed", "manualStartRestoresTargetPassed", "sameTargetNotificationContinuesPassed", "syntheticSequenceHotkeyActivated", "syntheticClickHotkeyActivated", "syntheticToggleStopped", "syntheticEmergencyStopped", "physicalSamplePassed", "commonKeysPassed", "unicodePassed", "clickTimingPassed", "clicksStopped", "realFocusLossStopped", "delayCancellationPassed", "typingCancellationPassed", "backgroundAfterWindowClosePassed", "finished"]
let failures = required.filter { report[$0] as? Bool != true }
let fixedRequired = physical ? [] : ["fixedPositionCapturePassed", "fixedPositionClickPassed", "fixedPositionPointerUnmovedPassed", "fixedPositionPauseStopPassed", "fixedPositionWrongTargetBlockedPassed", "fixedPositionOffDisplayBlockedPassed"]
let fixedFailures = fixedRequired.filter { report[$0] as? Bool != true }
if let error = report["error"] as? String { print("Verification error: \(error)") }
if !failures.isEmpty || !fixedFailures.isEmpty || report["error"] != nil {
    print("Verification failed or incomplete: \((failures + fixedFailures).joined(separator: ", "))")
    exit(1)
}
print("PASS: \(required.count + fixedRequired.count) live \(physical ? "physical-hotkey" : "local-input") checks. Citrix remains NOT VERIFIED.")
