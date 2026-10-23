import Foundation
import HouseCatCore
@testable import HouseCatStore
import Testing

private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

private let catalog = StoreCatalog(bundles: [
    ("cosy_study", "Cosy study", "housecat.room.cosy_study", "4.99"),
    ("housewarming_living", "Housewarming living room", "housecat.season.housewarming", "4.99"),
])

@Suite("Entitlements")
struct EntitlementTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func record(_ id: String, verified: Bool = true, revoked: Bool = false, expires: Date? = nil) -> PurchaseRecord {
        PurchaseRecord(productID: id, transactionID: "t-\(id)", isVerified: verified, isRevoked: revoked, expiresAt: expires)
    }

    @Test func onlyVerifiedTransactionsCount() {
        let result = EntitlementMapper.entitlements(from: [
            record("housecat.room.cosy_study", verified: false),
            record("housecat.season.housewarming"),
        ], catalog: catalog, now: now)
        #expect(result.bundles == ["housewarming_living"])
    }

    @Test func revokedAndRefundedTransactionsStripTheLook() {
        let result = EntitlementMapper.entitlements(from: [record("housecat.room.cosy_study", revoked: true)], catalog: catalog, now: now)
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
        #expect(active.hasClub && !active.ownsPaidTrack(season: "anything"), "the pass is sold on its own")
    }

    @Test func beanPacksUnlockNothingButCarryTheirBeans() {
        let result = EntitlementMapper.entitlements(from: [
            record("housecat.beans.jar"), record("housecat.starter"), record("housecat.not.a.product"),
        ], catalog: catalog, now: now)
        #expect(result.starter && result.bundles.isEmpty && !result.hasClub)
        #expect(catalog.product("housecat.beans.jar")?.beans == Tuning.Beans.packs[2])
        #expect(catalog.product(StoreCatalog.starter)?.beans == Tuning.Beans.starterPack)
    }

    @Test func eachBiggerPackGivesMoreBeansAPound() {
        let packs = StoreCatalog.beanPacks
        for (small, big) in zip(packs, packs.dropFirst()) {
            let rate = { (pack: (id: String, beans: Int, price: String, name: String)) in Double(pack.beans) / Double(pack.price)! }
            #expect(rate(big) > rate(small), "\(big.id)")
        }
    }

    @Test func theCacheMirrorsEntitlements() {
        let cache = InMemoryEntitlementCache()
        #expect(cache.load() == nil)
        var entitlements = Entitlements()
        entitlements.bundles = ["cosy_study"]
        cache.save(entitlements)
        #expect(cache.load() == entitlements)
    }
}

@Suite("Store catalogue")
struct CatalogueTests {
    @Test func threeKindsOfProduct() throws {
        let shipped = try StoreCatalog(content: ContentBundle.load(from: repo.appendingPathComponent("Content")))
        let kinds = Dictionary(grouping: shipped.products, by: \.kind)
        #expect(kinds[.autoRenewable]?.map(\.id).sorted() == ["housecat.club.monthly", "housecat.club.yearly"])
        #expect(kinds[.consumable]?.allSatisfy { $0.id.hasPrefix("housecat.beans.") } == true)
        #expect(kinds[.nonConsumable]?.allSatisfy { $0.id == StoreCatalog.starter || $0.beans == nil } == true)
        #expect(kinds[.nonRenewing] == nil)
        #expect(shipped.products.allSatisfy { $0.id.hasPrefix("housecat.") })
        #expect(Set(shipped.productIDs).count == shipped.products.count)
        #expect(shipped.product(bundle: "housewarming_living")?.id == StoreCatalog.housewarmingPack)
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
