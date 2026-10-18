import HouseCatCore

/// Every product (Josh, 18 Oct: three kinds, like a builder game's shop). Bean packs, the one currency, bought
/// as many times as wanted; room looks, a whole room in one tap, kept forever; and Cat Club, the one optional
/// subscription, which includes every season's paid track. Everything else (single pieces, outfits, presents
/// for a co-owner) is bought with Beans. Product IDs use the `housecat.` prefix and can never be renamed in App
/// Store Connect once live.
public struct ShopProduct: Hashable, Sendable, Codable {
    public enum Kind: String, Sendable, Codable {
        case nonConsumable
        case autoRenewable
        case nonRenewing
        case consumable
    }

    /// What owning the product gives.
    public enum Unlock: Hashable, Sendable, Codable {
        /// A pack of Beans, granted into the save once per transaction.
        case beans(Int)
        /// The once-only starter offer: Beans at a better rate, once.
        case starter(beans: Int)
        /// A room look (bundles.json), granted into the save once per transaction.
        case bundle(String)
        case club
    }

    public var id: String
    public var kind: Kind
    /// UK price in pounds (the App Store tier; StoreKit's `displayPrice` is what the app shows).
    public var priceGBP: String
    public var unlock: Unlock
    public var displayName: String

    /// Beans the product puts in the save (a pack or the starter offer).
    public var beans: Int? {
        switch unlock {
        case let .beans(amount), let .starter(amount): amount
        default: nil
        }
    }
}

public struct StoreCatalog: Sendable {
    public static let subscriptionGroup = "Cat Club"
    public static let clubMonthly = "housecat.club.monthly"
    public static let clubYearly = "housecat.club.yearly"
    public static let starter = "housecat.starter"
    /// The Housewarming living room, the launch month's look (its SKU from before looks were per room).
    public static let housewarmingPack = "housecat.season.housewarming"
    /// The 7-day trial is an introductory offer on the yearly plan.
    public static let yearlyTrialDays = 7

    /// The Bean packs, smallest first: id, Beans, UK price, name (each bigger pack gives more Beans a pound).
    public static let beanPacks: [(id: String, beans: Int, price: String, name: String)] = [
        ("housecat.beans.handful", Tuning.Beans.packs[0], "0.99", "A handful of Beans"),
        ("housecat.beans.pouch", Tuning.Beans.packs[1], "1.99", "A pouch of Beans"),
        ("housecat.beans.jar", Tuning.Beans.packs[2], "3.99", "A jar of Beans"),
        ("housecat.beans.sack", Tuning.Beans.packs[3], "9.99", "A sack of Beans"),
        ("housecat.beans.barrel", Tuning.Beans.packs[4], "19.99", "A barrel of Beans"),
    ]

    public private(set) var products: [ShopProduct]

    /// The products for the room looks given (id, name, SKU, UK price).
    public init(bundles: [(id: String, name: String, sku: String, price: String)]) {
        var products: [ShopProduct] = Self.beanPacks.map {
            ShopProduct(id: $0.id, kind: .consumable, priceGBP: $0.price, unlock: .beans($0.beans), displayName: $0.name)
        }
        products.append(.init(
            id: Self.starter,
            kind: .nonConsumable,
            priceGBP: "1.99",
            unlock: .starter(beans: Tuning.Beans.starterPack),
            displayName: "Starter Beans"
        ))
        for bundle in bundles {
            products.append(.init(id: bundle.sku, kind: .nonConsumable, priceGBP: bundle.price, unlock: .bundle(bundle.id), displayName: bundle.name))
        }
        products += [
            .init(id: Self.clubMonthly, kind: .autoRenewable, priceGBP: "2.99", unlock: .club, displayName: "Cat Club Monthly"),
            .init(id: Self.clubYearly, kind: .autoRenewable, priceGBP: "19.99", unlock: .club, displayName: "Cat Club Yearly"),
        ]
        self.products = products
    }

    /// The catalogue for the shipped content.
    public init(content: ContentBundle) {
        self.init(bundles: content.bundles.bundles.map { ($0.id, $0.name, $0.sku, $0.price) })
    }

    public func product(_ id: String) -> ShopProduct? {
        products.first { $0.id == id }
    }

    /// The product that sells a room look.
    public func product(bundle id: String) -> ShopProduct? {
        products.first { $0.unlock == .bundle(id) }
    }

    public var productIDs: [String] {
        products.map(\.id)
    }
}
