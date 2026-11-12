# Implementing Siri AI tools in an Expo app

This guide is for the people who own an app's code, and for the coding agents working for them. It starts where discovery ends: you have a `siri-tools.json` that lists which tools the app should have, from the `siri-ai-discover` skill or written by hand. It ends with each tool passing a Siri evaluation on a phone.

## The split

**The declaration is the interface.** Each entry gives Siri what it needs to choose and call a tool:

- `name`: the stable identifier evaluations check;
- `title`;
- `description`: what Siri reads to pick the tool;
- `parameters`: what Siri fills in from what the person said.

**The answer is your code.** Discovery doesn't decide how a tool gets its answer, and neither does this kit. Your app already knows which server to call and what's stored on the device. Your tool uses that.

Keep the interface the same whichever way you answer, because evaluations and Siri's choice depend on it. Changing a `name` breaks the evaluations; changing a `description` changes when Siri calls the tool.

## Where the code goes

Each tool has one handler file, named after the declaration's `javascript` value. When Siri calls a tool, its name leads straight to its file:

```
siri-tools.json                                the interface
src/siri-tools/
  unread-notifications.ts                      handler: turns your function into one sentence
  unread-notifications.test.ts                 what the sentence must be
  index.ts                                     registers every handler (once `defineSiriTool` ships)
src/features/notifications/api.ts              your existing code: getUnreadCount()
app-intents/GetUnreadNotificationsIntent.swift the Swift tool, until the `javascript` kind ships
```

- **The handler is thin.** It calls your existing function and words the result.
- **It calls plain functions, never hooks.** Siri can launch the app in the background, where no component renders, so `useNotifications()` isn't available. If the logic only exists inside a hook or a screen, move it into an exported function first; discovery's report marks those tools "needs extraction" and names the function.
- **Put `siri-tools/` in the source root,** never in `app/`, where Expo Router makes every file a route.
- **Discovery writes each handler as a stub that throws, with a failing test,** then offers to do the work: extract the functions, implement each handler until its test passes, and write the Swift tool that answers Siri today. Each job changes your code, so it asks first, and you can take any of them or none.

## Three ways to answer

| Way | Status | Your answer runs in | Use when |
|---|---|---|---|
| **Swift tool** in `app-intents/` | **Works today.** The example's cart tool passes 5 of 5 on a device. | Swift | Now, for any tool. |
| **`request` + `reply`** in the declaration | **Experimental** ([#8](https://github.com/airowe/syrup-ai-kit/pull/8), shipped in 0.3.0). A generated tool passed 5 of 5 on a device. | Generated Swift that makes one HTTP call | A public API at one fixed `https` host that needs no credentials. |
| **`javascript`** in the declaration | **Planned, not built.** | Your app's JavaScript | Once it ships: any tool, using your existing JS code. |

### Swift tool (works today)

Write the tool by hand with the same interface as its declaration entry:

```swift
// app-intents/GetUnreadNotificationsIntent.swift
import AppIntents
import SyrupAIKit

private let tool = SiriTool(appName: "Bluesky")

#if SIRI_AI_PREVIEW
@AppIntent(.tool)
#endif
struct GetUnreadNotificationsIntent: AppIntent {
  static let title: LocalizedStringResource = "Get Unread Notifications"
  static let description = IntentDescription("Says how many unread notifications the person has and who the latest ones are from.")

  func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
    let answer = await tool.answer { try await NotificationsClient.describeUnread() }
    return .result(value: answer, dialog: "\(answer)")
  }
}
```

- The type is the declaration's `name` plus `Intent`. `title` and `description` are copied word for word, and each declared parameter becomes a `@Parameter` with the same name and title.
- Swift can't call your JavaScript or read JS memory. It needs its own request code, and anything it reads (the server URL, ids) has to be shared from JS where Swift can read it, for example through App Group storage.
- `tool.answer` keeps to Siri's time budget (10 seconds by default), turns errors into sentences Siri can say ("Couldn't reach Bluesky right now."), and records the outcome for evaluations. The [SyrupAIKit README](../README.md) and the `siri-ai-tool` skill cover failures and Spotlight.

### `request` + `reply` (experimental)

When the tool is one HTTP call that the declaration can describe, replace the Swift with a `request` and a `reply` in the same entry. Prebuild then writes the Swift for you. The format and its limits are in [docs/spikes/tool-codegen.md](spikes/tool-codegen.md). Use it only when all of these hold:

- the host is fixed and `https`;
- the API needs no credentials;
- every field in the reply is always present in the response.

Generated tools send plain requests, and any non-2xx response is a failure.

Otherwise, write a Swift tool.

### `javascript` (planned)

The plan is in the [JS bridge spec](https://github.com/airowe/siri-ai-expo/pull/1). The entry names a handler:

```json
{ "name": "GetUnreadNotifications", "title": "Get Unread Notifications",
  "description": "Says how many unread notifications the person has and who the latest ones are from.",
  "parameters": [], "javascript": "unread-notifications" }
```

The handler lives in its own file and calls your existing code:

```ts
// src/siri-tools/unread-notifications.ts
import { getUnreadCount } from '../features/notifications/api'; // your existing code

export async function unreadNotifications(): Promise<string> {
  const { count, latestFrom } = await getUnreadCount();
  return count === 0 ? 'No unread notifications.' : `${count} unread, the latest from ${latestFrom.join(', ')}.`;
}
```

`index.ts` registers every handler, and your entry file imports it at the top level, so the handlers exist when Siri launches the app in the background:

```ts
// src/siri-tools/index.ts
import { defineSiriTool } from 'expo-syrup-ai-kit';
import { unreadNotifications } from './unread-notifications';

defineSiriTool('unread-notifications', unreadNotifications);
```

That works because the answer runs in your app's JavaScript, which already knows its hosts and storage. What it waits on:

1. Expo's `runBackgroundTask`. It's on Expo's `main` but in no released SDK, and is most likely coming in SDK 59.
2. Measuring cold-start time on a device, through Siri. On the Simulator, launch takes ~1.7 s and the JS answer 0.2–0.3 s more; device timing hasn't been measured.

Until it ships, the plugin rejects an entry with `javascript` as an unknown field. Write the tool in Swift with the same interface, and keep the declaration as its spec.

## What every tool must do, however it answers

- **Return only the value when Siri should chain the tool.** A spoken dialog ends Siri's turn. Tools an App Skill names declare `"returns": "value"`; in Swift that's `.result(value:)` without `ProvidesDialog`.
- **Answer in one spoken sentence.** For a list, give the count and at most three names. Keep it under about 200 characters, and leave out raw dates, HTML and ids.
- **Save tokens a locked phone can read.** Siri can run the tool while the phone is locked, so a tool that needs sign-in saves its tokens with `AfterFirstUnlock` or `AfterFirstUnlockThisDeviceOnly`. See [tools that need the person to be signed in](../README.md#tools-that-need-the-person-to-be-signed-in).
- **Fail in words.** Unreachable, timed out and failed each have a sentence (`ToolFailure` in Swift or JS).
- **Confirm before acting.** Siri must confirm any tool that changes something (posting, marking watched, buying) before it acts.
- **Finish within the timeout.** Siri stops waiting after 10 seconds. Work that must finish, like saving to a cache, can carry on after Siri stops waiting.
- **Keep the answer out of Spotlight.** If the app indexes the answer the tool gives, Siri answers from the index and never calls the tool. Index what identifies a record, not its live state.
- **Record the outcome.** Show `siri-ai-tool-outcome` in debug builds (see the plugin README), so evaluations can see what each call did.

## Prove it on a phone

For each tool, use the prompt and reply check from the discovery report. Discovery is an agent's proposal until a phone run says otherwise.

1. Five runs of the prompt naming the app. Check that Siri called the tool by `name`, and that the reply contains something only the person's live data has.
2. A negative control that breaks the tool with an `EvalSwitch` (for example, a host that can't be reached). The reply check must fail. That proves it reads your answer and doesn't just match text.
3. Optionally, the same question without the app's name. This is informational only. Until the phone has said yes to Siri's "from now on" prompt, Siri asks for consent and calls nothing. After one yes, it calls the tool every time.

Run them with the plugin's `evals` target and read the results with `syrup-ai-eval summarize --fail-on real`. The `siri-ai-eval` skill has the details.
