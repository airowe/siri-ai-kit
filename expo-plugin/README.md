# expo-siri-ai-kit

Expo config plugin for [SiriAIKit](https://github.com/airowe/siri-ai-kit). It lets the Swift tools in your Expo app use SiriAIKit, and turns on the Siri AI Developer Preview code (iOS 27.3 beta).

Not affiliated with or endorsed by Apple.

## What it does when you prebuild

- **Adds SiriAIKit** as a Swift package and links it to your app target. That's where [`expo-app-intents`](https://docs.expo.dev/versions/latest/sdk/app-intents) compiles the Swift in `app-intents/`, so your tools can `import SiriAIKit`.
- **With the preview on, it also:**
  - adds the `SIRI_AI_PREVIEW` Swift compilation condition, so `#if SIRI_AI_PREVIEW` code builds only with the 27.3 SDK;
  - sets the app target's deployment target to iOS 27.3, which `@Property(title:description:)` requires. Pods keep their own targets.

Running prebuild again doesn't add anything twice.

## Install

```bash
npx expo install expo-siri-ai-kit expo-app-intents
```

```json
{
  "expo": {
    "plugins": ["expo-app-intents", "expo-siri-ai-kit"]
  }
}
```

Then prebuild with the preview on:

```bash
SIRI_AI_PREVIEW=1 npx expo prebuild -p ios
```

## Options

```json
["expo-siri-ai-kit", { "version": "0.2.0", "preview": true }]
```

| Option | Default | What it does |
|---|---|---|
| `version` | The SiriAIKit release this plugin was tested with | Uses SiriAIKit up to the next minor version. |
| `branch` | None | Follows a SiriAIKit branch instead. Use it only to try unreleased changes. Can't be combined with `version`. |
| `preview` | `true` when `SIRI_AI_PREVIEW=1` is set | Turns on the Siri AI Developer Preview code. |

## A first tool

```swift
// app-intents/GetQuoteIntent.swift
import AppIntents
import Foundation
import SiriAIKit

private let tool = SiriTool(appName: "My App")

#if SIRI_AI_PREVIEW
@AppIntent(.tool)
#endif
struct GetQuoteIntent: AppIntent {
  static let title: LocalizedStringResource = "Get Quote of the Day"

  func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
    let answer = await tool.answer {
      let (data, _) = try await URLSession.shared.data(from: URL(string: "https://dummyjson.com/quotes/random")!)
      let quote = try JSONDecoder().decode(Quote.self, from: data)
      return "\(quote.quote) That's from \(quote.author)."
    }
    return .result(value: answer, dialog: "\(answer)")
  }
}

private struct Quote: Decodable {
  let quote: String
  let author: String
}
```

See the [SiriAIKit README](https://github.com/airowe/siri-ai-kit#readme) for `SiriTool`, outcomes, and testing with Siri Evaluations.

## Showing the tool's outcome in your app

Siri Evaluations read the last outcome from the screen. Expose it from your `AppIntentsSetup` inline module:

```swift
Function("siriToolOutcome") { () -> String in
  ToolOutcomeLog.standard.last
}
```

Then render it from JavaScript with `testID="siri-ai-tool-outcome"`.

## Requirements

- Expo SDK 58 or later, with `expo-app-intents`.
- Xcode 27.3 beta, and an iPhone on iOS 27.3 beta with Siri AI on, for the preview.
- Tools that answer Siri are written in Swift. Expo hasn't released a way for JavaScript to answer an intent yet.

## License

MIT
