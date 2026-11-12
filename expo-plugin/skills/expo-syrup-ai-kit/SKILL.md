---
name: expo-syrup-ai-kit
description: Use when adding a Siri AI tool (`@AppIntent(.tool)`) to an Expo or React Native app, setting up the expo-syrup-ai-kit config plugin, or when an Expo prebuild with `SIRI_AI_PREVIEW` fails, `import SyrupAIKit` can't be found in `app-intents/`, the Siri evaluation target disappears after prebuild, or a Siri tool in the app answers with stale data or is never called.
license: MIT
---

# Syrup AI Kit in an Expo app

## Overview

Expo apps answer Siri from Swift. `expo-app-intents` compiles the Swift files in `app-intents/` into the app target, and the `expo-syrup-ai-kit` config plugin links SyrupAIKit there during prebuild. JavaScript can't answer a Siri intent in a released Expo SDK yet, so don't try to route the tool through JS.

For the tool itself (`SiriTool`, failure replies, Spotlight indexing) use the siri-ai-tool skill; for testing use the siri-ai-eval skill. This skill covers only what's different in Expo.

## Setup

Expo SDK 58 or later. Never edit `ios/` by hand: it is regenerated.

```bash
npx expo install expo-syrup-ai-kit expo-app-intents
```

```json
{ "expo": { "plugins": ["expo-app-intents", "expo-syrup-ai-kit"] } }
```

```bash
npx expo-app-intents init --examples minimal   # unless app-intents/AppIntentsSetup.swift exists
SIRI_AI_PREVIEW=1 CP_CACHE_DIR="$PWD/.cp-cache" LANG=en_US.UTF-8 npx expo prebuild -p ios
```

`init` creates the `AppIntentsSetup` inline module and turns on inline modules in `app.json`. `npx expo install` adds both plugins; keep `expo-app-intents` first, as above.

With the preview on, the plugin adds the `SIRI_AI_PREVIEW` Swift condition and sets the **app target** to iOS 27.3. Without `SIRI_AI_PREVIEW=1` (or `["expo-syrup-ai-kit", { "preview": true }]`), tool code inside `#if SIRI_AI_PREVIEW` doesn't compile in, and Siri never sees the tool.

Options: `version` (SyrupAIKit release, up to next minor; defaults to the tested one), `branch` (unreleased SyrupAIKit; not with `version`), `preview`, `evals`, `skills` (`{ "sourceDir": "siri-skills" }`: a folder of Apple App Skills, one folder per skill with only a `SKILL.md`; checked at prebuild and compiled into the app as `Skills.skillsbundle`).

## The evaluation target comes from the plugin

Don't add the Siri Evaluations UI test target in Xcode: `prebuild --clean` drops it. Keep the tests outside `ios/` and set `evals`:

```json
["expo-syrup-ai-kit", { "preview": true, "evals": { "sourceDir": "siri-evals" } }]
```

Prebuild then adds a `<AppName>Evals` UI test target (rename with `targetName`) that compiles every `.swift` file under `siri-evals/`, tests the app, builds for iOS 27.3, links `SyrupAIEvalKit` from the same package, and has a shared scheme of the same name: `xcodebuild test -workspace ios/<App>.xcworkspace -scheme <App>Evals -configuration Release -destination 'platform=iOS,name=<device>'`. Use Release: a Debug build loads its JavaScript from the dev server and won't start without `npx expo start`. Prebuild again after adding or removing a test file.

## The tool lives in `app-intents/`

```swift
// app-intents/GetOrderStatusIntent.swift
import AppIntents
import SyrupAIKit

private let tool = SiriTool(appName: "ParcelPal")

#if SIRI_AI_PREVIEW
@AppIntent(.tool)
#endif
struct GetOrderStatusIntent: AppIntent {
  static let title: LocalizedStringResource = "Get Order Status"

  func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
    let answer = await tool.answer { try await OrderStatusClient.describeOrders() }
    return .result(value: answer, dialog: "\(answer)")
  }
}
```

The Swift tool can't call your JavaScript API client or read JS memory. It needs its own Swift request code.

The dialog makes Siri say the answer word for word and end its turn. If an App Skill names the tool, or Siri should combine it with others, return `some IntentResult & ReturnsValue<String>` and `.result(value: answer)` instead; a generated tool does this with `"returns": "value"`.

## Implementing tools from `siri-tools.json`

A `siri-tools.json` from the siri-ai-discover skill is the tools' interface. Each entry has `name`, `title`, `description` and `parameters`, and usually `"javascript": "<handler>"`. Implement every entry with that interface unchanged: evaluations check `name`, and Siri chooses tools by `description`.

| The entry has | Do this today |
|---|---|
| `javascript` | Not supported yet: the plugin rejects it as an unknown field. Write a Swift tool in `app-intents/` named `<name>Intent`, copy `title` and `description` word for word, and add one `@Parameter(title:description:)` per declared parameter, with its `title` and `description`. Keep the entry as the tool's spec, but leave it out of the `tools` file until the `javascript` kind ships. |
| `returns: "value"` | In Swift, return `.result(value: answer)` without `ProvidesDialog`. A generated tool does it for you. |
| `request` and `reply` | Generated at prebuild by the `tools` option (experimental). Use it only when the host is fixed and `https`, the API needs no credentials, and every reply field is always present. Generated tools send plain requests, and any non-2xx response is a failure. Otherwise write Swift. |

Discovery also writes a handler stub and a failing test per tool in `src/siri-tools/<handler>.ts` (or `siri-tools/` without `src/`). Discovery offers to implement it, and to write the Swift tool; if the owner declined, implement the handler against the test now: it's plain TypeScript that calls the app's own functions, never hooks. It answers Siri once the `javascript` kind ships; until then the Swift tool is what answers.

Whatever the kind, the answer is one sentence (the count and at most three names for a list). Failures go through `SiriTool`'s `ToolFailure` cases, and write actions ask Siri to confirm. The full guide for humans is `docs/implementing-tools.md` in the syrup-ai-kit repository.

## Show the tool's outcome for evaluations

The screen is React Native, so use a JS `<Text>` instead of SyrupAIKit's SwiftUI `ToolOutcomeView`. Expose the outcome from the `AppIntentsSetup` inline module that expo-app-intents uses (`app-intents/AppIntentsSetup.swift`; keep the class name):

```swift
internal import ExpoAppIntents
internal import ExpoModulesCore
import SyrupAIKit

final class AppIntentsSetup: Module {
  public func definition() -> ExpoModulesCore.ModuleDefinition {
    Name("AppIntentsSetup")
    Function("siriToolOutcome") { () -> String in ToolOutcomeLog.standard.last }
  }
}
```

```tsx
import { requireNativeModule } from 'expo';

const Setup = requireNativeModule<{ siriToolOutcome(): string }>('AppIntentsSetup');

export function SiriToolOutcome() {
  const [outcome, setOutcome] = useState(Setup.siriToolOutcome());
  useEffect(() => {
    const poll = setInterval(() => setOutcome(Setup.siriToolOutcome()), 1000);
    return () => clearInterval(poll);
  }, []);
  return <Text testID="siri-ai-tool-outcome">{outcome}</Text>;
}
```

Render `<SiriToolOutcome />` on a screen that's always visible. The testID `siri-ai-tool-outcome` is what SyrupAIEvalKit reads. Don't hide it behind `__DEV__`: evaluations run a Release build, so the outcome would never show. If the module already exists, add the `Function` to it rather than creating a second one. Import `SyrupAIKit` the same way in every file in `app-intents/`: plain `import SyrupAIKit` here and in the tools.

## Prebuild and build traps

| Symptom | Fix |
|---|---|
| CocoaPods: `Unicode Normalization not appropriate for ASCII-8BIT` | Run with `LANG=en_US.UTF-8` |
| `pod install`: `Info.plist` missing in `hermesvm.xcframework` or `React-Core-prebuilt/React.xcframework` | A broken CocoaPods cache, unrelated to SyrupAIKit: `cd ios && CP_CACHE_DIR="$PWD/../.cp-cache" LANG=en_US.UTF-8 pod install` |
| `ambiguous implicit access level for import of 'SyrupAIKit'` | One file in `app-intents/` has `internal import SyrupAIKit` and another plain `import SyrupAIKit`. Use one form in every file |
| No `app-intents/AppIntentsSetup.swift` to add the outcome function to | Run `npx expo-app-intents init --examples minimal`, then prebuild again |
| Evaluations run a Debug build | Debug loads JavaScript from the dev server, so the app needs `npx expo start` running. Use `-configuration Release` |
| Negative control's reply check passes: the `EvalSwitch` did nothing | Release compiles `#if DEBUG` out. Guard the switch with `#if DEBUG \|\| SIRI_AI_EVAL_SWITCHES` and pass `SIRI_AI_EVAL_SWITCHES=YES` to `xcodebuild test`. Generated tools already honour `bad-host` |
| `No such module 'SyrupAIKit'` in `app-intents/` | Plugin missing from `app.json`, or prebuild not re-run after adding it |
| Siri never calls the tool, no build error | Prebuilt without `SIRI_AI_PREVIEW=1`, so `@AppIntent(.tool)` compiled out |
| Evaluation UI test target gone | Set the plugin's `evals: { "sourceDir": "siri-evals" }` option instead of adding the target in Xcode, then prebuild again |
| `evals.sourceDir ... does not exist` / `has no .swift files` | `sourceDir` is relative to the project root, not `ios/`; it needs at least one `.swift` test file |
| `the App Skills in ... have problems` | Fix each listed `SKILL.md`: only `name` and `description` in the frontmatter, `name` matching its folder, no other files in the skill folder |
| `the app target already has a skills bundle` | A target can have only one. Remove the one added in Xcode and keep the skills in `skills.sourceDir` |
| App Skills added in Xcode don't reach Siri | Added as a plain folder, Xcode copies them raw and never compiles them. Use the plugin's `skills` option |

Siri evaluations need a development build on a physical iPhone running iOS 27.3; not Expo Go and not the Simulator.
