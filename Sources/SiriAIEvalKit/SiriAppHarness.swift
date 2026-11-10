#if os(iOS) && canImport(SiriEvaluations) && canImport(XCTest)
import Foundation
import SiriAIKit
import XCTest

public enum ReadySignal: Sendable {
    /// Ready once the element's label contains the text.
    case label(_ identifier: String, contains: String)
    /// Ready once the element's label begins with the text.
    case labelBegins(_ identifier: String, with: String)

    var identifier: String {
        switch self {
        case .label(let identifier, _), .labelBegins(let identifier, _): identifier
        }
    }

    var predicate: NSPredicate {
        switch self {
        case .label(_, let text): NSPredicate(format: "label CONTAINS %@", text)
        case .labelBegins(_, let text): NSPredicate(format: "label BEGINSWITH %@", text)
        }
    }
}

public enum HarnessError: Error, Equatable {
    /// The ready signal never appeared; `label` is what the element showed, or "missing".
    case notReady(label: String)
}

/// Launches your app before each Siri run and reads back what its tool did.
@available(iOS 27.3, *)
public struct SiriAppHarness: Sendable {
    public let bundleIdentifier: String
    public let readyWhen: ReadySignal
    public let timeout: Duration

    public init(bundleIdentifier: String, readyWhen: ReadySignal, timeout: Duration = .seconds(90)) {
        self.bundleIdentifier = bundleIdentifier
        self.readyWhen = readyWhen
        self.timeout = timeout
    }

    @MainActor public func launchAndWaitUntilReady() throws {
        let app = XCUIApplication(bundleIdentifier: bundleIdentifier)
        app.launch()
        let element = app.staticTexts[readyWhen.identifier]
        let expectation = XCTNSPredicateExpectation(predicate: readyWhen.predicate, object: element)
        let seconds = TimeInterval(timeout.components.seconds)
        guard XCTWaiter().wait(for: [expectation], timeout: seconds) == .completed else {
            throw HarnessError.notReady(label: element.exists ? element.label : "missing")
        }
    }

    /// Brings the app forward without relaunching it, so the outcome isn't reset, and reads the outcome label.
    @MainActor public func lastToolOutcome() -> String? {
        let app = XCUIApplication(bundleIdentifier: bundleIdentifier)
        app.activate()
        let element = app.staticTexts[ToolOutcomeLog.accessibilityIdentifier]
        guard element.waitForExistence(timeout: 10) else { return nil }
        return ToolOutcomeLog.outcome(fromLabel: element.label)
    }
}
#endif
