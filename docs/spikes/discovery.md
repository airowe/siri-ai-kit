# Spike: discovering an app's Siri AI tools

**Question.** Can an agent read an Expo app and propose the Siri AI tools a person would choose?

**Answer: yes, with the `siri-ai-discover` skill, as long as it only decides the tools' interfaces.** Across three
apps, the skill matched the reference choices (written before any agent ran) for the top of each list. Without the
skill, and in an earlier version of it, agents let "can a generated HTTP call reach this?" drive the choice. They
dropped the tools people want most (Bluesky notifications and posting) for public lookups nobody asks Siri.

Skill: `expo-plugin/skills/siri-ai-discover/SKILL.md`. What owners do next: [implementing-tools.md](../implementing-tools.md).

## The decision this spike forced

How a tool gets its answer belongs to the app's owners, not to discovery. Their code already handles sign-in, hosts,
tokens and device storage. Discovery outputs the interface: `name`, `title`, `description`, `parameters`, and a
`javascript` handler name, plus the `file:line` where the app already has the feature and an evaluation prompt for
each tool. The answer is then a Swift tool (works today), the declaration's `request` + `reply` (experimental, #8), or
a JavaScript handler (planned, see the JS bridge spec).

## Method

1. I picked three open-source Expo apps of different shapes:
   - Bluesky (`bluesky-social/social-app`, Expo 58): signed-in social.
   - Streamyfin (`streamyfin/streamyfin`, Expo 58): a Jellyfin client.
   - The Ignite boilerplate demo (`infinitered/ignite`, Expo 55).
2. Before any agent ran, I wrote down the tools a person would choose for each.
3. One Sonnet agent per app ran each round:
   - a baseline with the declaration format and no skill;
   - v1, an API-checking version of the skill;
   - v3, the interface-only skill.
4. I read every output and checked v1's declarations with the validator and a live call.

## Reference choices

| App | A person would pick |
|---|---|
| Bluesky | 1. Unread notifications 2. Post (with confirmation) 3. Profile or post lookup |
| Streamyfin | 1. Continue watching / next up 2. Recently added 3. Search the library |
| Ignite | 1. Latest podcast episodes |

## Results

| App | Baseline (no skill) | v1 (API-checking skill) | v3 (interface-only skill) |
|---|---|---|---|
| Bluesky | Profile counts, latest post by handle, trends. **0 of the top 2.** One tool's reply read a field the response doesn't have, so it would fail on every call. | Ranked notifications, messages and posting first, but marked them "Not expressible". Declared only public trends. | **Notifications, unread messages, post (confirmed), own follower count.** Top 2 matched, each with `file:line`. |
| Streamyfin | Continue watching, next up, search (2 of 3), built around a placeholder server URL. | Next up, continue watching, recently added, all "Not expressible"; no declaration. | **Next up, continue watching, search, upcoming episodes, mark watched (confirmed).** 2 of 3 matched; recently added was cut to keep five. |
| Ignite | Latest episode, plus a 450-character list reply. | One tool, latest episodes. | Latest episode, find episodes by topic, and a "signed-in account" tool on a fake login. **Over-proposed**; the skill now rejects mock and demo features. |

What changed when discovery stopped judging implementation:

- **No more swapping in buildable but low-value tools.** Bluesky's public trends and profile lookups dropped out on
  their own.
- **Actions came back,** each marked for confirmation: Bluesky posting and Streamyfin's mark-watched.
- **Every tool cites the code** that already has the feature, which is where the owners' handler starts.
- **On thin apps, agents fill the list with weak tools.** The Ignite demo has one real candidate. The rule against
  mock and demo features was added after this run, and hasn't been rerun.

## What's not proven

- No tool from these apps ran on a device. Discovery is a proposal until an evaluation passes.
- Today's plugin rejects the `javascript` answer kind, which discovery writes ("unknown field"). Until the bridge
  ships, owners implement each entry as a Swift tool with the same interface.
- Whether Siri picks correctly among five tools is discovery step 3, which comes next.
