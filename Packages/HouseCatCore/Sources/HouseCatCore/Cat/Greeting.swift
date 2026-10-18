import Foundation

/// The line the cat greets you with (SPEC "The session loop" 3: "A text box carries one line
/// from that personality's pack"). Contexts are the ids in Content/lines.json.
public enum Greeting {
    /// The line context for an arrival, read from the state before the arrival is appended
    /// (resolved through the arrival's day).
    /// The first arrival of a special day greets it (Content/lines.json `event.*`): a date in
    /// `Tuning.Lines.eventDays`, else a live event that names its lines (the Christmas one, the Housewarming).
    public static func context(
        before state: HouseholdState,
        at date: Date,
        source: GameEvent.Source = .app,
        rules: RulesContext = .empty
    ) -> String {
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
        if state.visitedToday {
            return "arrival.second_visit"
        }
        let day = state.clock.day(of: date)
        let monthDay = String(format: "%02d-%02d", day.date.month, day.date.day)
        if let special = Tuning.Lines.eventDays[monthDay] ?? EventRules.live(on: day, context: rules).compactMap(\.lines).first {
            return special
        }
        return "arrival.first_of_day"
    }

    /// One variant for the context in the cat's personality, the same all day for the same visit
    /// (`DaySeed`), with the cat's name filled in. `whole` keeps to the variants with no other placeholder
    /// (a reminder knows the gift is coming, not what it is), unless every variant has one.
    public static func line(_ context: String, cat: CatState, lines: LinesFile, rng: inout DaySeed, whole: Bool = false) -> String? {
        var variants = lines.variants(for: context, personality: cat.personality)
        if whole {
            let plain = variants.filter { !$0.replacingOccurrences(of: "{cat}", with: "").contains("{") }
            variants = plain.isEmpty ? variants : plain
        }
        guard !variants.isEmpty else { return nil }
        return variants[Int(rng.next() % UInt64(variants.count))].replacingOccurrences(of: "{cat}", with: cat.name)
    }
}

/// The lines for Feed and Pet (Content/lines.json `feed.*`, `pet.*`), read from the state before the event.
public enum CareLines {
    public static func feed(before state: HouseholdState, catID: String) -> String {
        state.isFedToday(catID) ? "feed.already_fed" : "feed.fed"
    }

    /// `taps` counts pets in a row, this one included (six in a row and most cats walk off).
    public static func pet(before state: HouseholdState, catID: String, taps: Int) -> String {
        guard let cat = state.cat(catID) else { return "pet.repeat" }
        if cat.personality.walksOff(afterConsecutivePets: taps) {
            return "pet.too_many"
        }
        return (state.today?.pets ?? 0) == 0 ? "pet.first" : "pet.repeat"
    }
}
