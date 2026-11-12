---
name: siri-ai-tool
description: Use when adding, changing or debugging a Siri AI tool (`@AppIntent(.tool)`) in a native iOS (Swift) app, or when a request says people should ask Siri for live app data such as an order, cart, balance or booking. Also use when Siri answers with stale data or never seems to call the app. In an Expo or React Native app, use expo-syrup-ai-kit instead.
license: MIT
---

# Siri AI tools with Syrup AI Kit

## Overview

A Siri AI tool is an App Intent marked `@AppIntent(.tool)` (Siri AI Developer Preview, iOS 27.3 SDK). Siri decides when to call it and waits for it. SyrupAIKit (`https://github.com/airowe/syrup-ai-kit`) wraps your existing API call so the tool keeps to Siri's time budget, turns errors into sentences Siri can say, and records what each call did.

A plain `AppIntent` plus an `AppShortcutsProvider` is the older Shortcuts path. It is not a Siri AI tool and does not get these guarantees.

## Before writing the tool, check the app

These break a tool on a real phone, even when the code compiles. Fix them in the same change.

| Check | Where | Fix |
|---|---|---|
| The answer is not in Spotlight | `CSSearchableItem`, `IndexedEntity`, `@Property(indexingKey:)` | Index what identifies a record (id, name, synonyms). Remove the answer the tool exists to give (status, total, balance, dates). Otherwise Siri answers from the index and never calls the tool. |
| Tokens are readable on a locked phone | Where the app saves tokens to the Keychain, or its secure-storage library's options | Siri can run the tool while the phone is locked. An item saved with `kSecAttrAccessibleWhenUnlocked`, the default in some secure-storage libraries, can't be read then, and the tool fails. Save with `kSecAttrAccessibleAfterFirstUnlock` or `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. |

Report them even when you can't fix them yet.

## The tool

```swift
import AppIntents
import SyrupAIKit

private let tool = SiriTool(appName: "ParcelPal") { error in
    (error as? ShopAPIError) == .serverDown ? .unreachable : nil   // nil: use the default rules
}

@AppIntent(.tool)
struct GetOrderStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Order Status"
    static let description = IntentDescription("Tells the person the live status of their current orders.")

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let answer = await tool.answer { describe(try await ShopAPI.shared.orders()) }
        return .result(value: answer, dialog: "\(answer)")
    }
}
```

- `answer` returns your sentence, or the failure sentence ("Couldn't reach ParcelPal right now." or "ParcelPal couldn't do that right now."). Use `run` when you need the value; it throws `ToolFailure` (`.timedOut`, `.unreachable`, `.failed`) and `failure.reply(appName:)` gives the sentence.
- `classify` maps your errors. If your networking library wraps `URLError`, unwrap it there, or network failures count as `.failed`.
- The default timeout is 10 seconds (`timeout:`). The tool stops waiting but your code keeps running, so saves to a cache still finish.
- `.result(value:dialog:)` makes Siri say the reply word for word and end its turn, so Siri can't chain the tool with another. For a tool Siri should combine with others (any tool an App Skill names), return `some IntentResult & ReturnsValue<String>` and `.result(value: answer)`: Siri then words the answer itself, so evaluations check for the value, not a sentence.
- Siri speaks the reply, so keep it to a sentence or two. With several records, say the most relevant one and how many others there are.
- The `description` is what Siri reads to choose the tool. Say what it returns, in the user's words.
- Give each parameter a description: `@Parameter(title: "Product", description: "The product to add, as the person names it, like \"oat milk\".")`. Siri reads it to fill the value from what the person said. Say what the person gives, with an example.
- Put the intent in the app target, where your API client already lives.

## Show each call's outcome

```swift
// Somewhere always on screen, so evaluations can read each call's outcome:
#if DEBUG
ToolOutcomeView()
#endif
```

From your API code, `ToolOutcomeLog.standard.note("served from cache")` adds detail to the recorded outcome. The view lists every call since the evaluation launched the app, so chained tools each show their own outcome.

## Common mistakes

| Mistake | Result |
|---|---|
| Plain `AppIntent` + `AppShortcutsProvider` instead of `@AppIntent(.tool)` | Not a Siri AI tool; no time budget or outcome record |
| Returning a dialog from a tool Siri should chain | Siri speaks it and ends the turn; the next tool never runs |
| Leaving the answer in the Spotlight index | Siri replies from stale indexed data; the tool never runs |
| No `ToolOutcomeView` | Evaluations can't tell what the tool did |

Prove it works with Siri Evaluations: **REQUIRED NEXT STEP:** use the siri-ai-eval skill.
