---
name: siri-ai-discover
description: Use when deciding which Siri AI tools an Expo or React Native app should have, when asked to find an app's primary actions for Siri, or when writing or reviewing the tool list in a siri-tools.json declaration for expo-siri-ai-kit's `tools` option.
license: MIT
---

# Discovering an app's Siri AI tools

## Overview

A Siri AI tool is something a person can ask Siri to do with the app: answer a question ("what's next up?") or do one action ("post this"). Discovery decides **which tools the app should have, what each one's interface is, and where each one's code goes**. Siri reads the interface: the name, the description, the parameters and what the answer says.

How a tool gets its answer is the app owners' decision. Their own code already knows how to sign in, which server to call, where tokens live and what is stored on the device. So never drop, demote or reshape a tool because of auth, hosts, tokens, storage or which endpoint it would call.

## The steps

1. **Find candidates** in the code.
2. **Draft a shortlist**, and check each candidate can run without a screen.
3. **Review it with the owner.** Stop and ask; don't write files yet.
4. **Write the outputs** for the tools the owner kept.

## 1. Find candidates

Read where people act and what they look at:

- the route files (`app/` or `src/app/`) and the tab bar;
- the main actions on each screen;
- the hooks, queries and stores behind them.

The app's own features are the candidates.

## 2. Draft a shortlist

Keep a candidate when both hold:

- **People would ask it by voice, without opening the app.** Their own live state ("how many unread", "what's next up", "is my order here") or one action ("post this", "add milk to my list").
- **The answer fits one spoken sentence.** For a list, say the count and at most three names.

Reject a candidate for one of these reasons only:

- **Too long to speak:** feeds, timelines, full lists.
- **Needs the app on screen:** playback, editing, browsing.
- **Settings or developer screens.**
- **Needs an id the person can't say:** "like that post". A tool may take a name the person can say ("play Dune").
- **Data that's gone when the app restarts:** plain component state such as `useState`. Data persisted on the device (MMKV, AsyncStorage, SQLite) is fine.
- **A mock or demo feature:** a fake login, sample data or a showroom screen. If no real person's data is behind it, there's nothing to ask about.

Rank by how often a person would want it. Mark write actions as needing confirmation. Draft three to five; every extra tool is another one Siri can pick by mistake.

### Can it run without a screen?

Siri can launch the app in the background, where no component renders. The tool's code can only call plain functions it imports, never a hook or a component. For each candidate, find the function that gets the data or does the action, and give it one status:

| Status | When | What goes in the report |
|---|---|---|
| **Callable** | A plain exported function does it (an API client call, a store action, a query function). | The function and its `file:line`. |
| **Needs extraction** | The logic lives only inside a hook or component (`useQuery` with an inline fetcher, a handler defined in a screen). | The hook's `file:line`, and the function to pull out of it, by name. |

A candidate whose data is only in memory was already rejected above.

**The signed-in session.** If the function takes a client, an agent or a token, the handler has to get one without React too. Find the app's own function that restores the session from storage (for example a `resumeSession` or `createSessionFromStoredAccount`), and record it with its `file:line`. If the session only exists in a React provider, mark the tool **needs extraction** and name that function too. Either way, how the session is restored stays the owners' code; you only point at it.

## 3. Review it with the owner

Show the owner the shortlist as one table: tool name, what a person says, what Siri answers, the function it calls, the session function if it needs one, and its status. Then ask, and wait for the answers:

1. **Which of these should Siri have?** They may drop, reorder or rename.
2. **For each action: is a spoken confirmation enough** before it runs, with the app closed? Drop any action they say no to.
3. **What do people ask for that isn't on a screen?** Add anything they name that the code supports, with the same checks.

If no owner can answer (you're running unattended), write the report with "Owner review: not done" at the top, and stop there: no `siri-tools.json`, no handler files.

## 4. Write the outputs

### `siri-tools.json`

One entry per kept tool, in the owner's order:

```json
{
  "name": "GetUnreadNotifications",
  "title": "Get Unread Notifications",
  "description": "Says how many unread notifications the person has and who the latest ones are from.",
  "parameters": [],
  "javascript": "unread-notifications"
}
```

- `name` is PascalCase, unique, and doesn't end in `Intent`. Evaluations use it to check which tool Siri called.
- `description` says what the tool returns, in the user's own words. Siri reads it to choose the tool.
- Each parameter has `name`, `type` and `title`. The type is one of `string`, `int`, `double`, `bool`, `date` or `enum` (with `cases`).
- `javascript` is the handler's name and its file name: `name` in kebab-case, dropping a leading `Get` (`GetUnreadNotifications` → `unread-notifications`, `PostMessage` → `post-message`). The handler function is the camelCase of the same words (`unreadNotifications`).

### One handler file per tool

Put a `siri-tools/` folder in the app's source root: `src/siri-tools/` when the app has `src/`, otherwise `siri-tools/` at the project root. Never inside `app/`, where Expo Router makes every file a route.

```
siri-tools.json
src/siri-tools/
  unread-notifications.ts         the handler
  unread-notifications.test.ts    its test (use the app's own test file pattern)
```

The handler turns the app's own function into one sentence. Sign-in, servers and tokens stay in the function it calls:

```ts
// src/siri-tools/unread-notifications.ts
import { getUnreadCount } from '../features/notifications/api';

export async function unreadNotifications(): Promise<string> {
  throw new Error('unread-notifications is not implemented');
}
```

The test describes the answer, and fails until the owners write the handler:

```ts
// src/siri-tools/unread-notifications.test.ts
import { getUnreadCount } from '../features/notifications/api';
import { unreadNotifications } from './unread-notifications';

jest.mock('../features/notifications/api');

it('says the unread count', async () => {
  jest.mocked(getUnreadCount).mockResolvedValue({ count: 3, latestFrom: ['Ana', 'Ben'] });
  await expect(unreadNotifications()).resolves.toBe('You have 3 unread notifications, the latest from Ana and Ben.');
});
```

- The stub imports the function the report names, and the session function if there is one. The test mocks both. For **needs extraction**, import the name the report says to extract; the import failing is how the owners see the extraction is the first job.
- A handler with parameters takes one object: `({ query }: { query: string })`.
- Don't edit the app's existing code. Extraction is the owners' change.

**Registering the handlers.** Check whether the installed `expo-siri-ai-kit` exports `defineSiriTool`. If it does, also write `src/siri-tools/index.ts`, which calls `defineSiriTool('<handler>', …)` for each handler, and say in the report that the app's entry file must import it at the top level. If it doesn't (true up to 0.2.0), write no `index.ts`: the plugin rejects the `javascript` kind today, and owners answer through a Swift tool in `app-intents/<name>Intent.swift` with the same interface until it ships.

### `siri-tools-report.md`

These parts, in this order:

1. **Owner review:** who answered and what they changed, or "not done".
2. **Tools.** One row per tool:
   - Tool: its `name`.
   - What a person says, naming the app ("In Bluesky, how many notifications do I have?").
   - What Siri answers, in one sentence. For an action, add that Siri confirms first.
   - Handler: the file under `siri-tools/`.
   - Calls: the function and its `file:line`.
   - Session: the function that restores the signed-in session outside React, with its `file:line`, or "none needed".
   - Status: callable, or needs extraction with the hook's `file:line` and the function to extract.
3. **Rejected.** Every candidate dropped, with its reason, including the owner's drops.
4. **Evaluations.** For each tool: a prompt that names the app, and what the reply must contain to prove the app answered (a value only the person's own data has, never generic text). The siri-ai-eval skill runs these.

## Check before handing over

- The owner answered, or the report says "not done" and no other files were written.
- Every tool has a handler file, a test, and a function with a `file:line`.
- Every function that takes a client, agent or token has a session function in the report.
- Every `javascript` value matches its file name.
- Every parameter appears in the spoken prompt, and nothing the prompt needs is missing.
- Two descriptions aren't easy to confuse.
- No existing app file changed.

## Common mistakes

| Mistake | Fix |
|---|---|
| Writing files before the owner answers | Show the shortlist and wait |
| Ranking by which endpoint is public or easy to call | Rank by what people would ask |
| Rejecting a tool because its token or host is hard to reach | Keep it; the handler calls the app's own code |
| Handler calls a hook (`useNotifications()`) | Call a plain function; if there isn't one, mark it needs extraction |
| Handler takes a client but nothing says where it comes from | Name the app's session-restore function; the stub imports it |
| Writing the handler's logic into the stub | The stub throws; the test says what the answer must be |
| Proposing features the app doesn't have | Every tool needs a function with a `file:line` |
| A tool that reads out a feed or a long list | The count and at most three names |
| Descriptions that say what the tool does, not what it returns | "Says how many unread notifications …", not "Handles notifications" |

**REQUIRED NEXT STEP:** once the owners have written a handler, prove the tool on a device with the siri-ai-eval skill.
