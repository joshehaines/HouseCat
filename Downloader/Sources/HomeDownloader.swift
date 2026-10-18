import BackgroundAssets
import ExtensionFoundation
import StoreKit

/// Downloads the homes' exterior packs (Apple-hosted Background Assets) for the app: the system calls this
/// extension when a pack the app asked for (Shared/Sources/HomePacks.swift) is due. Every pack is on demand, and
/// the defaults do the rest.
@main
struct HomeDownloader: StoreDownloaderExtension {
    func shouldDownload(_: AssetPack) -> Bool {
        true
    }
}
