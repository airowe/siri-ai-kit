import SiriAIKit

/// Switches the evaluations launch the app with. Compiled into both the app and the evaluations target, so the
/// names can't drift apart.
extension EvalSwitch {
    /// Turns off token refresh, so every call after the access token expires must reply "sign in again".
    static let refreshOff: EvalSwitch = "refresh-off"
}
