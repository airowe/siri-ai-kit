---
name: siri-ai-discover
description: Use when deciding which Siri AI tools an app should have (Expo, React Native or native iOS), when asked to find an app's primary actions for Siri, when writing or reviewing the tool list in a siri-tools.json declaration for expo-siri-ai-kit's `tools` option, or when drafting Apple App Skills for requests that need several of the app's tools.
license: MIT
---

# Discovering an app's Siri AI tools

## Overview

A Siri AI tool is something a person can ask Siri to do with the app: answer a question ("what's next up?") or do one action ("post this"). Discovery decides **which tools the app should have, what each one's interface is, and where each one's code goes**. Siri reads the interface: the name, the description, the parameters and what the answer says.

How a tool gets its answer is the app owners' decision. Their own code already knows which server to call and what is stored on the device. So never drop, demote or reshape a tool because of hosts, storage or which endpoint it would call.

## The steps

1. **Find candidates** in the code.
2. **Draft a shortlist**, check each candidate can run without a screen, and spot requests that need several tools (App Skills).
3. **Review it with the owner.** Stop and ask; don't write files yet.
4. **Write the outputs** for the tools the owner kept.
5. **Offer to implement them:** the extractions, the handlers, and a Swift tool that answers Siri today.

## Before you start

Check three things and put them at the top of the report. None of them stops discovery, but they decide what step 5 can offer.

| Check | Where | If it fails |
|---|---|---|
| The app ships on iOS | `app.json` / `app.config.*` has an `ios` section, and nothing says the app is Android-only | Say so: Siri tools are iOS-only, so the owner should decide whether to continue. |
| Expo SDK 58 or later | the `expo` version in `package.json` | Swift tools need `expo-app-intents`, which needs SDK 58. Don't offer step 5C; say upgrading is the owner's call. |
| A test runner | `jest`, `jest-expo` or `vitest` in `package.json`, or the app's own test files. Write the stubs' tests for the runner the app uses: `vi.mock` and `vi.mocked` under vitest. | The stubs' tests can't run. Say so in the report and in the step 5B offer. Adding a test runner is a dependency change: offer it, never install it yourself. |

## 1. Find candidates

Make two lists, then merge them.

**From the screens:** where people act and what they look at.

- the route files (`app/` or `src/app/`) and the tab bar;
- the main actions on each screen;
- the hooks, queries and stores behind them.

**From the data layer:** every read and write the app defines, whether or not a screen uses it. Find the data libraries in `package.json` (React Query, RTK Query, SWR, Apollo, tRPC, generated OpenAPI clients, hand-written API modules, Zustand or Redux), then list their definitions. Reads are candidate questions, and writes are candidate actions. `data-layers.md`, next to this skill, says where each library keeps its definitions.

Merge the two lists and note where each candidate came from: `screen`, `data layer` or `both`. The app's own features are the candidates.

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
| **Callable** | A plain exported function does it (an API client call, a store action, a query function), or the library can run the definition outside React (`queryClient.fetchQuery(options)`, `store.dispatch(api.endpoints.x.initiate())`). | The function or exact call, and its `file:line`. |
| **Needs extraction** | The logic lives only inside a hook or component (`useQuery` with an inline fetcher, a handler defined in a screen). | The hook's `file:line`, and the function to pull out of it, by name. |

A candidate whose data is only in memory was already rejected above. `data-layers.md` lists, for each library, what makes a definition callable and what needs extraction.

### Requests that need several tools: App Skills

An Apple App Skill is a short Markdown guide, one `SKILL.md`, that tells Siri how to combine the app's tools for one kind of request: "add oat milk and eggs and check out" is a search, then add to cart for each item, then place the order. Siri reads it as guidance; it doesn't guarantee the order of the steps.

Propose an App Skill only when all of these hold:

- **People ask for it in one breath.** Several tools in a row, for one request.
- **Every step is a tool on the shortlist.** If a step needs a tool the app lacks, or a tool's answer leaves out what the next step needs (a spoken answer that says "and 9 more"), don't draft the skill. List it as a gap with the tool change it would need; that change is the owner's call.
- **A single tool doesn't already answer it.** One question or one action needs no skill.

Draft at most two or three. A skill for every pair of tools is noise Siri has to read.


## 3. Review it with the owner

Show the owner the shortlist as one table: tool name, what a person says, what Siri answers, the function it calls, and its status. Then ask, and wait for the answers:

1. **Which of these should Siri have?** They may drop, reorder or rename.
2. **For each action: is a spoken confirmation enough** before it runs, with the app closed? Drop any action they say no to.
3. **What do people ask for that isn't on a screen?** Add anything they name that the code supports, with the same checks.
4. **Which App Skills should Siri have?** Show each proposed skill as the request it covers and the tools it calls, in order, plus the gaps. Drop any skill whose tools they dropped.

You may add questions about what a tool should cover, such as which of the app's modes or accounts it answers for. Every question is about what Siri should do. How the app reaches its server is already in the code the tool calls.

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
- Each parameter has `name`, `type`, `title` and `description`. The type is one of `string`, `int`, `double`, `bool`, `date` or `enum` (with `cases`). The `description` is one line saying what the person gives, with an example value: "The product to add, as the person names it, like 'oat milk'." Siri reads it to fill the parameter from what was said.
- `javascript` is the handler's name and its file name: `name` in kebab-case, dropping a leading `Get` (`GetUnreadNotifications` → `unread-notifications`, `PostMessage` → `post-message`). The handler function is the camelCase of the same words (`unreadNotifications`).

### One handler file per tool

Put a `siri-tools/` folder in the app's source root: `src/siri-tools/` when the app has `src/`, otherwise `siri-tools/` at the project root. Never inside `app/`, where Expo Router makes every file a route.

```
siri-tools.json
src/siri-tools/
  unread-notifications.ts         the handler
  unread-notifications.test.ts    its test (use the app's own test file pattern)
```

The handler just calls the app's own function and turns the result into one sentence:

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

jest.mock('../features/notifications/api', () => ({ getUnreadCount: jest.fn() }));

it('says the unread count', async () => {
  jest.mocked(getUnreadCount).mockResolvedValue({ count: 3, latestFrom: ['Ana', 'Ben'] });
  await expect(unreadNotifications()).resolves.toBe('You have 3 unread notifications, the latest from Ana and Ben.');
});
```

- The stub imports the function the report names. The test mocks it.
- **Mock with a factory** that lists the functions, as above, never a bare `jest.mock(path)`. A bare mock loads the real module and everything it imports, which in a React Native app reaches native modules and fails before any test runs. Use the import style (relative or the app's alias, such as `#/`) and mocking style of the app's own tests.
- For **needs extraction**, import the name the report says to extract. The typecheck failing on that import is how the owners see the extraction is the first job.
- **Dates in a test:** freeze the clock (`jest.useFakeTimers().setSystemTime(...)`) and build every date in local time (`new Date(2025, 2, 4, 12)`), never as a UTC string. An answer that says a weekday or a time is read in the phone's timezone, so a UTC fixture names a different day east or west of UTC. Setting `process.env.TZ` inside a test file is too late to fix this.
- A handler with parameters takes one object: `({ query }: { query: string })`.
- Don't edit the app's existing code. Extraction is the owners' change.

**Registering the handlers.** Check whether the installed `expo-siri-ai-kit` exports `defineSiriTool`. If it does, also write `src/siri-tools/index.ts`, which calls `defineSiriTool('<handler>', …)` for each handler, and say in the report that the app's entry file must import it at the top level. If it doesn't (true up to 0.2.0), write no `index.ts`: the plugin rejects the `javascript` kind today, and owners answer through a Swift tool in `app-intents/<name>Intent.swift` with the same interface until it ships.

### App Skills

One folder per kept skill, in `siri-skills/` at the project root:

```
siri-skills/
  fill-cart/
    SKILL.md
```

```markdown
---
name: fill-cart
description: Use when the person asks Basket to add groceries by name or kind, and optionally to check out afterwards.
---
1. For each item, call SearchProducts with the item as the person said it. If several match and the person gave no rule ("the cheapest"), say at most three names and ask which one.
2. Call AddToCart with the chosen product and quantity. It confirms first; skip the item if the person says no.
3. Call PlaceOrder only if the person asked to check out in this request. It confirms first.

Never add a product SearchProducts didn't return.
```

The plugin's `skills` option compiles this folder into the app, and stops prebuild if a skill breaks Apple's rules, so write it to pass them:

- The frontmatter has only `name` and `description`. No `version`, `tools` or any other field.
- `name` is 1 to 64 lowercase letters, digits and single hyphens, and is the folder's name.
- `description` is one line of at most 1,024 characters, saying which requests the skill is for.
- The body is at most 10,000 characters. Name tools by their `name` from `siri-tools.json`, give the steps in order, and say where each action confirms and what to do when a step finds nothing.
- The folder holds only `SKILL.md`. No notes, examples or references.

Turning the option on means adding `"skills": { "sourceDir": "siri-skills" }` to the plugin in `app.json`, an existing file. Don't edit it now: the report says it's needed, and step 5 offers it.

### `siri-tools-report.md`

These parts, in this order:

1. **Owner review:** who answered and what they changed, or "not done".
2. **Tools.** One row per tool:
   - Tool: its `name`.
   - What a person says, naming the app ("In Bluesky, how many notifications do I have?").
   - What Siri answers, in one sentence. For an action, add that Siri confirms first.
   - Handler: the file under `siri-tools/`.
   - Calls: the function and its `file:line`.
   - Status: callable, or needs extraction with the hook's `file:line` and the function to extract.
   - Found from: `screen`, `data layer` or `both`.
3. **Rejected.** Every candidate dropped, with its reason, including the owner's drops. Data-layer candidates can be grouped ("12 paged feed queries: too long to speak"), as long as each group names its definitions.
4. **App Skills.** One row per skill: its folder, the request it covers, and the tools it calls in order. Then the gaps: requests that would need a skill the tools can't support yet, with the tool change each needs. Say that `app.json` needs the `skills` option, or write "none" when no skill was kept.
5. **Evaluations.** For each tool: a prompt that names the app, and what the reply must contain to prove the app answered (a value only the person's own data has, never generic text). For each App Skill, a prompt for the whole request, and what the reply must contain from the last step (the order total, not just "done"). The siri-ai-eval skill runs these.

## Check before handing over

These hold at the end of step 4, before you offer step 5.

- The owner answered, or the report says "not done" and no other files were written.
- Every tool has a handler file, a test, and a function with a `file:line`.
- Every `javascript` value matches its file name.
- Every parameter appears in the spoken prompt, and nothing the prompt needs is missing.
- Every parameter has a one-line `description` with an example value.
- Two descriptions aren't easy to confuse.
- Every App Skill's steps name only tools in `siri-tools.json`, its `name` matches its folder, and its frontmatter has only `name` and `description`.
- No existing app file changed, `app.json` included.
- You ran the new tests with the app's own test command. Each test fails on the stub's "not implemented" error, not on loading the test. If the tests can't run (no `node_modules`, wrong Node version), say so in the report; never install anything to make them run.

## Common mistakes

| Mistake | Fix |
|---|---|
| Writing files before the owner answers | Show the shortlist and wait |
| Ranking by which endpoint is public or easy to call | Rank by what people would ask |
| Rejecting a tool because its host is hard to reach | Keep it; the handler calls the app's own code |
| Handler calls a hook (`useNotifications()`) | Call a plain function; if there isn't one, mark it needs extraction |
| `jest.mock(path)` without a factory | List the mocked functions in a factory, so the test doesn't load native modules |
| Extracting functions or writing handlers without asking | Offer each job in step 5 and wait for a yes |
| Changing a test's expected answer to make it pass | Fix the handler; only add mocks the stub didn't list. Change the answer only to follow an owner's decision, and say so |
| A test that passes in one timezone only | Freeze the clock and build dates in local time |
| Writing the handler's logic into the stub | The stub throws; the test says what the answer must be |
| Only reading screens, so calls no screen reaches are never seen | Sweep the data layer too, and merge the lists |
| Keeping every query and mutation the sweep finds | They go through the same shortlist rules; most are feeds, ids or plumbing |
| Proposing features the app doesn't have | Every tool needs a function with a `file:line` |
| A tool that reads out a feed or a long list | The count and at most three names |
| An App Skill that calls a tool the app doesn't have | Every step is a shortlisted tool; list the rest as gaps for the owner |
| An App Skill for a request one tool answers | Only requests that need several tools in a row |
| Extra frontmatter fields or files in a skill folder | Only `name` and `description`, and only `SKILL.md`; prebuild rejects the rest |
| Descriptions that say what the tool does, not what it returns | "Says how many unread notifications …", not "Handles notifications" |

## 5. Offer to implement them

Steps 1 to 4 never change the app's code. Step 5 does, so offer each job and wait for the owner's yes. They may take all, some or none, per tool. If no owner can answer, don't offer: the report already lists the work.

Do the jobs in this order, because each builds on the one before. If App Skills were kept, also offer to add the plugin's `skills` option to `app.json`; it needs nothing from the other jobs.

### A. Extract the functions

For each tool marked **needs extraction**, move the logic out of the hook into the exported function the report names, and make the hook call that function, so the screen behaves exactly as before. Then run the app's own typecheck and its existing tests: they must pass as they did before, and the handler's missing-import error must be gone.

### B. Implement the handlers

The stub's test is already failing. Write the handler until it passes: call the app's function and word the answer as one sentence. If that function needs an argument the handler doesn't have, ask the owner where it comes from; don't design it. Change the test only to mock a call the handler needs that the stub didn't list, and say so in your summary. Never change what the answer must be to make a test pass. The one exception is when the owner, during this job, decides how something is said, such as a currency symbol or a date format: update the expected answer to match their decision, and say so in your summary. Then run the app's lint and typecheck.

If the tests can't run (no test runner, no `node_modules`), say so when you offer this job: the handler will be written but not verified. Report what you did check, such as `node --check`, and don't call the handler done.

### C. Write the Swift tool

Offer this only when the app ships on iOS and is on Expo SDK 58 or later (see "Before you start"). Swift can't call JavaScript until the `javascript` kind ships, so the Swift tool is what answers Siri today. For each tool, write `app-intents/<name>Intent.swift`, following the expo-siri-ai-kit skill, with:

- the same `title` and `description`, word for word, and one `@Parameter(title:description:)` per declared parameter, with its `title` and `description` word for word;
- the same answer as the handler: the same sentence for the same data, and failures through `SiriTool`'s `ToolFailure` cases. Where the Swift needs something only the owners can provide, ask them; don't design it;
- an evaluation for each prompt in the report, following the siri-ai-eval skill, in the folder the plugin's `evals.sourceDir` names. If the app has no `expo-siri-ai-kit` plugin or no `evals` option yet, adding them is an `app.json` change: ask first.

Prebuild and build to check the Swift compiles. Running the evaluations needs the owner's phone, so stop and ask for it.

**REQUIRED NEXT STEP:** prove each tool on a device with the siri-ai-eval skill.
