import Foundation

/// The line the cat greets you with (SPEC "The session loop" 3: "A text box carries one line
/// from that personality's pack"). Contexts are the ids in Content/lines.json.
public enum Greeting {
    /// The line context for an arrival, read from the state before the arrival is appended
    /// (resolved through the arrival's day).
    public static func context(before state: HouseholdState, at date: Date, source: GameEvent.Source = .app) -> String {
        if state.lifetime.visits == 0 {
            return "arrival.first_ever"
        }
        // Back after a missed day: the sulk, then two warm-up visits (HouseholdState.mood).
        switch state.warmUpArrivals {
        case 0:
            let today = state.clock.day(of: date).index
            let missed = state.streak.lastVisitDay.map { today - $0.index - 1 } ?? 1
            return missed >= Tuning.Streak.weekMissDays ? "missed.week_plus" : missed > 1 ? "missed.few_days" : "missed.one_day"
        case 1:
            return "missed.thawing"
        case 2:
            return "missed.fine"
        default:
            break
        }
        switch source {
        case .mac: return "arrival.from_mac"
        case .watch: return "arrival.from_watch"
        default: break
        }
        let minutes = state.clock.localMinutes(of: date)
        if minutes >= Tuning.Day.lateNightMinutes {
            return "arrival.late_night"
        }
        if minutes < Tuning.Day.earlyMinutes {
            return "arrival.early"
        }
        return state.visitedToday ? "arrival.second_visit" : "arrival.first_of_day"
    }

    /// One variant for the context in the cat's personality, the same all day for the same visit
    /// (`DaySeed`), with the cat's name filled in.
    public static func line(_ context: String, cat: CatState, lines: LinesFile, rng: inout DaySeed) -> String? {
        let variants = lines.variants(for: context, personality: cat.personality)
        guard !variants.isEmpty else { return nil }
        return variants[Int(rng.next() % UInt64(variants.count))].replacingOccurrences(of: "{cat}", with: cat.name)
    }
}
