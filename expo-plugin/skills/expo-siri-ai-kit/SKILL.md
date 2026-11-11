---
name: expo-siri-ai-kit
description: Use when adding a Siri AI tool (`@AppIntent(.tool)`) to an Expo or React Native app, setting up the expo-siri-ai-kit config plugin, or when an Expo prebuild with `SIRI_AI_PREVIEW` fails, `import SiriAIKit` can't be found in `app-intents/`, or the Siri evaluation target disappears after prebuild.
license: MIT
---

# SiriAIKit in an Expo app

## Overview

Expo apps answer Siri from Swift. `expo-app-intents` compiles the Swift files in `app-intents/` into the app target, and the `expo-siri-ai-kit` config plugin links SiriAIKit there during prebuild. JavaScript can't answer a Siri intent in a released Expo SDK yet, so don't try to route the tool through JS.

For the tool itself (`SiriTool`, Keychain, Spotlight indexing, token refresh) use the siri-ai-tool skill; for testing use the siri-ai-eval skill. This skill covers only what's different in Expo.

## Setup

Expo SDK 58 or later. Never edit `ios/` by hand: it is regenerated.

```bash
npx expo install expo-siri-ai-kit expo-app-intents
```

```json
{ "expo": { "plugins": ["expo-app-intents", "expo-siri-ai-kit"] } }
```

```bash
SIRI_AI_PREVIEW=1 npx expo prebuild -p ios
```

With the preview on, the plugin adds the `SIRI_AI_PREVIEW` Swift condition and sets the **app target** to iOS 27.3. Without `SIRI_AI_PREVIEW=1` (or `["expo-siri-ai-kit", { "preview": true }]`), tool code inside `#if SIRI_AI_PREVIEW` doesn't compile in, and Siri never sees the tool.

Options: `version` (SiriAIKit release, up to next minor; defaults to the tested one), `branch` (unreleased SiriAIKit; not with `version`), `preview`, `evals`.

## The evaluation target comes from the plugin

Don't add the Siri Evaluations UI test target in Xcode: `prebuild --clean` drops it. Keep the tests outside `ios/` and set `evals`:

```json
["expo-siri-ai-kit", { "preview": true, "evals": { "sourceDir": "siri-evals" } }]
```

Prebuild then adds a `<AppName>Evals` UI test target (rename with `targetName`) that compiles every `.swift` file under `siri-evals/`, tests the app, builds for iOS 27.3, links `SiriAIEvalKit` from the same package, and has a shared scheme of the same name: `xcodebuild test -workspace ios/<App>.xcworkspace -scheme <App>Evals -destination 'platform=iOS,name=<device>'`. Prebuild again after adding or removing a test file.

## The tool lives in `app-intents/`

```swift
// app-intents/GetOrderStatusIntent.swift
import AppIntents
import SiriAIKit

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

The Swift tool can't call your JavaScript API client, and can't read tokens from JS memory. It needs its own Swift request code and the token from the Keychain. If the app stores tokens with `expo-secure-store`, its default `keychainAccessible` is `WHEN_UNLOCKED`, which Siri can't read on a locked phone. Save with `keychainAccessible: SecureStore.AFTER_FIRST_UNLOCK` and an explicit `keychainService`, then read that generic-password item from Swift with the same service. Check the installed expo-secure-store iOS source for the account attribute it uses before writing the Swift query.

## Show the tool's outcome for evaluations

The screen is React Native, so use a JS `<Text>` instead of SiriAIKit's SwiftUI `ToolOutcomeView`. Expose the outcome from the `AppIntentsSetup` inline module that expo-app-intents uses (`app-intents/AppIntentsSetup.swift`; keep the class name):

```swift
internal import ExpoModulesCore
import SiriAIKit

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
  return __DEV__ ? <Text testID="siri-ai-tool-outcome">{outcome}</Text> : null;
}
```

Render `<SiriToolOutcome />` on a screen that's always visible. The testID `siri-ai-tool-outcome` is what SiriAIEvalKit reads. If the module already exists, add the `Function` to it rather than creating a second one.

## Prebuild and build traps

| Symptom | Fix |
|---|---|
| CocoaPods: `Unicode Normalization not appropriate for ASCII-8BIT` | Run with `LANG=en_US.UTF-8` |
| `hermesvm.xcframework/Info.plist` missing during `pod install` | A broken CocoaPods cache, unrelated to SiriAIKit: `cd ios && CP_CACHE_DIR="$PWD/../.cp-cache" LANG=en_US.UTF-8 pod install` |
| `No such module 'SiriAIKit'` in `app-intents/` | Plugin missing from `app.json`, or prebuild not re-run after adding it |
| Siri never calls the tool, no build error | Prebuilt without `SIRI_AI_PREVIEW=1`, so `@AppIntent(.tool)` compiled out |
| Evaluation UI test target gone | Set the plugin's `evals: { "sourceDir": "siri-evals" }` option instead of adding the target in Xcode, then prebuild again |
| `evals.sourceDir ... does not exist` / `has no .swift files` | `sourceDir` is relative to the project root, not `ios/`; it needs at least one `.swift` test file |

Siri evaluations need a development build on a physical iPhone running iOS 27.3; not Expo Go and not the Simulator.
