import AppIntents
import Foundation
import SyrupAIKit

private let tool = SiriTool(appName: DemoAPI.appName)

/// Answers from a live API call, so nothing about the cart is indexed for Siri to answer from instead.
@AppIntent(.tool)
struct GetCartIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Cart"
    static let description = IntentDescription(
        "Tells the person what is in their shopping cart and what it costs."
    )

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let answer = await tool.answer { Self.describe(try await DemoAPI.cart()) }
        return .result(value: answer, dialog: "\(answer)")
    }

    private static func describe(_ cart: Cart) -> String {
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
