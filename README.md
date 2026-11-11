# SiriAIKit

Swift helpers for apps that adopt Apple's Siri AI Developer Preview (iOS 27.3 beta). Keep your own networking and auth. SiriAIKit adds what Siri needs on top:

- **`SiriAIKit`:** wraps the API code you already have in a Siri tool. It keeps to Siri's time budget, turns failures into sentences Siri can say, and records what each call did. It also includes a debug check that catches tokens Siri can't read on a locked phone.
- **`SiriAIEvalKit`:** less setup for Siri Evaluations tests. It launches your app, waits until it's ready, runs a scenario several times, and records what your tool did in each run.
- **`siri-ai-eval`:** a command-line tool that summarizes evaluation results and separates runs that were cut short from real failures.

SiriAIKit is not affiliated with or endorsed by Apple.

## Requirements

- Xcode 27.3 beta, Swift 6.
- `SiriAIKit`: iOS 17 or later.
- `SiriAIEvalKit`: iOS 27.3 on a device. Apple's evaluation frameworks don't ship for the Simulator.
- `siri-ai-eval`: macOS 15 or later.

Add `https://github.com/airowe/siri-ai-kit` in Xcode (File > Add Package Dependencies), or in `Package.swift`:

```swift
.package(url: "https://github.com/airowe/siri-ai-kit", from: "0.2.0")
```

Until 1.0, minor versions may change the API, since Apple's Siri AI APIs are still in beta. Pin with `.upToNextMinor(from: "0.2.0")` if you need stability.

Link `SiriAIKit` to your app target and `SiriAIEvalKit` to your UI test target.

**Expo apps:** the [`expo-siri-ai-kit`](expo-plugin/) config plugin adds SiriAIKit to your app target during prebuild, so Swift tools in `app-intents/` can import it.

## Wrapping your API code in a tool

```swift
import SiriAIKit

private let tool = SiriTool(appName: "My App") { error in
    (error as? MyAPIError) == .unauthorized ? .signedOut : nil
}

@AppIntent(.tool)
struct GetCartIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Cart"

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let answer = await tool.answer { describe(try await MyAPI.shared.cart()) }
        return .result(value: answer, dialog: "\(answer)")
    }
}
```

`answer` returns your string, or the sentence Siri should say instead. Use `run` when you need the value itself. It throws a `ToolFailure`, and `failure.reply(appName:)` gives the sentence.

**How failures are classified:**
1. The `classify` closure you pass. Return `nil` to fall through to the rules below.
2. A `ToolFailure` you throw yourself.
3. `CancellationError`, `URLError.timedOut` or `URLError.cancelled`: `.timedOut`.
4. Any other `URLError`: `.unreachable`.
5. Anything else: `.failed`.

If your networking library wraps `URLError` in its own error type, unwrap it in `classify`. Otherwise those failures count as `.failed`.

| Failure | What Siri says |
|---|---|
| `.signedOut` | "Open My App to sign in again." |
| `.timedOut`, `.unreachable` | "Couldn't reach My App right now." |
| `.failed` | "My App couldn't do that right now." |

Pass `replies: ToolReplies` to use your own wording.

**Time budget:**
- Siri waits for `perform()`, so `SiriTool` gives up after 10 seconds by default (`timeout:`), or as soon as Siri cancels the call, and reports `.timedOut`.
- It stops waiting but doesn't cancel your code, so work like saving refreshed tokens still finishes. Your code may keep running briefly after Siri has moved on.

### Showing what the tool did

`SiriTool` records each call's outcome: "succeeded", "signed out", "timed out", "unreachable" or "failed". Add details from your own code with `ToolOutcomeLog.standard.note("refreshed after 401")`. They appear with the outcome, as in "succeeded (refreshed after 401)". A note belongs to the `SiriTool` call whose code made it. Notes made outside a call, or after a call has timed out, are dropped.

Add `ToolOutcomeView()` (debug builds only) to your app so evaluations can read it. If you build your own view, show `ToolOutcomeLog.label()` with the accessibility identifier `ToolOutcomeLog.accessibilityIdentifier`.

### Checking tokens work on a locked phone

Siri can run your tool while the phone is locked. Keychain items saved with `WhenUnlocked` protection, the default in some secure-storage libraries, can't be read then. Call this at launch in debug builds:

```swift
#if DEBUG
KeychainLockCheck.warnIfLockedOut(service: "com.example.myapp.auth")
#endif
```

It logs a warning if the item isn't readable after first unlock, or if it can't be read at all. It stays silent when there's no item.

## Rules learned on a device

- **Answer within a few seconds.** Siri waits for your tool, and `SiriTool` enforces the budget.
- **Save tokens readable after first unlock** (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), or tools fail on a locked phone.
- **Refresh an expired token at most once per call, and never loop.**
  - Save the new tokens before using them.
  - Send every refresh in the app through one shared path that runs one refresh at a time. A Siri call that timed out may still be refreshing when the next one starts, and APIs that issue a new refresh token on every refresh reject the second use of the old one.
  - Only a rejected refresh (400, 401 or 403) means signed out. A server error or network failure isn't a reason to ask the person to sign in again, and neither is a Keychain read error.
  - [`Example/SiriAIKitExample/DemoAPI.swift`](Example/SiriAIKitExample/DemoAPI.swift) shows all of this.
- **Index what identifies a record (id, name, synonyms), never the answer the tool exists to give.** Otherwise Siri answers from the Spotlight index instead of calling your tool.

## Testing with Siri Evaluations

```swift
import AppIntentsTesting
import SiriAIEvalKit
import SiriEvaluations
import Testing

private let getCartIntent = IntentDefinitions(bundleIdentifier: "com.example.myapp").intents["GetCartIntent"]
private let harness = SiriAppHarness(
  bundleIdentifier: "com.example.myapp",
  readyWhen: .labelBegins("auth-status", with: "Signed in")
)

@Test(.evaluates(ToolEvaluation(
  name: "Cart, repeated",
  harness: harness,
  dataset: .repeating(times: 5) {
    SiriScenario {
      UserTurn("In My App, what's in my cart?") {
        Calls { getCartIntent }
        SiriResponse(.contains("motorcycle", caseSensitive: false))
      }
    }
  }
)))
func callsCartToolEveryTime() async throws {
  try expectAllPass(.intents, .siriResponse)
}
```

Before each run, `ToolEvaluation` launches the app and waits for the ready signal, up to 90 seconds. It then applies `before:` (for example, `.waitFor(.seconds(70))` so a token expires), runs the scenario, and saves the tool's outcome as an attachment named `siri-ai-eval-outcome`.

Summarize the results:

```bash
swift run siri-ai-eval summarize cart.xcresult [--json] [--fail-on any|real]
```

It prints each run's tool calls, reply, intents check, reply check, recorded outcome, and whether the run was cut short ("the run ended before all of its results arrived").

It also flags complete runs where the reply check passed but an expected tool wasn't called: "answered without calling the tool". Siri most likely answered from what your app indexed in Spotlight, so your tool's code never ran. Index only what identifies a record.

It prints two pass rates:

- **Apple pass rate:** Xcode's number, which counts runs that were cut short as failures.
- **Real pass rate:** runs that were cut short are left out.

**Exit codes:**
- 0: everything passed.
- 1: a run failed. With `--fail-on any` (the default), that includes runs that were cut short; with `--fail-on real`, only complete runs count.
- 2: the result bundle has no evaluations or can't be read.
- 64: bad usage.

The [example app](Example/) shows all of this working against a real API.

## Verified on a device

Run on Nov 11, 2026 on an iPhone 16 Pro on iOS 27.3 beta, with Xcode 27.3 beta (27C5020n), using the example app at 0.2.0:

| Evaluation | Runs | Apple pass rate | Real pass rate | Recorded outcomes |
|---|---|---|---|---|
| Cart from the demo API | 5 | 100% | 100% (5 of 5) | "succeeded" in all 5 |
| Cart after the one-minute token expires | 5 | 80% | 100% (4 of 4) | "succeeded (refreshed after 401)" in all 5 |
| Negative control: refresh turned off | 1 | 0% | 0% (0 of 1) | "signed out"; Siri said "Open SiriAIKit Example to sign in again." |

In the expired-token evaluation, the harness cut run 5 short before its results arrived. Siri still gave the right answer, and the tool recorded a refresh. Xcode counts that run as a failure; `siri-ai-eval` leaves it out of the real pass rate.

The negative control is a temporary edit (`DemoAPI.refreshEnabled = false`) and isn't committed. It shows the reply check can fail.

## Upgrading from 0.1.0

0.2.0 removes SiriAIKit's built-in auth. Your app's own networking and token storage handle that now.

- **`ToolHTTPClient`, `TokenAuthenticator`, `HTTPMethod`:** wrap your existing API call with `SiriTool.answer` or `SiriTool.run`.
- **`KeychainTokenStore`, `TokenStore`, `Tokens`, `KeychainAccessibility`:** keep tokens in your own store, saved with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, and check it with `KeychainLockCheck`.
- **`ToolError`:** replaced by `ToolFailure`. `.rejected` and `.invalidResponse` became `.failed`, and `.keychain` is gone.
- **Outcomes:** "used saved token" and "refreshed after 401" are no longer recorded automatically. Use `ToolOutcomeLog.standard.note(_:)` from your code.

## Development

```bash
swift test                     # SiriAIKit and summary tests, on the Mac
xcodebuild build -scheme SiriAIEvalKit -destination 'generic/platform=iOS'
```

The tests run on the Mac rather than the Simulator, because booting the iOS 27.3 beta Simulator crash-looped its `identityservicesd`. `KeychainLockCheck`'s decisions are unit tested. Its Keychain lookup is checked on a device through the example app.

## License

[MIT](LICENSE)
