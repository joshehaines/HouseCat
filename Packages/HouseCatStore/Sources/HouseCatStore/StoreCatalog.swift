import HouseCatCore

/// Every launch product (SPEC "Monetisation and the shop"). Product IDs use the
/// `housecat.` prefix and can never be renamed in App Store Connect. No rare
/// looks at launch: every cat-builder option is free.
public struct ShopProduct: Hashable, Sendable, Codable {
    public enum Kind: String, Sendable, Codable {
        case nonConsumable
        case autoRenewable
        case nonRenewing
        case consumable
    }

    /// What owning the product unlocks.
    public enum Unlock: Hashable, Sendable, Codable {
        case outfit(String)
        case set(String)
        /// A set, its outfit and Beans.
        case bundle(set: String, outfit: String, beans: Int)
        case catSlot(Int)
        case starter
        case housewarmingPack
        case club
        case lifetime
        case founders
        case seasonPass(String)
        /// Consumable gifts unlock nothing for the buyer; the recipient redeems them.
        case gift(GiftKind)
    }

    public enum GiftKind: Hashable, Sendable, Codable {
        case clubYearly
        case cat
        case set(String)
        case seasonPass
    }

    public var id: String
    public var kind: Kind
    /// UK price in pounds (the App Store tier; StoreKit's `displayPrice` is what the app shows).
    public var priceGBP: String
    public var unlock: Unlock
    public var displayName: String
}

public struct StoreCatalog: Sendable {
    public static let subscriptionGroup = "Cat Club"
    public static let clubMonthly = "housecat.club.monthly"
    public static let clubYearly = "housecat.club.yearly"
    public static let lifetime = "housecat.lifetime"
    public static let founders = "housecat.founders"
    public static let starter = "housecat.starter"
    public static let housewarmingPack = "housecat.season.housewarming"
    /// Adoptions for the second, third and fourth cat.
    public static let catSlots = [2, 3, 4]
    /// The 7-day trial is an introductory offer on the yearly plan.
    public static let yearlyTrialDays = 7

    public private(set) var products: [ShopProduct]

    /// Builds the catalogue from the content: paid outfits, the six sets and the seasons.
    public init(
        paidOutfits: [(id: String, name: String)],
        sets: [(id: String, name: String, outfit: String, beans: Int)],
        seasons: [(id: String, name: String)]
    ) {
        var products: [ShopProduct] = []
        for outfit in paidOutfits {
            products.append(.init(
                id: "housecat.outfit.\(outfit.id)",
                kind: .nonConsumable,
                priceGBP: "0.99",
                unlock: .outfit(outfit.id),
                displayName: outfit.name
            ))
        }
        for set in sets {
            products.append(.init(
                id: "housecat.set.\(set.id)",
                kind: .nonConsumable,
                priceGBP: "2.99",
                unlock: .set(set.id),
                displayName: set.name
            ))
            products.append(.init(
                id: "housecat.bundle.\(set.id)",
                kind: .nonConsumable,
                priceGBP: "4.99",
                unlock: .bundle(set: set.id, outfit: set.outfit, beans: set.beans),
                displayName: "\(set.name) Bundle"
            ))
        }
        for slot in Self.catSlots {
            products.append(.init(
                id: "housecat.cat.slot\(slot)",
                kind: .nonConsumable,
                priceGBP: "4.99",
                unlock: .catSlot(slot),
                displayName: "Adopt a Cat"
            ))
        }
        products += [
            .init(id: Self.starter, kind: .nonConsumable, priceGBP: "1.99", unlock: .starter, displayName: "Starter Pack"),
            .init(
                id: Self.housewarmingPack,
                kind: .nonConsumable,
                priceGBP: "4.99",
                unlock: .housewarmingPack,
                displayName: "Housewarming Pack"
            ),
            .init(id: Self.clubMonthly, kind: .autoRenewable, priceGBP: "2.99", unlock: .club, displayName: "Cat Club Monthly"),
            .init(id: Self.clubYearly, kind: .autoRenewable, priceGBP: "19.99", unlock: .club, displayName: "Cat Club Yearly"),
            .init(id: Self.lifetime, kind: .nonConsumable, priceGBP: "39.99", unlock: .lifetime, displayName: "Forever Home"),
            .init(id: Self.founders, kind: .nonConsumable, priceGBP: "29.99", unlock: .founders, displayName: "Founders' Pack"),
        ]
        for season in seasons {
            products.append(.init(
                id: "housecat.pass.\(season.id)",
                kind: .nonRenewing,
                priceGBP: "4.99",
                unlock: .seasonPass(season.id),
                displayName: "\(season.name) Pass"
            ))
        }
        products.append(.init(
            id: "housecat.gift.club.yearly",
            kind: .consumable,
            priceGBP: "19.99",
            unlock: .gift(.clubYearly),
            displayName: "Gift: Cat Club Yearly"
        ))
        products.append(.init(
            id: "housecat.gift.cat",
            kind: .consumable,
            priceGBP: "4.99",
            unlock: .gift(.cat),
            displayName: "Gift: Adopt a Cat"
        ))
        for set in sets {
            products.append(.init(
                id: "housecat.gift.set.\(set.id)",
                kind: .consumable,
                priceGBP: "2.99",
                unlock: .gift(.set(set.id)),
                displayName: "Gift: \(set.name)"
            ))
        }
        products.append(.init(
            id: "housecat.gift.pass",
            kind: .consumable,
            priceGBP: "4.99",
            unlock: .gift(.seasonPass),
            displayName: "Gift: Season Pass"
        ))
        self.products = products
    }

    /// The catalogue for the shipped content.
    public init(content: ContentBundle) {
        self.init(
            paidOutfits: content.outfits.outfits.filter { $0.pool == .paid }.map { ($0.id, $0.name) },
            sets: content.catalogue.sets.map { ($0.id, $0.name, $0.outfit, $0.bundleBeans) },
            seasons: content.seasons.seasons.map { ($0.id, $0.name) }
        )
    }

    public func product(_ id: String) -> ShopProduct? {
        products.first { $0.id == id }
    }

    public var productIDs: [String] {
        products.map(\.id)
    }
}
