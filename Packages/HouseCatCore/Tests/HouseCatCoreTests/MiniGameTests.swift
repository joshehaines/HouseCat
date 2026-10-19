import Foundation
@testable import HouseCatCore
import Testing

@Suite("Mini-games")
struct MiniGameTests {
    let dt = 1.0 / 60

    static func seed(_ game: String, _ play: Int = 0, household: UInt64 = 7) -> DaySeed {
        DaySeed(household: household, day: GameDay(index: 100), purpose: "minigame", salt: "\(game).\(play)")
    }

    @Test func starsComeFromTheGamesThresholds() {
        #expect(MiniGameRules.stars(score: 9.9, thresholds: [10, 18, 25]) == 0)
        #expect(MiniGameRules.stars(score: 10, thresholds: [10, 18, 25]) == 1)
        #expect(MiniGameRules.stars(score: 24, thresholds: [10, 18, 25]) == 2)
        #expect(MiniGameRules.stars(score: 5, thresholds: [3, 4, 5]) == 3)
        #expect(MiniGameRules.endLine(stars: 0) == "play.lose")
        #expect(MiniGameRules.endLine(stars: 2) == "play.win")
    }

    @Test func hitsInARowScoreTheComboUpToItsCap() {
        var combo = Combo()
        // One more every two in a row, up to five.
        #expect((1 ... 12).map { _ in combo.hit() } == [1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 5, 5])
        #expect(combo.best == 12)
        let lost = combo.breakOff()
        #expect(lost)
        #expect(combo.hit() == 1)
        // A lone hit lost is not a combo lost.
        let lone = combo.breakOff()
        #expect(!lone)
        _ = combo.hit()
        _ = combo.hit()
        let early = combo.tick(Tuning.MiniGames.comboSeconds - 0.1)
        let lapsed = combo.tick(0.2)
        #expect(!early)
        #expect(lapsed)
        #expect(combo.count == 0)
        #expect(combo.best == 12)
    }

    // MARK: Laser Pointer

    @Test func aDotLedAndHeldIsPouncedOnAndCaught() {
        var seed = Self.seed("laser_pointer")
        var game = LaserChase(duration: 20, personality: .velcro, seed: &seed)
        var beats: [PlayBeat] = []
        while !game.isOver {
            beats += game.step(dt, dot: MiniGameBot.laser(game))
        }
        #expect(beats.contains(.crouched))
        #expect(game.catches >= 8)
        #expect(game.combo.best >= 5)
        // Golden catches, and the catnip's zoomies.
        #expect(beats.contains { if case let .scored(hit) = $0 { hit.golden } else { false } })
        #expect(beats.contains { if case .zoomies = $0 { true } else { false } })
        #expect(beats.contains(.goldenAppeared))
    }

    @Test func aStillDotBoresTheCat() {
        var seed = Self.seed("laser_pointer")
        var game = LaserChase(duration: 20, personality: .velcro, seed: &seed)
        let dot = GamePoint(x: 9, y: 3)
        while !game.isOver {
            game.step(dt, dot: dot)
        }
        #expect(!game.interested)
        #expect(game.catches <= 1)
    }

    @Test func aDotFlickedAwayMidPounceIsMissedAndTheComboGoes() {
        var seed = Self.seed("laser_pointer")
        var game = LaserChase(duration: 20, personality: .gremlin, seed: &seed)
        // Two catches first.
        while game.catches < 2 {
            game.step(dt, dot: MiniGameBot.laser(game))
        }
        #expect(game.combo.count == 2)
        while game.phase != .leaping {
            game.step(dt, dot: MiniGameBot.laser(game))
        }
        let away = GamePoint(x: game.leapTo.x > 6 ? 1 : 11, y: game.leapTo.y > 3 ? 1 : 5)
        var beats: [PlayBeat] = []
        while game.phase == .leaping {
            beats += game.step(dt, dot: away)
        }
        #expect(beats.contains { if case .missed(_, true) = $0 { true } else { false } })
        #expect(game.combo.count == 0)
        #expect(game.catches == 2)
    }

    @Test func aDotFlickedFromCornerToCornerIsTooFast() {
        var seed = Self.seed("laser_pointer")
        var game = LaserChase(duration: 20, personality: .loaf, seed: &seed)
        let corners = [GamePoint(x: 0, y: 0), GamePoint(x: 12, y: 6), GamePoint(x: 0, y: 6), GamePoint(x: 12, y: 0)]
        var t = 0.0
        while !game.isOver {
            t += dt
            game.step(dt, dot: corners[Int(t / 0.4) % corners.count])
        }
        #expect(game.catches <= 2)
    }

    // MARK: Knock It Off

    @Test func tappingAsTheCatReachesEachThingKeepsTheShelfClearing() {
        var seed = Self.seed("knock_it_off")
        var game = KnockItOff(duration: 20, personality: .aloof, seed: &seed)
        #expect(game.things.count == Tuning.MiniGames.shelfStart)
        var beats: [PlayBeat] = []
        var most = 0
        while !game.isOver {
            beats += game.step(dt)
            most = max(most, game.things.count)
            if MiniGameBot.knock(game) {
                beats += game.tap()
            }
        }
        // Things kept coming long after the first three were gone, and never more than a shelf's worth.
        #expect(game.knocked >= 15)
        #expect(most <= Tuning.MiniGames.shelfSlots)
        #expect(game.combo.best >= 10)
        #expect(game.elapsed == 20)
        #expect(beats.contains { if case let .scored(hit) = $0 { hit.golden } else { false } })
        #expect(beats.contains { if case .zoomies = $0 { true } else { false } })
    }

    @Test func aSwipeAtNothingBreaksTheComboAndRestsTheCat() {
        var seed = Self.seed("knock_it_off")
        var game = KnockItOff(duration: 20, personality: .gremlin, seed: &seed)
        while game.knocked < 2 {
            game.step(dt)
            if MiniGameBot.knock(game) {
                game.tap()
            }
        }
        while game.inReach != nil {
            game.step(0.001)
        }
        let beats = game.tap()
        let at = GamePoint(x: game.paw, y: 0)
        #expect(beats == [.missed(at: at, lost: true)])
        #expect(game.combo.count == 0)
        let paw = game.paw
        game.step(0.3)
        #expect(game.paw == paw)
        let resting = game.tap()
        #expect(resting.isEmpty) // still resting
        game.step(Tuning.MiniGames.missRestSeconds)
        #expect(game.paw != paw)
    }

    @Test func theShelfFillsUpWhenNothingIsKnockedOff() {
        var seed = Self.seed("knock_it_off")
        var game = KnockItOff(duration: 20, personality: .loaf, seed: &seed)
        while !game.isOver {
            game.step(dt)
        }
        #expect(game.things.count >= Tuning.MiniGames.shelfSlots - 1)
        #expect(game.points == 0)
    }

    // MARK: String Chase

    @Test func stringsLeadTheCatToSparklesThatKeepComing() {
        var seed = Self.seed("string_chase", 1)
        var game = StringChase(duration: 20, personality: .velcro, seed: &seed)
        var again = Self.seed("string_chase", 1)
        #expect(StringChase(duration: 20, personality: .velcro, seed: &again).sparkles == game.sparkles)
        #expect(game.sparkles.count == Tuning.MiniGames.sparklesAtOnce)
        var beats: [PlayBeat] = []
        while !game.isOver {
            if let path = MiniGameBot.string(game) {
                game.draw(path)
            }
            beats += game.step(dt)
        }
        #expect(game.gathered >= 10)
        #expect(game.combo.best >= 4)
        #expect(beats.contains { if case let .scored(hit) = $0 { hit.golden } else { false } })
        #expect(beats.contains { if case .zoomies = $0 { true } else { false } })
    }

    @Test func sparklesFadeAndOthersTakeTheirPlace() {
        var seed = Self.seed("string_chase")
        var game = StringChase(duration: 20, personality: .loaf, seed: &seed)
        let first = Set(game.sparkles.map(\.id))
        let start = game.cat
        while !game.isOver {
            game.step(dt)
        }
        #expect(game.cat == start)
        #expect(game.gathered == 0)
        #expect(game.sparkles.count == Tuning.MiniGames.sparklesAtOnce)
        #expect(first.isDisjoint(with: game.sparkles.map(\.id)))
    }

    // MARK: Hide and Seek

    @Test func theCatPeeksFromWhereItHidesAndIsFoundThere() {
        var seed = Self.seed("hide_and_seek")
        var game = HideAndSeek(duration: 20, personality: .velcro, seed: &seed)
        #expect(game.places.count == Tuning.MiniGames.hidePlaces)
        #expect(Set(game.places).count == game.places.count)
        var beats: [PlayBeat] = []
        var spots: [Int] = []
        while !game.isOver {
            beats += game.step(dt)
            if let place = MiniGameBot.hide(game) {
                if place < 0 {
                    beats += game.tapCatnip()
                } else {
                    spots.append(place)
                    beats += game.tap(place: place)
                }
            }
        }
        // Every peek is at the cat's place, it moves between rounds, and quick finds, golden ones and the zoomies come.
        #expect(game.found >= 8)
        #expect(zip(spots, spots.dropFirst()).allSatisfy { $0 != $1 })
        #expect(beats.contains { if case let .scored(hit) = $0 { hit.perfect } else { false } })
        #expect(beats.contains { if case let .scored(hit) = $0 { hit.golden } else { false } })
        #expect(beats.contains { if case .zoomies = $0 { true } else { false } })
        #expect(beats.contains { if case .rustled = $0 { true } else { false } })
    }

    @Test func aWrongPlaceBreaksTheComboAndTheCatGivesItselfAway() {
        var seed = Self.seed("hide_and_seek")
        var game = HideAndSeek(duration: 20, personality: .aloof, seed: &seed)
        while game.found < 2 {
            game.step(dt)
            if let place = MiniGameBot.hide(game), place >= 0 {
                game.tap(place: place)
            }
        }
        while game.phase != .seeking {
            game.step(dt)
        }
        let wrong = (game.spot + 1) % game.places.count
        let beats = game.tap(place: wrong)
        #expect(beats.first == .missed(at: GamePoint(x: Double(wrong), y: 0), lost: true))
        #expect(beats.contains(.peeked(place: game.spot)))
        #expect(game.peeking)
        #expect(game.combo.count == 0)
        // A moment's rest before the next guess.
        let spot = game.spot
        let resting = game.tap(place: spot)
        #expect(resting.isEmpty)
        game.step(Tuning.MiniGames.missRestSeconds)
        let later = game.tap(place: spot)
        #expect(later.contains { if case .scored = $0 { true } else { false } })
    }

    @Test func leftUnfoundTheCatComesOutByItself() {
        var seed = Self.seed("hide_and_seek")
        var game = HideAndSeek(duration: 20, personality: .loaf, seed: &seed)
        var beats: [PlayBeat] = []
        while !game.isOver {
            beats += game.step(dt)
        }
        #expect(game.points == 0)
        #expect(beats.contains { if case .cameOut = $0 { true } else { false } })
        #expect(game.round >= 3)
    }

    // MARK: Stars

    /// Each game played three ways: by the steady player, by a careless one, and not at all.
    enum Player: CaseIterable {
        case steady, careless, idle
    }

    static func play(_ id: String, _ player: Player, personality: Personality, play: Int) -> Double {
        let dt = 1.0 / 60
        var seed = Self.seed(id, play, household: UInt64(play * 31 + 3))
        var t = 0.0
        switch id {
        case "laser_pointer":
            var game = LaserChase(duration: Tuning.MiniGames.roundSeconds, personality: personality, seed: &seed)
            while !game.isOver {
                t += dt
                let dot: GamePoint = switch player {
                case .steady: MiniGameBot.laser(game)
                // Never stops: a loop round the room, never waiting for the pounce.
                case .careless: GamePoint(x: 6 + 3.5 * cos(t * 0.6), y: 3 + 1.8 * sin(t * 0.6))
                case .idle: GamePoint(x: 9, y: 3)
                }
                game.step(dt, dot: dot)
            }
            return game.score
        case "knock_it_off":
            var game = KnockItOff(duration: Tuning.MiniGames.roundSeconds, personality: personality, seed: &seed)
            var rng = Self.seed("careless", play)
            var lastTap = 0.0
            while !game.isOver {
                t += dt
                game.step(dt)
                switch player {
                case .steady:
                    if MiniGameBot.knock(game) {
                        game.tap()
                    }
                case .careless:
                    // Taps about twice a second, roughly when something is near.
                    if t - lastTap > 0.5, game.things.contains(where: { abs($0.at - game.paw) < 0.15 }), rng.below(4) == 0 {
                        lastTap = t
                        game.tap()
                    }
                case .idle:
                    break
                }
            }
            return game.score
        case "hide_and_seek":
            var game = HideAndSeek(duration: Tuning.MiniGames.roundSeconds, personality: personality, seed: &seed)
            var rng = Self.seed("careless", play)
            var lastTap = 0.0
            var seen: Int?
            while !game.isOver {
                t += dt
                let beats = game.step(dt)
                if beats.contains(.hid) {
                    seen = nil
                }
                switch player {
                case .steady:
                    if let place = MiniGameBot.hide(game) {
                        place < 0 ? game.tapCatnip() : game.tap(place: place)
                    }
                case .careless:
                    // A tap now and then: where it last saw the cat peek, or a guess; never the catnip.
                    if game.peeking {
                        seen = game.spot
                    }
                    if t - lastTap > 0.8, game.phase == .seeking {
                        lastTap = t
                        game.tap(place: seen ?? rng.below(game.places.count))
                    }
                case .idle:
                    break
                }
            }
            return game.score
        default:
            var game = StringChase(duration: Tuning.MiniGames.roundSeconds, personality: personality, seed: &seed)
            var lastDraw = -10.0
            while !game.isOver {
                t += dt
                switch player {
                case .steady:
                    if let path = MiniGameBot.string(game) {
                        game.draw(path)
                    }
                case .careless:
                    // A string to whichever sparkle comes first in the list, now and then.
                    if t - lastDraw > 1.6, let sparkle = game.sparkles.first {
                        lastDraw = t
                        game.draw([sparkle.at])
                    }
                case .idle:
                    break
                }
                game.step(dt)
            }
            return game.score
        }
    }

    /// The thresholds in minigames.json: the steady player earns three stars in every personality, a careless one
    /// one or two, someone who does nothing none, over a spread of plays.
    @Test(arguments: ["laser_pointer", "knock_it_off", "string_chase", "hide_and_seek"])
    func starsRewardPlayingWell(_ id: String) throws {
        let content = try ContentBundle.load(from: ContentValidationTests.repo.appendingPathComponent("Content"))
        let thresholds = try #require(content.minigames.games.first { $0.id == id }).stars
        let print = ProcessInfo.processInfo.environment["HOUSECAT_STARS"] != nil
        for personality in Personality.allCases {
            for player in Player.allCases {
                let scores = (0 ..< 6).map { Self.play(id, player, personality: personality, play: $0) }
                let stars = scores.map { MiniGameRules.stars(score: $0, thresholds: thresholds) }
                if print {
                    Swift.print("\(id) \(personality) \(player): \(scores.map { Int($0) }) stars \(stars)")
                }
                switch player {
                case .steady: #expect(stars.allSatisfy { $0 == 3 }, "\(id) \(personality) steady: \(scores)")
                case .careless: #expect(stars.allSatisfy { (1 ... 2).contains($0) }, "\(id) \(personality) careless: \(scores)")
                case .idle: #expect(stars.allSatisfy { $0 == 0 }, "\(id) \(personality) idle: \(scores)")
                }
            }
        }
    }

    // MARK: Plays and pay

    /// Every game is 20 seconds on the clock, so a round from the count to the result is about half a minute.
    @Test func aRoundIsAboutHalfAMinute() throws {
        let content = try ContentBundle.load(from: ContentValidationTests.repo.appendingPathComponent("Content"))
        for game in content.minigames.games {
            #expect(Double(game.durationSeconds) == Tuning.MiniGames.roundSeconds, "\(game.id)")
            let round = Double(game.durationSeconds) + 3 * Tuning.MiniGames.countSeconds
            #expect((20 ... 45).contains(round), "\(game.id): \(round) s")
        }
    }

    /// Shorter games must not pay faster (Josh, 19 Oct): a day pays for five plays however many more are played and
    /// however quick they are, through the real content (its objectives included). Five three-star plays are the
    /// day's most from the games: 30 Beans and 25 XP before the objectives.
    @Test func moreGamesInADayPayNoMore() throws {
        let content = try ContentBundle.load(from: ContentValidationTests.repo.appendingPathComponent("Content"))
        let context = try content.rulesContext()
        let ids = content.minigames.games.map(\.id)
        func day(plays: Int) -> HouseholdState {
            var f = Fixture(context: context)
            f.visit(days: [0])
            for play in 0 ..< plays {
                // One every 40 seconds: as fast as the rounds allow.
                f.add(.miniGamePlayed(game: ids[play % ids.count], stars: 3), day: 0, hour: 10, minute: play * 2 / 3)
            }
            return f.state(through: 1)
        }
        let five = day(plays: 5), twenty = day(plays: 20), none = day(plays: 0)
        #expect(twenty.beans == five.beans)
        #expect(twenty.xp == five.xp)
        #expect(five.xp - none.xp >= 5 * Tuning.XP.play)
        let games = Tuning.MiniGames.playsPerDay * (Tuning.MiniGames.starBeans.last ?? 0)
        #expect(games == 30)
        #expect(five.beans - none.beans >= games)
    }

    @Test func fivePlaysADayPayAndThenStop() {
        var f = Fixture()
        f.visit(days: [0])
        let before = f.state.beans
        for i in 0 ..< 6 {
            f.add(.miniGamePlayed(game: "laser_pointer", stars: 3), day: 0, hour: 10, minute: i)
        }
        #expect(f.state.today?.plays == 5)
        #expect(MiniGameRules.playsLeft(f.state) == 0)
        #expect(f.state.beans - before >= 5 * Tuning.MiniGames.starBeans[2])
        #expect(MiniGameRules.playsLeft(f.state(through: 1)) == Tuning.MiniGames.playsPerDay)
    }

    @Test func aNapPaysOnceADayWhenItRunsItsCourse() {
        var f = Fixture()
        f.visit(days: [0])
        let start = f.at(0, 21)
        #expect(NapRules.end(of: start) == start.addingTimeInterval(20 * 60))
        #expect(!NapRules.isComplete(startedAt: start, at: start.addingTimeInterval(19 * 60)))
        #expect(NapRules.isComplete(startedAt: start, at: start.addingTimeInterval(20 * 60)))
        #expect(NapRules.pays(f.state))
        let xp = f.state.xp
        f.add(.napCompleted, day: 0, hour: 21, minute: 20)
        #expect(f.state.xp == xp + Tuning.XP.nap)
        #expect(!NapRules.pays(f.state))
        f.add(.napCompleted, day: 0, hour: 22)
        #expect(f.state.xp == xp + Tuning.XP.nap)
    }
}
