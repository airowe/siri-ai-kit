import SyrupAIKit

/// Switches the evaluations launch the app with. Compiled into both the app and the evaluations target, so the
/// names can't drift apart.
extension EvalSwitch {
    /// Points the API at a host that can't be reached, so every call must reply "Couldn't reach".
    static let badHost: EvalSwitch = "bad-host"
}
