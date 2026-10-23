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

    /// A window or door laid out for a standard room, the same way along a wall of another length and inside it.
    static func fit(_ opening: RoomModel.Opening, _ size: RoomSize) -> RoomModel.Opening {
        var fitted = opening
        let length = Double(opening.wall == "L" ? size.v : size.u)
        let standard = Double(opening.wall == "L" ? Tuning.Room.gridDepth : Tuning.Room.gridWidth)
        fitted.start = max(0.3, min(opening.start * length / standard, length - opening.along - 0.3))
        return fitted
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
        // The house is the rooms it has (Josh, 23 Oct: "the boat cannot be a big 3 room space"): those the ladder has
        // opened so far, laid out as that home is; the next house's rooms come with the next house (Homes).
        // Only rooms this home comes with by its own rung, so its outline is the one its town is painted round.
        let homeRung = HouseLadder.rungs.first { $0.style == style }?.number ?? HouseLadder.top
        let owned = plan.rooms.filter {
            ($0.room == .living || state.openedRooms.contains($0.room)) && HouseLadder.rung(opening: $0.room) <= homeRung
        }
        let size = Tuning.Room.sizes[style] ?? .standard
        let rooms = owned.map { spot -> HouseModel.Room in
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
            model.window = model.window.map { fit($0, size) }
            model.door = model.door.map { fit($0, size) }
            // Only what is in the room (a save's pieces are moved in when the household moves house).
            model.items = state.placed.filter { $0.room == spot.room && size.contains($0.x, $0.y) }.map {
                RoomModel.Placement(
                    id: $0.itemID,
                    u: Double($0.x),
                    v: Double($0.y),
                    facing: $0.facing.rawValue,
                    placementID: $0.placementID
                )
            }
            return HouseModel.Room(
                id: spot.room,
                storey: spot.storey,
                u: spot.at[0],
                v: spot.at[1],
                outdoor: spot.outdoor ?? false,
                model: model,
                lockLabel: nil
            )
        }
        // The scenery stands round the ground floor's rooms, the plot the house is built on.
        let plot = owned.filter { $0.storey == 0 }.map { (u: $0.at[0], v: $0.at[1]) }
        let backdrop = now.place.setting.flatMap { outdoors?.backdrops?[$0] }
        let scenery = backdrop != nil ? [] : outdoors.map {
            OutdoorRules.layout(
                biome: now.biome,
                setting: now.place.setting,
                rooms: plot,
                seed: state.seed,
                season: now.season,
                snowy: isSnowy(now.biome, season: now.season, weather: now.weather),
                file: $0
            )
        } ?? []
        let street = backdrop != nil ? nil : outdoors.flatMap { OutdoorRules.street(biome: now.biome, setting: now.place.setting, rooms: plot, file: $0) }
        var model = HouseModel(
            rooms: rooms,
            active: .living,
            sky: now.sky,
            ground: ground(now.biome, season: now.season, weather: now.weather),
            // Up only when a room upstairs is the household's.
            stairs: owned.contains { $0.storey > 0 } ? plan.stairs : nil,
            scenery: scenery,
            street: street
        )
        model.roomSize = size
        model.roads = backdrop != nil ? [] : outdoors.map { OutdoorRules.roads(rooms: plot, street: street, setting: now.place.setting, file: $0) } ?? []
        model.backdrop = backdrop
        return model
    }
}
