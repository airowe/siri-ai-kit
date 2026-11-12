# Contributing

Thanks for helping. Issues and pull requests are welcome, including small doc fixes.

## Before you start

- For anything bigger than a fix, open an issue first so we can agree on the approach.
- Issues labelled [`good first issue`](https://github.com/airowe/syrup-ai-kit/labels/good%20first%20issue) don't need a phone set up for Siri AI.

## Setup

- Xcode 27.3 beta and Swift 6 for the Swift package. Node 20 or later for the Expo plugin in `expo-plugin/`.
- Running Siri Evaluations needs an iPhone on iOS 27.3 beta with Siri AI on: see [INSTALL.md](INSTALL.md). Most changes don't need one.

## Checks

Run these before opening a pull request:

```bash
swift build && swift test
cd expo-plugin && npm ci && npm test && npx tsc --noEmit -p plugin
```

## Pull requests

- Write the test first, then the change. Swift tests use Swift Testing; plugin tests use Jest.
- Use [Conventional Commits](https://www.conventionalcommits.org/) for titles, for example `fix(expo-plugin): …` or `docs: …`.
- If you ran an evaluation on a device, paste the `syrup-ai-eval summarize` output in the description. Say so if you didn't.
- Keep claims about Siri to what a run showed. Apple's preview changes, so write down the iOS and Xcode builds you used.

## Reporting a Siri behaviour

Include the prompt, what Siri said, the tool outcome, and the iOS build. Run `syrup-ai-eval summarize <result>.xcresult` and paste its output if you have one.
