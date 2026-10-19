import Foundation

/// Hide and Seek (CONTENT.md §6): the cat hides behind one of the room's things while your eyes are shut, then peeks
/// out now and then: its ears over the top, its face round the side. Tap where it is to find it, each find scoring
/// the combo, twice over when quick. A wrong place breaks the combo and makes the cat peek again; left unfound, it
/// comes out by itself. As the game goes on its peeks get shorter and further apart and the other places rustle to
/// fool you. Some rounds it hides with a golden bell; once a catnip fish lies out, and the cat with the zoomies can't
/// keep still.
public struct HideAndSeek: Sendable {
    public enum Phase: Equatable, Sendable {
        /// Eyes shut: the cat is finding its place.
        case hiding
        case seeking
        /// Out from behind its place, found or not, before the next round.
        case found
    }

    /// The things it hides behind (indices into `Tuning.MiniGames.hidingPlaces`), left to right along the floor.
    public let places: [Int]
    /// Where the cat is hiding (an index into `places`).
    public private(set) var spot: Int
    public private(set) var phase = Phase.hiding
    public private(set) var phaseTime = 0.0
    public private(set) var elapsed = 0.0
    public private(set) var round = 0
    public private(set) var points = 0
    public private(set) var found = 0
    public private(set) var combo = Combo()
    /// The round's cat wears a golden bell.
    public private(set) var golden = false
    public private(set) var zoomiesLeft = 0.0
    /// The catnip lies by one of the places for a while.
    public private(set) var catnip: Catnip
    public let catnipPlace: Int
    /// A place rustling as a decoy now, and for how long more.
    public private(set) var rustling: Int?
    /// After a wrong guess the player waits this long.
    public private(set) var resting = 0.0
    /// How long the cat has been showing in this peek.
    public private(set) var peekedFor = 0.0
    public let duration: Double
    private var seed: DaySeed
    private var nextPeek = 0.0
    private var peekLeft = 0.0
    private var rustleLeft = 0.0
    private var nextRustle = 0.0
    private let goldenRounds: Set<Int>

    public init(duration: Double, personality _: Personality, seed: inout DaySeed) {
        self.duration = duration
        // Five of the hiding places, in an order of the play's own.
        var all = Array(Tuning.MiniGames.hidingPlaces.indices)
        var chosen: [Int] = []
        let count = min(Tuning.MiniGames.hidePlaces, all.count)
        while chosen.count < count {
            chosen.append(all.remove(at: seed.below(all.count)))
        }
        places = chosen
        spot = seed.below(chosen.count)
        goldenRounds = [3 + seed.below(2), 7 + seed.below(3)]
        catnipPlace = seed.below(chosen.count)
        let shows = MiniGameRules.moment(duration * 0.2, duration * 0.35, seed: &seed)
        catnip = Catnip(at: GamePoint(x: Double(catnipPlace), y: 0), from: shows, until: shows + duration * 0.3)
        self.seed = seed
    }

    public var isOver: Bool {
        elapsed >= duration
    }

    public var score: Double {
        Double(points)
    }

    public var hasZoomies: Bool {
        zoomiesLeft > 0
    }

    /// The cat showing from behind its place now.
    public var peeking: Bool {
        phase == .seeking && (peekLeft > 0 || hasZoomies)
    }

    @discardableResult
    public mutating func step(_ dt: Double) -> [PlayBeat] {
        guard !isOver else { return [] }
        let dt = min(dt, duration - elapsed)
        elapsed += dt
        phaseTime += dt
        resting = max(0, resting - dt)
        var beats: [PlayBeat] = []
        let t = Tuning.MiniGames.self
        switch phase {
        case .hiding:
            if phaseTime >= t.hideSeconds {
                phase = .seeking
                phaseTime = 0
                nextPeek = t.firstPeek
                // A decoy may come first, before the cat's own peek.
                nextRustle = t.firstPeek * 0.4
            }
        case .seeking:
            if peekLeft > 0 {
                peekLeft -= dt
                peekedFor += dt
            }
            nextPeek -= dt
            if nextPeek <= 0 {
                beats.append(peek())
            }
            if MiniGameRules.ramp(elapsed, of: duration) >= t.rustleFrom {
                nextRustle -= dt
                if nextRustle <= 0 {
                    nextRustle = t.rustleEvery
                    let others = places.indices.filter { $0 != spot }
                    let place = others[seed.below(others.count)]
                    rustling = place
                    rustleLeft = 0.4
                    beats.append(.rustled(place: place))
                }
            }
            if phaseTime >= t.comeOutSeconds {
                beats.append(.cameOut(place: spot))
                if combo.breakOff() {
                    beats.append(.comboLapsed)
                }
                enterFound()
            }
        case .found:
            if phaseTime >= t.foundSeconds {
                hide(&beats)
            }
        }
        if rustleLeft > 0 {
            rustleLeft -= dt
            if rustleLeft <= 0 {
                rustling = nil
            }
        }
        if zoomiesLeft > 0, !beats.contains(where: { if case .zoomies = $0 { true } else { false } }) {
            zoomiesLeft -= dt
            if zoomiesLeft <= 0 {
                zoomiesLeft = 0
                beats.append(.zoomiesOver)
            }
        }
        return beats
    }

    /// A tap on a place: found, or a wrong guess.
    @discardableResult
    public mutating func tap(place: Int) -> [PlayBeat] {
        guard !isOver, phase == .seeking, resting == 0, places.indices.contains(place) else { return [] }
        guard place == spot else {
            resting = Tuning.MiniGames.missRestSeconds
            // The cat gives itself away, a little.
            return [.missed(at: GamePoint(x: Double(place), y: 0), lost: combo.breakOff()), peek()]
        }
        found += 1
        let quick = phaseTime <= Tuning.MiniGames.quickSeconds
        var scored = combo.hit()
        if quick {
            scored *= Tuning.MiniGames.perfectTimes
        }
        if golden {
            scored *= Tuning.MiniGames.goldenTimes
        }
        if hasZoomies {
            scored *= Tuning.MiniGames.zoomiesTimes
        }
        points += scored
        let hit = Hit(points: scored, combo: combo.count, at: GamePoint(x: Double(place), y: 0), golden: golden, zoomies: hasZoomies, perfect: quick)
        enterFound()
        return [.scored(hit)]
    }

    /// A tap on the catnip while it lies out: the zoomies.
    @discardableResult
    public mutating func tapCatnip() -> [PlayBeat] {
        guard !isOver, catnip.showing(elapsed) else { return [] }
        _ = catnip.take(by: catnip.at, at: elapsed)
        zoomiesLeft = Tuning.MiniGames.zoomiesSeconds
        return [.zoomies(at: catnip.at)]
    }

    private mutating func peek() -> PlayBeat {
        let t = Tuning.MiniGames.self
        peekLeft = MiniGameRules.along(t.peekSeconds, elapsed, of: duration)
        peekedFor = 0
        nextPeek = MiniGameRules.along(t.peekEvery, elapsed, of: duration)
        return .peeked(place: spot)
    }

    private mutating func enterFound() {
        phase = .found
        phaseTime = 0
        peekLeft = 0
        rustling = nil
    }

    /// The next round: eyes shut, and the cat somewhere else.
    private mutating func hide(_ beats: inout [PlayBeat]) {
        round += 1
        let others = places.indices.filter { $0 != spot }
        spot = others[seed.below(others.count)]
        golden = goldenRounds.contains(round)
        phase = .hiding
        phaseTime = 0
        beats.append(.hid)
        if golden {
            beats.append(.goldenAppeared)
        }
    }
}
