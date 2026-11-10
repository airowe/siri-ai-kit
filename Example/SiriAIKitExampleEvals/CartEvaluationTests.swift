import AppIntentsTesting
import SiriAIEvalKit
import SiriEvaluations
import Testing

private let bundleIdentifier = "com.example.siriaikit"
private let getCartIntent = IntentDefinitions(bundleIdentifier: bundleIdentifier).intents["GetCartIntent"]
/// A product in DummyJSON's fixed cart 1. Nothing about the cart is indexed, so naming it proves the API was called.
private let productOnlyTheAPIKnows = "motorcycle"
private let reliabilityRuns = 5
/// Longer than the app's one-minute access token, so the tool must refresh it.
private let tokenExpiryWait: Duration = .seconds(70)
private let harness = SiriAppHarness(
    bundleIdentifier: bundleIdentifier,
    readyWhen: .labelBegins("auth-status", with: "Signed in")
)

private func cartScenario() -> SiriScenario {
    SiriScenario {
        UserTurn("In SiriAIKit Example, what's in my cart?") {
            Calls {
                getCartIntent
            }
            SiriResponse(.contains(productOnlyTheAPIKnows, caseSensitive: false))
        }
    }
}

@Test(.evaluates(ToolEvaluation(
    name: "Cart contents from the demo API, repeated",
    harness: harness,
    dataset: .repeating(times: reliabilityRuns, cartScenario)
)))
func callsCartToolEveryTime() async throws {
    try expectAllPass(.intents, .siriResponse)
}

@Test(.evaluates(ToolEvaluation(
    name: "Cart after the access token expires, repeated",
    harness: harness,
    before: .waitFor(tokenExpiryWait),
    dataset: .repeating(times: reliabilityRuns, cartScenario)
)))
func refreshesExpiredTokenEveryTime() async throws {
    try expectAllPass(.intents, .siriResponse)
}
