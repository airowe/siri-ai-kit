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

## Not tested

- Whether Siri picks up the skills. That needs a device.
- The 64, 1,024 and 10,000-character limits.
- Two bundles in one target.
- A real `expo prebuild`.
