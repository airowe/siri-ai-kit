import SyrupAIKit
import XCTest

/// Spike: can Siri trigger the example app's tool on the Simulator, and can a test see the result?
final class SiriOnSimulatorTests: XCTestCase {
    private let bundleIdentifier = "com.example.syrupaikit"
    private let request = "In SyrupAIKit Example, what's in my cart?"
    private let readyTimeout: TimeInterval = 60
    private let siriTimeout: TimeInterval = 60

    @MainActor
    func testSiriRequestRunsCartTool() throws {
        let app = XCUIApplication(bundleIdentifier: bundleIdentifier)
        app.launch()
        let status = app.staticTexts["app-status"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH 'Ready'"), object: status)
        XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: readyTimeout), .completed, "app-status: \(status.label)")
        let before = app.staticTexts[ToolOutcomeLog.accessibilityIdentifier].label
        print("SPIKE outcome before Siri: \(before)")

        XCUIDevice.shared.siriService.activate(voiceRecognitionText: request)

        // Record what Siri shows. Querying siri.staticTexts here times out ("Failed to resolve query") when the
        // Siri UI never presents, so this only takes screenshots.
        for second in stride(from: 5, through: Int(siriTimeout), by: 5) {
            RunLoop.current.run(until: Date.now.addingTimeInterval(5))
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "siri-\(second)s"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        app.activate()
        let outcome = app.staticTexts[ToolOutcomeLog.accessibilityIdentifier]
        XCTAssertTrue(outcome.waitForExistence(timeout: 10))
        print("SPIKE outcome after Siri: \(outcome.label)")
        XCTAssertNotEqual(outcome.label, before, "the tool never ran")
        XCTAssertTrue(ToolOutcomeLog.outcome(fromLabel: outcome.label).hasPrefix("succeeded"), outcome.label)
    }
}
