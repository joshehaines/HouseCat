import Foundation
import HouseCatCore

/// Builds the house the scene shows from the save and the home right now (SPEC "Sky, season, weather and
/// windows: one layered scene"): every room of the home's plan with its wallpaper, floor and furniture, the
/// closed ones bare with their price, and through every window the terrain of the place you pinned in its
/// season, under the sky at the home's local time.
public enum HouseBuilder {
    /// The terrain seen through the windows (assets/world/terrain).
    public static func terrain(_ biome: Biome, _ season: NatureSeason) -> String {
        "world/terrain/terr_\(biome.rawValue)_\(season.rawValue).png"
    }

    /// The ground around the house (assets/world/ground): the biome's own, under snow when it is snowing
    /// (or deep winter where winters are white), a leaf-strewn lawn in a country autumn.
    public static func ground(_ biome: Biome, season: NatureSeason, weather: Weather) -> String {
        let name: String = if isSnowy(biome, season: season, weather: weather) {
            "snow"
        } else if season == .autumn, biome == .countryside {
            "autumn"
        } else {
            biome.rawValue
        }
        return "world/ground/ground_\(name).png"
    }

    /// Whether snow lies on the ground: always in the snow biome, while it snows (never in the desert or the
    /// tropics), and all winter where winters are white.
    public static func isSnowy(_ biome: Biome, season: NatureSeason, weather: Weather) -> Bool {
        biome == .snow
            || weather == .snow && ![.desert, .tropical].contains(biome)
            || season == .winter && Tuning.Weather.whiteWinters.contains(biome.rawValue)
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
        now: HomeNow,
        outdoors: OutdoorsFile? = nil
    ) -> HouseModel? {
        guard let plan = plans.houses[style.rawValue] else { return nil }
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
                // A closed room is bare until it is opened (Josh, 19 Oct: blank, nothing in it): no furniture, and
                // indoors plain plaster and boards, so it reads as a room still to do up.
                model.items = []
                if spot.outdoor != true {
                    model.wall = Tuning.House.bareWall
                    model.floor = Tuning.House.bareFloor
                }
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
        // The scenery stands round the ground floor's rooms, the plot the house is built on.
        let plot = plan.rooms.filter { $0.storey == 0 }.map { (u: $0.at[0], v: $0.at[1]) }
        let scenery = outdoors.map {
            OutdoorRules.layout(
                biome: now.biome,
                rooms: plot,
                seed: state.seed,
                season: now.season,
                snowy: isSnowy(now.biome, season: now.season, weather: now.weather),
                file: $0
            )
        } ?? []
        return HouseModel(
            rooms: rooms,
            active: .living,
            sky: now.sky,
            ground: ground(now.biome, season: now.season, weather: now.weather),
            stairs: plan.stairs,
            scenery: scenery
        )
    }
}
