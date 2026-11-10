/// Where a tool reads and writes the signed-in person's tokens.
///
/// Siri can run a tool while the phone is locked, so a store must be readable then.
public protocol TokenStore: Sendable {
    func load() throws(ToolError) -> Tokens?
    func save(_ tokens: Tokens) throws(ToolError)
    func clear()
}
