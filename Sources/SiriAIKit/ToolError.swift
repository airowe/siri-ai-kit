import Foundation

public enum ToolError: Error, Equatable, Sendable {
    case signedOut
    case timedOut
    case unreachable
    case rejected(status: Int)
    case invalidResponse
    /// A token store failed with this Keychain status. Tools never see it: the client reports `.signedOut`.
    case keychain(OSStatus)
}
