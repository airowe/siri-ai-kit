# Feedback Assistant drafts: Siri on the Simulator

These are two separate bugs, written to paste into Feedback Assistant (feedbackassistant.apple.com). Both were seen on 2026-11-11. See `simulator-siri.md` for how they were found.

**Filed on 2026-11-11:**

| Report | Filed (with sysdiagnose and simctl diagnose) | Earlier filing of the same bug |
|---|---|---|
| 1. Siri `LostMyriadElection` | FB25534613 | FB25532615 |
| 2. `identityservicesd` crash-loop | FB25534616 | FB25532666 |

Attach a Simulator diagnose to each report: `xcrun simctl diagnose`, run right after reproducing the bug. It collects logs for every booted device, so boot only the Simulator you are reporting on.

---

## 1. Siri can't be activated on the iOS 27 Simulator: Myriad loses an election with 0 replies, and Siri dismisses itself

**Area:** Simulator, or Siri > Activation.
**Type:** Incorrect/Unexpected Behavior.

**Title:** iOS 27.2/27.3 Simulator: Siri dismisses immediately with LostMyriadElection, so XCUISiriService and the Siri button do nothing

**Environment**
- Xcode 27.3 beta (27C5020n), macOS 27.0.1 (26A434), Apple silicon.
- Fails on iOS 27.3 (24C5037i) and on iOS 27.2 (24B8117) Simulator runtimes. Tested on new iPhone 18 Pro and iPhone 17 Pro devices, not signed in to an Apple Account.
- Siri is on. Settings > Siri shows "Turn Off Siri", and `com.apple.assistant.backedup` reports `SiriAvailability.isAvailable = 1` with no unavailability reasons.

**Steps to reproduce**
1. Create and boot a new iOS 27.3 Simulator.
2. Long-press the Siri button (Device > Siri, or `simctl io` / Simulator hardware button).
3. Or, from a UI test, call `XCUIDevice.shared.siriService.activate(voiceRecognitionText: "What time is it?")`.

**Expected:** Siri's UI appears and handles the request. From a UI test, the request reaches the app's App Intent tool.

**Actual:** No Siri UI appears. `XCUISiriService` queries then time out with "Failed to resolve query: Timed out while evaluating UI query", and the app's intent never runs.

**What the logs show** (SpringBoard, subsystem `com.apple.siri`, one button press on 27.2):

```
SASMyriadController activateForRequest:withTimeout:visible:idleAndQuiet: #myriad BTLE Myriad direct trigger advertising needed
SCDA:Entry  startAdvertisingFromDirectTriggerWithContext: (null)
SASPresentationManager … transitioning from SASRequestStateOff to SASRequestStateStarting
SCDACoordinator _enterState: canceling advertising with nil trigger record, this likely means Siri UI was already dismissed … MyriadRecord: hash=0XFFFF,good=255,conf=255 … isMe=TRUE
SCDACoordinator _loseElection BTLE notify myriad loss, identity (null)
SCDACoordinator _endAdvertisingAnalyticsContext: Myriad decision is based on 0 replies
SASMyriadController scdaShouldAbortAnotherDeviceBetter:
SiriActivationService scdaShouldAbort: #myriad SCDA should abort session
SiriPresentationViewController … dismissal reason: LostMyriadElection
SASPresentationManager … transitioning from SASRequestStateStarting to SASRequestStateStopping
SASPresentationManager … transitioning from SASRequestStateStopping to SASRequestStateOff
SiriPresentationViewController setPresentationState: … from Presenting to Presented
SASPresentationManager … can't transition to state: SASRequestStateActive from state: SASRequestStateOff
SiriActivationService presentationManager:didEncounterError: #activation error: SASPresentationManagerErrorInvalidStateTransition
```

Through `XCUISiriService`, the same sequence follows `testmanagerd: Starting Siri UI request with text: …`. After it, testmanagerd logs `-[AFSettingsConnection startUIRequestWithText:] settingsService got error: Error Domain=NSCocoaErrorDomain Code=4099 "The connection to service … named com.apple.assistant.settings was invalidated"`.

**Analysis**
- A direct (button or text) activation starts Myriad BTLE arbitration with a **nil context**: `startAdvertisingFromDirectTriggerWithContext: (null)`.
- SCDA treats the missing trigger record as "UI already dismissed". It cancels advertising and calls `_loseElection` with **0 replies**, so the Simulator loses to no other device and Siri aborts with `LostMyriadElection`.
- The Siri view controller then finishes presenting after the request state is already Off, which produces `SASPresentationManagerErrorInvalidStateTransition`.
- The Simulator has no BTLE peers, so Myriad should be skipped there. Failing that, a direct trigger with no competing replies should count as a win, not a loss.

**Workarounds tried that didn't help**
- Setting `Allow Myriad Coordination = NO` and `Disable Myriad BLE Activity = YES` in `com.apple.assistant.support`, `com.apple.assistant.myriad` and `com.apple.assistant.backedup`, then rebooting. The same sequence still runs.
- Launching `com.apple.siri` directly. The app opens to a black screen.

**Impact:** Siri, and so App Intent tools invoked through Siri (`@AppIntent(.tool)`), can't be tested on the Simulator. Every Siri AI tool test needs a physical device.

**Ask:** Make Siri activation work on the Simulator by skipping Myriad arbitration there or treating it as a local win. Alternatively, provide a supported default that turns arbitration off for testing.

---

## 2. iOS 27.3 Simulator: `identityservicesd` crash-loops in `XPCPeerRequirement.hasEntitlement`

**Area:** Simulator.
**Type:** Crash/Hang/Data Loss.

**Title:** iOS 27.3 Simulator: identityservicesd traps in XPCPeerRequirement.hasEntitlement (XPC API misuse) and launchd restarts it every ~10 s

**Environment:** Xcode 27.3 beta (27C5020n), macOS 27.0.1 (26A434), iOS 27.3 Simulator runtime (24C5037i). **The iOS 27.2 runtime (24B8117) doesn't crash** on the same host; identityservicesd stays up there.

**Steps to reproduce**
1. Create and boot a new iOS 27.3 Simulator.
2. Watch `~/Library/Logs/DiagnosticReports/identityservicesd-*.ips` fill up, or run `xcrun simctl spawn booted launchctl list | grep identityservicesd`, which shows last exit `-5`.

**Expected:** identityservicesd starts and stays running, as it does on the 27.2 runtime.

**Actual:** It crashes about every 10 s for as long as the device is booted: 25 reports in 12 minutes on one device. The same crash appears on every 27.3 Simulator on this host.

**Crash** (`parentProc: launchd_sim`; both images are from the 27.3 runtime):

```
Exception Type: EXC_BREAKPOINT (SIGTRAP), Trace/BPT trap: 5
0 libswiftCore.dylib  _assertionFailure(_:_:file:line:flags:)
1 libswiftXPC.dylib   __XPC_INTERNAL_CRASH__(_:file:line:)
2 libswiftXPC.dylib   __XPC_API_MISUSE__(_:file:line:)
3 libswiftXPC.dylib   static XPCPeerRequirement.hasEntitlement(_:)
4 identityservicesd   (+7078256)
5 identityservicesd   (+7059521)
6 identityservicesd   (+3880181)
7 identityservicesd   (+4177413)
… libswift_Concurrency.dylib completeTaskWithClosure
identityservicesd UUID 0915c4fe-50dd-37de-8efc-3e1a7b061664
libswiftXPC.dylib UUID 9701f215-5150-3f1b-a77d-44b8f8b86c1b (XPC_swiftoverlay_Sim, PeerRequirement.swift)
```

**Analysis:** identityservicesd builds an `XPCPeerRequirement.hasEntitlement(_:)` requirement at startup. The Simulator build of the XPC Swift overlay rejects it as API misuse and traps. So either the overlay doesn't support entitlement requirements on the Simulator, or identityservicesd passes an argument the overlay rejects. Either way, a 27.3 Simulator never has a working identityservicesd. That breaks IDS-backed features: iMessage/FaceTime identity, device-to-device features, and likely Continuity-dependent Siri paths.

**Not the cause of report 1:** Siri fails the same way on the 27.2 runtime, where identityservicesd runs normally.

**Attach:** one `identityservicesd-*.ips` from `~/Library/Logs/DiagnosticReports` and the `xcrun simctl diagnose` archive.
