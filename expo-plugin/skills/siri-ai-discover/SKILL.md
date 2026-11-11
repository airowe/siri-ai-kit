---
name: siri-ai-discover
description: Use when deciding which Siri AI tools an Expo or React Native app should have, when asked to find an app's primary actions for Siri, or when writing or reviewing the tool list in a siri-tools.json declaration for expo-siri-ai-kit's `tools` option.
license: MIT
---

# Discovering an app's Siri AI tools

## Overview

A Siri AI tool is something a person can ask Siri to do with the app: answer a question ("what's next up?") or do one action ("post this"). Discovery decides **which tools the app should have and what each one's interface is**. Siri reads the interface: the name, the description, the parameters and what the answer says.

How a tool gets its answer is the app owners' decision, and it isn't part of discovery. Their own code already knows how to sign in, which server to call, where tokens live and what is stored on the device. So never drop, demote or reshape a tool because of auth, hosts, tokens, storage or which endpoint it would call.

## What you produce

### `siri-tools.json`

One entry per tool, ranked by value, using the declaration's interface fields:

```json
{
  "name": "GetUnreadNotifications",
  "title": "Get Unread Notifications",
  "description": "Says how many unread notifications the person has and who the latest ones are from.",
  "parameters": [],
  "javascript": "unread-notifications"
}
```

- `name` is the stable identifier evaluations use to check which tool Siri called. `title` is required by every App Intent.
- `description` is what Siri reads to choose the tool. Say what the tool returns, in the user's own words.
- Each parameter has `name`, `type` and `title`. The type is one of `string`, `int`, `double`, `bool`, `date` or `enum` (with `cases`).
- `javascript` names the handler the owners will write, so the answer comes from the app's own code. If the owners already use another answer kind (`request` plus `reply`, or a hand-written Swift tool), leave that choice to them.

### `siri-tools-report.md`

These parts, in this order:

1. **Tools, ranked.** One row per tool with:
   - Tool: its `name`.
   - What a person says, naming the app ("In Bluesky, how many notifications do I have?").
   - What Siri answers, in one sentence. For an action, add that Siri confirms before it acts.
   - Where it lives in the app: the `file:line` of the hook, store or function that already gets this data or does this action. This is where the owners' handler starts.
2. **Rejected.** Every candidate you dropped, with one reason from the list in "Choose tools".
3. **Evaluations.** For each tool:
   - a prompt that names the app;
   - what the reply must contain to prove the app answered: a value only the person's own data has, never generic text. The siri-ai-eval skill runs these.

## Find candidates

Read where people act and what they look at:

- the route files (`app/` or `src/app/`) and the tab bar;
- the main actions on each screen;
- the hooks, queries and stores behind them.

The app's own features are the candidates.

## Choose tools

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

Rank by how often a person would want it, and put the most-used first. Mark write actions as needing confirmation and rank them like the rest. Keep it to the few strongest tools: three to five is plenty for a first release, and every extra tool is another one Siri can pick by mistake.

## Check before handing over

- The `name`s are unique PascalCase, and none ends in `Intent`.
- Every `description` says what comes back. Two descriptions must not be easy to confuse.
- Every parameter appears in the spoken prompt, and nothing the prompt needs is missing as a parameter.
- Every tool has a `file:line`. Without one, the app doesn't have the feature: reject it.

## Common mistakes

| Mistake | Fix |
|---|---|
| Ranking by which endpoint is public or easy to call | Rank by what people would ask; how the tool answers is the owners' decision |
| Rejecting a tool because its token, host or data is hard to reach from native code | Keep it; the owners' handler runs in the app's own code |
| Proposing features the app doesn't have | Every tool needs a `file:line` in the app |
| A tool that reads out a feed or a long list | The count and at most three names |
| Descriptions that say what the tool does, not what it returns | "Says how many unread notifications …", not "Handles notifications" |
| A dozen tools | Three to five of the strongest |

The `javascript` answer kind is planned and not built yet, so today's plugin rejects these entries. Say so in the report. Until it ships, owners implement each entry as a Swift tool with the same interface; the expo-siri-ai-kit skill and `docs/implementing-tools.md` cover how.

**REQUIRED NEXT STEP:** prove each tool on a device with the siri-ai-eval skill, once the owners have written its handler.
