import AppIntentsTesting
import Evaluations
import SiriAIEvalKit
import SiriEvaluations
import Testing

// Spike evaluations for docs/spikes/deferred-property.md. They record what Siri does; they don't define the pattern.

private let bundleIdentifier = "com.example.siriaikit"
private let definitions = IntentDefinitions(bundleIdentifier: bundleIdentifier)
private let orderEntity = definitions.entities["OrderEntity"]
private let shipmentEntity = definitions.entities["ShipmentEntity"]
/// From DummyJSON cart 3 (OrderEntity). Its status is not indexed, so Siri can only say this by running the getter.
private let orderMarker = "fish"
/// From DummyJSON cart 2 (ShipmentEntity). Its status is indexed, so Siri can say this from Spotlight alone.
private let shipmentMarker = "charger"
private let runs = 5
/// Ready once the app has re-indexed all three probe entities.
private let harness = SiriAppHarness(
    bundleIdentifier: bundleIdentifier,
    readyWhen: .labelBegins("order-probe", with: "Indexed")
)

/// No `Calls`: the point is whether Siri answers from the entity alone. GetCartIntent reads cart 1, so it can't
/// supply either marker.
private func orderScenario() -> SiriScenario {
    SiriScenario {
        UserTurn("In SiriAIKit Example, what's in order 3?") {
            Finds {
                orderEntity.expectIdentifier("3")
            }
            SiriResponse(.contains(orderMarker, caseSensitive: false))
        }
    }
}

private func shipmentScenario() -> SiriScenario {
    SiriScenario {
        UserTurn("In SiriAIKit Example, what's in shipment 2?") {
            Finds {
                shipmentEntity.expectIdentifier("2")
            }
            SiriResponse(.contains(shipmentMarker, caseSensitive: false))
        }
    }
}

@available(iOS 27.3, *)
private func expectFoundEntities(sourceLocation: SourceLocation = #_sourceLocation) {
    let mean = EvaluationContext.current.result.aggregateValue(.mean(of: .foundEntitiesAllPass))
    #expect(mean == 1, "foundEntitiesAllPass mean was \(String(describing: mean))", sourceLocation: sourceLocation)
}

/// Does Siri read a deferred property live? Pass = it found the order and named a product only the getter knows.
/// Check the outcome attachment too: "order status getter" timed after the run means the getter ran for Siri,
/// not only at launch-time indexing.
@Test(.evaluates(ToolEvaluation(
    name: "Order status from a deferred property, repeated",
    harness: harness,
    dataset: .repeating(times: runs, orderScenario)
)))
func readsDeferredPropertyLive() async throws {
    expectFoundEntities()
    try expectAllPass(.siriResponse)
}

/// Control for the stale-answer rule. A pass whose recorded outcome isn't a "shipment status getter" timed after
/// the run means Siri answered from the index. (`summarize` can't flag that here: there's no expected tool.)
@Test(.evaluates(ToolEvaluation(
    name: "Shipment status from an indexed deferred property, repeated",
    harness: harness,
    dataset: .repeating(times: runs, shipmentScenario)
)))
func answersIndexedDeferredProperty() async throws {
    expectFoundEntities()
    try expectAllPass(.siriResponse)
}
