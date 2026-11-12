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
each tool. The answer is then a Swift tool (works today), the declaration's `request` + `reply` (experimental, shipped in 0.3.0 by #8), or
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

## v4: owner review and one handler file per tool

The skill now stops after the shortlist to ask the owner, and then writes one handler stub and one failing test per tool under `src/siri-tools/`. Each stub is named after its `javascript` value and imports the app function it should call. I reran it on Bluesky and answered as the owner.

- **It stopped and asked,** and wrote no files first. Its four candidates were unread notifications, unread messages, post, and follower count. It said it would drop follower count first.
- **It followed the owner's answers:** it dropped follower count and added "follow @handle" as a confirmed action.
- **Every tool says where its code goes:** a handler, a test, the function to call, and its status. Two tools are callable (`fetchUnreadCheckPage`, `post`). Two need extraction: `fetchUnreadCounts` from `useUnreadCountsQuery`, and `resolveDid` from `useFetchDid`.
- **It didn't change any existing app file.**
- **Gap found:** all four functions take a signed-in client, and nothing said where a handler gets one outside React. The skill now asks for the app's session-restore function; v5 reran it.
- **Tests not run:** the clone has no `node_modules`, and the app needs Node 24. See v5.

## v5: the tests run

I ran v4's stubs on Node 24 with the app's own Jest setup. One suite failed as intended. The other three never loaded: a bare `jest.mock(path)` loads the real module, and its imports reached a React Native native module (Worklets). The app's own tests mock with a factory and pass. The skill now requires factory mocks and the app's import style, and it runs the new tests before handing over.

Rerun on Bluesky, answering as the owner with the same choices as v4:

- **It named the session restore:** `createSessionBundleAndResume` from the stored account in persisted storage. The owner confirmed it.
- **All six tests fail on the stubs' "not implemented" error,** not on loading.
- **The typecheck flags both extractions** (`fetchUnreadCounts`, `fetchProfile`) as missing exports, as intended.
- **Positive control:** I implemented `unread-notifications` the way an owner would. Its test needed one change: it mocked `persisted.get` but not `persisted.init`, which has to run first. After that, both tests passed. The skill now records every call in the session restore, in order, so tests mock all of them.
- **Left to owners:** the stored account's type doesn't match what `createSessionBundleAndResume` takes, and posting needs its own `QueryClient` outside React.

## After v5: auth taken back out

The v4 and v5 session rules asked discovery to find how the app restores a signed-in session and to mock it in each test. That pulled authentication back into discovery, which the owner decided it shouldn't handle. The rules are removed. A stub now imports and mocks only the app function it calls. If that function needs something the handler doesn't have, such as a client, the agent asks the owner instead of working it out.

## v6: sweeping the data layer

Step 1 used to start from the screens and reach the data layer only by tracing back from them. Now it also lists every read and write the app's data libraries define, merges that with the screens, and notes where each candidate came from. `data-layers.md` says where each library keeps its definitions and when one can run without React.

The test app is Enatega's customer app (`enatega/food-delivery-multivendor`, Expo 53). It uses Apollo, axios and Zustand, and React Navigation rather than Expo Router. Both versions of the skill ran to the owner review, at the same time.

| | Baseline (`main` skill) | With the sweep |
|---|---|---|
| Candidates considered | About 25, most from screens | About 100, every query, mutation and subscription |
| Shortlist | Active order status, last order, cart summary, cancel order | The same four, plus "is this restaurant open?" |
| Held back for the owner | Reorder, cost of the last order, rider's name | Wallet credit and free deliveries, which only exist in the single-vendor mode |
| Dead code found | None | `restaurantList`, `myOrders`, `GET_ESTIMATED_DELIVERY_TIME` |
| Plain helpers it reused | None | `calulateRemainingTime`, `isOpen` |
| Callable or extraction | All needs extraction: the Apollo client is only built inside `App.js` | The same, citing `data-layers.md`'s rule "client only created inside a provider" |
| Asked about credentials | **Yes:** where the token comes from in the background | No: it asked only where the shared client comes from, and said it wouldn't design it |

What it shows:

- The top of the list didn't change: on this app, screens already reach the most-asked reads.
- The sweep found more possible tools, rejected most data-layer definitions quickly, and flagged dead code that a screen-only read can't see.
- The baseline asked the owner about tokens. The skill now says every owner question is about what Siri should do, and that credentials are already in the code the tool calls.
- "Is this restaurant open?" depends on matching a restaurant by name on a query with no name filter. The agent flagged that for the owner, which is right.
- Not run: steps 4 and 5. The credentials wording hasn't been rerun either.

## v7: the full flow, and a React Query app

**Enatega, steps 1 to 5,** with me answering as the owner. Enatega is plain JavaScript on Expo 53, with no test runner.

- **Owner questions stayed on Siri's behaviour,** such as which of the app's modes a tool covers. There were no credential questions in steps 1 to 3.
- **Step 4** wrote three stubs and tests for order status, last order and cancel order. It couldn't run the tests, and it said so.
- **Step 5A (extract)** moved the Apollo client out of `App.js` into an exported registry, and added `fetchActiveOrders`, `fetchPastOrders`, `abortOrder` and `fetchConfiguration`. The hooks keep their own `useQuery` but share the variables and filters, and the agent said so.
- **Step 5B (handlers)** kept every expected answer, added only mocks plus two cases for the owner's cancel rule, and asked the owner for the cancel rule and the currency format rather than choosing them.
- **Nothing ran:** no test runner, no `node_modules`, so no lint either. The agent checked the new files parse with `node --check`. I tried to install dependencies only to verify. Auto mode blocked it, because with no lockfile the install pulls unpinned packages.
- **Gap found:** it offered step 5C (Swift tools) on Expo 53, which can't use `expo-app-intents`. In 5C it also asked where the token and host come from, which it should, since Swift can't call the app's JavaScript.

**`jgalat/remote-app`, steps 1 to 3.** It's a Transmission remote on Expo 57, using TanStack Query over a hand-written client.

- **All five tools are callable through `createClient(server)`:** transfer status, what's downloading, progress by name, speed mode, and pause by name. The app's own background notifier already uses that client without React, which the agent cited.
- **Every candidate was tagged by source.** It flagged `queueMove*` as possibly dead code, and used the mock client as a rejection reason.
- **Gap found, the same as Enatega's:** the app is Android-first and on Expo 57, and nothing in the skill checks either.

**Fixes:**

- A new "Before you start" check covers iOS, Expo SDK 58 or later, and a test runner.
- Step 5C is offered only when the first two hold.
- Step 5B says when a handler can't be verified.
- `data-layers.md` explains extraction for Apollo hooks.

These fixes haven't been rerun.

## v8: the owner's own apps, and Enatega's tests running

Three of the owner's apps ran steps 1 to 3 in parallel, read-only, each through a separate agent. A `git status` afterwards showed every repo unchanged.

**The "Before you start" checks worked on all three.** Each ships on iOS, each is on Expo 54, so none was offered step 5C, and each has a test runner.

- **lazy-shopper** (Jest): five callable tools over plain functions in `lib/`. It flagged the catalog data as stale, with offers dated 2026-05-17. It asked no credential questions.
- **clearcost** (Vitest, tRPC): four tools: procedure price, nearby care, saved procedure prices, and hospital in network. All four need extraction, because the app only has `createTRPCReact` hooks and its `QueryClient` is created inside a component. The report named the vanilla client to add, which is what `data-layers.md` says for tRPC. 30 tRPC procedures were rejected as dead code, each with its `file:line`. One gap: the stub template uses `jest.mock`, and Vitest needs `vi.mock`.
- **heathen** (Jest, no server): five callable tools over AsyncStorage functions, including two write actions marked for confirmation. It rejected the React Query client as dead code, since nothing calls it, and rejected "log a session" because a logged session inflates streaks the app only grants after real playback.

**Enatega's tests ran** after installing its dependencies: 9 of 10 passed. The one failure was a stale expectation, not a handler bug:

- The stub's test expected `for 24.50`. In step 5B the owner chose to show the currency symbol, and the handler correctly said `$24.50`. The rule "never change what the answer must be" kept the old text.
- The test also depended on the timezone. Its dates were UTC strings, so in Auckland the answer said Wednesday. Setting `process.env.TZ` in the test file did not help, because Node has already read the timezone by then.

After the expected answer followed the owner's decision and the fixtures were built in local time, all 10 tests passed in UTC, Los Angeles, Auckland, Kiritimati (UTC+14) and Pago Pago (UTC−11).

**Fixes:**

- The test-runner check includes Vitest, and stubs use that runner's mocking.
- Tests that involve dates freeze the clock and build their dates in local time.
- In step 5B, an expected answer may change only to follow an owner's decision about how something is said, and the summary must say so.

## What's not proven

- No tool from these apps ran on a device. Discovery is a proposal until an evaluation passes.
- Today's plugin rejects the `javascript` answer kind, which discovery writes ("unknown field"). Until the bridge
  ships, owners implement each entry as a Swift tool with the same interface.
- Whether Siri picks correctly among five tools is discovery step 3, which comes next.
