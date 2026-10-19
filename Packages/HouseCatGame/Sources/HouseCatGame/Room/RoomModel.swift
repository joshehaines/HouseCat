import Foundation
import HouseCatCore

/// What a room scene draws: its surfaces, window, door, light and furniture.
/// Built by the app from the save; scenes never decide any of it.
public struct RoomModel: Decodable, Sendable {
    /// A window or door set into a wall, in cells.
    public struct Opening: Decodable, Sendable {
        public var id: String
        /// "R" (right wall) or "L" (left wall).
        public var wall: String
        public var start: Double
        public var along: Double
        public var height: Double
        public var up: Double?
    }

    /// A piece of furniture at a floor cell, facing R or L; wall items hang `up` cells high.
    public struct Placement: Decodable, Sendable {
        public var id: String
        public var u: Double
        public var v: Double
        public var facing: String
        public var up: Double?
        /// The save's placement this is (PlacedItem), so decorating can move it; nil in hand-made layouts.
        public var placementID: UUID?

        public init(id: String, u: Double, v: Double, facing: String, up: Double? = nil, placementID: UUID? = nil) {
            self.id = id
            self.u = u
            self.v = v
            self.facing = facing
            self.up = up
            self.placementID = placementID
        }
    }

    /// Wallpaper and floor surface ids (Content/catalogue.json surfaces).
    public var wall: String
    public var floor: String
    public var window: Opening?
    public var door: Opening?
    /// Painted scale of furniture by the reference room it was painted in.
    public var refScale: [String: Double]
    /// Per-item scale tweaks, set by eye.
    public var scale: [String: Double]
    /// The cat's standing height in room units.
    public var catHeight: Double
    /// Where the cat starts, in cells.
    public var cat: [Double]
    public var items: [Placement]
    /// Floor spots for activities with no furniture (nearPlayer, sunbeam, sulk, middle), in cells.
    public var spots: [String: [Double]] = [:]
    /// The light map: morning, midday, evening, overcast or night (set from the sky, not the layout).
    public var light = "midday"
    /// The sky outside the window, and the terrain seen through it.
    public var sky = SkyPhase.day
    public var terrain = "world/terrain/terr_city_autumn.png"
    /// The weather and season outside, for the particles in the window.
    public var weather = Weather.sun
    public var season = NatureSeason.autumn
    /// How much smaller than painted the furniture is drawn (Tuning.Room.furnitureScale).
    public var furnitureScale = Tuning.Room.furnitureScale

    private enum CodingKeys: String, CodingKey {
        case wall, floor, window, door, refScale, scale, catHeight, cat, items, spots
    }
}
