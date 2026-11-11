# expo-siri-ai-kit

Expo config plugin for [SiriAIKit](https://github.com/airowe/siri-ai-kit). It lets the Swift tools in your Expo app use SiriAIKit, and turns on the Siri AI Developer Preview code (iOS 27.3 beta).

Not affiliated with or endorsed by Apple.

## What it does when you prebuild

- **Adds SiriAIKit** as a Swift package and links it to your app target. That's where [`expo-app-intents`](https://docs.expo.dev/versions/latest/sdk/app-intents) compiles the Swift in `app-intents/`, so your tools can `import SiriAIKit`.
- **With the preview on, it also:**
  - adds the `SIRI_AI_PREVIEW` Swift compilation condition, so `#if SIRI_AI_PREVIEW` code builds only with the 27.3 SDK;
  - sets the app target's deployment target to iOS 27.3, which `@Property(title:description:)` requires. Pods keep their own targets.
- **With `evals` set, adds a UI test target for Siri Evaluations** (see [Evaluation target](#evaluation-target)), so it survives `prebuild --clean`.

Running prebuild again doesn't add anything twice.

## Install

The full setup, including the Mac, the iPhone and a checklist for coding agents, is in [INSTALL.md](https://github.com/airowe/siri-ai-kit/blob/main/INSTALL.md).

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
| `tools` | None | Path to a Siri tools declaration, such as `./siri-tools.json`. Generates a Swift tool for each entry. Experimental. |
| `evals` | None | `{ "sourceDir": "siri-evals", "targetName": "MyAppEvals" }`. Adds a UI test target for Siri Evaluations. `targetName` defaults to `<AppName>Evals`. |

## Evaluation target

`prebuild --clean` regenerates `ios/`, so a test target added in Xcode disappears. Keep the evaluation tests in a folder outside `ios/` and let the plugin add the target:

```json
["expo-siri-ai-kit", { "preview": true, "evals": { "sourceDir": "siri-evals" } }]
```

On every prebuild the plugin adds a `<AppName>Evals` UI test target that:

- compiles every `.swift` file under `sourceDir` (subfolders included), referenced in place rather than copied;
- tests the app target (`TEST_TARGET_NAME`), depends on it, and builds for iOS 27.3;
- links `SiriAIEvalKit` from the same SiriAIKit package, and copies the app's development team for signing;
- gets a shared scheme of the same name.

Run the evaluations on an iPhone on iOS 27.3 with Siri AI on:

```bash
xcodebuild test -workspace ios/MyApp.xcworkspace -scheme MyAppEvals -destination 'platform=iOS,name=My iPhone'
```

Prebuild fails with a clear message if `sourceDir` doesn't exist or has no `.swift` files. The file list is read at prebuild, so prebuild again after adding or removing a test file.

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

## Generating tools from a declaration (experimental)

Instead of writing Swift, list tools that call your HTTP API in a JSON file and pass its path as `tools`:

```json
{
  "tools": [
    {
      "name": "SearchProducts",
      "title": "Search Products",
      "description": "Searches the store's catalog and says how many products match and what they are called.",
      "parameters": [
        { "name": "query", "type": "string", "title": "Search Text" },
        { "name": "limit", "type": "int", "title": "Number of Results" }
      ],
      "request": { "method": "GET", "url": "https://dummyjson.com/products/search?q={query}&limit={limit}" },
      "reply": "Found {total} products. The first ones are {products.title}."
    }
  ]
}
```

At prebuild the plugin writes one Swift tool per entry, plus a shared `SiriToolsGenerated.swift`, to `ios/<App>/SiriTools/` and compiles that folder into the app target. A bad declaration stops prebuild with every problem listed. The format, what it supports and what's still open are in [docs/spikes/tool-codegen.md](../docs/spikes/tool-codegen.md).

## Implementing the tools discovery proposes

The `siri-ai-discover` skill writes each tool's interface to `siri-tools.json`, and leaves how the tool gets its answer to your code. [docs/implementing-tools.md](../docs/implementing-tools.md) covers:

- the three ways to answer: a Swift tool (works today), `request` + `reply` (experimental), or `javascript` (planned);
- what every tool must do, whichever way it answers;
- how to prove each tool on a phone.

## Showing the tool's outcome in your app

Siri Evaluations read the last outcome from the screen. Expose it from your `AppIntentsSetup` inline module:

```swift
Function("siriToolOutcome") { () -> String in
  ToolOutcomeLog.standard.last
}
```

Then render it from JavaScript with `testID="siri-ai-tool-outcome"`.

## Agent skills

This package includes two agent skills:

- `skills/expo-siri-ai-kit/SKILL.md` covers setup, the outcome bridge and known prebuild problems.
- `skills/siri-ai-discover/SKILL.md` finds which Siri AI tools an app should have and writes their interfaces (name, description, parameters) to `siri-tools.json`, with an evaluation prompt for each. How each tool gets its answer is left to the app's own code.

Claude Code users can install them with the other SiriAIKit skills: `/plugin marketplace add airowe/siri-ai-kit`, then `/plugin install siri-ai-kit@siri-ai-kit`.

## Requirements

- Expo SDK 58 or later, with `expo-app-intents`.
- Xcode 27.3 beta, and an iPhone on iOS 27.3 beta with Siri AI on, for the preview.
- Tools that answer Siri are written in Swift. Expo hasn't released a way for JavaScript to answer an intent yet.

## License

MIT
