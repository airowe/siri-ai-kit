# Syrup AI Kit example

A native iOS app with one Siri AI tool, `GetCartIntent`, which reads a public cart from [DummyJSON](https://dummyjson.com), plus Siri Evaluations tests that check it.

## Run it

You need Xcode 27.3 beta and an iPhone on iOS 27.3 beta with Siri AI on, Developer Mode on, and Settings > Developer > Enable UI Automation on. Siri Evaluations doesn't run on the Simulator.

1. Open `SyrupAIKitExample.xcodeproj`, choose your team for both targets, and run the app on your iPhone.
2. When the app shows "Ready", ask Siri: "In SyrupAIKit Example, what's in my cart?"

To regenerate the project after adding files: `ruby scripts/generate-project.rb`.

## Run the evaluations

Keep the phone unlocked, on power and quiet: Siri speaks each reply.

```bash
xcodebuild test -project Example/SyrupAIKitExample.xcodeproj -scheme SyrupAIKitExampleEvals \
  -destination 'id=<device UDID>' -allowProvisioningUpdates DEVELOPMENT_TEAM=<team ID> \
  -only-testing:'SyrupAIKitExampleEvals/callsCartToolEveryTime()' -resultBundlePath cart.xcresult
swift run syrup-ai-eval summarize cart.xcresult --fail-on real
```

`replyCheckFailsWithBadHost()` is the negative control. It launches the app with `EvalSwitch.badHost` (defined in `Shared/EvalSwitches.swift`), which points the API at a host that can't be reached. Every reply should say "Couldn't reach SyrupAIKit Example right now.", and the reply check must fail. No code edit is needed.

`cartToolWithoutTheAppName()` asks "What's in my cart?" without naming the app. It's informational: the summary reports its pass rate and never fails on it.

Run all three and summarize them together:

```bash
xcodebuild test -project Example/SyrupAIKitExample.xcodeproj -scheme SyrupAIKitExampleEvals \
  -destination 'id=<device UDID>' -allowProvisioningUpdates DEVELOPMENT_TEAM=<team ID> -resultBundlePath all.xcresult
swift run syrup-ai-eval summarize all.xcresult --fail-on real
```
