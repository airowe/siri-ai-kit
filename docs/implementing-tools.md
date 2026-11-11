# Implementing Siri AI tools in an Expo app

This guide is for the people who own an app's code, and for the coding agents working for them. It starts where discovery ends: you have a `siri-tools.json` that lists which tools the app should have, from the `siri-ai-discover` skill or written by hand. It ends with each tool passing a Siri evaluation on a phone.

## The split

**The declaration is the interface.** Each entry gives Siri what it needs to choose and call a tool:

- `name`: the stable identifier evaluations check;
- `title`;
- `description`: what Siri reads to pick the tool;
- `parameters`: what Siri fills in from what the person said.

**The answer is your code.** Discovery doesn't decide how a tool gets its answer, and neither does this kit. Your app already knows how to sign in, which server to call, where tokens live and what's stored on the device. Your tool uses that.

Keep the interface the same whichever way you answer, because evaluations and Siri's choice depend on it. Changing a `name` breaks the evaluations; changing a `description` changes when Siri calls the tool.

## Three ways to answer

| Way | Status | Your answer runs in | Use when |
|---|---|---|---|
| **Swift tool** in `app-intents/` | **Works today.** The example's cart tool passes 5 of 5 on a device. | Swift | Now, for any tool. |
| **`request` + `reply`** in the declaration | **Experimental** ([#8](https://github.com/airowe/siri-ai-kit/pull/8), not merged). A generated tool passed 5 of 5 on a device. | Generated Swift that makes one HTTP call | A public or long-lived-key API at one fixed `https` host, with no token refresh. |
| **`javascript`** in the declaration | **Planned, not built.** | Your app's JavaScript | Once it ships: any tool, using your existing JS code. |

### Swift tool (works today)

Write the tool by hand with the same interface as its declaration entry:

```swift
// app-intents/GetUnreadNotificationsIntent.swift
import AppIntents
import SiriAIKit

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
- Swift can't call your JavaScript or read JS memory. It needs its own request code, and anything it reads (tokens, the server URL, ids) has to be shared from JS where Swift can read it. For tokens, use the Keychain with `expo-secure-store`, `keychainAccessible: AFTER_FIRST_UNLOCK` and an explicit `keychainService`, so Siri can read it on a locked phone. For other values, use App Group storage.
- `tool.answer` keeps to Siri's time budget (10 seconds by default), turns errors into sentences Siri can say ("Open Bluesky to sign in again."), and records the outcome for evaluations. The [SiriAIKit README](../README.md) and the `siri-ai-tool` skill cover Keychain, Spotlight and token refresh.

### `request` + `reply` (experimental)

When the tool is one HTTP call that the declaration can describe, replace the Swift with a `request` and a `reply` in the same entry. Prebuild then writes the Swift for you. The format and its limits are in [docs/spikes/tool-codegen.md](spikes/tool-codegen.md). Use it only when all of these hold:

- the host is fixed and `https`;
- any token is in a Keychain item;
- there's no refresh;
- every field in the reply is always present in the response.

Otherwise, write a Swift tool.

### `javascript` (planned)

The plan is in the [JS bridge spec](https://github.com/airowe/siri-ai-expo/pull/1). The entry names a handler:

```json
{ "name": "GetUnreadNotifications", "title": "Get Unread Notifications",
  "description": "Says how many unread notifications the person has and who the latest ones are from.",
  "parameters": [], "javascript": "unread-notifications" }
```

The handler is defined at the top level of a module your entry file imports:

```ts
import { defineSiriTool, ToolFailure } from 'expo-siri-ai-kit';

defineSiriTool('unread-notifications', async ({ params, note }) => {
  const agent = await restoreSession();            // your existing session code
  if (!agent) throw new ToolFailure('signedOut');
  const { count, latest } = await getUnread(agent); // your existing query
  return count === 0 ? 'No unread notifications.' : `${count} unread, the latest from ${latest.join(', ')}.`;
});
```

That works because the answer runs in your app's JavaScript, which already handles auth, hosts and storage. What it waits on:

1. Expo's `runBackgroundTask`. It's on Expo's `main` but in no released SDK, and is most likely coming in SDK 59.
2. #8 merging.
3. Measuring cold-start time on a device, through Siri. On the Simulator, launch takes ~1.7 s and the JS answer 0.2–0.3 s more; device timing hasn't been measured.

Until it ships, the plugin rejects an entry with `javascript` as an unknown field. Write the tool in Swift with the same interface, and keep the declaration as its spec.

## What every tool must do, however it answers

- **Answer in one spoken sentence.** For a list, give the count and at most three names. Keep it under about 200 characters, and leave out raw dates, HTML and ids.
- **Fail in words.** Signed out, unreachable and timed out each have a sentence (`ToolFailure` in Swift or JS). Treat only "no credentials" or "credentials rejected" as signed out; any other storage or network error is its own failure.
- **Confirm before acting.** Siri must confirm any tool that changes something (posting, marking watched, buying) before it acts.
- **Finish within the timeout.** Siri stops waiting after 10 seconds. Work that must finish, like saving a refreshed token, can carry on after Siri stops waiting.
- **Keep the answer out of Spotlight.** If the app indexes the answer the tool gives, Siri answers from the index and never calls the tool. Index what identifies a record, not its live state.
- **Record the outcome.** Show `siri-ai-tool-outcome` in debug builds (see the plugin README), so evaluations can see what each call did.

## Prove it on a phone

For each tool, use the prompt and reply check from the discovery report. Discovery is an agent's proposal until a phone run says otherwise.

1. Five runs of the prompt naming the app. Check that Siri called the tool by `name`, and that the reply contains something only the person's live data has.
2. A negative control that breaks the tool with an `EvalSwitch` (signed out, wrong host). The reply check must fail. That proves it reads your answer and doesn't just match text.
3. Optionally, the same question without the app's name. This is informational only, because Siri asks the person for consent the first time.

Run them with the plugin's `evals` target and read the results with `siri-ai-eval summarize --fail-on real`. The `siri-ai-eval` skill has the details.
