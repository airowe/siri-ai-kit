---
name: siri-ai
description: Use when asked to make an iOS, Expo or React Native app work with Siri, Siri AI, the new Siri or Apple Intelligence in Siri, to let people talk to or ask Siri about the app, or to set up App Intents so Siri can use it. Start here before the other Siri AI skills.
license: MIT
---

# Making an app work with Siri AI

## Overview

Siri AI is Apple's Siri AI Developer Preview (iOS 27.3 SDK). An app joins it through **tools**: App Intents marked `@AppIntent(.tool)` that Siri calls to answer a question ("where's my order?") or do one action ("add milk to my list"). SyrupAIKit (`https://github.com/airowe/syrup-ai-kit`) and its Expo plugin, `expo-syrup-ai-kit`, cover the parts that are easy to get wrong. This skill picks the next skill to read.

## 1. Find the app's stack

| What the repo has | Stack |
|---|---|
| `expo` or `react-native` in `package.json`, an `app.json` or `app.config.*` | Expo / React Native |
| An `.xcodeproj` or `Package.swift`, Swift sources, no React Native | Native iOS |

## 2. Read the skill for the job

| The person wants | Expo / React Native | Native iOS |
|---|---|---|
| Siri in their app, and no tools are chosen yet | `siri-ai-discover` | `siri-ai-discover` steps 1 to 3, on the Swift code; skip `siri-tools.json` and the handlers |
| To set up the kit or write a tool | `expo-syrup-ai-kit` | `siri-ai-tool` |
| Proof that Siri calls the tool, or to read an evaluation | `siri-ai-eval` | `siri-ai-eval` |
| Siri to chain several tools for one request (App Skills) | `siri-ai-discover`, then the plugin's `skills` option | Add a Skills Bundle to the app target in Xcode |

A vague request ("add Siri", "make it work with Siri AI") starts with discovery: which questions and actions people would ask Siri for.

## 3. Tell the person what the preview allows

Say this before writing code, so they don't expect more than Siri can do yet:

- It needs Xcode 27.3 beta, and an iPhone that supports Apple Intelligence on the 27.3 beta.
- Tools reach only the developer's own builds and internal TestFlight testers; not external testers or the App Store.
- Siri runs it in English, French, Japanese, Korean, Portuguese and Spanish, not in the EU on iOS, and not for people under 13.

## Not covered here

- **Other Apple Intelligence features** (Writing Tools, Image Playground, the Foundation Models framework): they aren't Siri tools. Say so instead of using these skills.
- **Older Siri paths** (SiriKit intents, `AppShortcutsProvider` phrases): they aren't Siri AI tools. If the person wants those, say this kit is for the Siri AI preview.

## If the other skills are missing

Install them before going on. In Claude Code:

```
/plugin marketplace add airowe/syrup-ai-kit
/plugin install syrup-ai-kit@syrup-ai-kit
```

For other agents, see the kit's `INSTALL.md`.
