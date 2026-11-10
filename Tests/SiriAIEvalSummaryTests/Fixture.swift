import Foundation
@testable import SiriAIEvalSummary

enum Fixture: String, CaseIterable {
    case cartAllPass = "cart-all-pass"
    case cartNegativeControl = "cart-negative-control"
    case authWithIncomplete = "auth-with-incomplete"
    case orderOneIncomplete = "order-one-incomplete"
    case noToolExpected = "no-tool-expected"

    var url: URL {
        Bundle.module.url(forResource: rawValue, withExtension: "xcevalresult", subdirectory: "Fixtures")!
    }

    func report() throws -> EvalReport { try EvalResultParser.parse(contentsOf: url) }
}

func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "siri-ai-eval-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
