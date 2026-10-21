import HouseCatStore
import Testing

/// Cat Club's trial is named only to a player who is eligible for it (App Review 3.1.2; `ProductInfo.trialDays` is nil
/// for anyone StoreKit says has had the subscription before). The renewal price is always there.
@Suite("Cat Club's wording")
struct ClubWordingTests {
    let eligible = ProductInfo(
        id: StoreCatalog.clubYearly,
        displayName: "Cat Club Yearly",
        displayPrice: "£19.99",
        kind: .autoRenewable,
        trialDays: 7
    )
    let lapsed = ProductInfo(
        id: StoreCatalog.clubYearly,
        displayName: "Cat Club Yearly",
        displayPrice: "£19.99",
        kind: .autoRenewable,
        trialDays: nil
    )

    @Test func anEligiblePlayerIsOfferedTheTrialAndThePrice() {
        let terms = ClubWording.terms(yearly: true, yearPrice: eligible.displayPrice, monthPrice: "£2.99", trialDays: eligible.trialDays)
        #expect(terms.hasPrefix("7 days free, then £19.99 a year."))
        #expect(terms.contains("Renews automatically until you cancel"))
        #expect(ClubWording.planLine(yearly: true, perMonth: "£1.67", trialDays: eligible.trialDays) == "7 days free · £1.67 a month")
        #expect(ClubWording.offerLine(yearPrice: eligible.displayPrice, trialDays: eligible.trialDays) == "7 days free, then £19.99 a year")
    }

    @Test func aPlayerWhoIsNotEligibleSeesTheRenewalPriceAndNoTrial() {
        let terms = ClubWording.terms(yearly: true, yearPrice: lapsed.displayPrice, monthPrice: "£2.99", trialDays: lapsed.trialDays)
        #expect(terms.hasPrefix("£19.99 a year, from today."))
        #expect(!terms.lowercased().contains("free"))
        let plan = ClubWording.planLine(yearly: true, perMonth: "£1.67", trialDays: lapsed.trialDays)
        #expect(plan == "Billed yearly · £1.67 a month")
        #expect(!plan.lowercased().contains("free"))
        let offer = ClubWording.offerLine(yearPrice: lapsed.displayPrice, trialDays: lapsed.trialDays)
        #expect(offer == "£19.99 a year")
    }

    @Test func theMonthlyPlanNeverMentionsATrial() {
        for days in [nil, 7] {
            #expect(ClubWording.terms(yearly: false, yearPrice: "£19.99", monthPrice: "£2.99", trialDays: days)
                .hasPrefix("£2.99 a month, from today."))
            #expect(ClubWording.planLine(yearly: false, perMonth: nil, trialDays: days) == "Billed every month")
        }
    }

    @Test func aMissingPriceNeverPromisesANumber() {
        #expect(ClubWording.terms(yearly: true, yearPrice: nil, monthPrice: nil, trialDays: nil).hasPrefix("… a year, from today."))
        #expect(ClubWording.planLine(yearly: true, perMonth: nil, trialDays: nil) == "Billed every year")
    }
}
