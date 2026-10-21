@testable import HouseCatCore
import Testing

/// "Help improve HouseCat?" comes once, on the second day of care, and never on the day the Health card asks.
@Suite("The analytics card")
struct AnalyticsPromptTests {
    @Test func askedOnceOnTheSecondCareDayAndNotWithHealth() {
        var f = Fixture()
        f.visit(days: [0])
        // Day one: the tour and the reminders card have the day.
        #expect(!AnalyticsRules.shouldAsk(f.state, asked: false, healthAsked: false))
        f.visit(days: [1])
        #expect(AnalyticsRules.shouldAsk(f.state, asked: false, healthAsked: false))
        // Once answered (yes or Not now), never again.
        #expect(!AnalyticsRules.shouldAsk(f.state, asked: true, healthAsked: false))
        // A player who skipped day two meets the Health card on day three; the analytics card waits a day.
        f.visit(days: [2])
        #expect(HealthRules.shouldAsk(f.state, asked: false))
        #expect(!AnalyticsRules.shouldAsk(f.state, asked: false, healthAsked: false))
        #expect(AnalyticsRules.shouldAsk(f.state, asked: false, healthAsked: true))
    }
}
