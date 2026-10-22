import Foundation

/// One rung of the house ladder (docs/LADDER.md; Josh, 22 Oct: "rags to riches with your best friend"): a house in a
/// fixed city, what it costs in Beans, the level it needs, how many of the current house's tasks must be done
/// first, and the room it opens.
public struct Rung: Equatable, Sendable, Identifiable {
    /// 1 is the run-down terrace the player starts in; `HouseLadder.rungs.count` is the top.
    public var number: Int
    public var style: HouseStyle
    public var place: HomePlace
    /// Beans to buy it; 0 for the first rung.
    public var price: Int
    public var level: Int
    /// Tasks of the house below that must be done before this one is for sale.
    public var tasks: Int
    /// The room that opens with it (furniture and rooms carry up the ladder).
    public var room: RoomID?

    public var id: Int {
        number
    }

    /// As the ladder names it: the first house is the run-down one, whatever its painting borrows.
    public var name: String {
        number == 1 ? "Run-down terrace" : style.name
    }
}

/// Something a house asks before the next one is for sale, counted from moving in (`Tuning.Ladder.houseTasks`).
public struct HouseTask: Sendable, Equatable {
    public var metric: ObjectiveMetric
    public var target: Int
    /// "{cat}" is the cat's name.
    public var title: String

    public init(_ metric: ObjectiveMetric, _ target: Int, _ title: String) {
        self.metric = metric
        self.target = target
        self.title = title
    }
}

/// The eight houses bottom to top. No skipping and no going back down; each costs more and takes longer, like
/// a builder game's town halls.
public enum HouseLadder {
    public static let rungs: [Rung] = zip(Tuning.Ladder.rungs.indices, Tuning.Ladder.rungs).map { index, spec in
        Rung(
            number: index + 1,
            style: spec.style,
            place: spec.place,
            price: spec.price,
            level: spec.level,
            tasks: spec.tasks,
            room: spec.room
        )
    }

    public static var top: Int {
        rungs.count
    }

    /// The rung by its number, clamped to the ladder.
    public static func rung(_ number: Int) -> Rung {
        rungs[min(max(number, 1), top) - 1]
    }

    /// The rung a room opens on (the living room is there from the start).
    public static func rung(opening room: RoomID) -> Int {
        rungs.first { $0.room == room }?.number ?? 1
    }

    /// Why the next house can't be bought yet, or nil when it can.
    public enum Block: Equatable, Sendable {
        case atTheTop
        case needsLevel(Int)
        case needsTasks(done: Int, of: Int)
        case needsBeans(Int)
    }

    /// Whether the house above `current` can be bought now. Level and tasks come before Beans, so Beans alone
    /// never skip the climb.
    public static func block(above current: Int, level: Int, tasksDone: Int, beans: Int) -> Block? {
        guard current < top else { return .atTheTop }
        let next = rung(current + 1)
        if level < next.level { return .needsLevel(next.level) }
        if tasksDone < next.tasks { return .needsTasks(done: tasksDone, of: next.tasks) }
        if beans < next.price { return .needsBeans(next.price) }
        return nil
    }
}

public extension HouseholdState {
    /// The house the household lives in now. A save from before the ladder is put on the rung its rooms have
    /// reached, so nobody loses a room.
    var rung: Int {
        if let rung = home.rung { return rung }
        return openedRooms.map { HouseLadder.rung(opening: $0) }.max() ?? 1
    }

    var currentRung: Rung {
        HouseLadder.rung(rung)
    }

    /// Where the home is: the current house's city (the world map's pin is gone; Josh, 22 Oct).
    var homePlace: HomePlace {
        currentRung.place
    }

    /// Which house it is: the current rung's.
    var homeStyle: HouseStyle {
        currentRung.style
    }

    /// The home settings with the place and house the ladder gives (an old save's pin and style are ignored).
    var ladderHome: HomeSettings {
        var settings = home
        settings.place = homePlace
        settings.style = homeStyle
        return settings
    }

    /// The current house's tasks with how far each has got since moving in.
    func houseTaskProgress(on day: GameDay) -> [(task: HouseTask, done: Int)] {
        (Tuning.Ladder.houseTasks[rung] ?? []).map { task in
            let start = home.movedIn?[task.metric.rawValue] ?? 0
            return (task, min(task.target, max(0, lifetimeValue(task.metric, on: day) - start)))
        }
    }

    /// The current house's tasks done (what the next house asks for).
    var houseTasksDone: Int {
        let day = lastEventAt.map { clock.day(of: $0) } ?? GameDay(year: 2026, month: 1, day: 1)
        return houseTaskProgress(on: day).filter { $0.done >= $0.task.target }.count
    }

    /// The next house up, or nil at the top.
    var nextRung: Rung? {
        rung < HouseLadder.top ? HouseLadder.rung(rung + 1) : nil
    }
}
