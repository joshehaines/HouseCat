import BackgroundAssets
import Foundation
import HouseCatCore
import HouseCatGame
import Network
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
    /// Letters, digits and hyphens only: App Store Connect rejected `home.cottage` and `home_cottage` as invalid
    /// asset pack ids on 21 Oct 2026, so the style's underscores become hyphens (`home-mansion-flat`).
    static func id(_ style: HouseStyle) -> String {
        "home-\(style.rawValue.replacingOccurrences(of: "_", with: "-"))"
    }

    /// Whether the home's exteriors can be drawn now.
    static func isReady(_ style: HouseStyle) -> Bool {
        guard let art = GameWorld.art else { return false }
        return art.has(HouseBuilder.scene(style, .city, .summer) + ".jpg")
    }

    /// Whether choosing this home asks for a download: its exteriors are not in the app and not here yet.
    static func needsDownload(_ style: HouseStyle) -> Bool {
        !isReady(style) && Tuning.Exterior.packMegabytes[style] != nil
    }

    /// What the player is told before the pack is asked for (App Review 4.2.3: the size, and a chance to say no):
    /// how big it is, where it comes from, and that they are on mobile data when they are.
    static func downloadNote(for style: HouseStyle) -> String? {
        guard needsDownload(style), let megabytes = Tuning.Exterior.packMegabytes[style] else { return nil }
        var note = "Its outside views are a \(megabytes) MB download from Apple, fetched once you move in."
        if onMobileData {
            note += " You're on mobile data now."
        }
        return note
    }

    /// Watched from the house step on, so the note can say when the download would use mobile data.
    private static let network: NWPathMonitor = {
        let monitor = NWPathMonitor()
        monitor.start(queue: DispatchQueue(label: "housecat.network", qos: .utility))
        return monitor
    }()

    static func watchNetwork() {
        _ = network
    }

    static var onMobileData: Bool {
        network.currentPath.isExpensive
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
        #if DEBUG
            // Another home's cold open and outside view in a simulator, from the packs build_home_packs.py made:
            // HOUSECAT_PACKS=~/Library/Caches/HouseCat/packs (each home_<style>/homes/<style>/art.json).
            if !isReady(style), let folder = ProcessInfo.processInfo.environment["HOUSECAT_PACKS"], let art = GameWorld.art {
                try? art.add(packAt: URL(fileURLWithPath: folder).appendingPathComponent("home_\(style.rawValue)/homes/\(style.rawValue)"))
            }
        #endif
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
