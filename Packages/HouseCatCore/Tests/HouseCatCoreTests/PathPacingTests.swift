import Foundation
@testable import HouseCatCore
import Testing

/// The path's rhythm through the real rules and content (Josh, 19 Oct: "better progression"): the first hour, the
/// first week and the first month as a light, a regular and a keen player meet them, each doing what the tracker asks.
/// A light player feeds, strokes twice, takes the present and plays one game; a regular one strokes four times, plays
/// three and solves Pat's puzzle; a keen one strokes six times, plays all five, naps and plays the Games menu every day
/// (`ArcadeHabit`). HOUSECAT_PACING=1 prints the days.
@Suite("Pacing: the path")
struct PathPacingTests {
    enum Player: String, CaseIterable {
        case light, regular, keen
    }

    struct Day {
        var level: Int
        var beans: Int
        var rooms: Int
        /// The chapter being walked (0, 1, 2), or 3 once the path is done.
        var chapter: Int
        /// Path steps done that day.
        var steps: Int
        /// Every goal met that day: the path's, today's, this week's, milestones.
        var goals: Int
        var tracker: Int
    }

    let content: ContentBundle
    let context: RulesContext

    init() throws {
        content = try ContentBundle.load(from: ContentValidationTests.repo.appendingPathComponent("Content"))
        context = try content.rulesContext()
    }

    func chapterIndex(_ state: HouseholdState) -> Int {
        context.path.firstIndex { !state.pathDone.contains($0.id) } ?? context.path.count
    }

    /// When each of the first hour's steps was done, in minutes after the first arrival.
    func firstHour() -> [String: Double] {
        var walker = Walker(f: Fixture(context: context), content: content)
        walker.f.add(.arrived, day: 0, hour: 8)
        walker.finishMovingIn(day: 0)
        var done: [String: Double] = [:]
        var log = SaveLog()
        let start = walker.f.at(0, 8)
        for event in walker.f.log.events {
            let before = log.derive(context: context).pathDone
            log.append(event)
            for id in log.derive(context: context).pathDone.subtracting(before) {
                done[id] = event.at.timeIntervalSince(start) / 60
            }
        }
        return done
    }

    func days(_ player: Player, count: Int) -> [Day] {
        var walker = Walker(f: Fixture(context: context), content: content)
        walker.f.add(.arrived, day: 0, hour: 8)
        walker.finishMovingIn(day: 0)
        var out: [Day] = []
        var met = GoalTracker.met(walker.state)
        var path = walker.state.pathDone
        for day in 0 ..< count {
            if day > 0 {
                walker.dailyCare(day: day, pets: player == .light ? 2 : player == .regular ? 4 : 6,
                                 games: player == .light ? 1 : player == .regular ? 3 : 5, nap: player == .keen)
                walker.f.playArcade(ArcadeHabit(player: player.rawValue), day: day, arcade: walker.state.arcade)
                walker.followThePath(day: day, hour: 19)
                walker.catUsesNewPieces(day: day, hour: 20)
            }
            let state = walker.state
            let today = state.clock.day(of: walker.f.at(day, 21))
            let tracker = GoalTracker.make(state, objectives: content.objectives, context: context, catName: "Pip", on: today)
            let nowMet = GoalTracker.met(state)
            out.append(Day(
                level: state.level, beans: state.beans, rooms: state.openedRooms.count, chapter: chapterIndex(state),
                steps: state.pathDone.subtracting(path).count, goals: nowMet.subtracting(met).count, tracker: tracker.entries.count
            ))
            met = nowMet
            path = state.pathDone
        }
        return out
    }

    @Test func theFirstHourHasSomethingEveryFewMinutesAndEndsWithMovingIn() throws {
        let done = firstHour()
        if ProcessInfo.processInfo.environment["HOUSECAT_PACING"] != nil {
            for (id, minute) in done.sorted(by: { $0.value < $1.value }) {
                print(String(format: "%5.1f min  %@", minute, id))
            }
        }
        let movingIn = try #require(context.path.first)
        let finished = try #require(done[movingIn.id], "Moving in is done in the first hour")
        #expect(finished <= 60)
        // No long wait between one step and the next (the nap is the longest: twenty minutes).
        let times = movingIn.steps.compactMap { done[$0.id] }.sorted()
        #expect(times.count == movingIn.steps.count)
        let gaps = zip(times, times.dropFirst()).map { $1 - $0 }
        #expect(gaps.allSatisfy { $0 <= Double(Tuning.Care.napMinutes + 5) }, "gaps \(gaps)")
    }

    @Test func theFirstWeekAndMonthKeepARhythm() {
        let print = ProcessInfo.processInfo.environment["HOUSECAT_PACING"] != nil
        for player in Player.allCases {
            let days = days(player, count: 60)
            if print {
                Swift.print("== \(player.rawValue)")
                for (index, day) in days.enumerated() where index < 14 || [20, 29, 39, 59].contains(index) {
                    Swift.print("day \(index + 1): level \(day.level), \(day.beans) Beans, \(day.rooms) rooms, chapter \(day.chapter + 1), "
                        + "\(day.steps) steps, \(day.goals) goals, tracker \(day.tracker)")
                }
            }
            // The first hour opens the bedroom, and Settling in is under way.
            #expect(days[0].rooms == 2 && days[0].chapter == 1, "\(player): Moving in on the first day")
            // Every day of the first week something is done.
            for day in 1 ..< 7 {
                #expect(days[day].goals >= 1, "\(player): nothing met on day \(day + 1)")
            }
            // Settling in within the first week (a light player, ten days), Making it home within the month (light: six weeks).
            let settled = days.firstIndex { $0.chapter >= 2 }
            let home = days.firstIndex { $0.chapter >= 3 }
            #expect((settled ?? 99) < (player == .light ? 10 : 7), "\(player): Settling in done on day \(settled.map { $0 + 1 } ?? 0)")
            #expect((home ?? 99) < (player == .light ? 42 : 30), "\(player): Making it home done on day \(home.map { $0 + 1 } ?? 0)")
            // The tracker is never empty.
            #expect(days.allSatisfy { $0.tracker >= 1 }, "\(player): an empty tracker")
        }
    }
}

extension Walker {
    /// A day's care: an arrival, a meal, strokes, the present, games (every third one three stars) and perhaps a nap.
    mutating func dailyCare(day: Int, pets: Int, games: Int, nap: Bool) {
        minute = 0
        f.add(.arrived, day: day, hour: 8)
        f.add(.fed(catID: f.cat), day: day, hour: 8, minute: 1)
        for pet in 0 ..< pets {
            f.add(.petted(catID: f.cat), day: day, hour: 8, minute: 2 + pet)
        }
        f.collectGifts(day: day, hour: 12)
        for game in 0 ..< games {
            f.add(.miniGamePlayed(game: "laser", stars: (day + game) % 3 == 0 ? 3 : 2), day: day, hour: 18, minute: game)
        }
        if nap {
            f.add(.napCompleted, day: day, hour: 18, minute: 40)
        }
    }
}
