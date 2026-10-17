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
        /// What opening it takes, when it is closed ("Level 6 · 800 Beans").
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
    /// The room the view settles on and the cat is in; the view shows its storey.
    public var active: RoomID
    public var sky: SkyPhase
    /// The tile the house stands on (a surface sprite path), filling the view around it.
    public var ground: String?
    /// The staircase up, if the home has an upper storey.
    public var stairs: HousePlans.Stairs?

    public init(rooms: [Room], active: RoomID, sky: SkyPhase, ground: String? = nil, stairs: HousePlans.Stairs? = nil) {
        self.rooms = rooms
        self.active = active
        self.sky = sky
        self.ground = ground
        self.stairs = stairs
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

    public var houses: [String: Plan]
    /// The surface each biome's houses stand on.
    public var grounds: [String: String]
}
