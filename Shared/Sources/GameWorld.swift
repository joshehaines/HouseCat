import Foundation
import HouseCatCore
import HouseCatGame
import SpriteKit
#if canImport(UIKit)
    import UIKit
#endif

/// Loads the bundled art and content and builds the game's scenes.
@MainActor
enum GameWorld {
    static let content: ContentBundle? = Bundle.main.url(forResource: "Content", withExtension: nil)
        .flatMap { try? ContentBundle.load(from: $0) }
    static let art: ArtLibrary? = try? ArtLibrary(bundle: .main)

    /// The player's home until onboarding records one: the London terrace in the city, London time, seasons on Auto.
    enum DemoHome {
        static let house = HouseStyle.londonTerrace
        static let biome = Biome.city
        static let timeZone = TimeZone(identifier: "Europe/London") ?? .current
        static let southernHemisphere = false
        static let season = SeasonSetting.auto
    }

    /// The door points of the painted exteriors (assets/world/scenes/scenes.json).
    private struct SceneIndex: Decodable {
        var defaultDoor: [Double]
        var doors: [String: [Double]]
    }

    /// The home's exterior at this moment: its painting for the season, its sky for the local time.
    static func exteriorScene(size: CGSize, at date: Date) -> ExteriorScene? {
        guard let art, let index = try? art.data("world/scenes/scenes.json", as: SceneIndex.self) else { return nil }
        let wanted = DemoHome.season.season(at: date, timeZone: DemoHome.timeZone, southernHemisphere: DemoHome.southernHemisphere)
        // Until every season is painted for every home, fall back to one that is.
        let seasons = [wanted] + NatureSeason.allCases.filter { $0 != wanted }
        let base = "\(DemoHome.house.rawValue)_\(DemoHome.biome.rawValue)"
        guard let season = seasons.first(where: { art.has("world/scenes/\(base)_\($0.rawValue).jpg") }) else { return nil }
        let name = "\(base)_\(season.rawValue)"
        let door = index.doors[name] ?? index.defaultDoor
        let model = ExteriorScene.Model(scene: "world/scenes/\(name)", sky: skyPhase(at: date), door: CGPoint(x: door[0], y: door[1]))
        return ExteriorScene(size: size, art: art, model: model)
    }

    /// The sky over the home at its local time.
    static func skyPhase(at date: Date) -> SkyPhase {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = DemoHome.timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return SkyPhase.at(localMinutes: (parts.hour ?? 12) * 60 + (parts.minute ?? 0))
    }

    /// The home as the save has it: every room of the house's plan (assets/rooms/houses.json) around the
    /// living room, each with its wallpaper, floor and placed furniture, the closed ones veiled with their price.
    static func house(at date: Date, state: HouseholdState) -> HouseModel? {
        guard let art, let content, let layout = try? art.data("rooms/layout_living_demo.json", as: RoomModel.self),
              let plans = try? art.data("rooms/houses.json", as: HousePlans.self),
              let plan = plans.houses[DemoHome.house.rawValue]
        else { return nil }
        let sky = skyPhase(at: date)
        let catalogue = content.catalogue
        let chosen = Dictionary(uniqueKeysWithValues: catalogue.surfaces.map { ($0.id, $0) })
        let rooms = plan.rooms.map { spot -> HouseModel.Room in
            var model = layout
            model.sky = sky
            model.light = sky.lightMap(weather: .sun)
            // The save keeps one surface per room (the last changed); the other falls back to the room's first free one.
            let picked = state.surfaces[spot.room].flatMap { chosen[$0] }
            model.wall = picked?.kind == .wall ? picked?.id ?? "" : catalogue.defaultSurface(.wall, in: spot.room)?.id ?? layout.wall
            model.floor = picked?.kind == .floor ? picked?.id ?? "" : catalogue.defaultSurface(.floor, in: spot.room)?.id ?? layout.floor
            if spot.room == .living {
                model.wall = picked?.kind == .wall ? model.wall : layout.wall
                model.floor = picked?.kind == .floor ? model.floor : layout.floor
            } else {
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
        let ground = plans.grounds[DemoHome.biome.rawValue].flatMap { chosen[$0]?.sprite }
        return HouseModel(rooms: rooms, active: .living, sky: sky, ground: ground, stairs: plan.stairs)
    }

    /// The house with the cat arriving in the living room to do what the save says, or a blank scene if the art is missing.
    static func roomScene(size: CGSize, at date: Date = Date(), state: HouseholdState, arrival: GameSession.Arrival?) -> SKScene {
        guard let art, let content, let house = house(at: date, state: state), let rig = try? art.data("cat/rig.json", as: PuppetRig.self)
        else {
            return SKScene(size: size)
        }
        let scene = RoomScene(size: size, art: art, content: content, house: house)
        let start = scene.model.cat
        scene.addCat(rig: rig, at: CGFloat(start[0]), CGFloat(start[1]), pose: .loafThreeQuarterFront)
        if let arrival {
            scene.playArrival(then: arrival.choice, onRub: purr, onDone: {})
        }
        return scene
    }

    /// The rub along the bottom edge: a soft haptic (the purr sound joins with the audio step).
    static func purr() {
        #if canImport(UIKit) && !os(watchOS)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
    }
}
