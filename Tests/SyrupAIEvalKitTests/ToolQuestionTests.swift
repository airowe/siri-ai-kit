import Testing
@testable import SyrupAIEvalKit

struct ToolQuestionTests {
    static let appName = "SyrupAIKit Example"

    @Test(arguments: [
        ("What's in my cart?", "In SyrupAIKit Example, what's in my cart?"),
        ("  What's in my cart?  ", "In SyrupAIKit Example, what's in my cart?"),
        ("what's in my cart?", "In SyrupAIKit Example, what's in my cart?"),
        ("I want my cart total", "In SyrupAIKit Example, I want my cart total"),
        ("I'm out of milk, add it", "In SyrupAIKit Example, I'm out of milk, add it"),
        ("SKU 42 in stock?", "In SyrupAIKit Example, SKU 42 in stock?"),
        ("iPhone cases on sale?", "In SyrupAIKit Example, iPhone cases on sale?"),
        ("Is my order late?", "In SyrupAIKit Example, is my order late?"),
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
        ("What's in my SyrupAIKit Example cart?", true),
        ("what's in my syrupaikit example cart?", true),
        ("What's in my cart?", false),
        ("Is SyrupAIKit up?", false),
    ])
    func mentionsTheAppIgnoringCase(question: String, expected: Bool) {
        #expect(ToolQuestion.mentions(Self.appName, in: question) == expected)
    }
}
