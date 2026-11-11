# Installing SiriAIKit

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

Check the Mac:

```bash
xcodebuild -version   # Xcode 27.3 or later
xcrun --sdk iphoneos --show-sdk-version   # 27.3 or later
```

## 2a. A native iOS app

In Xcode, choose File > Add Package Dependencies and enter `https://github.com/airowe/siri-ai-kit`. Or add it to `Package.swift`:

```swift
.package(url: "https://github.com/airowe/siri-ai-kit", .upToNextMinor(from: "0.2.0"))
```

- Link **`SiriAIKit`** to the app target. It supports iOS 17 and later, and tool code needs iOS 27.3.
- Link **`SiriAIEvalKit`** to a UI Testing Bundle target. It's only needed for evaluations.
- Before 1.0, minor versions may change the API, because Apple's APIs are in beta. That's why the requirement above is up to the next minor.

## 2b. An Expo app

You need Expo SDK 58 or later and a development build. Expo Go can't load the native code.

```bash
npx expo install expo-siri-ai-kit expo-app-intents
```

Add both plugins to `app.json` (or `app.config.*`):

```json
{
  "expo": {
    "plugins": [
      "expo-app-intents",
      ["expo-siri-ai-kit", { "preview": true, "evals": { "sourceDir": "siri-evals" } }]
    ]
  }
}
```

- `preview: true` turns on the Developer Preview code: it adds the `SIRI_AI_PREVIEW` Swift condition and sets the app target to iOS 27.3. Setting `SIRI_AI_PREVIEW=1` in the environment does the same, without committing it.
- `evals` is optional. It adds a UI test target for Siri Evaluations that compiles the `.swift` files in `siri-evals/`. Create that folder with at least one test before you prebuild.
- `tools` (experimental) generates tools from a `siri-tools.json`. Leave it out until you have one.

Generate the native project and build to the phone:

```bash
npx expo prebuild -p ios
npx expo run:ios --device
```

Never edit `ios/` by hand. Prebuild regenerates it, so change `app.json` or the plugin options instead. Your tools go in `app-intents/` as Swift files, and `expo-app-intents` compiles them into the app target. See the [plugin README](expo-plugin/README.md) for every option, and [docs/implementing-tools.md](docs/implementing-tools.md) for writing tools.

## 3. The agent skills

The skills teach a coding agent the parts that are easy to get wrong:

| Skill | What it covers |
|---|---|
| `siri-ai-tool` | Writing a tool: Keychain items readable on a locked phone, the Spotlight index, token refresh |
| `siri-ai-eval` | Writing and reading Siri evaluations |
| `expo-siri-ai-kit` | Using SiriAIKit in an Expo app |
| `siri-ai-discover` | Choosing which tools an app should have |

**Claude Code:**

```
/plugin marketplace add airowe/siri-ai-kit
/plugin install siri-ai-kit@siri-ai-kit
```

**Other agents:** copy the folders in [`skills/`](skills/) and [`expo-plugin/skills/`](expo-plugin/skills/) into your agent's skills directory. For example, `~/.claude/skills/` for Claude Code, or `~/.agents/skills/` for agents that read that path. The npm package includes `skills/` from the release after 0.2.0; 0.2.0 doesn't have it, so copy the folders from the repository for now.

## 4. Check that it worked

**Native app:** build for the phone. In a file in the app target, `import SiriAIKit` should compile.

**Expo app**, after prebuild:

```bash
grep -c 'siri-ai-kit' ios/*.xcodeproj/project.pbxproj     # 1 or more: the package is linked
grep -c 'SIRI_AI_PREVIEW' ios/*.xcodeproj/project.pbxproj # 1 or more: the preview is on
ls ios/*.xcodeproj/xcshareddata/xcschemes/                # <App>Evals.xcscheme, if you set evals
```

**On the phone:** add a tool (the plugin README's "A first tool" works as-is). Build, then ask Siri a question that names the app. If Siri never calls the tool, check that the preview is on: without it, `#if SIRI_AI_PREVIEW` leaves the tool out.

**Evaluations:**

```bash
xcodebuild test -workspace ios/MyApp.xcworkspace -scheme MyAppEvals -destination 'id=<device UDID>' -allowProvisioningUpdates
swift run --package-path <siri-ai-kit checkout> siri-ai-eval summarize <result>.xcresult --fail-on real
```

Find the UDID with `xcrun devicectl list devices`.

**If prebuild or the build fails:** the `expo-siri-ai-kit` skill's "Prebuild and build traps" table lists the known causes. For example, CocoaPods failing on a non-UTF-8 `LANG`, `No such module 'SiriAIKit'`, and an evaluation target that disappeared.

## For coding agents

Follow these steps in order. Stop and ask the person at each **Ask** step, because those need their accounts, their phone or a decision only they can make.

1. **Check the Mac.** Run `xcodebuild -version` and `xcrun --sdk iphoneos --show-sdk-version`. If the SDK is older than 27.3, **ask** the person to install Xcode 27.3 beta. It needs their Apple ID, so don't try to install it yourself.
2. **Identify the project.** It's an Expo app if `package.json` has `expo` and there's an `app.json` or `app.config.*`; check the major version of `expo`. Otherwise it's a native app if there's an `.xcodeproj` or `Package.swift`.
3. **Install the skills** for yourself if they're missing (section 3), then read the `expo-siri-ai-kit` skill (Expo) or the `siri-ai-tool` skill (native) before changing anything.
4. **Install the kit** (section 2a or 2b).
   - Expo: use `npx expo install`, or `bunx expo install` when `bun.lock` is present, never `npm install`. Add the plugins to the app config, never to `ios/`.
   - Native: add the package in `Package.swift` or the project, and link the targets as described.
5. **Prebuild and verify** with the commands in section 4, and report each output to the person. A count of 0 means the step failed: say so, don't move on.
6. **Ask** the person to set up the phone: Siri AI, Developer Mode and Enable UI Automation on, plugged in and unlocked. Also ask for the device and team to build with. Pass the device UDID and team ID on the command line only, and never write them into files that get committed.
7. **Build to the phone** (`npx expo run:ios --device`, or `xcodebuild` with `-allowProvisioningUpdates`). If the build asks to sign in or to accept a license, **ask** the person to do it.
8. **Next:** use `siri-ai-discover` to choose tools, `docs/implementing-tools.md` to write them, and `siri-ai-eval` to prove each one on the phone.

Never:

- use Expo Go;
- edit `ios/` by hand;
- enter the person's Apple ID, password or tokens;
- commit device identifiers or team IDs;
- report the kit as installed before the step 5 checks pass.
