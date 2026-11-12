# expo-syrup-ai-kit

The Expo plugin for Syrup AI Kit: Siri AI tools for Expo and React Native apps. Formerly `expo-siri-ai-kit`.

Make your Expo or React Native app work with Siri AI. This Expo config plugin for [Syrup AI Kit](https://github.com/airowe/syrup-ai-kit) lets the Swift tools in your app use SyrupAIKit, and turns on the Siri AI Developer Preview code (iOS 27.3 beta).

Using a coding agent? Install the [agent skills](#agent-skills) and ask it to "make my app work with Siri AI".

Not affiliated with or endorsed by Apple.

## What it does when you prebuild

- **Adds SyrupAIKit** as a Swift package and links it to your app target. That's where [`expo-app-intents`](https://docs.expo.dev/versions/latest/sdk/app-intents) compiles the Swift in `app-intents/`, so your tools can `import SyrupAIKit`.
- **With the preview on, it also:**
  - adds the `SIRI_AI_PREVIEW` Swift compilation condition, so `#if SIRI_AI_PREVIEW` code builds only with the 27.3 SDK;
  - sets the app target's deployment target to iOS 27.3, which `@Property(title:description:)` requires. Pods keep their own targets.
- **With `evals` set, adds a UI test target for Siri Evaluations** (see [Evaluation target](#evaluation-target)), so it survives `prebuild --clean`.
- **With `skills` set, checks your Apple App Skills and adds them to the app as `Skills.skillsbundle`** (see [App Skills](#app-skills)).

Running prebuild again doesn't add anything twice.

## Install

The full setup, including the Mac, the iPhone and a checklist for coding agents, is in [INSTALL.md](https://github.com/airowe/syrup-ai-kit/blob/main/INSTALL.md).

```bash
npx expo install expo-syrup-ai-kit expo-app-intents
npx expo-app-intents init --examples minimal
```

`init` creates `app-intents/AppIntentsSetup.swift`, the inline module used in [Showing the tool's outcome](#showing-the-tools-outcome-in-your-app), and turns on inline modules in `app.json`. `npx expo install` adds both plugins; list them in this order:

```json
{
  "expo": {
    "plugins": ["expo-app-intents", "expo-syrup-ai-kit"]
  }
}
```

Then prebuild with the preview on:

```bash
SIRI_AI_PREVIEW=1 CP_CACHE_DIR="$PWD/.cp-cache" LANG=en_US.UTF-8 npx expo prebuild -p ios
```

`CP_CACHE_DIR` gives CocoaPods a cache of its own, which avoids a missing-`Info.plist` failure from a broken shared cache. `LANG` avoids a CocoaPods encoding error.

## Options

```json
["expo-syrup-ai-kit", { "version": "0.3.0", "preview": true }]
```

| Option | Default | What it does |
|---|---|---|
| `version` | The SyrupAIKit release this plugin was tested with | Uses SyrupAIKit up to the next minor version. |
| `branch` | None | Follows a SyrupAIKit branch instead. Use it only to try unreleased changes. Can't be combined with `version`. |
| `preview` | `true` when `SIRI_AI_PREVIEW=1` is set | Turns on the Siri AI Developer Preview code. |
| `tools` | None | Path to a Siri tools declaration, such as `./siri-tools.json`. Generates a Swift tool for each entry. Experimental. |
| `evals` | None | `{ "sourceDir": "siri-evals", "targetName": "MyAppEvals" }`. Adds a UI test target for Siri Evaluations. `targetName` defaults to `<AppName>Evals`. |
| `skills` | None | `{ "sourceDir": "siri-skills" }`. A folder of Apple App Skills, one folder per skill holding a `SKILL.md`. Checked against Apple's rules and compiled into the app. |

## Evaluation target

`prebuild --clean` regenerates `ios/`, so a test target added in Xcode disappears. Keep the evaluation tests in a folder outside `ios/` and let the plugin add the target:

```json
["expo-syrup-ai-kit", { "preview": true, "evals": { "sourceDir": "siri-evals" } }]
```

On every prebuild the plugin adds a `<AppName>Evals` UI test target that:

- compiles every `.swift` file under `sourceDir` (subfolders included), referenced in place rather than copied;
- tests the app target (`TEST_TARGET_NAME`), depends on it, and builds for iOS 27.3;
- links `SyrupAIEvalKit` from the same SyrupAIKit package, and copies the app's development team for signing;
- gets a shared scheme of the same name.

Run the evaluations on an iPhone on iOS 27.3 with Siri AI on:

```bash
xcodebuild test -workspace ios/MyApp.xcworkspace -scheme MyAppEvals -configuration Release \
  -destination 'platform=iOS,name=My iPhone' -resultBundlePath evals.xcresult
```

Use Release so the JavaScript is in the app. A Debug build loads it from the dev server, so it only starts while `npx expo start` is running.

Prebuild fails with a clear message if `sourceDir` doesn't exist or has no `.swift` files. The file list is read at prebuild, so prebuild again after adding or removing a test file.

## App Skills

An App Skill is a short Markdown guide that tells Siri how to use several of your tools together, such as "search, add to the cart, then check out". Keep them in a folder at the project root:

```
siri-skills/
  cart-checkout/
    SKILL.md
```

```markdown
---
name: cart-checkout
description: Guides a purchase from search to checkout in ShopApp.
---
Search for the item first, add it to the cart, then confirm the total before checking out.
```

```json
["expo-syrup-ai-kit", { "preview": true, "skills": { "sourceDir": "siri-skills" } }]
```

At prebuild the plugin copies each `SKILL.md` into `ios/<App>/Skills.skillsbundle` and adds the bundle to the app target with Xcode's skills-bundle file type, so Xcode compiles it into the app. A skill you delete stops shipping on the next prebuild.

Prebuild stops, listing every problem, if a skill breaks Apple's rules. Xcode itself ignores or only warns about some of them:

- The frontmatter has only `name` and `description`.
- `name` is 1 to 64 lowercase letters, digits and single hyphens, and matches its folder.
- `description` is one line of at most 1,024 characters.
- The body is at most 10,000 characters.
- Each skill folder holds only its `SKILL.md`.

**A skill only helps if Siri can chain your tools, and today it can't chain a tool that returns a dialog.** Such a tool returns `.result(value:dialog:)`, as in [A first tool](#a-first-tool), and so does every tool the `tools` option generates unless it sets `"returns": "value"`. On a phone, Siri speaks a dialog and ends the turn. Tools that return only `.result(value:)` let Siri call one after another, and in the same test Siri chained them with or without a skill. The skill changed only how Siri worded the answer. So every tool a skill names should return only `.result(value:)`: in Swift, drop `ProvidesDialog` and the `dialog:` argument; in a declaration, set `"returns": "value"`. See [docs/spikes/app-skills-bundle.md](https://github.com/airowe/syrup-ai-kit/blob/main/docs/spikes/app-skills-bundle.md#device-runs) and [#31](https://github.com/airowe/syrup-ai-kit/issues/31).

Skills guide Siri; they don't guarantee it follows the steps in order. Nothing checks that a skill names tools your app has, so test the flow with a Siri evaluation. App Skills are part of the Siri AI Developer Preview, with the same limits on who can use them (see the [SyrupAIKit README](https://github.com/airowe/syrup-ai-kit#readme)).

## A first tool

```swift
// app-intents/GetQuoteIntent.swift
import AppIntents
import Foundation
import SyrupAIKit

private let tool = SiriTool(appName: "Sample App")

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

See the [Syrup AI Kit README](https://github.com/airowe/syrup-ai-kit#readme) for `SiriTool`, outcomes, and testing with Siri Evaluations.

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
        {
          "name": "query",
          "type": "string",
          "title": "Search Text",
          "description": "What to search the catalog for, as the person says it, like \"phone case\"."
        },
        { "name": "limit", "type": "int", "title": "Number of Results" }
      ],
      "request": { "method": "GET", "url": "https://dummyjson.com/products/search?q={query}&limit={limit}" },
      "reply": "Found {total} products. The first ones are {products.title}."
    }
  ]
}
```

A parameter's optional `description` is one line saying what the person gives, with an example. Siri reads it to fill the value.

A tool's optional `returns` says what Siri gets back:

- `"dialog"` (the default): Siri says the reply word for word and ends its turn.
- `"value"`: Siri gets the reply to use, words the answer itself, and can call another tool first. Use it for tools an [App Skill](#app-skills) names, or any tool Siri should combine with others.

At prebuild the plugin writes one Swift tool per entry, plus a shared `SiriToolsGenerated.swift`, to `ios/<App>/SiriTools/` and compiles that folder into the app target. A bad declaration stops prebuild with every problem listed. The format, what it supports and what's still open are in [docs/spikes/tool-codegen.md](../docs/spikes/tool-codegen.md).

## Implementing the tools discovery proposes

The `siri-ai-discover` skill writes each tool's interface to `siri-tools.json`, and leaves how the tool gets its answer to your code. [docs/implementing-tools.md](../docs/implementing-tools.md) covers:

- the three ways to answer: a Swift tool (works today), `request` + `reply` (experimental), or `javascript` (planned);
- what every tool must do, whichever way it answers;
- how to prove each tool on a phone.

## Showing the tool's outcome in your app

Siri Evaluations read the last outcome from the screen. Expose it from your `AppIntentsSetup` inline module, the one `npx expo-app-intents init` created:

```swift
// app-intents/AppIntentsSetup.swift
internal import ExpoAppIntents
internal import ExpoModulesCore
import SyrupAIKit

final class AppIntentsSetup: Module {
  public func definition() -> ExpoModulesCore.ModuleDefinition {
    Name("AppIntentsSetup")

    Function("siriToolOutcome") { () -> String in
      ToolOutcomeLog.standard.last
    }
  }
}
```

Import `SyrupAIKit` the same way in every file in `app-intents/`. Here it's a plain `import`, as in [A first tool](#a-first-tool). If one file says `internal import SyrupAIKit` and another `import SyrupAIKit`, the build fails with "ambiguous implicit access level".

Then show it on a screen that's always visible, with `testID="siri-ai-tool-outcome"`:

```tsx
import { requireNativeModule } from 'expo';
import { useEffect, useState } from 'react';
import { Text } from 'react-native';

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

## Agent skills

This package includes two agent skills:

- `skills/expo-syrup-ai-kit/SKILL.md` covers setup, the outcome bridge and known prebuild problems.
- `skills/siri-ai-discover/SKILL.md` finds which Siri AI tools an app should have and writes their interfaces (name, description, parameters) to `siri-tools.json`, with an evaluation prompt for each. How each tool gets its answer is left to the app's own code.

Install them with the other Syrup AI Kit skills, including `siri-ai`, the one to start from. In Claude Code: `/plugin marketplace add airowe/syrup-ai-kit`, then `/plugin install syrup-ai-kit@syrup-ai-kit`. In other agents: `npx skills add airowe/syrup-ai-kit`.

## Requirements

- Expo SDK 58 or later, with `expo-app-intents`.
- Xcode 27.3 beta, and an iPhone on iOS 27.3 beta with Siri AI on, for the preview.
- Tools that answer Siri are written in Swift. Expo hasn't released a way for JavaScript to answer an intent yet.

## License

MIT
