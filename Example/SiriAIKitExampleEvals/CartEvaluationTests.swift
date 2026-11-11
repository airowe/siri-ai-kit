import AppIntentsTesting
import SiriAIEvalKit
import SiriAIKit
import SiriEvaluations
import Testing

private let bundleIdentifier = "com.example.siriaikit"
private let getCartIntent = IntentDefinitions(bundleIdentifier: bundleIdentifier).intents["GetCartIntent"]
private let cartQuestion = ToolQuestion("What's in my cart?", appName: "SiriAIKit Example")
/// A product in DummyJSON's fixed cart 1. Nothing about the cart is indexed, so naming it proves the API was called.
private let productOnlyTheAPIKnows = "motorcycle"
private let reliabilityRuns = 5
/// More than one, so a single run the harness cuts short can't leave the control with nothing to show.
private let negativeControlRuns = 2
/// Longer than the app's one-minute access token, so the tool must refresh it.
private let tokenExpiryWait: Duration = .seconds(70)
private let harness = SiriAppHarness(
    bundleIdentifier: bundleIdentifier,
    readyWhen: .labelBegins("auth-status", with: "Signed in")
)

private func cartScenario(_ prompt: String) -> SiriScenario {
    SiriScenario {
        UserTurn(prompt) {
            Calls {
                getCartIntent
            }
            SiriResponse(.contains(productOnlyTheAPIKnows, caseSensitive: false))
        }
    }
}

private func cartScenarioNamingApp() -> SiriScenario { cartScenario(cartQuestion.namingApp) }

@Test(.evaluates(ToolEvaluation(
    name: "Cart contents from the demo API, repeated",
    harness: harness,
    dataset: .repeating(times: reliabilityRuns, cartScenarioNamingApp)
)))
func callsCartToolEveryTime() async throws {
    try expectAllPass(.intents, .siriResponse)
}

@Test(.evaluates(ToolEvaluation(
    name: "Cart after the access token expires, repeated",
    harness: harness,
    before: .waitFor(tokenExpiryWait),
    dataset: .repeating(times: reliabilityRuns, cartScenarioNamingApp)
)))
func refreshesExpiredTokenEveryTime() async throws {
    try expectAllPass(.intents, .siriResponse)
}

/// The same scenario with token refresh switched off: the reply check must fail, or it can't be trusted.
@Test(.evaluates(ToolEvaluation.negativeControl(
    name: "Cart after the access token expires, refresh off",
    harness: harness,
    turningOn: .refreshOff,
    before: .waitFor(tokenExpiryWait),
    dataset: .repeating(times: negativeControlRuns, cartScenarioNamingApp)
)))
func replyCheckFailsWithRefreshOff() async throws {
    try expectAllFail(.siriResponse)
}

/// "What's in my cart?" without the app's name. Informational: the summary reports it and never fails on it.
@Test(.evaluates(ToolEvaluation.appNotNamed(
    name: "Cart contents without the app's name, repeated",
    harness: harness,
    question: cartQuestion,
    times: reliabilityRuns,
    scenario: cartScenario
)))
func cartToolWithoutTheAppName() async throws {}
