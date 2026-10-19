import Foundation
@testable import HouseCatCore
import Testing

/// The first month as three kinds of player meet it, through the real rules and content (the review Josh passed on,
/// 19 Oct: the Bean earn rate had never met a player). Each day: a light player drops in, feeds and strokes the cat
/// and takes the present; a regular one also plays two games; a keen one plays all five, naps and strokes more. Each
/// opens a room the moment it can. HOUSECAT_PACING=1 prints the days.
@Suite("Pacing")
struct PacingTests {
    enum Player: String, CaseIterable {
        case light, regular, keen
    }

    struct Day {
        var level: Int
        var beans: Int
        var earned: Int
        var rooms: [RoomID]
    }

    static func month(_ player: Player, context: RulesContext, days: Int = 30) -> [Day] {
        var f = Fixture(context: context)
        f.add(.tourFinished, day: 0, hour: 7, minute: 30)
        var out: [Day] = []
        let order: [RoomID] = [.bedroom, .kitchen, .garden, .study, .attic]
        for day in 0 ..< days {
            f.add(.arrived, day: day, hour: 8)
            f.add(.fed(catID: f.cat), day: day, hour: 8, minute: 2)
            let pets = player == .light ? 2 : player == .regular ? 4 : 6
            for pet in 0 ..< pets {
                f.add(.petted(catID: f.cat), day: day, hour: 8, minute: 4 + pet)
            }
            f.collectGifts(day: day, hour: 12)
            let games = player == .light ? 0 : player == .regular ? 2 : 5
            for game in 0 ..< games {
                f.add(
                    .miniGamePlayed(game: ["laser", "knock", "string"][game % 3], stars: player == .keen ? 3 : 2),
                    day: day,
                    hour: 18,
                    minute: game
                )
            }
            if player == .keen {
                f.add(.napCompleted, day: day, hour: 21)
            }
            // Opens the next room as soon as the level and the Beans allow.
            var state = f.state
            for room in order where !state.openedRooms.contains(room) {
                guard state.level >= room.requiredLevel, state.beans >= RoomRules.cost(of: room, clubActive: false) else { break }
                f.add(.roomOpened(room, beans: RoomRules.cost(of: room, clubActive: false)), day: day, hour: 21, minute: 30)
                state = f.state
            }
            out.append(Day(
                level: state.level,
                beans: state.beans,
                earned: state.beansEarnedClosed + state.beansSpent,
                rooms: order.filter { state.openedRooms.contains($0) }
            ))
        }
        return out
    }

    @Test func theFirstMonthShowsWhatEachPlayerCanDo() throws {
        let content = try ContentBundle.load(from: ContentValidationTests.repo.appendingPathComponent("Content"))
        let context = try content.rulesContext()
        let print = ProcessInfo.processInfo.environment["HOUSECAT_PACING"] != nil
        for player in Player.allCases {
            let days = Self.month(player, context: context)
            if print {
                Swift.print("== \(player.rawValue)")
                for (index, day) in days.enumerated() where [0, 1, 2, 3, 4, 6, 9, 13, 20, 29].contains(index) {
                    Swift.print("day \(index + 1): level \(day.level), \(day.beans) Beans, rooms \(day.rooms.map(\.rawValue))")
                }
            }
            // Everyone has a room to open in the first week, and something left to spend.
            #expect(days[6].rooms.contains(.bedroom), "\(player): the bedroom by day 7")
        }
    }
}
