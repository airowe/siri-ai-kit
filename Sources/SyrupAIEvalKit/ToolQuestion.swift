import Foundation

/// One question asked two ways: naming the app ("In ParcelPal, where's my order?") and without it
/// ("Where's my order?"), so an evaluation can measure whether Siri still picks the tool unprompted.
public struct ToolQuestion: Sendable, Equatable {
    public let question: String
    public let appName: String

    /// `question` is phrased as the person would ask without naming the app, for example "What's in my cart?".
    public init(_ question: String, appName: String) {
        precondition(!Self.mentions(appName, in: question), "ToolQuestion must not name the app: \(question)")
        self.question = question
        self.appName = appName
    }

    public var namingApp: String {
        "In \(appName), " + Self.recased(trimmed) { $0.lowercased() }
    }

    public var withoutAppName: String {
        Self.recased(trimmed) { $0.uppercased() }
    }

    private var trimmed: String { question.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Changes the first letter's case, unless the first word is "I" or has capitals of its own ("SKU", "iPhone").
    static func recased(_ text: String, _ change: (String) -> String) -> String {
        guard let first = text.first else { return text }
        let firstWord = text.prefix { !$0.isWhitespace }
        let pronounI = firstWord.prefix { $0 != "'" && $0 != "’" } == "I"
        let ownCapitals = firstWord.dropFirst().contains(where: \.isUppercase)
        guard !pronounI, !ownCapitals else { return text }
        return change(String(first)) + text.dropFirst()
    }

    static func mentions(_ appName: String, in question: String) -> Bool {
        question.localizedCaseInsensitiveContains(appName)
    }
}
