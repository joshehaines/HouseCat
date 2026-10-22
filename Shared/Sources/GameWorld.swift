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
    /// The cat builder's sprites, tinted into each cat's look.
    static let catArt: CatArt? = art.flatMap { try? CatArt(art: $0) }
    static let rig: PuppetRig? = try? art?.data("cat/rig.json", as: PuppetRig.self)

    /// The home's style: the save's, the London terrace until one is chosen. Debug builds can try another
    /// home with HOUSECAT_HOME=cottage (scheme environment).
    static func style(_ state: HouseholdState) -> HouseStyle {
        #if DEBUG
            if let name = ProcessInfo.processInfo.environment["HOUSECAT_HOME"], let style = HouseStyle(rawValue: name) {
                return style
            }
            if let rung = ProcessInfo.processInfo.environment["HOUSECAT_RUNG"].flatMap(Int.init) {
                return HouseLadder.rung(rung).style
            }
        #endif
        return state.homeStyle
    }

    /// The home right now: its pin, season, sky at its local time and today's weather. Debug builds can
    /// override what the save says with HOUSECAT_BIOME, HOUSECAT_SEASON and HOUSECAT_TIME (dawn, day, dusk, night).
    static func now(state: HouseholdState, at date: Date) -> HomeNow {
        var now = state.homeNow(
            at: date,
            weather: content?.weather ?? WeatherFile(tables: [:]),
            report: RealWeather.report,
            context: GameSession.shared.rules
        )
        #if DEBUG
            let environment = ProcessInfo.processInfo.environment
            // HOUSECAT_RUNG=5: a house up the ladder, in its town, whatever the save has.
            if let rung = environment["HOUSECAT_RUNG"].flatMap(Int.init) {
                now.place = HouseLadder.rung(rung).place
                now.biome = now.place.biome
            }
            if let name = environment["HOUSECAT_BIOME"], let biome = Biome(rawValue: name) {
                now.biome = biome
            }
            if let name = environment["HOUSECAT_SEASON"], let season = NatureSeason(rawValue: name) {
                now.season = season
            }
            if let name = environment["HOUSECAT_TIME"], let sky = SkyPhase(rawValue: name) {
                now.sky = sky
            }
            if let name = environment["HOUSECAT_WEATHER"], let weather = Weather(rawValue: name) {
                now.weather = weather
            }
        #endif
        return now
    }

    /// The door points of the painted exteriors and where each house stands in its painting
    /// (assets/world/scenes/scenes.json, tools/asset-pipeline/scenes.py doors and houses).
    private struct SceneIndex: Decodable {
        var defaultDoor: [Double]
        var doors: [String: [Double]]
        var houses: [String: [Double]]?
        /// Each scene's windows the cat can sit in: [left, top, right, bottom, row] (scenes.py windows).
        var windows: [String: [[Double]]]?
    }

    /// A painted scene's front door (a fraction of the picture), from scenes.json.
    static func door(for name: String) -> CGPoint {
        guard let index = try? art?.data("world/scenes/scenes.json", as: SceneIndex.self) else { return CGPoint(x: 0.5, y: 0.7) }
        let door = index.doors[name] ?? index.defaultDoor
        return CGPoint(x: door[0], y: door[1])
    }

    /// The home's exterior at this moment: its painting for its biome and season, its sky for the local time.
    static func exteriorScene(size: CGSize, at date: Date, state: HouseholdState, looking: Bool = false) -> ExteriorScene? {
        guard let art, let index = try? art.data("world/scenes/scenes.json", as: SceneIndex.self) else { return nil }
        let now = now(state: state, at: date)
        let style = style(state)
        // A home whose pack has not arrived has no cold open yet (HomePacks); otherwise its painting for the
        // biome and season, falling back to another season if one is missing.
        let seasons = [now.season] + NatureSeason.allCases.filter { $0 != now.season }
        // The ladder's first house is the run-down one (docs/LADDER.md), painted for itself.
        let firstHouse = state.rung == 1 ? seasons.map { "world/scenes/\(Tuning.Cutscene.firstHouseScene)_\(now.biome.rawValue)_\($0.rawValue)" } : []
        guard let path = (firstHouse + seasons.map({ HouseBuilder.scene(style, now.biome, $0) })).first(where: { art.has("\($0).jpg") })
        else { return nil }
        let name = String(path.dropFirst("world/scenes/".count))
        let door = index.doors[name] ?? index.defaultDoor
        let house = index.houses?[name].flatMap { $0.count == 4 ? CGRect(x: $0[0], y: $0[1], width: $0[2] - $0[0], height: $0[3] - $0[1]) : nil }
        let model = ExteriorScene.Model(
            scene: path,
            sky: now.sky,
            door: CGPoint(x: door[0], y: door[1]),
            weather: now.weather,
            season: now.season,
            house: house,
            windows: (index.windows?[name] ?? []).compactMap(SceneWindow.init)
        )
        let scene = ExteriorScene(size: size, art: art, model: model)
        scene.looking = looking
        return scene
    }

    /// The opening cutscene's house (docs/LADDER.md): the first house in the rain at dusk, shown, not entered.
    static func cutsceneScene(size: CGSize) -> ExteriorScene? {
        guard let art, let index = try? art.data("world/scenes/scenes.json", as: SceneIndex.self) else { return nil }
        let name = "\(Tuning.Cutscene.firstHouseScene)_city_autumn"
        guard art.has("world/scenes/\(name).jpg") else { return nil }
        let door = index.doors[name] ?? index.defaultDoor
        let house = index.houses?[name].flatMap { $0.count == 4 ? CGRect(x: $0[0], y: $0[1], width: $0[2] - $0[0], height: $0[3] - $0[1]) : nil }
        let model = ExteriorScene.Model(
            scene: "world/scenes/\(name)",
            sky: .dusk,
            door: CGPoint(x: door[0], y: door[1]),
            weather: .rain,
            season: .autumn,
            house: house
        )
        let scene = ExteriorScene(size: size, art: art, model: model)
        scene.showcase = true
        return scene
    }

    /// The player's cat as it is, for the cutscene's doorway.
    static func playerCat(state: HouseholdState, at date: Date) -> CatNode? {
        guard let art, let rig else { return nil }
        let cat = state.cats.first
        let node = CatNode(
            art: art,
            rig: rig,
            catArt: catArt,
            look: cat?.look ?? .midnight,
            isKitten: cat?.isKittenStage(on: state.clock.day(of: date)) ?? false,
            height: 100
        )
        node.wear(GameSession.shared.wornOutfit)
        return node
    }

    /// The cat at a window of the exterior (Josh, 20 Oct: "have your cat in the window"; `WindowCatRules` says which
    /// and how): on the floor of the room it is in, as it is there, in its look and outfit.
    static func seatCat(
        in exterior: ExteriorScene,
        house: RoomScene,
        room: RoomID,
        activity: Activity?,
        watchingYou: Bool,
        state: HouseholdState,
        at date: Date,
        fade: Bool = true
    ) {
        guard let art, let rig, !exterior.model.windows.isEmpty else { return }
        let cat = state.cats.first
        let context = WindowCatRules.Context(
            storey: house.house.room(room)?.storey ?? 0,
            storeys: (house.storeys.max() ?? 0) + 1,
            activity: activity,
            mood: state.mood(of: GameSession.catID, at: date),
            sky: exterior.model.sky,
            watchingYou: watchingYou,
            door: exterior.model.door.x
        )
        guard let sighting = WindowCatRules.sighting(
            windows: exterior.model.windows,
            context: context,
            household: state.seed,
            day: state.clock.day(of: date),
            minutes: state.clock.localMinutes(of: date)
        ) else { return }
        let node = CatNode(
            art: art,
            rig: rig,
            catArt: catArt,
            look: cat?.look ?? .midnight,
            isKitten: cat?.isKittenStage(on: state.clock.day(of: date)) ?? false,
            height: 100
        )
        node.wear(GameSession.shared.wornOutfit)
        exterior.seat(node, at: sighting, fade: fade)
    }

    /// The sky over the home at its local time.
    static func skyPhase(at date: Date, state: HouseholdState) -> SkyPhase {
        now(state: state, at: date).sky
    }

    /// The home as the save has it: every room of the house's plan around the living room, each with its
    /// wallpaper, floor and placed furniture, the closed ones veiled, every window showing the pinned place.
    static func house(at date: Date, state: HouseholdState) -> HouseModel? {
        guard let art, let content, let layout = try? art.data("rooms/layout_living_demo.json", as: RoomModel.self),
              let plans = try? art.data("rooms/houses.json", as: HousePlans.self)
        else { return nil }
        return HouseBuilder.house(
            style: style(state),
            plans: plans,
            layout: layout,
            state: state,
            catalogue: content.catalogue,
            now: now(state: state, at: date),
            outdoors: content.outdoors
        )
    }

    /// The house with the cat where its day put it, greeting you in its own way and going on to what the save says,
    /// or a blank scene if the art is missing.
    /// `onRub` runs when the cat reaches you and rubs along the bottom edge; `onArrived` when it has gone on to what it does next.
    static func roomScene(
        size: CGSize,
        at date: Date = Date(),
        state: HouseholdState,
        arrival: GameSession.Arrival?,
        onRub: @escaping @MainActor () -> Void = {},
        onArrived: @escaping @MainActor () -> Void = {}
    ) -> SKScene {
        guard let art, let content, let house = house(at: date, state: state), let rig else {
            return SKScene(size: size)
        }
        let scene = RoomScene(size: size, art: art, content: content, house: house)
        let start = scene.model.cat
        let cat = state.cats.first
        let day = state.clock.day(of: date)
        scene.addCat(
            rig: rig,
            catArt: catArt,
            look: cat?.look ?? .midnight,
            isKitten: cat?.isKittenStage(on: day) ?? false,
            at: CGFloat(start[0]),
            CGFloat(start[1]),
            pose: .loafThreeQuarterFront
        )
        if let arrival {
            scene.placeCat(for: arrival.start)
            scene.playArrival(arrival.style, then: arrival.choice, onRub: {
                purr()
                onRub()
            }, onDone: onArrived)
        }
        return scene
    }

    /// The rub along the bottom edge: a soft haptic and the purr.
    static func purr() {
        #if canImport(UIKit) && !os(watchOS)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
        Sound.loop("cat_purr_loop", volume: Tuning.Sound.purr)
        Sound.stop("cat_purr_loop", after: Tuning.Sound.purrSeconds)
    }
}
