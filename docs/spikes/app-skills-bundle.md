# Spike: can the Expo plugin add an App Skills bundle?

**Question.** Apple's App Skills live in one `Skills.skillsbundle` per app target. If the expo-syrup-ai-kit config plugin adds that bundle to the Xcode project at prebuild, does Xcode validate and compile it the same way it does a bundle made from its "Skills Bundle" template?

**Answer: yes.** The bundle needs to be a file reference of type `wrapper.skillsbundle` in the app target's Copy Bundle Resources phase.

**How it was tested.** Xcode 27.3 beta (27C5020n), building the native example app for `generic/platform=iOS` with signing off. The project file was edited by hand, the way a config plugin would. Expo prebuild itself wasn't run.

## What Xcode does

- **The template** (`File Templates/MultiPlatform/Resource/SkillsBundle.xctemplate`) only contains `Skills.skillsbundle/Skills/sample-skill/SKILL.md`. It adds nothing else to the project, and no build setting is involved.
- **SwiftBuild's `SkillsBundle.xcspec`** declares the file type `wrapper.skillsbundle` (UTI `com.apple.skillsbundle`). Its compiler runs:
  ```
  appintentsskillsprocessor --skillsbundle <bundle> --output <app>/Metadata.appintents
  ```
- **The build log** shows a `ProcessSkillsBundle` step, then `Writing skills bundle: .../Metadata.appintents/Skills.skillsc`.
- **The app contains no raw bundle.** `Skills.skillsc` is a binary plist mapping each skill name to its `description` and body (`content`). The frontmatter is stripped.

The project-file entries that built:

```
B1 /* Skills.skillsbundle in Resources */ = {isa = PBXBuildFile; fileRef = F1 /* Skills.skillsbundle */; };
F1 /* Skills.skillsbundle */ = {isa = PBXFileReference; lastKnownFileType = wrapper.skillsbundle; path = Skills.skillsbundle; sourceTree = "<group>"; };
```

`F1` goes in the app's group, and `B1` goes in the app target's `PBXResourcesBuildPhase`. Leaving out `lastKnownFileType` also worked, because Xcode infers the type from the extension, but writing it is safer.

## Negative controls

| Case | Result |
|---|---|
| `name` doesn't match its folder | Build fails: `SKILL.md:2: error: 'cart-checkout': The 'name' field must match the parent directory name` |
| Unsupported frontmatter field (`version: 1`) | Warning only, the build succeeds: `Unrecognized field 'version'` |
| Extra files in the bundle (`notes.txt`, `references/a.md`) | No message. They're left out of `Skills.skillsc`. |
| Added as type `folder` or `text` | The build succeeds with no `ProcessSkillsBundle` step. The folder is copied raw and never validated, even with the invalid name still in it. |

## What this means for the plugin

- **Write the file type explicitly.** With the wrong type, Xcode silently skips validation and compilation, and the app has no skills.
- **The plugin must check what Xcode doesn't:**
  - extra files in the bundle;
  - unsupported frontmatter fields, which Xcode only warns about;
  - one bundle per target. SwiftBuild rejects a second bundle ("only one is allowed per target"), but the plugin should say so first, in its own terms.
- **Skills aren't checked against the app's intents at build time.** `appintentsskillsprocessor` takes an optional `--metadata-file`, but Xcode doesn't pass it.

## Device runs

Nov 12, 2026, iPhone 16 Pro on iOS 27.3 beta, Xcode 27.3 beta (27C5020n). The app was a fresh Expo 58 app with `expo-syrup-ai-kit@0.3.0` from npm, built in Release. A real `expo prebuild` with the `skills` option wrote `ios/<App>/Skills.skillsbundle`, and the build log shows the `ProcessSkillsBundle` step.

The question needs two tools: "In Syrup Quotes, find phones and tell me the price of the first result."
- Search Products searches DummyJSON and names the results, without prices.
- Get Product Price looks one product up by its full name.

The answer, $549.99, comes only from the second tool. The skill, `first-result-price`, said:
1. Search with the person's words and a limit of 3.
2. Take the first name.
3. Get its price.
4. Answer with the name and the price.

| Tools | Skill | Both tools called (complete runs) | Price in reply | Siri's reply |
|---|---|---|---|---|
| Generated, `.result(value:dialog:)` | yes | 0 of 5 | 0 of 5 | The search tool's dialog, word for word: "Found 4 products. The first ones are …" |
| Hand-written, `.result(value:)` only | yes | 3 of 3 | 5 of 5 | "The first result found is the Apple AirPods Max Silver, which costs $549.99." |
| Hand-written, `.result(value:)` only | no | 3 of 3 | 5 of 5 | "… which costs $549.99 and has 59 in stock." |

Two runs in each value-only row ended before their tool calls were recorded. They're left out of the "complete runs" count, but their replies still had the price.

What it shows:

- **A tool that returns a dialog ends Siri's turn.** Siri speaks the dialog as written and doesn't call another tool. Tools that return only a value let Siri chain them and word the answer itself. Every pattern the kit documents or generates returns a dialog, so none can be chained yet ([#31](https://github.com/airowe/syrup-ai-kit/issues/31)).
- **Siri chained without the skill.** For a request this direct, the tools' titles and descriptions were enough.
- **Siri does read the skill.** The only difference between the last two rows is the skill, and it changed the reply. With it, Siri gave the name and price, as the skill asked. Without it, Siri also gave the stock count, in all 5 runs.
- **Chaining is slower.** About 60 seconds per run, against about 12 for a single tool.

## Not tested

- Whether a skill helps with requests Siri can't chain on its own: vaguer wording, more steps, or write actions that need confirmation.
- Skills in the native example (only the Expo path ran).
- The 64, 1,024 and 10,000-character limits.
- Two bundles in one target.
