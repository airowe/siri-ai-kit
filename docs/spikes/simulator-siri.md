# Spike: can a Siri AI tool be triggered and checked on the Simulator?

**Question.** Can an agent ask Siri to run one of our tools, and then confirm the tool ran, on the iOS 27.3 beta Simulator without a physical iPhone? If it can, an agent-device `siri` command (callstack/agent-device) could drive Siri tool tests on the Simulator.

**Answer: no, not on this beta.** Siri accepts the text request, then fails to show its UI, and the tool never runs. The root cause is an Apple bug: on the Simulator, Siri's Myriad device arbitration loses an election with 0 replies, and Siri then dismisses itself (see "Follow-up" below and `simulator-siri-feedback.md`). Two parts of the setup do work on the Simulator, though. `AppIntentsTesting` runs the tool directly, without Siri, and the `Evaluations` types work. So the useful Simulator command today is "run this tool", not "ask Siri".

Run on 2026-11-11.

## Setup

| | |
|---|---|
| Host | macOS 27.0.1 (26A434), Apple silicon |
| Xcode | 27.3 beta (27C5020n) |
| Runtime | iOS 27.3 (24C5037i) |
| Device | A new iPhone 18 Pro Simulator made for this spike (`SiriSpike-27.3`), never signed in to an Apple Account |
| App | `Example/SiriAIKitExample` with its `GetCartIntent` tool, built from a throwaway project in `Example/spikes/simulator-siri/` |

The spike project exists because the real evals target imports `SiriEvaluations`, which isn't in the Simulator SDK, so it can't build for the Simulator. Regenerate the spike project with `ruby Example/spikes/simulator-siri/generate-project.rb`, then run:

```bash
xcodebuild test -project Example/spikes/simulator-siri/SimulatorSiriSpike.xcodeproj \
  -scheme SimulatorSiriSpikeTests -destination 'id=<simulator UDID>'
```

## Results

### 1. Boot: `identityservicesd` still crash-loops, but boot finishes

`simctl bootstatus -b` finished in 40 s, including a 31 s data migration. `identityservicesd` inside the Simulator crashes again and again. There were 25 crash reports in the first ~12 minutes, and launchd retries roughly every 10 s. `launchctl list` shows its last exit as `-5`.

```
EXC_BREAKPOINT (SIGTRAP), "Trace/BPT trap: 5"
libswiftCore      _assertionFailure(_:_:file:line:flags:)
libswiftXPC       __XPC_INTERNAL_CRASH__(_:file:line:)
libswiftXPC       __XPC_API_MISUSE__(_:file:line:)
libswiftXPC       static XPCPeerRequirement.hasEntitlement(_:)
identityservicesd ...
parentProc: launchd_sim, coalition com.apple.CoreSimulator.SimDevice.<UDID>
```

It's an XPC entitlement-check assertion in the runtime's own daemon, so it's an Apple bug. It doesn't block booting, Settings, app installs, UI tests or networking from the app. I found no workaround and didn't need one for anything except Siri, and nothing shows that it causes the Siri failure below.

### 2. Siri is on and backed by Apple Intelligence, out of the box

Settings > Siri shows **Turn Off Siri**, so Siri is on. The pane's footer says Siri "uses Apple Intelligence to find information and take action across your apps". It also offers a ChatGPT extension (Set Up). `com.apple.assistant.backedup` reports `SiriAvailability.isAvailable = 1`, `unavailabilityReasons = 0`, `restrictionReasons = 0`, `linwoodEverAvailable = 0`. Nothing needed turning on.

### 3. `XCUISiriService`: the request is sent, Siri fails to present, and the tool doesn't run

I checked the real API in the 27.3 SDK headers (`XCUIAutomation.framework/Headers/XCUISiriService.h` plus its apinotes) before writing the test. There is no `XCUISiriService.shared`; `init` is unavailable with the message "Access XCUISiriService through the siriService property on XCUIDevice." The call is:

```swift
XCUIDevice.shared.siriService.activate(voiceRecognitionText: "In SiriAIKit Example, what's in my cart?")
```

It exists in both the Simulator and device SDKs.

The test is in `Example/spikes/simulator-siri/SimulatorSiriSpikeTests/SiriOnSimulatorTests.swift`. It:

1. launches the app and waits for "Signed in" (this worked against the live DummyJSON API);
2. reads the `siri-ai-tool-outcome` label;
3. calls `activate(voiceRecognitionText:)`;
4. takes a screenshot every 5 s for 60 s;
5. brings the app forward and checks that the label changed and now begins with "succeeded".

It failed both times I ran it.

- **Run 1.** The before label was `Last tool call: none`. XCTest logged `Activate Siri with voice recognition text: …`, then `Wait for com.apple.siri to idle`. Querying `siriService.staticTexts` then failed after ~90 s with `Failed to resolve query: Timed out while evaluating UI query.` The screenshot taken 9 s after activation shows only the app; no Siri UI.
- **Run 2** (screenshots only). The label was `Last tool call: succeeded at 11:40:35 AM`, left by the `AppIntentsTesting` probe that ran just before. It still had the same timestamp after Siri. The assertion failed with: `XCTAssertNotEqual failed: ("Last tool call: succeeded at 11:40:35 AM") is equal to ("Last tool call: succeeded at 11:40:35 AM") - the tool never ran`. None of the 12 screenshots show any Siri UI; they differ only in the clock.

The timestamp is the negative control. The label records each real tool run with the time, and the same check passes when the probe runs the tool. So it can tell a run happened, and here none did.

The Simulator's unified log shows where the request dies:

```
testmanagerd  Starting Siri UI request with text: In SiriAIKit Example, what's in my cart?
testmanagerd  -[AFSettingsConnection startUIRequestWithText:]_block_invoke settingsService got error:
              Error Domain=NSCocoaErrorDomain Code=4099 "The connection to service with pid … named
              com.apple.assistant.settings was invalidated …"
assistantd    Background Connection - Reader: Error. SiriNetwork.NetworkConnectionError.readFailure(nil)
assistantd    … Callback to Completion with error SiriNetwork.NetworkConnectionError.fallbackNotAvailable
assistantd    -[ADSessionRemoteServer _sendServerCommand:] Error sending command SASyncGetAnchors … SiriNetwork.NetworkConn…
SpringBoard   -[SiriPresentationViewController siriViewController] #activation Attempting to use siriViewController, but one does not exist
SpringBoard   -[SiriActivationService presentationManager:didEncounterError:] #activation error: SASPresentationManagerErrorInvalidStateTransition
SpringBoard   -[SiriPresentationViewController _presentationDismissalRequestedWithOptions:withCompletion:] #activation dismissal reason: PresentationManagerError
SpringBoard   -[AFUISiriSession _connection] The AFConnection for this session … has been invalidated.
```

To rule out a problem in `XCUISiriService` itself, I pressed the Simulator's hardware Siri button (long press). Siri failed in the same way, with `siriViewController … does not exist` followed by `SASPresentationManagerErrorInvalidStateTransition`, and nothing appeared on screen. So Siri's own presentation is broken on this runtime, and the XCTest hook has nothing to work with. The app's own HTTPS calls succeed from the same Simulator; only Siri's server connection (`SiriNetwork`) fails.

**Not tried:** signing the Simulator in to an Apple Account, which might be what Siri's server connection needs. Doing that would mean someone entering real Apple Account credentials, which an agent shouldn't do; a person could try it as a follow-up.

### 4. Which frameworks import and run on the Simulator

What the SDK ships: `iPhoneSimulator.platform/Developer/Library/Frameworks` has `AppIntentsTesting.framework` and `Evaluations.framework`, but no `SiriEvaluations.framework`; `iPhoneOS.platform` has `SiriEvaluations.framework`. The probe results are in `FrameworkProbeTests.swift`.

| Framework | `canImport` on Simulator | Works on Simulator? | Evidence |
|---|---|---|---|
| `AppIntentsTesting` | yes | **Yes, fully.** It ran the real tool against the live API. | `IntentDefinitions(bundleIdentifier: "com.example.siriaikit").intents["GetCartIntent"].makeIntent().run()` returned `Your cart has 4 products, $13,037.88: Blue Frock, Generic Motorcycle, iPhone 6, Baseball Ball.` It also updated the app's `siri-ai-tool-outcome` label to `succeeded at …`. Test passed in 12.4 s. |
| `Evaluations` | yes | **Yes, for the types.** I didn't run a model-backed evaluation. | `TrajectoryExpectation(expected: "GetCartIntent")` encoded to `{"disallowed":[],"allowsAdditionalCalls":true,"unordered":[{"name":"GetCartIntent","arguments":[]}],"ordered":[]}`. Test passed. |
| `SiriEvaluations` | **no** | No. It isn't in the Simulator SDK, so `SiriAIEvalKit`'s `#if canImport(SiriEvaluations)` code compiles out. | `SPIKE imports: ["AppIntentsTesting", "Evaluations"]` |

## Follow-up: root cause and workarounds tried

I compared against the iOS 27.2 runtime (24B8117) with the same Xcode, and both problems turned out to be Apple bugs, unrelated to each other. Draft reports for Feedback Assistant are in `simulator-siri-feedback.md`.

**Siri (27.2 and 27.3).** Siri fails the same way on 27.2, where `identityservicesd` is healthy, so the crash isn't the cause. The full SpringBoard sequence shows what happens:

1. A button press or `XCUISiriService` text request starts Myriad, the arbitration that decides which nearby device answers Siri. It starts with a nil context: `startAdvertisingFromDirectTriggerWithContext: (null)`.
2. `SCDACoordinator` sees a nil trigger record, assumes "Siri UI was already dismissed", and calls `_loseElection`; the log says "Myriad decision is based on 0 replies".
3. Siri aborts with `dismissal reason: LostMyriadElection`.
4. The view controller finishes presenting after the request state is already Off, which gives `SASPresentationManagerErrorInvalidStateTransition`.

In short, the Simulator loses a Bluetooth election against no other device.

**Workarounds tried, none of which fixed it:**
- Setting `Allow Myriad Coordination = NO` and `Disable Myriad BLE Activity = YES` in `com.apple.assistant.support`, `com.apple.assistant.myriad` and `com.apple.assistant.backedup`, then rebooting. I found these preference names in the runtime's shared cache, but SpringBoard still logs "BTLE Myriad direct trigger advertising needed" and loses.
- Launching the new Siri app (`com.apple.siri`) directly. It opens to a black screen.
- Not tried: signing in to an Apple Account, because it needs real credentials. It wouldn't change the Myriad path anyway: the election is lost locally before any server call.

I didn't try anything more invasive, such as patching or injecting into SpringBoard or overriding unknown feature flags. That would stop the Simulator from behaving like stock iOS, and it wouldn't be a sound base for tests.

**`identityservicesd` (27.3 only).** It traps in the 27.3 runtime's own `libswiftXPC` (`XPC_swiftoverlay_Sim/PeerRequirement.swift`): `XPCPeerRequirement.hasEntitlement(_:)` → `__XPC_API_MISUSE__`. The 27.2 runtime doesn't have this crash.

## Recommendation

**No to an agent-device `siri` command for the Simulator on iOS 27.3 beta (27C5020n / 24C5037i).** Siri can't present on the Simulator, by the test API or by the hardware button, so there is nothing to drive. And even if Siri started working, `SiriEvaluations` (the scored Siri runs `SiriAIEvalKit` wraps) isn't in the Simulator SDK. Siri tests still need a device.

**Worth building instead:** a Simulator command that runs a tool directly through `AppIntentsTesting` and then reads `siri-ai-tool-outcome`. It skips Siri's choice of tool and Siri's reply, but it does check the tool's own behaviour (auth, refresh, the API call, the recorded outcome) without a phone. It works today.

**Check again when:** a new Xcode beta or Simulator runtime ships, Apple's release notes say Siri works on the Simulator, or someone has signed a Simulator in to an Apple Account. The fast check is to long-press the Simulator's Siri button: if no Siri UI appears, the rest won't work.
