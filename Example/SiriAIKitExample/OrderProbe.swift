import AppIntents
import CoreSpotlight
import Foundation
import SiriAIKit
import Synchronization

// Spike probe, not part of the example's pattern: can Siri answer live from an entity's @DeferredProperty,
// with only the entity's identity indexed? See docs/spikes/deferred-property.md.
//
// Three entities, each with a marker word that only one source can supply:
// - OrderEntity: identity indexed, status a @DeferredProperty with no indexing key. Marker "fish" (cart 3).
// - ShipmentEntity: status a @DeferredProperty *with* an indexing key. Marker "charger" (cart 2).
// - ReceiptEntity: control. Status a stored @Property with an indexing key, so it is certainly indexed. Marker "zebra".

private let probeTool = SiriTool(appName: DemoAPI.appName)

enum OrderProbe {
    static let orderMarker = "fish"
    static let shipmentMarker = "charger"
    static let controlMarker = "zebra"
    static let accessibilityIdentifier = "order-probe"

    /// How many times each entity's deferred getter has run in this process.
    static let getterCalls = Mutex<[String: Int]>([:])

    /// The live answer a deferred getter gives. It runs as a SiriTool call, so the outcome label shows which
    /// getter ran and when.
    static func liveStatus(of entity: String, _ fetch: @escaping @Sendable () async throws -> Cart) async -> String {
        getterCalls.withLock { $0[entity, default: 0] += 1 }
        return await probeTool.answer {
            ToolOutcomeLog.standard.note("\(entity) status getter")
            return describe(try await fetch())
        }
    }

    static func describe(_ cart: Cart) -> String {
        let total = cart.total.formatted(.currency(code: "USD"))
        let titles = cart.products.map(\.title).joined(separator: ", ")
        return "\(cart.totalProducts) products, \(total): \(titles)."
    }

    /// Indexes one of each entity, then reports whether indexing ran the getters and which markers Spotlight holds.
    static func run() async -> String {
        let index = CSSearchableIndex.default()
        do {
            try await index.deleteAppEntities(ofType: OrderEntity.self)
            try await index.deleteAppEntities(ofType: ShipmentEntity.self)
            try await index.deleteAppEntities(ofType: ReceiptEntity.self)
            try await index.indexAppEntities([OrderEntity(id: OrderEntity.onlyID)])
            try await index.indexAppEntities([ShipmentEntity(id: ShipmentEntity.onlyID)])
            try await index.indexAppEntities([ReceiptEntity(id: ReceiptEntity.onlyID)])
        } catch {
            return "Index failed: \(error)"
        }
        let callsWhileIndexing = getterCalls.withLock { calls in
            ["order", "shipment"].map { "\($0)=\(calls[$0, default: 0])" }.joined(separator: " ")
        }
        // Spotlight ingests asynchronously after indexAppEntities returns.
        try? await Task.sleep(for: .seconds(5))
        let counts = await [orderMarker, shipmentMarker, controlMarker].asyncMap { "\($0)=\(await matches($0))" }
        let attributeText = OrderEntity(id: OrderEntity.onlyID).defaultAttributeSet.contentDescription ?? "nil"
        let report = """
            Indexed. Getter calls while indexing: \(callsWhileIndexing). \
            Spotlight matches: \(counts.joined(separator: " ")). \
            Order contentDescription: \(attributeText)
            """
        print("[order-probe] \(report)")
        return report
    }

    /// Items in this app's Spotlight index whose text contains the word; "failed", or "timeout" (the query never
    /// finishes on the Simulator).
    static func matches(_ word: String) async -> String {
        await withTaskGroup(of: String.self) { group in
            group.addTask {
                let context = CSSearchQueryContext()
                context.fetchAttributes = ["contentDescription", "displayName"]
                let query = CSSearchQuery(queryString: "** == \"*\(word)*\"cd", queryContext: context)
                var count = 0
                do {
                    for try await _ in query.results { count += 1 }
                } catch {
                    return "failed"
                }
                return "\(count)"
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(10))
                return "timeout"
            }
            let first = await group.next() ?? "failed"
            group.cancelAll()
            return first
        }
    }
}

private extension Array where Element: Sendable {
    func asyncMap<T>(_ transform: (Element) async -> T) async -> [T] {
        var results: [T] = []
        for element in self { results.append(await transform(element)) }
        return results
    }
}

struct OrderEntity: IndexedEntity {
    static let onlyID = "3"
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Order"
    static let defaultQuery = OrderQuery()

    let id: String

    // The macro adds a stored `_status`, which replaces the memberwise init.
    init(id: String) { self.id = id }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "Order \(id)", synonyms: ["order \(id)", "my order"])
    }

    @DeferredProperty(title: "Status", description: "What's in the order and what it costs, fetched live.")
    var status: String {
        get async throws {
            await OrderProbe.liveStatus(of: "order") { try await DemoAPI.publicCart(id: 3) }
        }
    }
}

struct OrderQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [OrderEntity] {
        identifiers.filter { $0 == OrderEntity.onlyID }.map(OrderEntity.init)
    }

    func suggestedEntities() async throws -> [OrderEntity] { [OrderEntity(id: OrderEntity.onlyID)] }
}

struct ShipmentEntity: IndexedEntity {
    static let onlyID = "2"
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Shipment"
    static let defaultQuery = ShipmentQuery()

    let id: String

    // The macro adds a stored `_status`, which replaces the memberwise init.
    init(id: String) { self.id = id }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "Shipment \(id)", synonyms: ["shipment \(id)", "my shipment"])
    }

    @DeferredProperty(
        title: "Status",
        description: "What's in the shipment and what it costs, fetched live.",
        indexingKey: \.contentDescription
    )
    var status: String {
        get async throws {
            await OrderProbe.liveStatus(of: "shipment") { try await DemoAPI.publicCart(id: 2) }
        }
    }
}

struct ShipmentQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ShipmentEntity] {
        identifiers.filter { $0 == ShipmentEntity.onlyID }.map(ShipmentEntity.init)
    }

    func suggestedEntities() async throws -> [ShipmentEntity] { [ShipmentEntity(id: ShipmentEntity.onlyID)] }
}

struct ReceiptEntity: IndexedEntity {
    static let onlyID = "9"
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Receipt"
    static let defaultQuery = ReceiptQuery()

    let id: String

    @Property(title: "Status", indexingKey: \.contentDescription)
    var status: String

    init(id: String) {
        self.id = id
        status = "One \(OrderProbe.controlMarker) plush, $12.00."
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "Receipt \(id)", synonyms: ["receipt \(id)", "my receipt"])
    }
}

struct ReceiptQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ReceiptEntity] {
        identifiers.filter { $0 == ReceiptEntity.onlyID }.map(ReceiptEntity.init)
    }

    func suggestedEntities() async throws -> [ReceiptEntity] { [ReceiptEntity(id: ReceiptEntity.onlyID)] }
}
