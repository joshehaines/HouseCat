import Foundation
import HouseCatCore
@testable import HouseCatStore
import Testing

private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

private let catalog = StoreCatalog(
    paidOutfits: [("beanie", "Beanie", []), ("raincoat", "Raincoat", []), ("pumpkinhat", "Pumpkin hat", [10])],
    sets: [("rainy_london", "Rainy London", "raincoat", 300), ("cabin", "Cabin", "beanie", 300)],
    seasons: [("housewarming", "Housewarming")]
)

@Suite("Entitlements")
struct EntitlementTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func record(_ id: String, verified: Bool = true, revoked: Bool = false, expires: Date? = nil) -> PurchaseRecord {
        PurchaseRecord(productID: id, transactionID: "t-\(id)", isVerified: verified, isRevoked: revoked, expiresAt: expires)
    }

    @Test func onlyVerifiedTransactionsCount() {
        let result = EntitlementMapper.entitlements(from: [
            record("housecat.outfit.beanie", verified: false),
            record("housecat.outfit.raincoat"),
        ], catalog: catalog, now: now)
        #expect(result.outfits == ["raincoat"])
    }

    @Test func revokedAndRefundedTransactionsStripTheItem() {
        let result = EntitlementMapper.entitlements(from: [record("housecat.set.cabin", revoked: true)], catalog: catalog, now: now)
        #expect(result == .none)
    }

    @Test func anExpiredSubscriptionIsNotClub() {
        let lapsed = EntitlementMapper.entitlements(
            from: [record("housecat.club.monthly", expires: now.addingTimeInterval(-1))], catalog: catalog, now: now
        )
        #expect(!lapsed.hasClub)
        let active = EntitlementMapper.entitlements(
            from: [record("housecat.club.yearly", expires: now.addingTimeInterval(86400))], catalog: catalog, now: now
        )
        #expect(active.hasClub && active.extraCatSlots == 1)
    }

    @Test func lifetimeAndFoundersIncludeCatClubAndEveryPass() {
        for id in ["housecat.lifetime", "housecat.founders"] {
            let result = EntitlementMapper.entitlements(from: [record(id)], catalog: catalog, now: now)
            #expect(result.hasClub)
            #expect(result.ownsPaidTrack(season: "anything"))
        }
    }

    @Test func aBundleUnlocksItsSetAndOutfit() {
        let result = EntitlementMapper.entitlements(from: [record("housecat.bundle.cabin")], catalog: catalog, now: now)
        #expect(result.sets == ["cabin"] && result.outfits == ["beanie"])
    }

    @Test func aSeasonPassIsKeptAndGiftsUnlockNothingForTheBuyer() {
        let result = EntitlementMapper.entitlements(from: [
            record("housecat.pass.housewarming"),
            record("housecat.gift.club.yearly"),
            record("housecat.gift.set.cabin"),
            record("housecat.cat.slot2"),
            record("housecat.not.a.product"),
        ], catalog: catalog, now: now)
        #expect(result.passes == ["housewarming"])
        #expect(!result.hasClub && result.sets.isEmpty)
        #expect(result.catSlots == [2] && result.extraCatSlots == 1)
    }

    @Test func theCacheMirrorsEntitlements() {
        let cache = InMemoryEntitlementCache()
        #expect(cache.load() == nil)
        var entitlements = Entitlements()
        entitlements.outfits = ["beanie"]
        cache.save(entitlements)
        #expect(cache.load() == entitlements)
    }
}

@Suite("Store catalogue")
struct CatalogueTests {
    @Test func everyProductHasTheRightType() {
        let shipped = try? ContentBundle.load(from: repo.appendingPathComponent("Content"))
        let catalog = shipped.map(StoreCatalog.init(content:)) ?? catalog
        let kinds = Dictionary(grouping: catalog.products, by: \.kind)
        #expect(kinds[.autoRenewable]?.map(\.id).sorted() == ["housecat.club.monthly", "housecat.club.yearly"])
        #expect(kinds[.nonRenewing]?.allSatisfy { $0.id.hasPrefix("housecat.pass.") } == true)
        #expect(kinds[.consumable]?.allSatisfy { $0.id.hasPrefix("housecat.gift.") } == true)
        #expect(catalog.products.allSatisfy { $0.id.hasPrefix("housecat.") })
        #expect(!catalog.products.contains { $0.id.hasPrefix("housecat.look.") }) // no rare looks at launch
        #expect(Set(catalog.productIDs).count == catalog.products.count)
    }

    @Test func theStoreKitConfigurationMatchesTheCatalogue() throws {
        let content = try ContentBundle.load(from: repo.appendingPathComponent("Content"))
        let catalog = StoreCatalog(content: content)
        let data = try Data(contentsOf: repo.appendingPathComponent("Store/HouseCat.storekit"))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var configured: [String: String] = [:]
        for entry in json["products"] as? [[String: Any]] ?? [] {
            try configured[#require(entry["productID"] as? String)] = entry["type"] as? String
        }
        for entry in json["nonRenewingSubscriptions"] as? [[String: Any]] ?? [] {
            try configured[#require(entry["productID"] as? String)] = entry["type"] as? String
        }
        var trial: [String: Any]?
        for group in json["subscriptionGroups"] as? [[String: Any]] ?? [] {
            #expect(group["name"] as? String == StoreCatalog.subscriptionGroup)
            for subscription in group["subscriptions"] as? [[String: Any]] ?? [] {
                let id = try #require(subscription["productID"] as? String)
                configured[id] = subscription["type"] as? String
                if id == StoreCatalog.clubYearly {
                    trial = subscription["introductoryOffer"] as? [String: Any]
                }
            }
        }
        let expectedType: [ShopProduct.Kind: String] = [
            .nonConsumable: "NonConsumable", .consumable: "Consumable", .nonRenewing: "NonRenewingSubscription",
            .autoRenewable: "RecurringSubscription",
        ]
        #expect(Set(configured.keys) == Set(catalog.productIDs))
        for product in catalog.products {
            #expect(configured[product.id] == expectedType[product.kind], "\(product.id)")
        }
        #expect(trial?["paymentMode"] as? String == "free")
        #expect(trial?["subscriptionPeriod"] as? String == "P1W")
    }
}

@Suite("Seasonal stock in the shop")
struct SeasonalStockTests {
    @Test func aSeasonalOutfitIsOnSaleOnlyInItsMonth() throws {
        let pumpkin = try #require(catalog.product("housecat.outfit.pumpkinhat"))
        #expect(pumpkin.months == [10])
        #expect(pumpkin.isOnSale(on: GameDay(year: 2026, month: 10, day: 20)))
        #expect(!pumpkin.isOnSale(on: GameDay(year: 2026, month: 11, day: 20)))
        #expect(catalog.product("housecat.outfit.beanie")?.isOnSale(on: GameDay(year: 2026, month: 11, day: 20)) == true)
    }

    @Test func theShippedSeasonalOutfitsCarryTheirMonths() throws {
        let content = try ContentBundle.load(from: repo.appendingPathComponent("Content"))
        let shipped = StoreCatalog(content: content)
        let seasonal = Dictionary(uniqueKeysWithValues: shipped.products.filter { !$0.months.isEmpty }.map { ($0.id, $0.months) })
        #expect(seasonal == [
            "housecat.outfit.pumpkinhat": [10], "housecat.outfit.skeleton": [10], "housecat.outfit.xmasjumper": [12],
        ])
    }
}
