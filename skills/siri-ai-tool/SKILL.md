---
name: siri-ai-tool
description: Use when adding, changing or debugging a Siri AI tool (`@AppIntent(.tool)`) in an iOS app, or when a request says people should ask Siri for live app data such as an order, cart, balance or booking. Also use when Siri says to sign in while the phone is locked, answers with stale data, or never seems to call the app.
license: MIT
---

# Siri AI tools with SiriAIKit

## Overview

A Siri AI tool is an App Intent marked `@AppIntent(.tool)` (Siri AI Developer Preview, iOS 27.3 SDK). Siri decides when to call it and waits for it. SiriAIKit (`https://github.com/airowe/siri-ai-kit`) wraps your existing API call so the tool keeps to Siri's time budget, turns errors into sentences Siri can say, and records what each call did.

A plain `AppIntent` plus an `AppShortcutsProvider` is the older Shortcuts path. It is not a Siri AI tool and does not get these guarantees.

## Before writing the tool, check the app

Each of these breaks a tool on a real phone, even when the code compiles. Fix them in the same change.

| Check | Where | Fix |
|---|---|---|
| Tokens readable on a locked phone | Keychain writes (`kSecAttrAccessible`, or the secure-storage library's default) | Save with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Re-save existing items at launch. Never "fix" this with `authenticationPolicy = .requiresLocalDeviceAuthentication`: Siri then cannot answer while locked. |
| Keychain read errors are not "signed out" | Token loading | Only `errSecItemNotFound` means signed out. Throw other statuses as their own error. |
| The answer is not in Spotlight | `CSSearchableItem`, `IndexedEntity`, `@Property(indexingKey:)` | Index what identifies a record (id, name, synonyms). Remove the answer the tool exists to give (status, total, balance, dates). Otherwise Siri answers from the index and never calls the tool. |
| Expired tokens refresh once | The API client's 401 path | Refresh at most once per call, save new tokens before use, one refresh at a time app-wide, and only a rejected refresh (400/401/403) means signed out. See `references/token-refresh.md`. |

Report each problem you find, even when you can't fix it yet (for example, no refresh endpoint exists).

## The tool

```swift
import AppIntents
import SiriAIKit

private let tool = SiriTool(appName: "ParcelPal") { error in
    (error as? ShopAPIError) == .unauthorized ? .signedOut : nil   // nil: use the default rules
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

- `answer` returns your sentence, or the failure sentence ("Open ParcelPal to sign in again.", "Couldn't reach ParcelPal right now.", "ParcelPal couldn't do that right now."). Use `run` when you need the value; it throws `ToolFailure` (`.signedOut`, `.timedOut`, `.unreachable`, `.failed`) and `failure.reply(appName:)` gives the sentence.
- `classify` maps your errors. If your networking library wraps `URLError`, unwrap it there, or network failures count as `.failed`.
- The default timeout is 10 seconds (`timeout:`). The tool stops waiting but your code keeps running, so token saves still finish.
- Siri speaks the reply, so keep it to a sentence or two. With several records, say the most relevant one and how many others there are.
- The `description` is what Siri reads to choose the tool. Say what it returns, in the user's words.
- Put the intent in the app target, where your API client and Keychain items already live.

## Wire up the debug helpers

```swift
// At launch:
#if DEBUG
KeychainLockCheck.warnIfLockedOut(service: "com.example.parcelpal.auth")
#endif

// Somewhere always on screen, so evaluations can read each call's outcome:
#if DEBUG
ToolOutcomeView()
#endif
```

From your API code, `ToolOutcomeLog.standard.note("refreshed after 401")` adds detail to the recorded outcome.

## Common mistakes

| Mistake | Result |
|---|---|
| Plain `AppIntent` + `AppShortcutsProvider` instead of `@AppIntent(.tool)` | Not a Siri AI tool; no time budget or outcome record |
| Requiring device unlock instead of changing Keychain accessibility | Siri asks to unlock, or fails, every time the phone is locked |
| Leaving the answer in the Spotlight index | Siri replies from stale indexed data; the tool never runs |
| Every Keychain or refresh failure mapped to `.signedOut` | Siri tells signed-in people to sign in again |
| No `ToolOutcomeView` | Evaluations can't tell what the tool did |

Prove it works with Siri Evaluations: **REQUIRED NEXT STEP:** use the siri-ai-eval skill.
