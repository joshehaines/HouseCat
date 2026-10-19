import BackgroundAssets
import Foundation
import HouseCatCore
import HouseCatGame
import System

/// The homes' exteriors that are not inside the app (every home but the London terrace): one Background Assets
/// pack a home, Apple-hosted and downloaded on demand (tools/app-assets/build_home_packs.py builds them). A pack
/// that has arrived is added to the art library; until then the visit goes straight inside, since the house view
/// and every window only need the bundled terrain.
///
/// The download needs the App Group and the downloader extension, which need the developer team (CLAUDE.md
/// "Known gaps"); until then every call here finds nothing and the bundled home is the only one with a cold open.
@MainActor
enum HomePacks {
    static func id(_ style: HouseStyle) -> String {
        "home.\(style.rawValue)"
    }

    /// Whether the home's exteriors can be drawn now.
    static func isReady(_ style: HouseStyle) -> Bool {
        guard let art = GameWorld.art else { return false }
        return art.has(HouseBuilder.scene(style, .city, .summer) + ".jpg")
    }

    /// Whether Background Assets can be asked at all: the app must be entitled to the App Group its Info.plist
    /// names (`BAAppGroupID`). Without it, `AssetPackManager.shared` traps rather than throwing (Josh's iPad, 19 Oct:
    /// a build signed without the App Group crashed the moment a home was chosen).
    static var isAvailable: Bool {
        guard Bundle.main.object(forInfoDictionaryKey: "BAHasManagedAssetPacks") as? Bool == true,
              let group = Bundle.main.object(forInfoDictionaryKey: "BAAppGroupID") as? String else { return false }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil
    }

    /// Adds the pack's art if it is already on the device, else asks for it; `ready` runs once it is here.
    static func prepare(_ style: HouseStyle, ready: (@MainActor () -> Void)? = nil) {
        guard !isReady(style) else {
            ready?()
            return
        }
        // No App Group, no packs: the visit goes straight inside, as with no pack.
        guard isAvailable else { return }
        // Already downloaded or not, ensureLocalAvailability returns once the pack is on the device.
        Task {
            do {
                let pack = try await AssetPackManager.shared.assetPack(withID: id(style))
                try await AssetPackManager.shared.ensureLocalAvailability(of: pack)
                register(style)
                ready?()
            } catch {
                // No pack yet (no team, offline, not uploaded): the visit goes straight inside.
            }
        }
    }

    /// The pack's files sit under homes/<style>/, with their own art.json.
    private static func register(_ style: HouseStyle) {
        guard let art = GameWorld.art,
              let index = try? AssetPackManager.shared.url(for: FilePath("homes/\(style.rawValue)/art.json")) else { return }
        try? art.add(packAt: index.deletingLastPathComponent())
    }
}
