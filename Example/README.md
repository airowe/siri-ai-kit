# SiriAIKit example

A native iOS app with one Siri AI tool, `GetCartIntent`, which reads a cart from [DummyJSON](https://dummyjson.com) with a logged-in token, plus Siri Evaluations tests that check it.

The app signs in to DummyJSON's public demo account when it opens. Access tokens last one minute, so every test exercises a refresh.

## Run it

You need Xcode 27.3 beta and an iPhone on iOS 27.3 beta with Siri AI on, Developer Mode on, and Settings > Developer > Enable UI Automation on. Siri Evaluations doesn't run on the Simulator.

1. Open `SiriAIKitExample.xcodeproj`, choose your team for both targets, and run the app on your iPhone.
2. Wait for "Signed in at …", then ask Siri: "In SiriAIKit Example, what's in my cart?"

To regenerate the project after adding files: `ruby scripts/generate-project.rb`.

## Run the evaluations

Keep the phone unlocked, on power and quiet: Siri speaks each reply.

```bash
xcodebuild test -project Example/SiriAIKitExample.xcodeproj -scheme SiriAIKitExampleEvals \
  -destination 'id=<device UDID>' -allowProvisioningUpdates DEVELOPMENT_TEAM=<team ID> \
  -only-testing:'SiriAIKitExampleEvals/callsCartToolEveryTime()' -resultBundlePath cart.xcresult
swift run siri-ai-eval summarize cart.xcresult --fail-on real
```

`refreshesExpiredTokenEveryTime()` waits 70 seconds before each run so the token expires. For the negative control, set `DemoAPI.refreshEnabled` to `false`: every reply should then say to sign in again, and the reply check must fail.
