import Foundation
import HouseCatCore

/// The whole home around the room you are in (SPEC "Rooms", "Home and furniture"): every room laid
/// out on one isometric grid, upper storeys lifted clear above the ground floor, the rooms not yet
/// opened shown as lit silhouettes with what they cost. Built by the app from the home's plan
/// (assets/rooms/houses.json) and the save; the scene decides nothing.
public struct HouseModel: Sendable {
    public struct Room: Sendable {
        public var id: RoomID
        public var storey: Int
        /// The room's back corner on the house grid, in cells.
        public var u: Double
        public var v: Double
        /// A garden, balcony or terrace: low walls, outdoor light.
        public var outdoor: Bool
        public var model: RoomModel
        /// What opening it takes, when it is closed: the house it comes with and its price ("Cottage", then "1,500 Beans" under it).
        public var lockLabel: String?

        public init(id: RoomID, storey: Int, u: Double, v: Double, outdoor: Bool, model: RoomModel, lockLabel: String?) {
            self.id = id
            self.storey = storey
            self.u = u
            self.v = v
            self.outdoor = outdoor
            self.model = model
            self.lockLabel = lockLabel
        }
    }

    public var rooms: [Room]
    /// The room you are in: the view settles on it and shows its storey (the cat has its own, `RoomScene.catRoom`).
    public var active: RoomID
    public var sky: SkyPhase
    /// The tile the house stands on (a surface sprite path), filling the view around it.
    public var ground: String?
    /// The staircase up, if the home has an upper storey.
    public var stairs: HousePlans.Stairs?
    /// The trees, bushes and stones of the home's place round the plot (OutdoorRules).
    public var scenery: [OutdoorPiece]
    /// A city's street behind the house, with its traffic (OutdoorRules.street).
    public var street: OutdoorStreet?
    /// The neighbourhood's roads round the block (OutdoorRules.roads).
    public var roads: [OutdoorRoad] = []

    public init(
        rooms: [Room],
        active: RoomID,
        sky: SkyPhase,
        ground: String? = nil,
        stairs: HousePlans.Stairs? = nil,
        scenery: [OutdoorPiece] = [],
        street: OutdoorStreet? = nil
    ) {
        self.street = street
        self.rooms = rooms
        self.active = active
        self.sky = sky
        self.ground = ground
        self.stairs = stairs
        self.scenery = scenery
    }

    /// The storey the active room is on.
    public var storey: Int {
        rooms.first { $0.id == active }?.storey ?? 0
    }

    /// One room on its own, every wall standing (tests and previews).
    public static func single(_ model: RoomModel, id: RoomID = .living) -> HouseModel {
        HouseModel(rooms: [Room(id: id, storey: 0, u: 0, v: 0, outdoor: false, model: model, lockLabel: nil)], active: id, sky: model.sky)
    }

    /// The walls a room shows: full on the house's back edge, a stub where another room of the same
    /// storey stands behind it (the view looks over the partition), never on the camera side.
    func walls(of room: Room) -> (left: RoomNode.Wall, right: RoomNode.Wall) {
        let cells = Double(Tuning.Room.gridWidth)
        let behindLeft = rooms.contains { $0.storey == room.storey && $0.u + cells == room.u && $0.v == room.v }
        let behindRight = rooms.contains { $0.storey == room.storey && $0.v + cells == room.v && $0.u == room.u }
        return (behindLeft ? .stub : .full, behindRight ? .stub : .full)
    }

    public func room(_ id: RoomID) -> Room? {
        rooms.first { $0.id == id }
    }

    /// A doorway between two rooms side by side on a storey: in the partition, halfway along it.
    public struct Link: Sendable {
        public var from: RoomID
        public var to: RoomID
        /// The doorway as a floor cell of each room (on the wall line they share).
        public var exit: CGPoint
        public var entry: CGPoint
    }

    /// The doorways out of a room to the rooms beside it on its storey.
    public func links(from id: RoomID) -> [Link] {
        guard let room = room(id) else { return [] }
        let cells = Double(Tuning.Room.gridWidth), along = Tuning.House.doorwayAlong
        var links: [Link] = []
        for other in rooms where other.storey == room.storey && other.id != id {
            if other.v == room.v, other.u == room.u + cells {
                links.append(Link(from: id, to: other.id, exit: CGPoint(x: cells, y: along), entry: CGPoint(x: 0, y: along)))
            } else if other.v == room.v, other.u + cells == room.u {
                links.append(Link(from: id, to: other.id, exit: CGPoint(x: 0, y: along), entry: CGPoint(x: cells, y: along)))
            } else if other.u == room.u, other.v == room.v + cells {
                links.append(Link(from: id, to: other.id, exit: CGPoint(x: along, y: cells), entry: CGPoint(x: along, y: 0)))
            } else if other.u == room.u, other.v + cells == room.v {
                links.append(Link(from: id, to: other.id, exit: CGPoint(x: along, y: 0), entry: CGPoint(x: along, y: cells)))
            }
        }
        return links
    }

    /// The doorways cut into a room's partitions, by wall ("L", "R"), as the cell along the wall at their middle.
    func doorways(of room: Room) -> [String: CGFloat] {
        var doors: [String: CGFloat] = [:]
        for link in links(from: room.id) {
            if link.exit.x == 0 {
                doors["L"] = link.exit.y
            } else if link.exit.y == 0 {
                doors["R"] = link.exit.x
            }
        }
        return doors
    }

    /// The way through the open rooms of one storey, doorway by doorway (nil if there is none).
    public func route(from start: RoomID, to end: RoomID) -> [Link]? {
        guard start != end else { return [] }
        var previous: [RoomID: Link] = [:]
        var queue = [start], seen: Set<RoomID> = [start]
        while !queue.isEmpty {
            let id = queue.removeFirst()
            for link in links(from: id) where !seen.contains(link.to) && room(link.to)?.lockLabel == nil {
                seen.insert(link.to)
                previous[link.to] = link
                if link.to == end {
                    var path: [Link] = []
                    var at = end
                    while let step = previous[at] {
                        path.insert(step, at: 0)
                        at = step.from
                    }
                    return path
                }
                queue.append(link.to)
            }
        }
        return nil
    }
}

/// Where each home's rooms sit (assets/rooms/houses.json).
public struct HousePlans: Decodable, Sendable {
    public struct Placement: Decodable, Sendable {
        public var room: RoomID
        public var storey: Int
        public var at: [Double]
        public var outdoor: Bool?
    }

    /// The staircase up: the room it stands in, its back cell and the wall it runs along.
    public struct Stairs: Decodable, Sendable {
        public var room: RoomID
        public var at: [Double]
        public var facing: String
    }

    public struct Plan: Decodable, Sendable {
        public var rooms: [Placement]
        public var stairs: Stairs?
    }

    /// A room type's window, and the furniture shown under its veil while it is closed.
    public struct RoomStyle: Decodable, Sendable {
        public var window: RoomModel.Opening?
        public var preview: [RoomModel.Placement]?
    }

    public var houses: [String: Plan]
    /// The surface each biome's houses stand on.
    public var grounds: [String: String]
    public var roomStyles: [String: RoomStyle]
}
