import Foundation

/// The garden round the house, laid out as a garden is rather than scattered (Josh, 19 Oct: the items were placed
/// completely at random). Behind the house, along both back sides, two staggered lines of the place's trees, with a
/// shed or a washing line among them; along both front sides a border of its low plants (a hedge, dune grass,
/// planters, agave) with a gap for a gate, stones at the corners; and in the front garden (the empty square of the
/// plot the rooms leave, or the square off the house's front corner) its pieces set out: a pond in the middle, a bench
/// beside it, the bird table, pots by the walls. A city's street side has street trees and lamps along the pavement
/// instead of a tree line. Only where the pieces stand varies a little from home to home (the household's seed).
enum OutdoorPlan {
    /// What a piece is for in the plan (outdoors.json `role`).
    enum Role: String {
        case tree, hedge, rock, feature, seat, birdtable, pots, shed, line, lamp
    }

    struct Spot {
        var role: Role
        var u: Double
        var v: Double
        /// Which of the role's pieces, when it has several (alternating species along a line).
        var pick: Int
    }

    /// The plan's spots round a plot of rooms (each a square of `cells` from its corner).
    static func spots(
        rooms: [(u: Double, v: Double)],
        street: OutdoorStreet?,
        has: @escaping (Role) -> Bool,
        unit: @escaping () -> Double
    ) -> [Spot] {
        var planner = Planner(rooms: rooms, street: street, has: has, unit: unit)
        planner.behind()
        planner.front()
        planner.gardens()
        return planner.spots
    }

    /// The plot's bounds and the spots laid out so far.
    private struct Planner {
        let rooms: [(u: Double, v: Double)]
        let street: OutdoorStreet?
        let has: (Role) -> Bool
        let unit: () -> Double
        let t = Tuning.Outdoors.self
        let cells = Double(Tuning.Room.gridWidth)
        let minU: Double, minV: Double, maxU: Double, maxV: Double
        var spots: [Spot] = []

        init(rooms: [(u: Double, v: Double)], street: OutdoorStreet?, has: @escaping (Role) -> Bool, unit: @escaping () -> Double) {
            self.rooms = rooms
            self.street = street
            self.has = has
            self.unit = unit
            minU = rooms.map(\.u).min() ?? 0
            minV = rooms.map(\.v).min() ?? 0
            maxU = (rooms.map(\.u).max() ?? 0) + cells
            maxV = (rooms.map(\.v).max() ?? 0) + cells
        }

        func jitter() -> Double {
            (unit() - 0.5) * 2 * t.planJitter
        }

        mutating func add(_ role: Role, _ u: Double, _ v: Double) {
            let onRoad = street.map { abs(v - $0.v) < $0.width / 2 + 2.3 } ?? false
            guard has(role), !onRoad else { return }
            spots.append(Spot(role: role, u: u, v: v, pick: spots.count))
        }

        mutating func behind() {
            // Behind: two staggered tree lines along each back side; a shed in the back corner, a washing line along the
            // left side's middle. The city's back-right side is the street: street trees and lamps along its pavement.
            for (row, distance) in t.treeRows.enumerated() {
                let offset = row.isMultiple(of: 2) ? 0 : t.treeSpacing / 2
                if street == nil || row > 0 {
                    var u = minU - distance + offset
                    while u <= maxU + t.treeRows[0] {
                        if street == nil {
                            add(.tree, u + jitter(), minV - distance + jitter())
                        }
                        u += t.treeSpacing
                    }
                }
                var v = minV - distance + offset
                while v <= maxV + t.treeRows[0] {
                    add(.tree, minU - distance + jitter(), v + jitter())
                    v += t.treeSpacing
                }
            }
            if let street {
                var u = street.from + 3
                var index = 0
                let pavement = street.v + street.width / 2 + 1.2
                while u < street.to - 3 {
                    spots.append(Spot(role: index.isMultiple(of: 3) ? .lamp : .tree, u: u + jitter(), v: pavement, pick: index))
                    u += t.treeSpacing * 1.4
                    index += 1
                }
            }
            add(.shed, minU - t.treeRows[0] + 0.4, minV - t.treeRows[0] + 0.4)
            if has(.line) {
                spots
                    .removeAll {
                        $0.role == .tree && abs($0.u - (minU - t.treeRows[0])) < 1 && abs($0.v - (minV + maxV) / 2) < t.treeSpacing / 2
                    }
                add(.line, minU - t.treeRows[0], (minV + maxV) / 2)
            }
        }

        mutating func front() {
            // In front: a border along both front sides, a gap for the gate in each, stones at its ends and corner. A place
            // with no low plants (the woods, the hills, the snow) edges it with stones, further apart.
            let edge = t.borderDistance
            let edging: Role = has(.hedge) ? .hedge : .rock
            let spacing = edging == .hedge ? t.borderSpacing : t.borderSpacing * 2.4
            func border(along length: ClosedRange<Double>, at place: (Double) -> (u: Double, v: Double)) {
                let gate = (length.lowerBound + length.upperBound) / 2
                var s = length.lowerBound
                while s <= length.upperBound {
                    if abs(s - gate) > t.gateWidth / 2 {
                        let p = place(s)
                        add(edging, p.u + jitter() * 0.3, p.v + jitter() * 0.3)
                    }
                    s += spacing
                }
            }
            border(along: minV ... maxV + edge) { (maxU + edge, $0) }
            border(along: minU ... maxU + edge - spacing) { ($0, maxV + edge) }
            add(.rock, maxU + edge + 0.6, maxV + edge + 0.6)
            add(.rock, maxU + edge + 0.4, minV - 1.2)
            add(.rock, minU - 1.2, maxV + edge + 0.4)
        }

        mutating func gardens() {
            let edge = t.borderDistance
            // The front garden: the empty squares the rooms leave in the plot, front-most first; else the square off the
            // front corner. Its pieces set out in the front-most, a few low plants in any other.
            let taken = Set(rooms.map { "\(Int($0.u)),\(Int($0.v))" })
            var gardens: [(u: Double, v: Double)] = []
            for u in stride(from: minU, to: maxU, by: cells) {
                for v in stride(from: minV, to: maxV, by: cells) where !taken.contains("\(Int(u)),\(Int(v))") {
                    gardens.append((u, v))
                }
            }
            gardens.sort { $0.u + $0.v > $1.u + $1.v }
            let outside = gardens.isEmpty
            if outside {
                gardens = [(maxU + edge + 1.5, maxV + edge + 1.5)]
            }
            for (index, square) in gardens.enumerated() {
                func at(_ u: Double, _ v: Double, _ role: Role) {
                    add(role, square.u + u + jitter() * 0.4, square.v + v + jitter() * 0.4)
                }
                if index == 0 {
                    at(5.5, 5.5, .feature)
                    at(2.6, 6.2, .seat)
                    at(6.4, 2.6, .birdtable)
                    if !outside {
                        at(2.2, 2.2, .pots)
                    }
                    at(8.4, 2.4, .pots)
                    at(2.4, 8.4, .hedge)
                    at(8.0, 8.0, .rock)
                } else {
                    at(5, 5, .hedge)
                    at(3, 7, .rock)
                }
            }
        }
    }
}
