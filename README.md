# Syrup AI Kit

Syrup AI Kit: Siri AI tools for iOS, Expo and React Native apps. Formerly SiriAIKit.

Make your iOS, Expo or React Native app work with Siri AI, Apple's Siri AI Developer Preview (iOS 27.3 beta): people ask Siri about their orders, bookings or balances, or ask it to act, and Siri calls your app's tools.

Using a coding agent? Install the skills and ask it to "make my app work with Siri AI":

```
/plugin marketplace add airowe/syrup-ai-kit
/plugin install syrup-ai-kit@syrup-ai-kit
```

Other agents: `npx skills add airowe/syrup-ai-kit`. Expo apps also use the [`expo-syrup-ai-kit`](expo-plugin/) config plugin.

Keep your own networking. Syrup AI Kit adds what Siri needs on top:

- **`SyrupAIKit`:** wraps the API code you already have in a Siri tool. It keeps to Siri's time budget, turns failures into sentences Siri can say, and records what each call did.
- **`SyrupAIEvalKit`:** less setup for Siri Evaluations tests. It launches your app, waits until it's ready, runs a scenario several times, and records what your tool did in each run.
- **`siri-ai-eval`:** a command-line tool that summarizes evaluation results and separates runs that were cut short from real failures.

Syrup AI Kit is not affiliated with or endorsed by Apple.

## Requirements

Step-by-step setup for the Mac, the iPhone, native and Expo apps, and the agent skills, with a checklist for coding agents: [INSTALL.md](INSTALL.md).

- Xcode 27.3 beta, Swift 6.
- `SyrupAIKit`: iOS 17 or later.
- `SyrupAIEvalKit`: iOS 27.3 on a device. Apple's evaluation frameworks don't ship for the Simulator.
- `siri-ai-eval`: macOS 15 or later.

Add `https://github.com/airowe/syrup-ai-kit` in Xcode (File > Add Package Dependencies), or in `Package.swift`:

```swift
.package(url: "https://github.com/airowe/syrup-ai-kit", from: "0.3.0")
```

Until 1.0, minor versions may change the API, since Apple's Siri AI APIs are still in beta. Pin with `.upToNextMinor(from: "0.3.0")` if you need stability.

### Who can use your tools today

Apple's Siri AI Developer Preview limits who can try what you build. This is as of Apple's [announcement](https://developer.apple.com/news/?id=gdk2umrf) of November 3, 2026 and its [preview guide](https://developer.apple.com/documentation/appintents/siri-ai-developer-preview):

- **Your own builds and internal TestFlight testers only.** The preview isn't available to external TestFlight testers or to apps from the App Store. Apple says App Store submission opens "in the spring".
- **Devices that support Apple Intelligence**, on the 27.3 betas. This kit targets iOS; Apple also lists iPadOS, macOS and visionOS.
- **The device's language must be English, French, Japanese, Korean, Portuguese or Spanish.** Apple says more languages are coming.
- **Not in the EU on iOS and iPadOS, and not for people under 13.**
- **Siri AI has daily usage limits**, because it uses server-side models.
- **Apple may change the App Intents API and Siri behaviour during the preview.**

Link `SyrupAIKit` to your app target and `SyrupAIEvalKit` to your UI test target.

**Expo apps:** the [`expo-syrup-ai-kit`](expo-plugin/) config plugin adds SyrupAIKit to your app target during prebuild, so Swift tools in `app-intents/` can import it.

## Wrapping your API code in a tool

```swift
import SyrupAIKit

private let tool = SiriTool(appName: "My App") { error in
    (error as? MyAPIError) == .serverDown ? .unreachable : nil
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
| `.timedOut`, `.unreachable` | "Couldn't reach My App right now." |
| `.failed` | "My App couldn't do that right now." |

Pass `replies: ToolReplies` to use your own wording.

**Speaking the answer, or handing it to Siri.** `.result(value:dialog:)` makes Siri say your sentence word for word and end its turn. That suits a tool that answers a question on its own. For a tool Siri should use inside a bigger request, such as "what's in my cart, and is the first item in stock?", return only the value:

```swift
func perform() async throws -> some IntentResult & ReturnsValue<String> {
    .result(value: await tool.answer { describe(try await MyAPI.shared.cart()) })
}
```

Siri then words the reply itself and can call another tool first. On a phone, Siri chained two value-only tools in 5 of 5 runs and two dialog tools in 0 of 5 ([docs/spikes/app-skills-bundle.md](docs/spikes/app-skills-bundle.md#device-runs)). Because Siri picks the wording, evaluations of a value-only tool should check for the value, not a fixed sentence.

**Time budget:**
- Siri waits for `perform()`, so `SiriTool` gives up after 10 seconds by default (`timeout:`), or as soon as Siri cancels the call, and reports `.timedOut`.
- It stops waiting but doesn't cancel your code, so work like saving to a cache still finishes. Your code may keep running briefly after Siri has moved on.

### Showing what the tool did

`SiriTool` records each call's outcome: "succeeded", "timed out", "unreachable" or "failed". Add details from your own code with `ToolOutcomeLog.standard.note("served from cache")`. They appear with the outcome, as in "succeeded (served from cache)". A note belongs to the `SiriTool` call whose code made it. Notes made outside a call, or after a call has timed out, are dropped.

Add `ToolOutcomeView()` (debug builds only) to your app so evaluations can read it. If you build your own view, show `ToolOutcomeLog.label()` with the accessibility identifier `ToolOutcomeLog.accessibilityIdentifier`.

## Rules learned on a device

- **Answer within a few seconds.** Siri waits for your tool, and `SiriTool` enforces the budget.
- **A tool that returns a dialog ends Siri's turn.** Siri won't chain it with another tool. Return only the value from any tool that Siri should combine with others, including every tool an App Skill names.
- **Index what identifies a record (id, name, synonyms), never the answer the tool exists to give.** Otherwise Siri answers from the Spotlight index instead of calling your tool.

## Testing with Siri Evaluations

```swift
import AppIntentsTesting
import SyrupAIEvalKit
import SiriEvaluations
import Testing

private let getCartIntent = IntentDefinitions(bundleIdentifier: "com.example.myapp").intents["GetCartIntent"]
private let harness = SiriAppHarness(
  bundleIdentifier: "com.example.myapp",
  readyWhen: .labelBegins("app-status", with: "Ready")
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

Before each run, `ToolEvaluation` launches the app and waits for the ready signal, up to 90 seconds. It then applies `before:` (for example, `.waitFor(.seconds(70))` until a cache expires), runs the scenario, and saves the tool's outcome as an attachment named `siri-ai-eval-outcome`.

### Prove the checks can fail, and measure without the app's name

A pass rate is only worth trusting when the same checks fail once the tool is broken. Break the app at launch with an `EvalSwitch`, never with a code edit you have to remember to revert:

```swift
// Shared by the app and the UI test target.
extension EvalSwitch {
  static let badHost: EvalSwitch = "bad-host"
}

// In the app's own code. Release builds ignore it.
static var baseURL: URL {
  #if DEBUG
  if EvalSwitch.badHost.isOn() { return URL(string: "https://unreachable.invalid")! }
  #endif
  return URL(string: "https://api.example.com")!
}

// In the UI test target: same scenario, app launched with the switch on.
@Test(.evaluates(ToolEvaluation.negativeControl(
  name: "Cart, bad host",
  harness: harness,
  turningOn: .badHost,
  dataset: .repeating(times: 2, cartScenario)
)))
func replyCheckFailsWithBadHost() async throws {
  try expectAllFail(.siriResponse)
}
```

`expectAllFail` passes only when the metric failed in every run. The harness launches the app with `--siri-ai-eval-switch=bad-host`, and relaunches it before every run, so the switch never leaks into other evaluations.

To measure whether Siri picks your tool when the person doesn't name your app, ask the same question both ways with `ToolQuestion`:

```swift
private let cartQuestion = ToolQuestion("What's in my cart?", appName: "My App")
// cartQuestion.namingApp      == "In My App, what's in my cart?"
// cartQuestion.withoutAppName == "What's in my cart?"

@Test(.evaluates(ToolEvaluation.appNotNamed(
  name: "Cart without the app's name",
  harness: harness,
  question: cartQuestion,
  times: 5,
  scenario: cartScenario  // (String) -> SiriScenario
)))
func cartToolWithoutTheAppName() async throws {}
```

It's a separate, informational evaluation, not runs mixed into the required one. Siri may fairly ask which app you mean, so a low rate here is a finding, not a regression, and mixing it in would drag down the required pass rate. Don't assert it.

Both helpers tag the evaluation's name (`[negative control]`, `[informational]`), so the tag reaches the result bundle and Xcode's report too.

Summarize the results:

```bash
swift run syrup-ai-eval summarize cart.xcresult [--json] [--fail-on any|real]
```

It prints each run's tool calls, reply, intents check, reply check, recorded outcome, and whether the run was cut short ("the run ended before all of its results arrived").

It also flags complete runs where the reply check passed but an expected tool wasn't called: "answered without calling the tool". Siri most likely answered from what your app indexed in Spotlight, so your tool's code never ran. Index only what identifies a record.

Under a tagged evaluation's name it adds a line. An informational evaluation is never counted toward the exit status. A negative control passes only when the reply check failed in every run it counts. Under `--fail-on real`, that means every complete run, and at least one run must be complete. The JSON output has a `kind` field: `required`, `informational` or `negative control`.

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

Run on Nov 12, 2026 on an iPhone 16 Pro on iOS 27.3 beta, with Xcode 27.3 beta (27C5020n), using the example app at 0.3.0 against DummyJSON's public cart:

| Evaluation | Runs | Apple pass rate | Real pass rate | What Siri did |
|---|---|---|---|---|
| Cart from the demo API | 5 | 100% | 100% (5 of 5) | Called `GetCartIntent` and read the cart in all 5 |
| Cart with a bad host (negative control) | 2 (1 complete) | 0% | Passed: the reply check failed, as expected | Called `GetCartIntent` and said "Couldn't reach SyrupAIKit Example right now." Outcome: "unreachable" |
| Cart without the app's name (informational) | 5 | 0% | 0% (0 of 5) | Asked to handle such requests in the app from now on, and waited for a yes |

The 0.2.0 example passed the cart evaluation 5 of 5 on the same phone on Nov 11.

## Upgrading from SiriAIKit 0.2.0

SiriAIKit is now Syrup AI Kit, and 0.3.0 is the first release under the new name. The types (`SiriTool`, `ToolFailure`, `SiriToolOutcome`) keep their names.

- **Swift package:** `https://github.com/airowe/syrup-ai-kit` (the old URL redirects). Products: `SyrupAIKit`, `SyrupAIEvalKit`. Change `import SiriAIKit` to `import SyrupAIKit`, and `import SiriAIEvalKit` to `import SyrupAIEvalKit`.
- **Command-line tool:** `swift run syrup-ai-eval summarize …`, was `siri-ai-eval`.
- **Expo plugin:** the npm package is `expo-syrup-ai-kit`, was `expo-siri-ai-kit`. Change the name in `app.json` plugins and `package.json`.
- **Agent skills:** the plugin is `syrup-ai-kit@syrup-ai-kit`, and the Expo skill is `expo-syrup-ai-kit`. The `siri-ai*` skills keep their names.

- **`ToolFailure.signedOut`:** removed, along with its reply and recorded outcome. Map those errors to another `ToolFailure` in `classify`, or let them fall through to `.failed`.
- **`ToolReplies`:** takes `unreachable:` and `failed:` only.
- **`KeychainLockCheck`:** removed.

## Upgrading from 0.1.0

0.2.0 removed SiriAIKit's networking layer. Your app's own networking handles requests now.

- **`ToolHTTPClient`, `TokenAuthenticator`, `HTTPMethod`:** wrap your existing API call with `SiriTool.answer` or `SiriTool.run`.
- **`KeychainTokenStore`, `TokenStore`, `Tokens`, `KeychainAccessibility`:** removed. Keep what they stored in your app's own code.
- **`ToolError`:** replaced by `ToolFailure`. `.rejected` and `.invalidResponse` became `.failed`, and `.keychain` is gone.
- **Outcomes:** details are no longer recorded automatically. Use `ToolOutcomeLog.standard.note(_:)` from your code.

## Agent skills

Syrup AI Kit ships skills that teach coding agents to build and test Siri AI tools: `siri-ai-tool`, `siri-ai-eval`, `expo-syrup-ai-kit` and `siri-ai-discover`. They cover the checks agents miss without them, such as answers left in the Spotlight index. `siri-ai-discover` chooses which tools an app should have.

In Claude Code:

```
/plugin marketplace add airowe/syrup-ai-kit
/plugin install syrup-ai-kit@syrup-ai-kit
```

For other agents, copy the folders in [`skills/`](skills/) and [`expo-plugin/skills/`](expo-plugin/skills/) into the agent's skills directory. From the release after 0.2.0, the `expo-syrup-ai-kit` npm package also includes the Expo skills, under `node_modules/expo-syrup-ai-kit/skills/`. 0.2.0 doesn't.

## Development

```bash
swift test                     # SyrupAIKit, SyrupAIEvalKit and summary tests, on the Mac
xcodebuild build -scheme SyrupAIEvalKit -destination 'generic/platform=iOS'
```

The tests run on the Mac rather than the Simulator, because booting the iOS 27.3 beta Simulator crash-looped its `identityservicesd`.

## License

[MIT](LICENSE)
