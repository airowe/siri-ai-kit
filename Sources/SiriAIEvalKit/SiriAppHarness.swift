#if canImport(SiriEvaluations) && canImport(XCTest)
import XCTest
import SiriEvaluations
import Evaluations
import AppIntentsTesting

@available(iOS 27.3, *)
public struct SiriAppHarness: Sendable {
    public let bundleIdentifier: String
}
#endif
