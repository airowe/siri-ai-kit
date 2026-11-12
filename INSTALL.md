# Installing Syrup AI Kit

Siri AI tools need beta software end to end, so most of the setup is outside your project. Do it in this order:

1. The Mac and the iPhone.
2. The kit, in a native iOS app or in an Expo app.
3. The agent skills, if you use a coding agent.
4. Check that it worked.

If you are a coding agent, follow [For coding agents](#for-coding-agents) at the end.

## 1. The Mac and the iPhone

| Need | Why |
|---|---|
| A Mac with **Xcode 27.3 beta** | The Siri AI Developer Preview APIs (`@AppIntent(.tool)`) are only in the iOS 27.3 SDK. |
| An **iPhone on iOS 27.3 beta** | Siri AI and Siri Evaluations don't run on the Simulator. |
| On the iPhone: **Siri AI on**, **Developer Mode on**, and **Settings > Developer > Enable UI Automation on** | Siri Evaluations drives Siri through UI automation. |
| An Apple Developer team signed in to Xcode | To install the app and the evaluation runner on the phone. |
| An iPhone that supports Apple Intelligence, set to English, French, Japanese, Korean, Portuguese or Spanish, outside the EU | Siri AI isn't available otherwise. |

Only you and your internal TestFlight testers can use the tools you build during the preview. External TestFlight testers and App Store users can't. The README's [Who can use your tools today](README.md#who-can-use-your-tools-today) has the details and Apple's sources.

Check the Mac:

```bash
xcodebuild -version   # Xcode 27.3 or later
xcrun --sdk iphoneos --show-sdk-version   # 27.3 or later
```

## 2a. A native iOS app

In Xcode, choose File > Add Package Dependencies and enter `https://github.com/airowe/syrup-ai-kit`. Or add it to `Package.swift`:

```swift
.package(url: "https://github.com/airowe/syrup-ai-kit", .upToNextMinor(from: "0.4.0"))
```

- Link **`SyrupAIKit`** to the app target. It supports iOS 17 and later, and tool code needs iOS 27.3.
- Link **`SyrupAIEvalKit`** to a UI Testing Bundle target. It's only needed for evaluations.
- Before 1.0, minor versions may change the API, because Apple's APIs are in beta. That's why the requirement above is up to the next minor.

## 2b. An Expo app

You need Expo SDK 58 or later and a development build. Expo Go can't load the native code.

```bash
npx expo install expo-syrup-ai-kit expo-app-intents
npx expo-app-intents init --examples minimal
```

`init` creates `app-intents/AppIntentsSetup.swift`, the inline module that your Swift in `app-intents/` and the outcome readout use, and turns on inline modules in `app.json`. Keep the class name.

`npx expo install` adds both plugins by name only. Replace them in `app.json` (or `app.config.*`) with:

```json
{
  "expo": {
    "plugins": [
      "expo-app-intents",
      ["expo-syrup-ai-kit", { "preview": true, "evals": { "sourceDir": "siri-evals" } }]
    ]
  }
}
```

- `preview: true` turns on the Developer Preview code: it adds the `SIRI_AI_PREVIEW` Swift condition and sets the app target to iOS 27.3. Setting `SIRI_AI_PREVIEW=1` in the environment does the same, without committing it.
- `evals` is optional. It adds a UI test target for Siri Evaluations that compiles the `.swift` files in `siri-evals/`. Create that folder with at least one test before you prebuild.
- `tools` (experimental) generates tools from a `siri-tools.json`. Leave it out until you have one.

Generate the native project and build to the phone:

```bash
CP_CACHE_DIR="$PWD/.cp-cache" LANG=en_US.UTF-8 npx expo prebuild -p ios
npx expo run:ios --device
```

`CP_CACHE_DIR` gives CocoaPods a cache of its own. A shared cache that's been left broken makes `pod install` fail with a missing `Info.plist` in a React Native or Hermes framework. Add `.cp-cache` to `.gitignore`.

Import `SyrupAIKit` the same way in every file in `app-intents/`. `init` writes `internal import` for its own modules. If one file says `internal import SyrupAIKit` and another plain `import SyrupAIKit`, the build stops with "ambiguous implicit access level". The examples in these docs use plain `import SyrupAIKit`.

Never edit `ios/` by hand. Prebuild regenerates it, so change `app.json` or the plugin options instead. Your tools go in `app-intents/` as Swift files, and `expo-app-intents` compiles them into the app target. See the [plugin README](expo-plugin/README.md) for every option, and [docs/implementing-tools.md](docs/implementing-tools.md) for writing tools.

## 3. The agent skills

The skills teach a coding agent the parts that are easy to get wrong:

| Skill | What it covers |
|---|---|
| `siri-ai` | Where to start: finds the app's stack and picks the next skill |
| `siri-ai-tool` | Writing a tool: the time budget, failure replies, the Spotlight index |
| `siri-ai-eval` | Writing and reading Siri evaluations |
| `expo-syrup-ai-kit` | Using SyrupAIKit in an Expo app |
| `siri-ai-discover` | Choosing which tools an app should have |

**Claude Code:**

```
/plugin marketplace add airowe/syrup-ai-kit
/plugin install syrup-ai-kit@syrup-ai-kit
```

**Other agents:** the [skills CLI](https://github.com/vercel-labs/skills) reads this repository's plugin manifest:

```
npx skills add airowe/syrup-ai-kit
```

Or copy the folders in [`skills/`](skills/) and [`expo-plugin/skills/`](expo-plugin/skills/) into your agent's skills directory. For example, `~/.claude/skills/` for Claude Code, or `~/.agents/skills/` for agents that read that path. The npm package includes `skills/` from the release after 0.2.0; 0.2.0 doesn't have it, so copy the folders from the repository for now.

## 4. Check that it worked

**Native app:** build for the phone. In a file in the app target, `import SyrupAIKit` should compile.

**Expo app**, after prebuild:

```bash
grep -c 'syrup-ai-kit' ios/*.xcodeproj/project.pbxproj     # 1 or more: the package is linked
grep -c 'SIRI_AI_PREVIEW' ios/*.xcodeproj/project.pbxproj # 1 or more: the preview is on
ls ios/*.xcodeproj/xcshareddata/xcschemes/                # <App>Evals.xcscheme, if you set evals
```

**On the phone:** add a tool (the plugin README's "A first tool" works as-is). Build, then ask Siri a question that names the app. If Siri never calls the tool, check that the preview is on: without it, `#if SIRI_AI_PREVIEW` leaves the tool out.

**Evaluations:**

```bash
xcodebuild test -workspace ios/MyApp.xcworkspace -scheme MyAppEvals -configuration Release \
  -destination 'id=<device UDID>' -allowProvisioningUpdates -resultBundlePath evals.xcresult
swift run --package-path <syrup-ai-kit checkout> syrup-ai-eval summarize evals.xcresult --fail-on real
```

Find the UDID with `xcrun devicectl list devices`.

For an Expo app, build the evaluations in Release. A Debug build loads its JavaScript from the dev server, so the evaluation can only launch the app while `npx expo start` is running. To run a negative control, also pass `SIRI_AI_EVAL_SWITCHES=YES` and guard the switch with `#if DEBUG || SIRI_AI_EVAL_SWITCHES` (see the plugin README's "Negative controls in an Expo app").

**If prebuild or the build fails:** the `expo-syrup-ai-kit` skill's "Prebuild and build traps" table lists the known causes. For example, CocoaPods failing on a non-UTF-8 `LANG` or a broken cache, `No such module 'SyrupAIKit'`, "ambiguous implicit access level", and an evaluation target that disappeared.

## For coding agents

Follow these steps in order. Stop and ask the person at each **Ask** step, because those need their accounts, their phone or a decision only they can make.

1. **Check the Mac.** Run `xcodebuild -version` and `xcrun --sdk iphoneos --show-sdk-version`. If the SDK is older than 27.3, **ask** the person to install Xcode 27.3 beta. It needs their Apple ID, so don't try to install it yourself.
2. **Identify the project.** It's an Expo app if `package.json` has `expo` and there's an `app.json` or `app.config.*`; check the major version of `expo`. Otherwise it's a native app if there's an `.xcodeproj` or `Package.swift`.
3. **Install the skills** for yourself if they're missing (section 3), then read the `expo-syrup-ai-kit` skill (Expo) or the `siri-ai-tool` skill (native) before changing anything.
4. **Install the kit** (section 2a or 2b).
   - Expo: use `npx expo install`, or `bunx expo install` when `bun.lock` is present, never `npm install`. Run `npx expo-app-intents init --examples minimal` unless `app-intents/AppIntentsSetup.swift` already exists. Add the plugins to the app config, never to `ios/`.
   - Native: add the package in `Package.swift` or the project, and link the targets as described.
5. **Prebuild and verify** with the commands in section 4, and report each output to the person. A count of 0 means the step failed: say so, don't move on.
6. **Ask** the person to set up the phone: Siri AI, Developer Mode and Enable UI Automation on, plugged in and unlocked. Its language must be one Siri AI supports, and it must be outside the EU. If Siri never calls the tool, check these before changing code. Also ask for the device and team to build with. Pass the device UDID and team ID on the command line only, and never write them into files that get committed.
7. **Build to the phone** (`npx expo run:ios --device`, or `xcodebuild` with `-allowProvisioningUpdates`). If the build asks to sign in or to accept a license, **ask** the person to do it.
8. **Next:** use `siri-ai-discover` to choose tools, `docs/implementing-tools.md` to write them, and `siri-ai-eval` to prove each one on the phone.

Never:

- use Expo Go;
- edit `ios/` by hand;
- enter the person's Apple ID or passwords;
- commit device identifiers or team IDs;
- report the kit as installed before the step 5 checks pass.
