import Foundation
import HouseCatCore

/// Builds the house the scene shows from the save and the home right now (SPEC "Sky, season, weather and
/// windows: one layered scene"): every room of the home's plan with its wallpaper, floor and furniture, the
/// closed ones veiled with their price, and through every window the terrain of the place you pinned in its
/// season, under the sky at the home's local time.
public enum HouseBuilder {
    /// The terrain seen through the windows (assets/world/terrain).
    public static func terrain(_ biome: Biome, _ season: NatureSeason) -> String {
        "world/terrain/terr_\(biome.rawValue)_\(season.rawValue).png"
    }

    /// A home's painted exterior in a biome and season (assets/world/scenes, without the extension).
    public static func scene(_ house: HouseStyle, _ biome: Biome, _ season: NatureSeason) -> String {
        "world/scenes/\(house.rawValue)_\(biome.rawValue)_\(season.rawValue)"
    }

    public static func house(
        style: HouseStyle,
        plans: HousePlans,
        layout: RoomModel,
        state: HouseholdState,
        catalogue: CatalogueFile,
        now: HomeNow
    ) -> HouseModel? {
        guard let plan = plans.houses[style.rawValue] else { return nil }
        let surfaces = Dictionary(uniqueKeysWithValues: catalogue.surfaces.map { ($0.id, $0) })
        let rooms = plan.rooms.map { spot -> HouseModel.Room in
            var model = layout
            model.sky = now.sky
            model.light = now.sky.lightMap(weather: now.weather)
            model.terrain = terrain(now.biome, now.season)
            model.weather = now.weather
            model.season = now.season
            model.wall = state.surface(.wall, in: spot.room, catalogue: catalogue) ?? layout.wall
            model.floor = state.surface(.floor, in: spot.room, catalogue: catalogue) ?? layout.floor
            if spot.room != .living {
                // Each room type's own window; doors between rooms are open partitions.
                model.window = plans.roomStyles[spot.room.rawValue]?.window
                model.door = nil
            }
            model.items = state.placed.filter { $0.room == spot.room }.map {
                RoomModel.Placement(
                    id: $0.itemID,
                    u: Double($0.x),
                    v: Double($0.y),
                    facing: $0.facing.rawValue,
                    placementID: $0.placementID
                )
            }
            let open = state.openedRooms.contains(spot.room)
            if !open {
                // A closed room shows what it could be, under its veil.
                model.items = plans.roomStyles[spot.room.rawValue]?.preview ?? []
            }
            let label = "Level \(spot.room.requiredLevel) · \(RoomRules.cost(of: spot.room, clubActive: false)) Beans"
            return HouseModel.Room(
                id: spot.room,
                storey: spot.storey,
                u: spot.at[0],
                v: spot.at[1],
                outdoor: spot.outdoor ?? false,
                model: model,
                lockLabel: open ? nil : label
            )
        }
        let ground = plans.grounds[now.biome.rawValue].flatMap { surfaces[$0]?.sprite }
        return HouseModel(rooms: rooms, active: .living, sky: now.sky, ground: ground, stairs: plan.stairs)
    }
}
