# Spike: generating Siri AI tools from a declaration

**Question.** Can an Expo app get Siri AI tools from a small declaration at prebuild, so nobody writes Swift?

**Answer: yes, on a phone too, for String and Int parameters.** See [Device run](#device-run) for the evaluation. The `expo-syrup-ai-kit` plugin now takes a `tools` option. It reads a JSON
declaration, validates it, and writes one Swift tool per entry into the app target at prebuild. The generated Swift
type-checks against the iOS 27.3 SDK and the real SyrupAIKit sources in Swift 5 and Swift 6 modes. It also builds in a
full `xcodebuild`, where Xcode's App Intents metadata step records each tool with the same `ToolIntent` system
protocol as the hand-written `GetCartIntent`, which passes 5/5 on device. A generated tool has now passed
5/5 on a phone as well.

Code: `expo-plugin/plugin/src/siriTools/` (parser and generator) and `expo-plugin/plugin/src/withSiriTools.ts`
(prebuild wiring). The sample declaration and its approved Swift are in
`expo-plugin/plugin/src/__tests__/fixtures/siri-tools/`. `expo-plugin/scripts/generate-siri-tools.js` writes the Swift for
any declaration without an Expo project (with no arguments it refreshes the approved sample), and
`expo-plugin/scripts/typecheck-siri-tools.sh` type-checks it.

## Why a declaration has to be compiled at all

Siri reads tools from `Metadata.appintents`, which Xcode extracts from Swift at build time. Tools can't be added at
runtime, and released Expo can't answer an intent from JavaScript, so a generated tool calls the app's HTTP API from
Swift and turns the JSON reply into a sentence.

## The format

```json
{
  "appName": "Siri Spike",
  "tools": [
    {
      "name": "BookTrip",
      "title": "Book Trip",
      "description": "Books a hotel stay for the signed-in person and says the booking number and total price.",
      "parameters": [
        { "name": "city", "type": "string", "title": "City" },
        { "name": "nights", "type": "int", "title": "Nights" },
        { "name": "budget", "type": "double", "title": "Nightly Budget" },
        { "name": "refundable", "type": "bool", "title": "Refundable Only" },
        { "name": "checkIn", "type": "date", "title": "Check-in Date" },
        { "name": "room", "type": "enum", "title": "Room", "cases": { "standard": "Standard", "suite": "Suite" } }
      ],
      "request": {
        "method": "POST",
        "url": "https://api.example.com/cities/{city}/bookings",
        "body": ["nights", "budget", "refundable", "checkIn", "room"],
        "auth": { "service": "com.example.auth", "account": "accessToken" }
      },
      "reply": "Booked {booking.id} for {booking.total} dollars. Refundable: {booking.refundable}."
    }
  ]
}
```

Plugin config: `["expo-syrup-ai-kit", { "tools": "./siri-tools.json" }]`.

### Why each field exists

| Field | Required | Why |
|---|---|---|
| `appName` | no | `SiriTool` puts it in failure replies ("Couldn't reach Siri Spike right now"). Defaults to the Expo `name`. |
| `name` | yes | The Swift type (`<name>Intent`) and file name. It's also the identifier evaluations use to check which tool Siri called, so it has to be stable and separate from the title. |
| `title` | yes | `static let title`. Every App Intent needs one. |
| `description` | yes | `IntentDescription`. Siri uses it to pick the tool, so it's the most important text in the file. |
| `parameters[].name` | yes | The Swift property, and the `{placeholder}` name in the URL and the body key. |
| `parameters[].type` | yes | `string`, `int`, `double`, `bool`, `date` or `enum`: the six types this spike covers. |
| `parameters[].title` | yes | `@Parameter(title:)`. Siri uses it to fill the value and to ask for it. |
| `parameters[].description` | no | `@Parameter(description:)`. One line saying what the person gives, with an example; Siri reads it to fill the value. |
| `parameters[].cases` | enum only | Raw value → spoken title. Becomes an `AppEnum` with `caseDisplayRepresentations`. |
| `request.method` | yes | GET, POST, PUT, PATCH or DELETE. |
| `request.url` | yes | `https://` only (ATS blocks plain http). `{parameter}` placeholders are percent-encoded, so a value can't add a path segment or a query field. |
| `request.body` | no | Parameter names sent as a JSON object. Without it, a POST could only send query strings. Not allowed on GET. |
| `request.auth.service`, `.account` | with auth | The Keychain generic-password item that holds the token, as UTF-8. No item means signed out. |
| `request.auth.header` | no | Defaults to `Authorization`. Lets APIs that want `X-API-Key` work. |
| `request.auth.value` | no | Defaults to `Bearer {token}`. Must contain `{token}`. |
| `reply` | yes | What Siri says. `{field.path}` reads from the JSON response (see below). |
| `returns` | no | `dialog` (default): Siri says the reply and ends its turn. `value`: Siri gets the reply and can chain another tool ([#31](https://github.com/airowe/syrup-ai-kit/issues/31)). |

Left out on purpose: response types (the reply reads JSON by path instead of decoding), headers other than auth,
optional parameters and token refresh. See open questions.

### Reply paths

`{a.b.c}` walks the JSON object. On an array, a number indexes it (`{items.0.name}`), `count` is its length, and any
other name maps over the elements (`{products.title}` reads "A, B, C"). Numbers are spoken with up to two decimals and
no grouping; booleans read "yes" and "no". A missing field throws `ToolFailure.failed`, so Siri says the app couldn't
do it rather than reading half a sentence.

### Validation

`declarationProblems` reports every problem at once, with a path, and prebuild stops with the list:

```
expo-syrup-ai-kit: siri-tools.json has problems:
  - tools[0].parameters[1].type: must be one of string, int, double, bool, date, enum
  - tools[1].reply: has a { without a matching }
```

It checks: unknown fields; Swift type, property and case names (including keywords); duplicate tool and parameter
names; a name ending in "Intent"; enum cases; HTTP method; `https://`; URL placeholders and body names that aren't
parameters; **parameters that are never sent** (Siri would ask the person for a value that does nothing); a body on a
GET; auth without a service or account; an auth value without `{token}`; and malformed reply placeholders. 34 jest
cases cover these.

## What gets generated

Prebuild writes to `ios/<App>/SiriTools/`:

- `SiriToolsGenerated.swift`: the shared `SiriTool`, the request (URL template, JSON body, Keychain token, 401 and
  403 map to signed out), and the reply renderer. Shared so each tool file is short and readable.
- `<Name>Intent.swift` per tool: `@AppIntent(.tool)`, `@Parameter`s, an `AppEnum` per enum parameter, and a
  `perform()` that runs the request inside `SiriTool.answer` and returns `.result(value:dialog:)`, or `.result(value:)` when `returns` is `value`.

Every generated file is wrapped in `#if SIRI_AI_PREVIEW … #endif`, not just the attribute. Without the preview, the app
target keeps Expo's deployment target, and SyrupAIKit's tool code needs 27.3, so the generated files have to compile to
nothing. They do (checked with the flag off).

The folder joins the app target as a `PBXFileSystemSynchronizedRootGroup`, the mechanism Expo uses for inline
modules in `app-intents/`. Files compile without being listed in the project, and removing a tool from the declaration
deletes its file on the next prebuild. Writing into the user's `app-intents/` source folder was the alternative. It
was rejected because generated files don't belong in a source folder, and it would depend on the inline-modules
experiment being on.

The SDK forms come from `iPhoneOS27.3.sdk/.../AppIntents.swiftmodule/arm64e-apple-ios.swiftinterface`:
`public macro AppIntent(_ traits: AppIntentTraits)` with `AppIntentTraits.tool` attaches only an extension adding
`ToolIntent`. `public protocol ToolIntent : AppIntent {}` has no requirements of its own.

## What compiled

| Check | Result |
|---|---|
| `expo-plugin/scripts/typecheck-siri-tools.sh`: `xcrun -sdk iphoneos swiftc -typecheck -target arm64-apple-ios27.3`, `-D SIRI_AI_PREVIEW`, against a SyrupAIKit module built from `Sources/SyrupAIKit` | Pass in Swift 5 and Swift 6 modes for all 4 files (3 tools + support) |
| Same, flag off | Pass (files are empty) |
| Negative controls: `[String: Int]` parameter, `@AppIntent(.bogus)`, enum without `caseDisplayRepresentations` | Each fails with the expected error, so the type-check can say no |
| `xcodebuild build` of `Example/` with the 4 files added, `generic/platform=iOS`, `SIRI_AI_PREVIEW` on, Xcode 27.3 beta (27C5020n) | `BUILD SUCCEEDED`, including `ExtractAppIntentsMetadata` for the app |
| Extracted `Metadata.appintents/extract.actionsdata` | `BookTripIntent`, `GetRecipesIntent` and `SearchProductsIntent` present with `systemProtocols: [ToolIntent]`. Apart from names and parameters, the action metadata is identical to `GetCartIntent`. Both enums are present. |
| `npx expo prebuild -p ios --no-install` on a scratch copy of the siri-ai-expo app, plugin from this branch | Files written to `ios/SiriSpike/SiriTools/`, group in the app target. A second prebuild adds nothing twice. A bad declaration fails prebuild with the list. |
| jest | 73 tests: 34 parser, 12 generator (exact strings and approved fixture files), 11 prebuild wiring and options, plus the existing 16 |

Not run: `pod install` plus a full build of the Expo app. The synchronized group is the same kind Expo's inline modules
already build with in that project (objectVersion 54), but this one hasn't been built there.

## Parameter types the 27.3 SDK accepts for tools

Because `ToolIntent` adds no constraints, a tool takes whatever `@Parameter` takes. In the 27.3 swiftinterface, these
types conform to `_IntentValue`: `String`, `Int`, `Double`, `Bool`, `Date`, `DateComponents`, `URL`,
`AttributedString`, `Measurement`, `Calendar.RecurrenceRule`, `CLPlacemark`, `IntentFile`, `IntentPerson`,
`IntentCurrencyAmount`, `IntentPaymentMethod`, `EntityIdentifier`, `EntityCollection`, plus `Array`, `Set` and
`Optional` of those. `Duration` has its own `@Parameter` initializers. `AppEnum` and `AppEntity` types work through
their own protocols.

Verified in this spike (compiled and present in extracted metadata):

| Declaration type | Swift | Metadata value type |
|---|---|---|
| `string` | `String` | primitive 0 |
| `bool` | `Bool` | primitive 1 |
| `int` | `Int` | primitive 2 |
| `double` | `Double` | primitive 7 |
| `date` | `Date` | primitive 8 |
| `enum` | generated `String`-backed `AppEnum` | `linkEnumeration` |

The SDK accepting a type doesn't mean Siri fills it well. That's a device question, and the next step.

## Open questions

1. **Does Siri call a generated tool 5/5?** **Yes** (see [Device run](#device-run)).
2. **Which parameter types does Siri AI actually fill?** String and Int: yes, from natural speech. Date (relative
   dates like "next Friday"), Double and enum are still untested, and the likeliest to differ. Evaluate one tool per
   type.
3. **Optional parameters.** Everything is required now, so Siri must ask for any value the person didn't say.
   Optional parameters need a rule for dropping empty query fields from the URL.
4. **Parameter descriptions.** The plugin writes `@Parameter(description:)` from a parameter's `description`. In the
   device run, Siri filled the described parameter correctly. No run left the description out, so it isn't known
   whether the description helped.
5. **Token refresh.** The generated request reads a token and treats 401 as signed out. Apps with short-lived tokens
   (like the Example) need refresh, which differs per API. The likely answer is a hook into the app's own Swift rather
   than more JSON.
6. **Where the shared code lives.** `SiriToolsGenerated.swift` could move into SyrupAIKit as public API (`HTTPTool`?)
   once the shape settles, which would make generated files smaller and testable in Swift.
7. **Reply wording.** Lists read "A, B, C" with no "and", and numbers have no units or currency. Siri reads the
   list out exactly that way on the phone. A `format` per placeholder may be needed.
8. **Tool and enum names across apps.** Enums are named `<Tool><Parameter>` at the top level to keep metadata simple.
   Nesting them inside the intent is untested.

## Device run

Nov 12, 2026, iPhone 16 Pro on iOS 27.3 beta, Xcode 27.3 beta (27C5020n). A fresh Expo 58 app had
`expo-syrup-ai-kit@0.3.0` from npm and `"tools": "./siri-tools.json"` holding the README's `SearchProducts` sample.
Prebuild wrote `SearchProductsIntent.swift`, with the query's `@Parameter(description:)`. The evaluation was a
Release build, asking "In Syrup Quotes, search for phones and give me three results" five times.

| Runs | Apple pass rate | Real pass rate | What Siri did |
|---|---|---|---|
| 5 | 100% | 100% (5 of 5) | Called `SearchProductsIntent` with query "phones" and limit 3. Replied "Found 4 products. The first ones are Apple AirPods Max Silver, Beats Flex Wireless Earphones, Selfie Stick Monopod." |

Siri passes the words the person says, so the reply check needs a marker from the API's results for those exact
words. The first attempt used a marker from the results for "phone", and failed its reply check in every complete
run, although Siri called the tool each time. Check the marker with `curl` against the exact query before a run.

This ran the Expo path (step 5 below), not the native Example steps. The negative control in step 4 hasn't been run.

## Device run 2: value-only tools, an enum, a failure and a write action

Nov 12, 2026, same phone and Xcode. A fresh Expo 58 app named "Sample App" had `expo-syrup-ai-kit@0.3.1` from npm and
three generated tools against DummyJSON:

- `SearchProducts`, `"returns": "value"`: replies with the first three titles and their product ids, but not prices.
- `GetProductDetails`, `"returns": "value"`: takes an `int` product id and replies with the title, price and stock.
- `ListCategoryProducts`, the default dialog: takes an `enum` category with cases `smartphones` ("Phones"),
  `laptops` and `tablets`.

It also had one hand-written Swift tool, `AddToCart`, that calls `requestConfirmation(actionName: .add, dialog:)`
before `SiriTool.answer` POSTs to `/carts/add`. Release build, summarized with `syrup-ai-eval summarize --fail-on real`.

| Evaluation | Runs | Real pass rate | What Siri did |
|---|---|---|---|
| "Search for phones and tell me the price of the first one": search, then details | 5 | 60% (3 of 5) | In 3 runs it called `SearchProducts`, then `GetProductDetails` with the first id, and said "$549.99". In 2 it called neither: it picked `ListCategoryProducts`, because "phones" matched that tool's "Phones" case, and listed phones from that category. |
| "How much is product 1?" (one value-only tool) | 5 | 100% (5 of 5) | Called `GetProductDetails` and worded the answer itself: "Product 1, Essence Mascara Lash Princess, costs $9.99." |
| "What laptops do you sell?" (enum parameter) | 5 | 100% (5 of 5) | Called `ListCategoryProducts` with `laptops` and read the reply word for word. |
| "How much is product 99999?" (the API returns 404) | 4 (3 complete) | Reported, not asserted | The tool failed: its outcome was "failed (productId 99999)". Siri said, for example, "Sample App couldn't find product 99999 or return a price for it." It never made up a price. |
| "Add 2 of product 1 to my cart", then "Yes" | 5 | 100% (5 of 5) | Asked to confirm, then called `AddToCart` and said "Added. Your cart total is now 19.98 dollars." |
| The same, then "No" (negative control) | 2 | Passed: the total was never said | "OK. I won't add that to your cart." The tool's request never ran. |

What it showed:

- **A generated value-only tool can be chained and works on its own.** Siri words the answer, so check for the
  value (the price), not a sentence.
- **Tools whose words overlap compete.** An enum case title counts: "phones" picked the "Phones" case over a search.
  Keep tool descriptions and case titles apart, or expect Siri to choose either.
- **Confirmation works with two turns.** `requestConfirmation` before `SiriTool.answer` means a "No" never reaches
  the API, and the confirmation wait doesn't count against the tool's timeout.
- **The outcome log keeps only the last call.** Generated tools share one `SiriTool`, so when Siri calls a second
  tool after a failure, its "succeeded" replaces the failure. The product id note above is what showed which call
  failed. It was added to the generated Swift for this run only. *Fixed since:* `ToolOutcomeLog` now keeps every call
  in a run (#42).
- **Value-only runs took about a minute each in the harness,** against about 11 seconds for dialog tools. The cause
  wasn't measured, and nothing here shows how long the person waits.
- **A generated tool still has no negative control.** Its URL is fixed, so an `EvalSwitch` can't break it.
  *Fixed since:* the `bad-host` switch below (#43).

The first attempt at the first three evaluations failed before any Siri request with "Timed out while enabling
automation mode"; they passed this table's numbers on a rerun.

## Negative control

A generated tool's URL is fixed in the declaration, so in 0.3.1 no `EvalSwitch` could break it, and an Expo app
couldn't run a negative control for any tool: its evaluations run in Release, and the documented `#if DEBUG` guard
compiled the switch out.

Now `SiriToolsGenerated.Request` sends every request to `https://siri-ai-eval-bad-host.invalid` when the app is
launched with the `bad-host` switch, and reads the switch only inside `#if DEBUG || SIRI_AI_EVAL_SWITCHES`. With the
preview on, the plugin sets two build settings on the app target:

```
SWIFT_ACTIVE_COMPILATION_CONDITIONS = "$(inherited) SIRI_AI_PREVIEW $(SIRI_AI_EVAL_SWITCHES_CONDITION_$(SIRI_AI_EVAL_SWITCHES))"
SIRI_AI_EVAL_SWITCHES_CONDITION_YES = SIRI_AI_EVAL_SWITCHES
```

`SIRI_AI_EVAL_SWITCHES` is set by no one but the person running `xcodebuild test ... SIRI_AI_EVAL_SWITCHES=YES`, so
the condition is on in that build alone. An unset or other value expands to nothing.

**Why not a condition on in every Release build:** a person can't pass launch arguments to an App Store build today,
but that's iOS policy, not something this code controls. A check that isn't compiled in can't be reached at all, and
keeping it out costs one extra `xcodebuild` setting. If that's wrong in the other direction, and someone passes the
setting to an archive, that archive reads the switch, which only ever points the app at a host that doesn't resolve.
If the setting doesn't reach the compiler, the switch does nothing and the negative control fails, so the mistake
shows up rather than passing silently.

**On a phone (Nov 12, 2026):** the Sample App from device run 2, prebuilt with this plugin and kit `main`, built in
Release with `SIRI_AI_EVAL_SWITCHES=YES`:

| Evaluation | Result |
|---|---|
| "How much is product 1?", required | 5 of 5 passed; each run's outcome lists one call |
| The same with `bad-host` on, negative control | The reply check failed in 4 of 4 complete runs, as it should: Siri said "I'm having trouble reaching Sample App right now". Every outcome was "unreachable". |
| "How much is product 99999?" | Both outcomes list the failure and the next call ("failed …; succeeded …"), which 0.3.1 lost |

The bad-host URL is in the app binary built with the setting and not in a Release build without it.

One reply check missed only on punctuation: Siri wrote "couldn’t" with a typographic apostrophe, which
`.contains("couldn't")` doesn't match. Check for a word without an apostrophe, such as "find".

## Running a device evaluation of a generated tool

Target: 5/5 runs where Siri calls the tool and says something only the API knows. Use `SearchProducts` from the
sample, because it calls DummyJSON with no auth. For "search for phones and give me three results", Siri passes the
query "phones", which returns "Beats Flex Wireless Earphones" today. Check with
`curl 'https://dummyjson.com/products/search?q=phones&limit=3'`, and use a marker from that exact query.

1. In a checkout of this branch, generate the files and add them to the Example app (the project globs its folder):
   ```bash
   cd expo-plugin && npm ci && npm run build && cd ..
   # A declaration with only SearchProducts from the sample, written to Example/siri-tools.json
   node expo-plugin/scripts/generate-siri-tools.js Example/siri-tools.json Example/SyrupAIKitExample "SyrupAIKit Example"
   ruby Example/scripts/generate-project.rb
   ```
   In Xcode, add `SIRI_AI_PREVIEW` to the app target's Active Compilation Conditions (Debug), or pass
   `'SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG SIRI_AI_PREVIEW'` to `xcodebuild`.
2. Add `Example/SyrupAIKitExampleEvals/SearchProductsEvaluationTests.swift`, based on `CartEvaluationTests.swift`:
   `IntentDefinitions(bundleIdentifier:).intents["SearchProductsIntent"]`, the user turn
   "In SyrupAIKit Example, search for phones and give me three results", `Calls { searchProductsIntent }`,
   `SiriResponse(.contains("beats", caseSensitive: false))`, and `.repeating(times: 5, …)`.
3. With the phone set up as in `Example/README.md` (Siri AI, Developer Mode and UI Automation on, unlocked, on power):
   ```bash
   xcodebuild test -project Example/SyrupAIKitExample.xcodeproj -scheme SyrupAIKitExampleEvals \
     -destination 'id=<device UDID>' -allowProvisioningUpdates DEVELOPMENT_TEAM=<team ID> \
     'SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG SIRI_AI_PREVIEW' \
     -only-testing:'SyrupAIKitExampleEvals/callsSearchProductsToolEveryTime()' -resultBundlePath search.xcresult
   swift run syrup-ai-eval summarize search.xcresult --fail-on real
   ```
4. Negative control: add a second `@Test` with `ToolEvaluation.negativeControl(turningOn: .badHost, …)` and the same
   scenario, asserting `expectAllFail(.siriResponse)`. With `bad-host` on, the generated request goes to
   `https://siri-ai-eval-bad-host.invalid`, so Siri should say it couldn't reach the app and the "beats" check must
   fail in every run. The Example builds in Debug, which reads the switch; an Expo app needs `SIRI_AI_EVAL_SWITCHES=YES`
   (see "Negative control" below).
5. To test the Expo path end to end instead, use a copy of the siri-ai-expo app with
   `["expo-syrup-ai-kit", { "tools": "./siri-tools.json", "preview": true }]` pointing at this branch's plugin, then
   `SIRI_AI_PREVIEW=1 npx expo prebuild -p ios --clean` and `npx expo run:ios --device`. This also covers the untested
   `pod install` plus full Expo build.
