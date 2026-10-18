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

    @Test func theConfigurationLoadsEveryProduct() async throws {
        let service = StoreKitEntitlementService(catalog: catalog, cache: InMemoryEntitlementCache())
        defer { service.stopListening() }
        let products = try await service.products()
        #expect(Set(products.map(\.id)) == Set(catalog.productIDs))
        let yearly = try #require(try await Product.products(for: [StoreCatalog.clubYearly]).first)
        #expect(yearly.type == .autoRenewable)
        #expect(yearly.subscription?.introductoryOffer?.paymentMode == .freeTrial)
        let trial = try #require(yearly.subscription?.introductoryOffer?.period)
        #expect(trial.unit == .week && trial.value == 1)
        let pack = try #require(try await Product.products(for: ["housecat.beans.jar"]).first)
        #expect(pack.type == .consumable)
    }

    @Test func aBeanPackIsHandedOverOnceAndALookSurvivesARelaunch() async throws {
        let keychain = KeychainEntitlementCache(service: "com.housecatgame.housecat.tests")
        keychain.clear()
        defer { keychain.clear() }
        var grants: [StoreGrant] = []
        let first = StoreKitEntitlementService(catalog: catalog, cache: keychain)
        first.onGrant = { grants.append($0) }
        let pack = try await buy("housecat.beans.pouch", into: first)
        // A pack bought outside the purchase call reaches the app through the unfinished transactions.
        for _ in 0 ..< 20 where !grants.contains(where: { $0.transactionID == String(pack.id) }) {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(grants.contains { $0.productID == "housecat.beans.pouch" && $0.transactionID == String(pack.id) })
        let bundle = try #require(catalog.products.first { if case .bundle = $0.unlock { true } else { false } })
        try await buy(bundle.id, into: first)
        guard case let .bundle(bundleID) = bundle.unlock else { return }
        #expect(first.entitlements.bundles == [bundleID])
        #expect(grants.contains { $0.productID == bundle.id })
        first.stopListening()

        // Relaunch: the new service starts from the Keychain mirror, then re-derives from StoreKit.
        let relaunched = StoreKitEntitlementService(catalog: catalog, cache: keychain)
        defer { relaunched.stopListening() }
        #expect(relaunched.entitlements.bundles == [bundleID])
        await relaunched.refresh()
        #expect(relaunched.entitlements.bundles == [bundleID])
    }

    @Test func catClubIncludesThePaidTrack() async throws {
        let service = StoreKitEntitlementService(catalog: catalog, cache: InMemoryEntitlementCache())
        defer { service.stopListening() }
        #expect(!service.entitlements.hasClub)
        try await buy(StoreCatalog.clubYearly, into: service)
        #expect(service.entitlements.hasClub)
        #expect(service.entitlements.ownsPaidTrack(season: "midwinter"))
    }

    @Test func aRefundStripsTheLookOnTheNextRefresh() async throws {
        let service = StoreKitEntitlementService(catalog: catalog, cache: InMemoryEntitlementCache())
        defer { service.stopListening() }
        let bundle = try #require(catalog.products.first { if case .bundle = $0.unlock { true } else { false } })
        let transaction = try await buy(bundle.id, into: service)
        #expect(service.entitlements.bundles.count == 1)
        try session.refundTransaction(identifier: UInt(transaction.id))
        // The refund reaches StoreKit's current entitlements shortly after.
        for _ in 0 ..< 20 where !service.entitlements.bundles.isEmpty {
            try await Task.sleep(for: .milliseconds(100))
            await service.refresh()
        }
        #expect(service.entitlements.bundles.isEmpty)
    }
}
