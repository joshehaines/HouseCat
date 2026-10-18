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
        #endif
        return state.home.style ?? .londonTerrace
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

    /// The door points of the painted exteriors (assets/world/scenes/scenes.json).
    private struct SceneIndex: Decodable {
        var defaultDoor: [Double]
        var doors: [String: [Double]]
    }

    /// A painted scene's front door (a fraction of the picture), from scenes.json.
    static func door(for name: String) -> CGPoint {
        guard let index = try? art?.data("world/scenes/scenes.json", as: SceneIndex.self) else { return CGPoint(x: 0.5, y: 0.7) }
        let door = index.doors[name] ?? index.defaultDoor
        return CGPoint(x: door[0], y: door[1])
    }

    /// The home's exterior at this moment: its painting for its biome and season, its sky for the local time.
    static func exteriorScene(size: CGSize, at date: Date, state: HouseholdState) -> ExteriorScene? {
        guard let art, let index = try? art.data("world/scenes/scenes.json", as: SceneIndex.self) else { return nil }
        let now = now(state: state, at: date)
        let style = style(state)
        // A home whose pack has not arrived has no cold open yet (HomePacks); otherwise its painting for the
        // biome and season, falling back to another season if one is missing.
        let seasons = [now.season] + NatureSeason.allCases.filter { $0 != now.season }
        guard let path = seasons.map({ HouseBuilder.scene(style, now.biome, $0) }).first(where: { art.has("\($0).jpg") })
        else { return nil }
        let name = String(path.dropFirst("world/scenes/".count))
        let door = index.doors[name] ?? index.defaultDoor
        let model = ExteriorScene.Model(
            scene: path,
            sky: now.sky,
            door: CGPoint(x: door[0], y: door[1]),
            weather: now.weather,
            season: now.season
        )
        return ExteriorScene(size: size, art: art, model: model)
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

    /// The house with the cat arriving in the living room to do what the save says, or a blank scene if the art is missing.
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
            scene.playArrival(then: arrival.choice, onRub: {
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
