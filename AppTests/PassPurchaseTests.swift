import Foundation
@testable import HouseCat
import HouseCatCore
import HouseCatModels
import HouseCatStore
import StoreKit
import StoreKitTest
import Testing

/// The season's premium pass through StoreKit (Josh, 19 Oct: each season's own purchase, kept by Restore), in the
/// StoreKit suite so the two never share the test session at once.
extension StoreKitPurchaseTests {
    /// The pass for the season running today (there always is one).
    @MainActor
    func todaysPass() throws -> (season: SeasonDefinition, product: ShopProduct) {
        let game = try GameSession(store: EventStore(inMemory: true))
        let info = try #require(game.passInfo())
        let product = try #require(catalog.product(pass: info.season.passID))
        return (info.season, product)
    }

    /// Asks again every tenth of a second until it holds, for ten seconds at most.
    func passEventually(_ holds: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            if await holds() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return await holds()
    }

    @Test func theSeasonPassIsBoughtOnceAndComesBackOnAnotherDevice() async throws {
        let (season, product) = try todaysPass()
        let service = StoreKitEntitlementService(catalog: catalog, cache: InMemoryEntitlementCache())
        var grants: [StoreGrant] = []
        service.onGrant = { grants.append($0) }
        #expect(!service.entitlements.ownsPaidTrack(season: season.passID))
        let transaction = try await session.buyProduct(identifier: product.id)
        _ = await passEventually {
            await service.refresh()
            return service.entitlements.passes.contains(season.passID)
        }
        #expect(service.entitlements.ownsPaidTrack(season: season.passID))
        #expect(!service.entitlements.hasClub)
        #expect(grants.contains { $0.productID == product.id && $0.transactionID == String(transaction.id) })
        service.stopListening()

        // Another device, or after deleting the app: nothing in the Keychain, and StoreKit gives it back.
        let fresh = StoreKitEntitlementService(catalog: catalog, cache: InMemoryEntitlementCache())
        defer { fresh.stopListening() }
        #expect(fresh.entitlements.passes.isEmpty)
        await fresh.refresh()
        #expect(fresh.entitlements.passes.contains(season.passID))
    }

    @Test func theGrantRecordsThePassInTheSaveAndOpensThePremiumTrack() async throws {
        let game = try GameSession(store: EventStore(inMemory: true))
        let info = try #require(game.passInfo())
        #expect(!info.ownsPaid)
        let product = try #require(catalog.product(pass: info.season.passID))
        let transaction = try await session.buyProduct(identifier: product.id)
        game.grant(StoreGrant(productID: product.id, transactionID: String(transaction.id)), catalog: catalog)
        // Heard again on the next refresh: recorded once.
        game.grant(StoreGrant(productID: product.id, transactionID: String(transaction.id)), catalog: catalog)
        let state = game.state(at: game.now())
        #expect(state.passes[info.season.id]?.purchased == true)
        #expect(game.passInfo()?.ownsPaid == true)
        #expect(game.log.events.filter { if case .passPurchased = $0.kind { true } else { false } }.count == 1)
    }

    @Test func aRefundedPassOpensNothingOnTheNextRefresh() async throws {
        let (season, product) = try todaysPass()
        let service = StoreKitEntitlementService(catalog: catalog, cache: InMemoryEntitlementCache())
        defer { service.stopListening() }
        let transaction = try await session.buyProduct(identifier: product.id)
        _ = await passEventually {
            await service.refresh()
            return service.entitlements.passes.contains(season.passID)
        }
        try session.refundTransaction(identifier: UInt(transaction.id))
        _ = await passEventually {
            await service.refresh()
            return service.entitlements.passes.isEmpty
        }
        #expect(!service.entitlements.ownsPaidTrack(season: season.passID))
    }
}
