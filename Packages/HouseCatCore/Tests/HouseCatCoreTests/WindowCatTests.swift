import Foundation
@testable import HouseCatCore
import Testing

@Suite("The cat at a window, from outside")
struct WindowCatTests {
    /// A terrace's windows: the bay and a sash downstairs, two sashes up.
    let windows = [
        SceneWindow(left: 0.47, top: 0.56, right: 0.55, bottom: 0.69, row: 0),
        SceneWindow(left: 0.39, top: 0.58, right: 0.42, bottom: 0.66, row: 0),
        SceneWindow(left: 0.40, top: 0.34, right: 0.43, bottom: 0.44, row: 1),
        SceneWindow(left: 0.50, top: 0.38, right: 0.54, bottom: 0.49, row: 1),
    ]
    let day = GameDay(year: 2026, month: 10, day: 20)

    func sighting(_ context: WindowCatRules.Context, minutes: Int = 600, seed: UInt64 = 7) -> WindowSighting? {
        WindowCatRules.sighting(windows: windows, context: context, household: seed, day: day, minutes: minutes)
    }

    @Test func theCatIsAtAWindowOnTheFloorOfItsRoom() throws {
        for seed in UInt64(0) ..< 40 {
            for minutes in stride(from: 0, to: 24 * 60, by: 60) {
                let down = try #require(sighting(.init(storey: 0, storeys: 3, activity: .sit, sky: .day), minutes: minutes, seed: seed))
                #expect(windows[down.window].row == 0)
                let up = try #require(sighting(.init(storey: 1, storeys: 3, activity: .sleep, sky: .day), minutes: minutes, seed: seed))
                #expect(windows[up.window].row == 1)
                #expect(up.pose == .asleep)
                // The attic, in a home painted with two rows of windows: the top row.
                let attic = try #require(sighting(.init(storey: 2, storeys: 3, activity: nil, sky: .day), minutes: minutes, seed: seed))
                #expect(windows[attic.window].row == 1)
            }
        }
    }

    @Test func storeysSpreadOverTheRowsThePaintingHas() {
        #expect(WindowCatRules.row(storey: 0, storeys: 3, rows: [0, 1, 2]) == 0)
        #expect(WindowCatRules.row(storey: 1, storeys: 3, rows: [0, 1, 2]) == 1)
        #expect(WindowCatRules.row(storey: 2, storeys: 3, rows: [0, 1, 2]) == 2)
        // A two-storey plan in a block of three rows: upstairs is the top row.
        #expect(WindowCatRules.row(storey: 1, storeys: 2, rows: [0, 1, 2]) == 2)
        // Upstairs never shows downstairs while there is a row above, and one row serves every storey.
        #expect(WindowCatRules.row(storey: 1, storeys: 3, rows: [0, 1]) == 1)
        #expect(WindowCatRules.row(storey: 2, storeys: 3, rows: [0]) == 0)
        #expect(WindowCatRules.row(storey: 0, storeys: 1, rows: []) == 0)
    }

    @Test func theSameMomentGivesTheSameWindowAndTheDayMovesItAbout() throws {
        let context = WindowCatRules.Context(storey: 0, storeys: 3, activity: .sit, sky: .day)
        #expect(sighting(context, minutes: 610) == sighting(context, minutes: 610))
        // Within a part of the day it stays put.
        #expect(sighting(context, minutes: 600) == sighting(context, minutes: 600 + Tuning.WindowCat.slotMinutes - 1))
        // Over a week of days it uses both downstairs windows, the bay more often than the small sash.
        var counts = [Int: Int]()
        for date in 1 ... 7 {
            for minutes in stride(from: 0, to: 24 * 60, by: Tuning.WindowCat.slotMinutes) {
                let seen = try #require(WindowCatRules.sighting(
                    windows: windows,
                    context: context,
                    household: 7,
                    day: GameDay(year: 2026, month: 10, day: date),
                    minutes: minutes
                ))
                counts[seen.window, default: 0] += 1
            }
        }
        #expect(counts[0, default: 0] > counts[1, default: 0])
        #expect(counts[1, default: 0] > 0)
    }

    @Test func aCatWatchingYouIsAtTheWindowNearestTheDoorLookingOut() throws {
        for storey in 0 ... 2 {
            let seen = try #require(sighting(.init(storey: storey, storeys: 3, activity: .nearPlayer, sky: .dusk, watchingYou: true, door: 0.40)))
            #expect(seen.window == 1)
            #expect(seen.pose == .lookingOut)
        }
    }

    @Test func itSitsAtTheWindowAsItIsInside() throws {
        func pose(_ activity: Activity?, mood: Mood? = nil, sky: SkyPhase = .day) throws -> WindowPose {
            try #require(sighting(.init(storey: 0, storeys: 3, activity: activity, mood: mood, sky: sky))).pose
        }
        #expect(try pose(.sleep) == .asleep)
        #expect(try pose(.windowWatch) == .lookingOut)
        #expect(try pose(.sunbeamLoaf) == .loafing)
        #expect(try pose(.sit, mood: .sulky) == .backTurned)
        #expect(try pose(.sulk) == .backTurned)
        #expect(try [.lookingOut, .watchingStreet].contains(pose(.perch)))
        // Not known: by the time of day.
        #expect(try pose(nil, sky: .night) == .asleep)
        #expect(try pose(nil, sky: .dusk) == .loafing)
        #expect(try pose(nil, mood: .sleepy, sky: .day) == .asleep)
        #expect(try [.lookingOut, .watchingStreet].contains(pose(nil, sky: .day)))
        // Watching from the window: the biggest one on its floor.
        #expect(try #require(sighting(.init(storey: 0, storeys: 3, activity: .windowWatch, sky: .day))).window == 0)
    }

    @Test func aSceneWithNoWindowHasNoCatInIt() {
        let context = WindowCatRules.Context(storey: 0, storeys: 1, activity: nil, sky: .day)
        #expect(WindowCatRules.sighting(windows: [], context: context, household: 1, day: day, minutes: 0) == nil)
    }

    /// Every painted exterior the app ships (each home in each biome and season) has a window the cat can sit in,
    /// inside its house and with its rows counted up from the ground floor's.
    @Test func everyPaintedHomeHasAWindowForTheCat() throws {
        struct Index: Decodable {
            var houses: [String: [Double]]
            var windows: [String: [[Double]]]
        }
        let url = ContentValidationTests.repo.appendingPathComponent("assets/world/scenes/scenes.json")
        let index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: url))
        let homes = ["london_terrace", "mansion_flat", "cottage", "georgian_townhouse", "newbuild_balcony", "houseboat",
                     "mediterranean_rooftop", "woodland_cabin"]
        for home in homes {
            for biome in Biome.allCases {
                for season in NatureSeason.allCases {
                    let name = "\(home)_\(biome.rawValue)_\(season.rawValue)"
                    let windows = (index.windows[name] ?? []).compactMap(SceneWindow.init)
                    #expect(!windows.isEmpty, "\(name) has no window")
                    let rows = Set(windows.map(\.row)).sorted()
                    #expect(rows.isEmpty || rows == Array(0 ..< rows.count), "\(name) rows \(rows)")
                    for window in windows {
                        #expect(window.width > 0.005 && window.height > 0.01, "\(name) \(window)")
                        #expect(window.width < 0.2 && window.height < 0.3, "\(name) \(window)")
                        #expect(window.left >= 0 && window.right <= 1 && window.top >= 0 && window.bottom <= 1, "\(name) \(window)")
                    }
                }
            }
        }
    }
}
