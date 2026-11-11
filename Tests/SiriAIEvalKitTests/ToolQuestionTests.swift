import Testing
@testable import SiriAIEvalKit

struct ToolQuestionTests {
    static let appName = "SiriAIKit Example"

    @Test(arguments: [
        ("What's in my cart?", "In SiriAIKit Example, what's in my cart?"),
        ("  What's in my cart?  ", "In SiriAIKit Example, what's in my cart?"),
        ("what's in my cart?", "In SiriAIKit Example, what's in my cart?"),
        ("I want my cart total", "In SiriAIKit Example, I want my cart total"),
        ("I'm out of milk, add it", "In SiriAIKit Example, I'm out of milk, add it"),
        ("SKU 42 in stock?", "In SiriAIKit Example, SKU 42 in stock?"),
        ("iPhone cases on sale?", "In SiriAIKit Example, iPhone cases on sale?"),
        ("Is my order late?", "In SiriAIKit Example, is my order late?"),
    ])
    func namingAppPrefixesTheApp(question: String, expected: String) {
        #expect(ToolQuestion(question, appName: Self.appName).namingApp == expected)
    }

    @Test(arguments: [
        ("What's in my cart?", "What's in my cart?"),
        ("  what's in my cart?\n", "What's in my cart?"),
        ("iPhone cases on sale?", "iPhone cases on sale?"),
        ("SKU 42 in stock?", "SKU 42 in stock?"),
    ])
    func withoutAppNameIsTheQuestionAlone(question: String, expected: String) {
        #expect(ToolQuestion(question, appName: Self.appName).withoutAppName == expected)
    }

    @Test(arguments: [
        ("What's in my SiriAIKit Example cart?", true),
        ("what's in my siriaikit example cart?", true),
        ("What's in my cart?", false),
        ("Is SiriAIKit up?", false),
    ])
    func mentionsTheAppIgnoringCase(question: String, expected: Bool) {
        #expect(ToolQuestion.mentions(Self.appName, in: question) == expected)
    }
}
