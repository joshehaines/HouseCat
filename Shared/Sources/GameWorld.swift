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

    /// The living room with the demo layout, the cat arriving to do what the save says, or a blank
    /// scene if the art is missing.
    static func roomScene(size: CGSize, at date: Date = Date(), arrival: GameSession.Arrival?) -> SKScene {
        guard let art, let content, var model = try? art.data("rooms/layout_living_demo.json", as: RoomModel.self),
              let rig = try? art.data("cat/rig.json", as: PuppetRig.self)
        else {
            return SKScene(size: size)
        }
        let sky = skyPhase(at: date)
        model.sky = sky
        model.light = sky.lightMap(weather: .sun)
        let scene = RoomScene(size: size, art: art, content: content, model: model)
        scene.addCat(rig: rig, at: CGFloat(model.cat[0]), CGFloat(model.cat[1]), pose: .loafThreeQuarterFront)
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
