import Foundation

/// A named switch an evaluation turns on by launching the app with an argument, to put the app in a known state
/// before Siri runs: usually a broken one, for a negative control. Read it only in debug builds.
public struct EvalSwitch: Hashable, Sendable, ExpressibleByStringLiteral {
    public static let argumentPrefix = "--siri-ai-eval-switch="

    public let name: String

    /// `name` uses lowercase letters, digits and hyphens, for example "refresh-off".
    public init(_ name: String) {
        precondition(Self.isValidName(name), "EvalSwitch names use lowercase letters, digits and hyphens: \(name)")
        self.name = name
    }

    public init(stringLiteral name: String) { self.init(name) }

    /// What the evaluation passes to the app at launch.
    public var launchArgument: String { Self.argumentPrefix + name }

    /// Whether the app was launched with this switch.
    public func isOn(in arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains(launchArgument)
    }

    static func isValidName(_ name: String) -> Bool {
        name.wholeMatch(of: /[a-z0-9]+(-[a-z0-9]+)*/) != nil
    }
}
