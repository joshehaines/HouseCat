/// Always a season (Josh, 19 Oct 2026: the pass is the main progression, so it is always there). Every slot of
/// `SeasonCalendar` from the first season in seasons.json on has one. A slot seasons.json names runs that season.
/// Any later slot it does not name runs a season again: the one in the same slot a year before (so Midwinter comes
/// back each December), or, for a slot that never had one, the named seasons in turn (Christmas ones only at
/// Christmas). A run again keeps the season's name, rewards and premium pass, so a pass bought once opens every run
/// of it; it has its own dates and its own id, `<passID>@<first day>`, so its tiers start again from nothing.
public enum SeasonSchedule {
    /// Every season from the first named one through the slot holding `last`.
    public static func seasons(named: [SeasonDefinition], through last: GameDay) -> [SeasonDefinition] {
        let named = named.sorted { $0.startDay < $1.startDay }
        guard let first = named.first else { return [] }
        let byStart = Dictionary(named.map { ($0.startDay, $0) }, uniquingKeysWith: { a, _ in a })
        var scheduled: [GameDay: SeasonDefinition] = [:]
        var out: [SeasonDefinition] = []
        var slot = SeasonCalendar.slot(containing: first.startDay)
        var turn = 0
        while slot.start <= last {
            let season: SeasonDefinition
            if let own = byStart[slot.start] {
                season = own
            } else if let lastYear = yearBefore(slot).flatMap({ scheduled[$0.start] }) {
                season = rerun(of: lastYear, in: slot)
            } else {
                let pool = named.filter { isChristmas($0) == slot.isChristmas }
                let from = pool.isEmpty ? named : pool
                season = rerun(of: from[turn % from.count], in: slot)
                turn += 1
            }
            scheduled[slot.start] = season
            out.append(season)
            slot = SeasonCalendar.slot(containing: slot.end)
        }
        return out
    }

    /// A season run again in another slot.
    public static func rerun(of season: SeasonDefinition, in slot: SeasonCalendar.Slot) -> SeasonDefinition {
        SeasonDefinition(
            id: "\(season.passID)@\(slot.start)",
            name: season.name,
            passID: season.passID,
            sku: season.sku,
            startDay: slot.start,
            endDay: slot.end,
            freeTrack: season.freeTrack,
            paidTrack: season.paidTrack
        )
    }

    /// The same slot a year earlier: the same place among the thirteen that end with a Christmas season.
    static func yearBefore(_ slot: SeasonCalendar.Slot) -> SeasonCalendar.Slot? {
        let year = slot.start.date.year
        for christmasYear in [year, year + 1] {
            let slots = SeasonCalendar.slots(endingWithChristmasOf: christmasYear)
            if let index = slots.firstIndex(where: { $0.start == slot.start }) {
                return SeasonCalendar.slots(endingWithChristmasOf: christmasYear - 1)[index]
            }
        }
        return nil
    }

    static func isChristmas(_ season: SeasonDefinition) -> Bool {
        SeasonCalendar.slot(containing: season.startDay).isChristmas
    }
}

public extension SeasonsFile {
    /// The day the game launched (events count their days from it): seasons.json's `launchAt`, else its first season.
    var launchDay: GameDay? {
        GameDay(iso: launchAt ?? seasons.first?.startAt ?? "")
    }

    /// Every season the rules know: the named ones and the runs again after them, `Tuning.Pass.scheduleYears` on.
    func schedule() throws -> [SeasonDefinition] {
        let named = try seasons.map { try $0.definition() }
        guard let end = named.map(\.endDay).max() else { return [] }
        return SeasonSchedule.seasons(named: named, through: end.advanced(by: 365 * Tuning.Pass.scheduleYears))
    }
}
