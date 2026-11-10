import AppIntents
import Foundation
import SiriAIKit

/// Answers from a live, authenticated API call, so nothing about the cart is indexed for Siri to answer from instead.
@AppIntent(.tool)
struct GetCartIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Cart"
    static let description = IntentDescription(
        "Tells the person what is in their shopping cart and what it costs."
    )

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let answer: String
        do {
            answer = describe(try await DemoAPI.client.get("auth/carts/1", as: Cart.self))
        } catch {
            answer = error.reply(appName: DemoAPI.appName)
        }
        return .result(value: answer, dialog: "\(answer)")
    }

    private func describe(_ cart: Cart) -> String {
        let total = cart.total.formatted(.currency(code: "USD"))
        let titles = cart.products.map(\.title).joined(separator: ", ")
        return "Your cart has \(cart.totalProducts) products, \(total): \(titles)."
    }
}

struct Cart: Decodable {
    struct Product: Decodable {
        let title: String
    }

    let products: [Product]
    let total: Double
    let totalProducts: Int
}
