import Foundation
@testable import HouseCatCore
import Testing

/// The outfit catalogue's rule: what each outfit is to the household, with the real outfits.
@Suite("Outfit catalogue")
struct OutfitAvailabilityTests {
    static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    let outfits: [String: OutfitsFile.Outfit]

    init() throws {
        let content = try ContentBundle.load(from: Self.repo.appendingPathComponent("Content"))
        outfits = Dictionary(uniqueKeysWithValues: content.outfits.outfits.map { ($0.id, $0) })
    }

    private func availability(_ id: String, owned: Set<String> = [], worn: String? = nil, month: Int = 3) throws -> OutfitAvailability {
        try OutfitAvailability.of(#require(outfits[id]), owned: owned, worn: worn, on: GameDay(year: 2027, month: month, day: 10))
    }

    @Test func paidOutfitsAreSoldForBeans() throws {
        #expect(try availability("beanie") == .forSale(beans: Tuning.Beans.outfit))
        #expect(try availability("raincoat") == .forSale(beans: Tuning.Beans.outfit))
    }

    @Test func aSeasonalOutfitIsSoldInItsMonthsOnly() throws {
        #expect(try availability("pumpkinhat", month: 3) == .outOfSeason(months: [10]))
        #expect(try availability("pumpkinhat", month: 10) == .forSale(beans: Tuning.Beans.outfit))
    }

    @Test func ownedAndWornComeFirst() throws {
        #expect(try availability("beanie", owned: ["beanie"]) == .owned)
        #expect(try availability("beanie", owned: ["beanie"], worn: "beanie") == .wearing)
        // Owned outright, a pass or streak outfit is just owned.
        #expect(try availability("hoodie", owned: ["hoodie"]) == .owned)
        #expect(OutfitAvailability.wearing.rank < OutfitAvailability.owned.rank)
        #expect(OutfitAvailability.owned.rank < OutfitAvailability.forSale(beans: 1).rank)
    }

    @Test func theRestSayWhatTheyComeFrom() throws {
        #expect(try availability("hoodie") == .earned(source: "streak_30"))
        #expect(try availability("bowtie") == .earned(source: "streak_100"))
        #expect(try availability("buckethat") == .earned(source: "referral"))
        #expect(try availability("bandana") == .pass(club: false))
        #expect(try availability("crown") == .pass(club: true))
    }
}
