---
name: siri-ai-eval
description: Use when writing, running or reading Siri Evaluations tests for a Siri AI tool (`@AppIntent(.tool)`), when asked to prove Siri calls an app's tool, or when a Siri evaluation pass rate looks wrong, flaky, or too good to trust. Also covers `siri-ai-eval summarize` output and `.xcresult` bundles from Siri evaluations.
license: MIT
---

# Siri evaluations with SiriAIEvalKit

## Overview

A Siri evaluation speaks a prompt to Siri on a real device and checks two things: which intents Siri called, and what Siri said. Siri varies between runs, so one pass proves little. A pass rate is only worth trusting when the checks can fail and you can see what the tool did in each run.

Requirements: iOS 27.3 on a physical iPhone (the frameworks don't ship for the Simulator), a UI test target linking `SiriAIEvalKit`, and the app showing `ToolOutcomeView()` in debug builds (see the siri-ai-tool skill). Without that view every run records "tool outcome missing".

Setup: add a UI Testing Bundle target (for example `ParcelPalEvals`) that targets the app, link `SiriAIEvalKit` to it, and give it a shared scheme. Sign the device in to a test account whose data you control, so the expected reply text is known.

## Write the test

```swift
import AppIntentsTesting
import SiriAIEvalKit
import SiriEvaluations
import Testing

private let bundleIdentifier = "com.example.parcelpal"
private let getOrderStatus = IntentDefinitions(bundleIdentifier: bundleIdentifier).intents["GetOrderStatusIntent"]
/// Only the live API returns this. It is never indexed in Spotlight, so hearing it proves the tool ran.
private let textOnlyTheAPIKnows = "Blue Kettle"
private let harness = SiriAppHarness(
    bundleIdentifier: bundleIdentifier,
    readyWhen: .labelBegins("auth-status", with: "Signed in")   // an element the app shows once it can call the API
)

private func orderScenario() -> SiriScenario {
    SiriScenario {
        UserTurn("In ParcelPal, where's my order?") {     // name the app in the prompt
            Calls { getOrderStatus }
            SiriResponse(.contains(textOnlyTheAPIKnows, caseSensitive: false))
        }
    }
}

@Test(.evaluates(ToolEvaluation(
    name: "Order status, repeated",
    harness: harness,
    dataset: .repeating(times: 5, orderScenario)
)))
func callsOrderStatusToolEveryTime() async throws {
    try expectAllPass(.intents, .siriResponse)
}
```

Rules:

- **Check both metrics.** `.intents` proves the tool was called; `.siriResponse` proves its answer reached the person.
- **Check for text only the API returns**, and confirm the app doesn't index it (`CSSearchableItem`, `IndexedEntity`). If it does, a passing reply proves nothing.
- **Repeat each scenario at least 5 times.** `.repeating(times:_:)` takes a closure that returns one `SiriScenario`. For another phrasing, write another scenario function and another `@Test`.
- **The ready signal must exist.** `readyWhen` waits up to 90 seconds for an accessibility element. Add one to the app (for example `Text("Signed in at …").accessibilityIdentifier("auth-status")`) if there isn't one.
- `before: .waitFor(.seconds(70))` delays each run, for example until an access token expires, to exercise refresh.

## Prove the checks can fail (negative control)

Break the tool, not the expectation. Make a temporary, uncommitted change so the tool can't produce the answer (turn off token refresh, point it at a bad host, or sign out before the run), run the same test once, and confirm the reply check fails and the recorded outcome shows the failure ("signed out", "unreachable"). An expectation for an impossible string only proves string matching works. Revert the change afterwards.

## Run on the device

The phone must be unlocked, on power and quiet (Siri speaks each reply), with Siri AI on, Developer Mode on and Settings > Developer > Enable UI Automation on.

```bash
xcodebuild test -project ParcelPal.xcodeproj -scheme ParcelPalEvals \
  -destination 'id=<device UDID>' -allowProvisioningUpdates DEVELOPMENT_TEAM=<team ID> \
  -only-testing:'ParcelPalEvals/callsOrderStatusToolEveryTime()' -resultBundlePath order.xcresult
swift run --package-path <path to siri-ai-kit checkout> siri-ai-eval summarize order.xcresult --fail-on real
```

Find the device UDID with `xcrun devicectl list devices`. A result bundle path that already exists makes `xcodebuild` fail; use a new name per run.

## Read the summary

| Output | Meaning |
|---|---|
| "the run ended before all of its results arrived" | The harness cut the run short. Not a tool failure. |
| Apple pass rate | Xcode's number; counts cut-short runs as failures. |
| Real pass rate | Leaves cut-short runs out. Report this one, with the run count ("4 of 4"). |
| "answered without calling the tool" | Reply passed but the tool wasn't called: Siri answered from the Spotlight index. Remove the answer from the index. |
| Outcome "succeeded (refreshed after 401)" | What the tool recorded via `ToolOutcomeLog`. "tool outcome missing" means no `ToolOutcomeView` on screen. |

Exit codes: 0 all passed; 1 a run failed (`--fail-on real` ignores cut-short runs); 2 no evaluations or unreadable bundle, which is never a pass; 64 bad usage. Add `--json` for machine-readable output.

## Common mistakes

| Mistake | Fix |
|---|---|
| Two `SiriScenario`s inside one `.repeating` closure | One scenario per closure; one `@Test` per phrasing |
| Reply check on text the app also indexes | Check text only the live API returns |
| Negative control that expects an impossible string | Break the tool temporarily and watch the reply check fail |
| Reporting Xcode's pass rate alone | Report the real pass rate and how many runs were cut short |
| Running on the Simulator | Physical device only |
