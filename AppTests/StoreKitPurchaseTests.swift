import Foundation
import HouseCatCore
import HouseCatStore
import StoreKit
import StoreKitTest
import Testing

private final class BundleToken {}

/// StoreKit against Store/HouseCat.storekit, inside the app in the simulator.
@MainActor
@Suite("StoreKit purchases", .serialized)
struct StoreKitPurchaseTests {
    let session: SKTestSession
    let catalog: StoreCatalog

    init() throws {
        let bundle = Bundle(for: BundleToken.self)
        let configuration = try #require(bundle.url(forResource: "HouseCat", withExtension: "storekit"))
        session = try SKTestSession(contentsOf: configuration)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        let content = try #require(bundle.url(forResource: "Content", withExtension: nil))
        catalog = try StoreCatalog(content: ContentBundle.load(from: content))
    }

    /// A purchase made the way StoreKit's own sheet would make it, without the sheet (in this simulator the sheet
    /// asks for an Apple Account sign-in and waits). The service hears it as it hears any transaction.
    @discardableResult
    func buy(_ id: String, into service: StoreKitEntitlementService) async throws -> Transaction {
        let transaction = try await session.buyProduct(identifier: id)
        await service.refresh()
        return transaction
    }

    func firstProduct(_ matches: (ShopProduct.Unlock) -> Bool) throws -> ShopProduct {
        try #require(catalog.products.first { matches($0.unlock) })
    }

    @Test func theConfigurationLoadsEveryLaunchProduct() async throws {
        let service = StoreKitEntitlementService(catalog: catalog, cache: InMemoryEntitlementCache())
        defer { service.stopListening() }
        let products = try await service.products()
        #expect(Set(products.map(\.id)) == Set(catalog.productIDs))
        let yearly = try #require(try await Product.products(for: [StoreCatalog.clubYearly]).first)
        #expect(yearly.type == .autoRenewable)
        #expect(yearly.subscription?.introductoryOffer?.paymentMode == .freeTrial)
        let trial = try #require(yearly.subscription?.introductoryOffer?.period)
        #expect(trial.unit == .week && trial.value == 1)
        let pass = try #require(try await Product.products(for: ["housecat.pass.housewarming"]).first)
        #expect(pass.type == .nonRenewable)
        let gift = try #require(try await Product.products(for: ["housecat.gift.cat"]).first)
        #expect(gift.type == .consumable)
    }

    @Test func anOutfitPurchaseUnlocksItAfterARelaunch() async throws {
        let keychain = KeychainEntitlementCache(service: "com.housecatgame.housecat.tests")
        keychain.clear()
        defer { keychain.clear() }
        let outfit = try firstProduct {
            if case .outfit = $0 {
                true
            } else {
                false
            }
        }
        guard case let .outfit(outfitID) = outfit.unlock else { return }

        let first = StoreKitEntitlementService(catalog: catalog, cache: keychain)
        try await buy(outfit.id, into: first)
        #expect(first.entitlements.outfits == [outfitID])
        first.stopListening()

        // Relaunch: the new service starts from the Keychain mirror, then re-derives from StoreKit.
        let relaunched = StoreKitEntitlementService(catalog: catalog, cache: keychain)
        defer { relaunched.stopListening() }
        #expect(relaunched.entitlements.outfits == [outfitID])
        await relaunched.refresh()
        #expect(relaunched.entitlements.outfits == [outfitID])
    }

    @Test func catClubTheSeasonPassAndGifts() async throws {
        let service = StoreKitEntitlementService(catalog: catalog, cache: InMemoryEntitlementCache())
        defer { service.stopListening() }
        try await buy("housecat.pass.housewarming", into: service)
        #expect(service.entitlements.passes == ["housewarming"])
        #expect(!service.entitlements.hasClub)
        try await buy(StoreCatalog.clubYearly, into: service)
        #expect(service.entitlements.hasClub)
        #expect(service.entitlements.ownsPaidTrack(season: "midwinter"))
        let before = service.entitlements
        let gift = try await buy("housecat.gift.cat", into: service)
        #expect(gift.productID == "housecat.gift.cat")
        #expect(service.entitlements == before) // a gift unlocks nothing for the buyer
    }

    @Test func aRefundStripsTheItemOnTheNextRefresh() async throws {
        let service = StoreKitEntitlementService(catalog: catalog, cache: InMemoryEntitlementCache())
        defer { service.stopListening() }
        let set = try firstProduct {
            if case .set = $0 {
                true
            } else {
                false
            }
        }
        let transaction = try await buy(set.id, into: service)
        #expect(service.entitlements.sets.count == 1)
        try session.refundTransaction(identifier: UInt(transaction.id))
        // The refund reaches StoreKit's current entitlements shortly after.
        for _ in 0 ..< 20 where !service.entitlements.sets.isEmpty {
            try await Task.sleep(for: .milliseconds(100))
            await service.refresh()
        }
        #expect(service.entitlements.sets.isEmpty)
    }
}
