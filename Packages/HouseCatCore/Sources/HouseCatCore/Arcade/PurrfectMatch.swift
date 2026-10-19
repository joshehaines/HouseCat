import Foundation

/// Purrfect Match (the Games menu's match-three): swap two neighbouring pieces to line up three or more of a kind.
/// Four in a line makes a paw swipe (it clears the line across the one it was made in), an L or T makes a box (it
/// clears the nine round it), five in a line makes the laser dot (swapped with a piece it clears every one of that
/// kind). Dust under pieces is cleared by matching on it, parcels by a match beside them or a blast; tangled pieces
/// cannot be moved until they are matched. The level's goals within its moves win it. Every step is deterministic
/// for the level and the attempt's seed.
public enum MatchKind: Int, Codable, Sendable, CaseIterable {
    case fish, yarn, mouse, biscuit, catnip, feather

    /// The painting's name (art: arcade/match/match_<name>.png) and the goal's word in the level file.
    public var name: String {
        switch self {
        case .fish: "fish"
        case .yarn: "yarn"
        case .mouse: "mouse"
        case .biscuit: "biscuit"
        case .catnip: "catnip"
        case .feather: "feather"
        }
    }
}

public enum MatchSpecial: Int, Codable, Sendable {
    /// Clears its row.
    case swipeRow
    /// Clears its column.
    case swipeColumn
    /// Clears the three by three round it.
    case box
    /// No kind of its own: swapped with a piece it clears every piece of that kind.
    case laser
}

public struct MatchPiece: Hashable, Sendable {
    public var kind: MatchKind?
    public var special: MatchSpecial?

    public init(kind: MatchKind?, special: MatchSpecial? = nil) {
        self.kind = kind
        self.special = special
    }
}

/// A point on the board: column from the left, row from the top.
public struct MatchPoint: Hashable, Codable, Sendable {
    public let x: Int
    public let y: Int

    public init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }
}

/// A level's goal.
public enum MatchGoal: Hashable, Sendable {
    /// Clear this many pieces of a kind.
    case collect(MatchKind, Int)
    /// Clear every bit of dust.
    case dust
    /// Open every parcel.
    case parcels
}

/// One level of Purrfect Match (Content/match_levels.json).
public struct MatchLevel: Codable, Equatable, Sendable {
    public var id: Int
    /// The shape, top row first: "." no cell, "o" a cell, "d" a cell with dust, "D" double dust, "p" a parcel,
    /// "P" a parcel tied twice, "t" a tangled piece.
    public var layout: [String]
    public var moves: Int
    /// How many kinds of piece fall (4 to 6: fewer is easier).
    public var kinds: Int
    /// "dust", "parcels" or "collect:<kind>:<count>".
    public var goals: [String]
    /// The score for two and three stars (one star is the goals met).
    public var stars: [Int]
    /// The level's name on its card ("Tidy the living room").
    public var title: String

    public init(id: Int, layout: [String], moves: Int, kinds: Int, goals: [String], stars: [Int], title: String) {
        self.id = id
        self.layout = layout
        self.moves = moves
        self.kinds = kinds
        self.goals = goals
        self.stars = stars
        self.title = title
    }

    public var width: Int {
        layout.map(\.count).max() ?? 0
    }

    public var height: Int {
        layout.count
    }

    public var parsedGoals: [MatchGoal] {
        goals.compactMap(Self.goal)
    }

    static func goal(_ text: String) -> MatchGoal? {
        if text == "dust" { return .dust }
        if text == "parcels" { return .parcels }
        let parts = text.split(separator: ":")
        guard parts.count == 3, parts[0] == "collect", let count = Int(parts[2]), count > 0,
              let kind = MatchKind.allCases.first(where: { $0.name == parts[1] }) else { return nil }
        return .collect(kind, count)
    }
}

public struct MatchLevelsFile: Codable, Sendable {
    public var version: Int
    public var levels: [MatchLevel]

    public init(version: Int, levels: [MatchLevel]) {
        self.version = version
        self.levels = levels
    }
}

/// What a move did, wave by wave, for the scene to animate: what was cleared and made, then the falls and the new
/// pieces (which drop in from above their column).
public struct MatchWave: Sendable {
    public var cleared: [MatchPoint: MatchPiece] = [:]
    public var made: [MatchPoint: MatchPiece] = [:]
    public var fired: [MatchPoint: MatchSpecial] = [:]
    public var dustCleared: Set<MatchPoint> = []
    public var parcelsHit: Set<MatchPoint> = []
    public var tanglesCleared: Set<MatchPoint> = []
    /// Pieces that fell, from and to (a piece's whole fall in the wave).
    public var falls: [(from: MatchPoint, to: MatchPoint)] = []
    /// New pieces and where they come to rest.
    public var spawned: [MatchPoint: MatchPiece] = [:]
    public var points = 0
    /// The cascade this wave was (1 for the move itself).
    public var cascade = 1
}

public struct MatchGame: Sendable {
    public let level: MatchLevel
    public let width: Int
    public let height: Int
    public let goals: [MatchGoal]
    private var cell: [Bool]
    private var grid: [MatchPiece?]
    private var dustLayers: [Int]
    private var parcelLayers: [Int]
    private var tangled: [Bool]
    public private(set) var movesLeft: Int
    public private(set) var score = 0
    public private(set) var collected: [MatchKind: Int] = [:]
    /// Specials made over the game, and dust cleared (for the challenges).
    public private(set) var made: [MatchSpecial: Int] = [:]
    public private(set) var dustCleared = 0
    /// Times the board had no move and was shuffled.
    public private(set) var shuffles = 0
    private var seed: DaySeed
    private let kinds: [MatchKind]
    private let tops: Set<Int>

    public init(level: MatchLevel, seed: DaySeed) {
        self.level = level
        width = level.width
        height = level.height
        goals = level.parsedGoals
        movesLeft = level.moves
        self.seed = seed
        kinds = Array(MatchKind.allCases.prefix(min(max(level.kinds, 3), MatchKind.allCases.count)))
        let count = level.width * level.height
        cell = Array(repeating: false, count: count)
        grid = Array(repeating: nil, count: count)
        dustLayers = Array(repeating: 0, count: count)
        parcelLayers = Array(repeating: 0, count: count)
        tangled = Array(repeating: false, count: count)
        for (y, line) in level.layout.enumerated() {
            for (x, mark) in line.enumerated() where mark != "." {
                let i = y * level.width + x
                cell[i] = true
                switch mark {
                case "d": dustLayers[i] = 1
                case "D": dustLayers[i] = 2
                case "p": parcelLayers[i] = 1
                case "P": parcelLayers[i] = 2
                case "t": tangled[i] = true
                default: break
                }
            }
        }
        // New pieces drop in at the top of each column, and below any gap in it.
        var tops: [Int] = []
        for i in 0 ..< count where cell[i] && (i < level.width || !cell[i - level.width]) {
            tops.append(i)
        }
        self.tops = Set(tops)
        fillWithoutMatches()
    }

    /// Sets the pieces from a picture, top row first, one token per cell separated by spaces (for tests): a kind's
    /// letter (f fish, y yarn, m mouse, b biscuit, c catnip, e feather), with "-" a row swipe, "|" a column swipe,
    /// "#" a box; "L" the laser; "." nothing.
    mutating func set(_ picture: [String]) {
        let letters: [Character: MatchKind] = ["f": .fish, "y": .yarn, "m": .mouse, "b": .biscuit, "c": .catnip, "e": .feather]
        for (y, line) in picture.enumerated() {
            for (x, token) in line.split(separator: " ").enumerated() {
                let i = y * width + x
                guard cell[i], parcelLayers[i] == 0 else { continue }
                if token == "L" {
                    grid[i] = MatchPiece(kind: nil, special: .laser)
                } else if token == "." {
                    grid[i] = nil
                } else {
                    let kind = letters[token.first!]
                    let special: MatchSpecial? = switch token.dropFirst().first {
                    case "-": .swipeRow
                    case "|": .swipeColumn
                    case "#": .box
                    default: nil
                    }
                    grid[i] = MatchPiece(kind: kind, special: special)
                }
            }
        }
    }

    // MARK: Reading the board

    func index(_ p: MatchPoint) -> Int? {
        p.x >= 0 && p.x < width && p.y >= 0 && p.y < height ? p.y * width + p.x : nil
    }

    func point(_ i: Int) -> MatchPoint {
        MatchPoint(i % width, i / width)
    }

    public func isCell(_ p: MatchPoint) -> Bool {
        index(p).map { cell[$0] } ?? false
    }

    public func piece(at p: MatchPoint) -> MatchPiece? {
        index(p).flatMap { grid[$0] }
    }

    public func dust(at p: MatchPoint) -> Int {
        index(p).map { dustLayers[$0] } ?? 0
    }

    public func parcel(at p: MatchPoint) -> Int {
        index(p).map { parcelLayers[$0] } ?? 0
    }

    public func isTangled(_ p: MatchPoint) -> Bool {
        index(p).map { tangled[$0] } ?? false
    }

    public var goalsMet: Bool {
        goals.allSatisfy { remaining($0) == 0 }
    }

    /// What is left of a goal.
    public func remaining(_ goal: MatchGoal) -> Int {
        switch goal {
        case let .collect(kind, count): max(0, count - collected[kind, default: 0])
        case .dust: dustLayers.reduce(0, +)
        case .parcels: parcelLayers.reduce(0, +)
        }
    }

    public var isOver: Bool {
        goalsMet || movesLeft <= 0
    }

    /// Stars at the end: none without the goals, then one more for each score reached.
    public var stars: Int {
        guard goalsMet else { return 0 }
        return 1 + level.stars.prefix(2).filter { score >= $0 }.count
    }

    func movable(_ i: Int) -> Bool {
        grid[i] != nil && !tangled[i] && parcelLayers[i] == 0
    }

    // MARK: Moves

    public static func neighbours(_ a: MatchPoint, _ b: MatchPoint) -> Bool {
        abs(a.x - b.x) + abs(a.y - b.y) == 1
    }

    /// The kind that lines up at `i` (a laser lines up with nothing).
    private func lineKind(_ i: Int) -> MatchKind? {
        guard let piece = grid[i], piece.special != .laser else { return nil }
        return piece.kind
    }

    /// Whether a piece of `kind` at `p` would be in a line of three, the board's other pieces as they are except
    /// `a` and `b` swapped.
    private func lines(_ kind: MatchKind, at p: MatchPoint, swapping a: Int, _ b: Int) -> Bool {
        func kindAt(_ x: Int, _ y: Int) -> MatchKind? {
            guard x >= 0, x < width, y >= 0, y < height else { return nil }
            var i = y * width + x
            if i == a { i = b } else if i == b { i = a }
            return lineKind(i)
        }
        var along = 1, x = p.x - 1
        while kindAt(x, p.y) == kind { along += 1; x -= 1 }
        x = p.x + 1
        while kindAt(x, p.y) == kind { along += 1; x += 1 }
        if along >= 3 { return true }
        var up = 1, y = p.y - 1
        while kindAt(p.x, y) == kind { up += 1; y -= 1 }
        y = p.y + 1
        while kindAt(p.x, y) == kind { up += 1; y += 1 }
        return up >= 3
    }

    /// Whether swapping `a` and `b` is a move (it lines something up, or brings a special into play).
    public func canSwap(_ a: MatchPoint, _ b: MatchPoint) -> Bool {
        guard Self.neighbours(a, b), let ia = index(a), let ib = index(b), movable(ia), movable(ib),
              let pa = grid[ia], let pb = grid[ib] else { return false }
        if pa.special != nil, pb.special != nil { return true }
        if pa.special == .laser || pb.special == .laser { return true }
        if let kb = pb.kind, lines(kb, at: a, swapping: ia, ib) { return true }
        if let ka = pa.kind, lines(ka, at: b, swapping: ia, ib) { return true }
        return false
    }

    /// Every move on the board.
    public func moves() -> [(MatchPoint, MatchPoint)] {
        var out: [(MatchPoint, MatchPoint)] = []
        for y in 0 ..< height {
            for x in 0 ..< width {
                let a = MatchPoint(x, y)
                for b in [MatchPoint(x + 1, y), MatchPoint(x, y + 1)] where canSwap(a, b) {
                    out.append((a, b))
                }
            }
        }
        return out
    }

    /// Plays a swap: the waves it set off (empty when it was not a move, which costs nothing).
    @discardableResult
    public mutating func swap(_ a: MatchPoint, _ b: MatchPoint) -> [MatchWave] {
        guard !isOver, canSwap(a, b), let ia = index(a), let ib = index(b), let pa = grid[ia], let pb = grid[ib] else { return [] }
        movesLeft -= 1
        grid[ia] = pb
        grid[ib] = pa
        var waves: [MatchWave] = []
        var wave = MatchWave()
        if pa.special != nil, pb.special != nil {
            combine(pa, now: ib, pb, now: ia, into: &wave)
        } else if pa.special == .laser {
            laser(at: ib, with: pb, at: ia, into: &wave)
        } else if pb.special == .laser {
            laser(at: ia, with: pa, at: ib, into: &wave)
        } else {
            matchLines(swapped: [ia, ib], into: &wave)
        }
        while true {
            wave.cascade = waves.count + 1
            resolve(&wave)
            waves.append(wave)
            wave = MatchWave()
            matchLines(swapped: [], into: &wave)
            if wave.cleared.isEmpty, wave.fired.isEmpty, wave.made.isEmpty { break }
        }
        if goalsMet {
            score += movesLeft * Tuning.Arcade.Match.pointsPerMoveLeft
        } else if !isOver, moves().isEmpty {
            reshuffle()
        }
        return waves
    }

    // MARK: Lines and blasts

    /// Lines of three or more of a kind on the whole board: each line's cells and whether it runs along a row.
    private func allLines() -> [([Int], Bool)] {
        var found: [([Int], Bool)] = []
        for y in 0 ..< height {
            var x = 0
            while x < width {
                guard let k = lineKind(y * width + x) else { x += 1; continue }
                var end = x + 1
                while end < width, lineKind(y * width + end) == k { end += 1 }
                if end - x >= 3 { found.append(((x ..< end).map { y * width + $0 }, true)) }
                x = end
            }
        }
        for x in 0 ..< width {
            var y = 0
            while y < height {
                guard let k = lineKind(y * width + x) else { y += 1; continue }
                var end = y + 1
                while end < height, lineKind(end * width + x) == k { end += 1 }
                if end - y >= 3 { found.append(((y ..< end).map { $0 * width + x }, false)) }
                y = end
            }
        }
        return found
    }

    /// Clears every line on the board, making specials from long ones and crossings.
    private mutating func matchLines(swapped: [Int], into wave: inout MatchWave) {
        let lines = allLines()
        guard !lines.isEmpty else { return }
        // Lines of the same kind that touch make one shape.
        var group = Array(0 ..< lines.count)
        func root(_ i: Int) -> Int { group[i] == i ? i : root(group[i]) }
        for i in 0 ..< lines.count {
            for j in 0 ..< i where !Set(lines[i].0).isDisjoint(with: lines[j].0) {
                group[root(i)] = root(j)
            }
        }
        var shapes: [Int: [Int]] = [:]
        for i in 0 ..< lines.count { shapes[root(i), default: []].append(i) }
        // The specials to make, decided before anything is cleared.
        var making: [(Int, MatchPiece)] = []
        var clearing: [Int] = []
        for members in shapes.keys.sorted().compactMap({ shapes[$0] }) {
            let cells = Set(members.flatMap { lines[$0].0 })
            let longest = members.map { lines[$0].0.count }.max() ?? 0
            let kind = grid[lines[members[0]].0[0]]?.kind
            var special: MatchSpecial?
            if longest >= 5 {
                special = .laser
            } else if members.count > 1 {
                special = .box
            } else if longest == 4 {
                special = lines[members[0]].1 ? .swipeColumn : .swipeRow
            }
            clearing += cells.sorted()
            if let special {
                // Where the player swapped if it is in the shape, else where its lines cross, else the line's middle.
                let line = lines[members[0]].0
                var spot = swapped.first { cells.contains($0) }
                if spot == nil, members.count > 1 {
                    spot = line.first { c in members.dropFirst().contains { lines[$0].0.contains(c) } }
                }
                let place = spot ?? line[line.count / 2]
                making.append((place, MatchPiece(kind: special == .laser ? nil : kind, special: special)))
            }
        }
        for i in clearing {
            clear(i, into: &wave, blast: false)
        }
        for (place, piece) in making where grid[place] == nil {
            grid[place] = piece
            wave.made[point(place)] = piece
            made[piece.special!, default: 0] += 1
        }
    }

    /// Clears the piece at `i` (setting off its special) with the dust under it; a match also knocks the parcels
    /// beside it, a blast the parcel it reaches.
    private mutating func clear(_ i: Int, into wave: inout MatchWave, blast: Bool) {
        guard cell[i] else { return }
        let p = point(i)
        if parcelLayers[i] > 0 {
            if blast { hitParcel(i, into: &wave) }
            return
        }
        guard let piece = grid[i] else { return }
        grid[i] = nil
        wave.cleared[p] = piece
        if tangled[i] {
            tangled[i] = false
            wave.tanglesCleared.insert(p)
        }
        if let kind = piece.kind, piece.special != .laser {
            collected[kind, default: 0] += 1
        }
        if dustLayers[i] > 0 {
            dustLayers[i] -= 1
            dustCleared += 1
            wave.dustCleared.insert(p)
        }
        if !blast {
            for q in [MatchPoint(p.x + 1, p.y), MatchPoint(p.x - 1, p.y), MatchPoint(p.x, p.y + 1), MatchPoint(p.x, p.y - 1)] {
                if let j = index(q), parcelLayers[j] > 0 { hitParcel(j, into: &wave) }
            }
        }
        if let special = piece.special {
            fire(special, at: i, kind: piece.kind, into: &wave)
        }
    }

    private mutating func hitParcel(_ i: Int, into wave: inout MatchWave) {
        let p = point(i)
        guard parcelLayers[i] > 0, !wave.parcelsHit.contains(p) else { return }
        wave.parcelsHit.insert(p)
        parcelLayers[i] -= 1
    }

    private mutating func fire(_ special: MatchSpecial, at i: Int, kind: MatchKind?, into wave: inout MatchWave) {
        let p = point(i)
        wave.fired[p] = special
        switch special {
        case .swipeRow:
            for x in 0 ..< width { clear(p.y * width + x, into: &wave, blast: true) }
        case .swipeColumn:
            for y in 0 ..< height { clear(y * width + p.x, into: &wave, blast: true) }
        case .box:
            for dy in -1 ... 1 {
                for dx in -1 ... 1 {
                    if let j = index(MatchPoint(p.x + dx, p.y + dy)) { clear(j, into: &wave, blast: true) }
                }
            }
        case .laser:
            // Set off by a blast: the kind the board has most of.
            guard let target = kind ?? mostCommonKind() else { return }
            for j in 0 ..< grid.count where grid[j]?.kind == target && grid[j]?.special != .laser {
                clear(j, into: &wave, blast: true)
            }
        }
    }

    private func mostCommonKind() -> MatchKind? {
        var counts = [Int](repeating: 0, count: MatchKind.allCases.count)
        for piece in grid {
            if let kind = piece?.kind, piece?.special != .laser { counts[kind.rawValue] += 1 }
        }
        guard let most = counts.max(), most > 0, let raw = counts.firstIndex(of: most) else { return nil }
        return MatchKind(rawValue: raw)
    }

    /// The laser swapped with a piece: every piece of that kind goes (a special of that kind turns them all into
    /// its special first, and they all go off).
    private mutating func laser(at laserIndex: Int, with other: MatchPiece, at otherIndex: Int, into wave: inout MatchWave) {
        grid[laserIndex] = nil
        wave.fired[point(laserIndex)] = .laser
        wave.cleared[point(laserIndex)] = MatchPiece(kind: nil, special: .laser)
        guard let kind = other.kind else { return }
        let targets = (0 ..< grid.count).filter { grid[$0]?.kind == kind && grid[$0]?.special != .laser }
        for (n, j) in targets.enumerated() {
            if let special = other.special {
                grid[j] = MatchPiece(kind: kind, special: special == .box ? .box : (n % 2 == 0 ? .swipeRow : .swipeColumn))
            }
        }
        for j in targets {
            clear(j, into: &wave, blast: true)
        }
        _ = otherIndex
    }

    /// Two specials swapped together: a bigger blast where they meet (two lasers clear the board).
    private mutating func combine(_ first: MatchPiece, now ia: Int, _ second: MatchPiece, now ib: Int, into wave: inout MatchWave) {
        if first.special == .laser || second.special == .laser {
            if first.special == .laser, second.special == .laser {
                grid[ia] = nil
                grid[ib] = nil
                wave.fired[point(ia)] = .laser
                wave.fired[point(ib)] = .laser
                for j in 0 ..< grid.count { clear(j, into: &wave, blast: true) }
                return
            }
            if first.special == .laser {
                laser(at: ia, with: second, at: ib, into: &wave)
            } else {
                laser(at: ib, with: first, at: ia, into: &wave)
            }
            return
        }
        let centre = point(ia)
        grid[ia] = nil
        grid[ib] = nil
        wave.cleared[point(ia)] = first
        wave.cleared[point(ib)] = second
        wave.fired[point(ia)] = first.special
        wave.fired[point(ib)] = second.special
        let boxes = [first.special, second.special].filter { $0 == .box }.count
        let reach = boxes == 0 ? 0 : 1
        for dy in -reach ... reach where centre.y + dy >= 0 && centre.y + dy < height {
            for x in 0 ..< width { clear((centre.y + dy) * width + x, into: &wave, blast: true) }
        }
        for dx in -reach ... reach where centre.x + dx >= 0 && centre.x + dx < width {
            for y in 0 ..< height { clear(y * width + centre.x + dx, into: &wave, blast: true) }
        }
        if boxes == 2 {
            for dy in -2 ... 2 {
                for dx in -2 ... 2 {
                    if let j = index(MatchPoint(centre.x + dx, centre.y + dy)) { clear(j, into: &wave, blast: true) }
                }
            }
        }
    }

    // MARK: Falling and filling

    /// Scores the wave, then the pieces fall and new ones drop in.
    private mutating func resolve(_ wave: inout MatchWave) {
        let pieces = wave.cleared.count + Tuning.Arcade.Match.specialWorth * (wave.fired.count + wave.made.count)
        wave.points = Tuning.Arcade.Match.pointsPerPiece * pieces * min(wave.cascade, Tuning.Arcade.Match.cascadeCap)
        score += wave.points
        settle(into: &wave)
    }

    private func isEmpty(_ i: Int) -> Bool {
        cell[i] && grid[i] == nil && parcelLayers[i] == 0
    }

    /// Straight down where it can; new pieces at the top of each column and under anything that does not fall.
    private mutating func settle(into wave: inout MatchWave) {
        var origins: [Int: MatchPoint] = [:]
        var fresh: [Int: MatchPiece] = [:]
        func move(_ from: Int, to: Int) {
            grid[to] = grid[from]
            grid[from] = nil
            if let piece = fresh.removeValue(forKey: from) {
                fresh[to] = piece
            } else {
                origins[to] = origins.removeValue(forKey: from) ?? point(from)
            }
        }
        var moved = true
        while moved {
            moved = false
            for y in stride(from: height - 1, through: 0, by: -1) {
                for x in 0 ..< width {
                    let i = y * width + x
                    guard isEmpty(i) else { continue }
                    if y > 0, movable(i - width) {
                        move(i - width, to: i)
                        moved = true
                    } else if tops.contains(i) || !cell[i - width] || parcelLayers[i - width] > 0 || tangled[i - width] {
                        // The top of a column, or under something that does not fall (a gap, a parcel, a tangle): a
                        // new piece drops in here, so no cell is ever left empty.
                        let piece = MatchPiece(kind: kinds[seed.below(kinds.count)])
                        grid[i] = piece
                        fresh[i] = piece
                        moved = true
                    }
                }
            }
        }
        for (i, piece) in fresh {
            wave.spawned[point(i)] = piece
        }
        wave.falls = origins.map { (from: $0.value, to: point($0.key)) }.sorted { ($0.to.y, $0.to.x) > ($1.to.y, $1.to.x) }
    }

    /// A first board with nothing lined up and at least one move.
    private mutating func fillWithoutMatches() {
        for _ in 0 ..< 200 {
            for i in 0 ..< grid.count {
                grid[i] = nil
            }
            for y in 0 ..< height {
                for x in 0 ..< width {
                    let i = y * width + x
                    guard cell[i], parcelLayers[i] == 0 else { continue }
                    var options = kinds
                    if x >= 2, let k = grid[i - 1]?.kind, grid[i - 2]?.kind == k { options.removeAll { $0 == k } }
                    if y >= 2, let k = grid[i - width]?.kind, grid[i - 2 * width]?.kind == k { options.removeAll { $0 == k } }
                    grid[i] = MatchPiece(kind: options[seed.below(options.count)])
                }
            }
            if !moves().isEmpty { return }
        }
    }

    /// No move left: the same pieces shuffled into a board with nothing lined up and a move.
    private mutating func reshuffle() {
        let spots = (0 ..< grid.count).filter { movable($0) }
        let bag = spots.compactMap { grid[$0] }
        shuffles += 1
        for _ in 0 ..< 300 {
            let shuffled = seed.shuffled(bag)
            for (i, piece) in zip(spots, shuffled) { grid[i] = piece }
            if allLines().isEmpty, !moves().isEmpty { return }
        }
        for i in spots { grid[i] = MatchPiece(kind: kinds[seed.below(kinds.count)]) }
        if !allLines().isEmpty || moves().isEmpty { fillWithoutMatches() }
    }
}

/// A plain player for checking levels: it plays the move that does the most for the goals now (a special counts
/// for more), ties broken by the seed. A person plays better, so a level it can win is a level that can be won.
public enum MatchBot {
    public static func play(_ game: inout MatchGame, seed: inout DaySeed) {
        while !game.isOver, let move = choose(game, seed: &seed) {
            game.swap(move.0, move.1)
        }
    }

    /// The move it would play now (nil when there is none).
    public static func choose(_ game: MatchGame, seed: inout DaySeed) -> (MatchPoint, MatchPoint)? {
        let moves = game.moves()
        guard !moves.isEmpty else { return nil }
        var best = Int.min, choices: [(MatchPoint, MatchPoint)] = []
        for move in moves {
            var trial = game
            let waves = trial.swap(move.0, move.1)
            let value = worth(waves, before: game, after: trial)
            if value > best {
                best = value
                choices = [move]
            } else if value == best {
                choices.append(move)
            }
        }
        return choices[seed.below(choices.count)]
    }

    static func worth(_ waves: [MatchWave], before: MatchGame, after: MatchGame) -> Int {
        var value = 0
        for goal in before.goals {
            value += 20 * (before.remaining(goal) - after.remaining(goal))
        }
        value += waves.reduce(0) { $0 + $1.cleared.count + 8 * $1.made.count }
        if after.goalsMet { value += 100_000 }
        return value
    }
}
