# SiriAIKit

Swift helpers for apps that adopt Apple's Siri AI Developer Preview (iOS 27.3 beta):

- **`SiriAIKit`:** code that runs inside your Siri tools. Token storage that works on a locked phone, one-time refresh of expired tokens, an HTTP client with a short timeout, and errors Siri can speak.
- **`SiriAIEvalKit`:** less setup for Siri Evaluations tests. It launches your app, waits until it's ready, runs a scenario several times, and records what your tool did in each run.
- **`siri-ai-eval`:** a command-line tool that summarizes evaluation results and separates runs the harness cut short from real failures.

SiriAIKit is not affiliated with or endorsed by Apple.

## Requirements

- Xcode 27.3 beta, Swift 6.
- `SiriAIKit`: iOS 17 or later.
- `SiriAIEvalKit`: iOS 27.3 on a device. Apple's evaluation frameworks don't ship for the Simulator.
- `siri-ai-eval`: macOS 15 or later.

Add the package in Xcode, or in `Package.swift`:

```swift
.package(path: "../siri-ai-kit")
```

Link `SiriAIKit` to your app target and `SiriAIEvalKit` to your UI test target.

## Calling your API from a tool

```swift
import SiriAIKit

enum API {
  static let store = KeychainTokenStore(service: "com.example.myapp.auth")
  static let auth = TokenAuthenticator(store: store) { tokens in
    try await refreshTokens(tokens)   // your refresh call
  }
  static let client = ToolHTTPClient(baseURL: URL(string: "https://api.example.com")!, auth: auth)
}

@AppIntent(.tool)
struct GetCartIntent: AppIntent {
  static let title: LocalizedStringResource = "Get Cart"

  func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
    let answer: String
    do {
      answer = describe(try await API.client.get("carts/1", as: Cart.self))
    } catch {
      answer = error.reply(appName: "My App")
    }
    return .result(value: answer, dialog: "\(answer)")
  }
}
```

What the client does:

- **Sends the saved access token.** With no tokens saved, it sends no request and throws `.signedOut`.
- **Refreshes when the API says the token expired** (401 by default; set `expiredStatuses` for APIs that use 403). It refreshes at most once, saves the new tokens and retries. If several calls fail at the same moment, they share that one refresh.
- **Never loops.** If the refresh fails, saving fails, or the retry is rejected again, the call throws `.signedOut`.
- **Times out after 10 seconds**, because Siri waits for `perform()`. A cancelled call counts as timed out.

`error.reply(appName:)` turns each failure into a sentence Siri says:

| Error | Reply |
|---|---|
| `.signedOut` | "Open My App to sign in again." |
| `.timedOut`, `.unreachable` | "Couldn't reach My App right now." |
| `.rejected`, `.invalidResponse` | "My App couldn't do that right now." |

Pass `overrides: ToolReplies` to use your own wording.

`ToolError` also has a `.keychain(OSStatus)` case, which isn't in the original design. Custom `TokenStore`s throw it when the Keychain fails, and the client turns it into `.signedOut` before your tool sees it.

### Locked phones

Siri can run your tool while the phone is locked. `KeychainTokenStore` defaults to `.afterFirstUnlockThisDeviceOnly`, so tokens can be read once the phone has been unlocked after a restart. Stores that only allow reading while the phone is unlocked fail on a locked phone.

### Showing what the tool did

`ToolHTTPClient` records each call's outcome: "used saved token", "refreshed after 401" or "signed out". Add `ToolOutcomeView()` (debug builds only) to your app so evaluations can read it. If you build your own view, show `ToolOutcomeLog.label()` with the accessibility identifier `ToolOutcomeLog.accessibilityIdentifier`.

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

It prints each run's tool calls, reply, reply check, recorded outcome, and whether the run was cut short ("the run ended before all of its results arrived"). It prints two pass rates:

- **Apple pass rate:** Xcode's number, which counts runs that were cut short as failures.
- **Real pass rate:** runs that were cut short are left out.

**Exit codes:**
- 0: everything passed.
- 1: a run failed. With `--fail-on any` (the default), that includes runs that were cut short; with `--fail-on real`, only complete runs count.
- 2: the result bundle has no evaluations or can't be read.
- 64: bad usage.

The [example app](Example/) shows all of this working against a real API.

## Verified on a device

Run on Nov 10, 2026 on an iPhone 16 Pro on iOS 27.3 beta, with Xcode 27.3 beta (27C5020n), using the example app:

| Evaluation | Runs | Apple pass rate | Real pass rate | Recorded outcomes |
|---|---|---|---|---|
| Cart from the demo API | 5 | 100% | 100% (5 of 5) | "used saved token" in all 5 |
| Cart after the one-minute token expires | 5 | 100% | 100% (5 of 5) | "refreshed after 401" in all 5 |
| Negative control: refresh turned off | 1 | 0% | 0% (0 of 1) | "signed out"; Siri said "Open SiriAIKit Example to sign in again." |

The negative control is a temporary edit (`DemoAPI.refreshEnabled = false`) and isn't committed. It shows the reply check can fail.

## Development

```bash
swift test                     # SiriAIKit and summary tests, on the Mac
xcodebuild build -scheme SiriAIEvalKit -destination 'generic/platform=iOS'
```

The `SiriAIKit` tests run on the Mac rather than the Simulator. The Simulator's test runner has no Keychain entitlement, and booting the iOS 27.3 beta Simulator crash-looped its `identityservicesd`. The Keychain's accessibility setting is checked through the attributes the store passes to `SecItemAdd`, and on a device through the example app.

## License

[MIT](LICENSE)
