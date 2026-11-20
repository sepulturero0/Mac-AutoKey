import Foundation
import Darwin

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let report = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
let physical = report["mode"] as? String == "human physical hotkey integration"
let imageOnly = report["mode"] as? String == "image condition integration"
let cropOnly = report["mode"] as? String == "screen crop integration"
let required = cropOnly ? ["finished", "screenCropSavedPassed", "screenCropMatchesPassed", "screenCropCancelPreservedPassed", "screenCropDidNotClickPassed"] : imageOnly ? ["finished"] : physical
    ? ["physicalSequenceHotkeyPassed", "physicalClickTogglePassed", "physicalEmergencyPassed", "backgroundWithWindowClosedPassed", "finished"]
    : ["clickPauseResumePassed", "keyboardPauseResumePassed", "pausedResumeRejectsWrongTargetPassed", "stopWhilePausedPassed", "independentCommandHotkeyPassed", "manualStartRestoresTargetPassed", "sameTargetNotificationContinuesPassed", "syntheticSequenceHotkeyActivated", "syntheticClickHotkeyActivated", "syntheticToggleStopped", "syntheticEmergencyStopped", "physicalSamplePassed", "commonKeysPassed", "unicodePassed", "clickTimingPassed", "clicksStopped", "realFocusLossStopped", "delayCancellationPassed", "typingCancellationPassed", "backgroundAfterWindowClosePassed", "finished"]
let imageChecks = report["imageConditionIncluded"] as? Bool == true ? ["imageInitiallyWaitsPassed", "imageAppearsStartsPassed", "imageDisappearsStopsPassed", "imageReturnsResumesPassed", "imageCannotOverridePausePassed", "imageManualResumePassed", "imageCannotOverrideStopPassed"] : []
let delayChecks = report["imageDelayIncluded"] as? Bool == true ? ["imageDelayBlocksEarlyClickPassed", "imageDelayDisappearanceCancelsPassed", "imageDelayRestartsPassed"] : []
let checks = (physical || imageOnly || cropOnly ? required : required + ["statusButtonPassed"]) + imageChecks + delayChecks
let failures = checks.filter { report[$0] as? Bool != true }
let fixedRequired = physical || imageOnly || cropOnly ? [] : ["fixedPositionCapturePassed", "fixedPositionClickPassed", "fixedPositionPointerUnmovedPassed", "fixedPositionPauseStopPassed", "fixedPositionWrongTargetBlockedPassed", "fixedPositionOffDisplayBlockedPassed"]
let fixedFailures = fixedRequired.filter { report[$0] as? Bool != true }
if let error = report["error"] as? String { print("Verification error: \(error)") }
if !failures.isEmpty || !fixedFailures.isEmpty || report["error"] != nil {
    print("Verification failed or incomplete: \((failures + fixedFailures).joined(separator: ", "))")
    exit(1)
}
print("PASS: \(checks.count + fixedRequired.count) live \(physical ? "physical-hotkey" : "local-input") checks. Citrix remains NOT VERIFIED.")
