import Foundation
import SyrupAIKit

/// The app's own API code: DummyJSON's public carts.
enum DemoAPI {
    static let appName = "SyrupAIKit Example"
    /// A host that never resolves, used only when an evaluation launches the app with `EvalSwitch.badHost`, for the
    /// negative control: every call must then reply "Couldn't reach". Release builds ignore the switch.
    static var base: URL {
        #if DEBUG
        if EvalSwitch.badHost.isOn() { return URL(string: "https://syrup-ai-kit-bad-host.invalid")! }
        #endif
        return URL(string: "https://dummyjson.com")!
    }

    /// The cart the Siri tool reads.
    static func cart() async throws -> Cart {
        try await publicCart(id: 1)
    }

    /// A public cart by id. The deferred-property spike uses carts 2 and 3 so their products never overlap cart 1's.
    static func publicCart(id: Int) async throws -> Cart {
        let (data, response) = try await URLSession.shared.data(from: base.appending(path: "carts/\(id)"))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw DemoAPIError.badStatus(status) }
        return try JSONDecoder().decode(Cart.self, from: data)
    }
}

enum DemoAPIError: Error, Equatable {
    case badStatus(Int)
}
