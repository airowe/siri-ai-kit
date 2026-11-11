# Spike: generating Siri AI tools from a declaration

**Question.** Can an Expo app get Siri AI tools from a small declaration at prebuild, so nobody writes Swift?

**Answer so far: yes, up to the device.** The `expo-siri-ai-kit` plugin now takes a `tools` option. It reads a JSON
declaration, validates it, and writes one Swift tool per entry into the app target at prebuild. The generated Swift
type-checks against the iOS 27.3 SDK and the real SiriAIKit sources in Swift 5 and Swift 6 modes. It also builds in a
full `xcodebuild`, where Xcode's App Intents metadata step records each tool with the same `ToolIntent` system
protocol as the hand-written `GetCartIntent`, which passes 5/5 on device. **No generated tool has run on a phone
yet.** The steps for that are at the end.

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

Plugin config: `["expo-siri-ai-kit", { "tools": "./siri-tools.json" }]`.

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
| `parameters[].cases` | enum only | Raw value → spoken title. Becomes an `AppEnum` with `caseDisplayRepresentations`. |
| `request.method` | yes | GET, POST, PUT, PATCH or DELETE. |
| `request.url` | yes | `https://` only (ATS blocks plain http). `{parameter}` placeholders are percent-encoded, so a value can't add a path segment or a query field. |
| `request.body` | no | Parameter names sent as a JSON object. Without it, a POST could only send query strings. Not allowed on GET. |
| `request.auth.service`, `.account` | with auth | The Keychain generic-password item that holds the token, as UTF-8. No item means signed out. |
| `request.auth.header` | no | Defaults to `Authorization`. Lets APIs that want `X-API-Key` work. |
| `request.auth.value` | no | Defaults to `Bearer {token}`. Must contain `{token}`. |
| `reply` | yes | What Siri says. `{field.path}` reads from the JSON response (see below). |

Left out on purpose: response types (the reply reads JSON by path instead of decoding), headers other than auth,
optional parameters, parameter descriptions, and token refresh. See open questions.

### Reply paths

`{a.b.c}` walks the JSON object. On an array, a number indexes it (`{items.0.name}`), `count` is its length, and any
other name maps over the elements (`{products.title}` reads "A, B, C"). Numbers are spoken with up to two decimals and
no grouping; booleans read "yes" and "no". A missing field throws `ToolFailure.failed`, so Siri says the app couldn't
do it rather than reading half a sentence.

### Validation

`declarationProblems` reports every problem at once, with a path, and prebuild stops with the list:

```
expo-siri-ai-kit: siri-tools.json has problems:
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
  `perform()` that runs the request inside `SiriTool.answer` and returns `.result(value:dialog:)`.

Every generated file is wrapped in `#if SIRI_AI_PREVIEW … #endif`, not just the attribute. Without the preview, the app
target keeps Expo's deployment target, and SiriAIKit's tool code needs 27.3, so the generated files have to compile to
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
| `expo-plugin/scripts/typecheck-siri-tools.sh`: `xcrun -sdk iphoneos swiftc -typecheck -target arm64-apple-ios27.3`, `-D SIRI_AI_PREVIEW`, against a SiriAIKit module built from `Sources/SiriAIKit` | Pass in Swift 5 and Swift 6 modes for all 4 files (3 tools + support) |
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

1. **Does Siri call a generated tool 5/5?** Only the metadata says so. Run the device evaluation below.
2. **Which parameter types does Siri AI actually fill?** Date (relative dates like "next Friday"), Double and enum
   are the likeliest to differ from String and Int. Evaluate one tool per type.
3. **Optional parameters.** Everything is required now, so Siri must ask for any value the person didn't say.
   Optional parameters need a rule for dropping empty query fields from the URL.
4. **Parameter descriptions.** `@Parameter(description:)` may improve how Siri fills values. Add it only if the
   evaluation shows a need.
5. **Token refresh.** The generated request reads a token and treats 401 as signed out. Apps with short-lived tokens
   (like the Example) need refresh, which differs per API. The likely answer is a hook into the app's own Swift rather
   than more JSON.
6. **Where the shared code lives.** `SiriToolsGenerated.swift` could move into SiriAIKit as public API (`HTTPTool`?)
   once the shape settles, which would make generated files smaller and testable in Swift.
7. **Reply wording.** Lists read "A, B, C" with no "and", and numbers have no units or currency. A `format` per
   placeholder may be needed.
8. **Tool and enum names across apps.** Enums are named `<Tool><Parameter>` at the top level to keep metadata simple.
   Nesting them inside the intent is untested.

## Running a device evaluation of a generated tool

Target: 5/5 runs where Siri calls the tool and says something only the API knows. Use `SearchProducts` from the
sample, because it calls DummyJSON with no auth, and "phone, three results" returns the "Apple iPhone Charger"
product today (check with `curl 'https://dummyjson.com/products/search?q=phone&limit=3'`).

1. In a checkout of this branch, generate the files and add them to the Example app (the project globs its folder):
   ```bash
   cd expo-plugin && npm ci && npm run build && cd ..
   # A declaration with only SearchProducts from the sample, written to Example/siri-tools.json
   node expo-plugin/scripts/generate-siri-tools.js Example/siri-tools.json Example/SiriAIKitExample "SiriAIKit Example"
   ruby Example/scripts/generate-project.rb
   ```
   In Xcode, add `SIRI_AI_PREVIEW` to the app target's Active Compilation Conditions (Debug), or pass
   `'SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG SIRI_AI_PREVIEW'` to `xcodebuild`.
2. Add `Example/SiriAIKitExampleEvals/SearchProductsEvaluationTests.swift`, based on `CartEvaluationTests.swift`:
   `IntentDefinitions(bundleIdentifier:).intents["SearchProductsIntent"]`, the user turn
   "In SiriAIKit Example, search for phones and give me three results", `Calls { searchProductsIntent }`,
   `SiriResponse(.contains("charger", caseSensitive: false))`, and `.repeating(times: 5, …)`.
3. With the phone set up as in `Example/README.md` (Siri AI, Developer Mode and UI Automation on, unlocked, on power):
   ```bash
   xcodebuild test -project Example/SiriAIKitExample.xcodeproj -scheme SiriAIKitExampleEvals \
     -destination 'id=<device UDID>' -allowProvisioningUpdates DEVELOPMENT_TEAM=<team ID> \
     'SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG SIRI_AI_PREVIEW' \
     -only-testing:'SiriAIKitExampleEvals/callsSearchProductsToolEveryTime()' -resultBundlePath search.xcresult
   swift run siri-ai-eval summarize search.xcresult --fail-on real
   ```
4. Negative control: change the sample's `SearchProducts` reply to `"Found {total} products."`, rerun
   `generate-siri-tools.js` and the test. Siri should still call the
   tool, but the "charger" response check must fail 5/5. If it passes, the check isn't reading the tool's answer.
5. To test the Expo path end to end instead, use a copy of the siri-ai-expo app with
   `["expo-siri-ai-kit", { "tools": "./siri-tools.json", "preview": true }]` pointing at this branch's plugin, then
   `SIRI_AI_PREVIEW=1 npx expo prebuild -p ios --clean` and `npx expo run:ios --device`. This also covers the untested
   `pod install` plus full Expo build.
