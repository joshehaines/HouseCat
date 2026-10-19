import Foundation
import HouseCatCore
@testable import HouseCatStore
import Testing

private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

/// Each season's premium pass (Josh, 19 Oct: its own purchase each season, and in Cat Club too).
@Suite("Season passes in the store")
struct PassStoreTests {
    let content: ContentBundle
    let catalog: StoreCatalog
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        content = try ContentBundle.load(from: repo.appendingPathComponent("Content"))
        catalog = StoreCatalog(content: content)
    }

    @Test func everySeasonSellsItsOwnPremiumPass() throws {
        #expect(catalog.passProducts.count == content.seasons.seasons.count)
        for season in content.seasons.seasons {
            let product = try #require(catalog.product(pass: season.id), "\(season.id)")
            #expect(product.id == StoreCatalog.passProductID(season: season.id))
            #expect(product.id == season.sku)
            #expect(product.kind == .nonConsumable, "Restore Purchases brings it back")
            #expect(product.priceGBP == StoreCatalog.passPriceGBP)
            #expect(product.displayName.count <= 35, "\(product.displayName)")
            #expect(product.beans == nil)
        }
    }

    @Test func theStoreKitConfigurationNamesAndPricesEachPass() throws {
        let data = try Data(contentsOf: repo.appendingPathComponent("Store/HouseCat.storekit"))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let products = Dictionary(uniqueKeysWithValues: (json["products"] as? [[String: Any]] ?? []).compactMap { entry in
            (entry["productID"] as? String).map { ($0, entry) }
        })
        for product in catalog.passProducts {
            let entry = try #require(products[product.id], "\(product.id) is not in HouseCat.storekit")
            #expect(entry["displayPrice"] as? String == StoreCatalog.passPriceGBP)
            let local = try #require((entry["localizations"] as? [[String: Any]])?.first)
            let name = try #require(local["displayName"] as? String)
            let description = try #require(local["description"] as? String)
            // App Store Connect's limits.
            #expect(name == product.displayName && name.count <= 35)
            #expect(description.count <= 55, "\(description)")
        }
    }

    @Test func aBoughtPassOpensItsSeasonsPremiumTrackAndClubOpensEverySeasons() {
        let pass = PurchaseRecord(productID: "housecat.pass.housewarming", transactionID: "t1", isVerified: true)
        let owned = EntitlementMapper.entitlements(from: [pass], catalog: catalog, now: now)
        #expect(owned.passes == ["housewarming"])
        #expect(owned.ownsPaidTrack(season: "housewarming"))
        #expect(!owned.ownsPaidTrack(season: "midwinter"))
        #expect(!owned.hasClub)

        let club = PurchaseRecord(productID: StoreCatalog.clubMonthly, transactionID: "t2", isVerified: true, expiresAt: now.addingTimeInterval(86_400))
        let member = EntitlementMapper.entitlements(from: [club], catalog: catalog, now: now)
        #expect(member.ownsPaidTrack(season: "midwinter") && member.ownsPaidTrack(season: "firstlight"))
    }

    @Test func anUnverifiedOrRefundedPassOpensNothing() {
        let unverified = PurchaseRecord(productID: "housecat.pass.midwinter", transactionID: "t1", isVerified: false)
        let refunded = PurchaseRecord(productID: "housecat.pass.firstlight", transactionID: "t2", isVerified: true, isRevoked: true)
        let owned = EntitlementMapper.entitlements(from: [unverified, refunded], catalog: catalog, now: now)
        #expect(owned.passes.isEmpty)
    }

    @Test func aKeychainMirrorFromBeforePassesStillLoads() throws {
        let old = Data(#"{"clubSubscription":true,"starter":false,"bundles":["cosy_study"]}"#.utf8)
        let decoded = try JSONDecoder().decode(Entitlements.self, from: old)
        #expect(decoded.hasClub && decoded.bundles == ["cosy_study"] && decoded.passes.isEmpty)
        var owned = Entitlements()
        owned.passes = ["blackcat"]
        let cache = InMemoryEntitlementCache()
        cache.save(owned)
        #expect(cache.load() == owned)
    }
}
