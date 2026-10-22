import AVFoundation
import HouseCatCore
import SwiftUI
import UIKit

/// The launch's film of the logo (the cat bounding onto the wordmark and curling up, rendered from HouseCatGame's
/// `LogoScene` by tools/app-assets/build_logo_film.sh). While the app builds the home its main thread is busy, and a
/// SpriteKit scene would stand still; a film plays on regardless. One player for the whole launch, so the film runs
/// on from the first frame's curtain into the room's.
@MainActor
enum LaunchFilm {
    /// Whether the launch is still showing the film (the curtain stays until it ends or is tapped).
    @MainActor @Observable
    final class State {
        var holding = false
    }

    static let state = State()
    private static var player: AVPlayer?
    private static var shown = false
    private static var waiting: [CheckedContinuation<Void, Never>] = []

    /// The film's player, started the first time it is asked for (nil when the film is not in the app).
    static func player(dark _: Bool) -> AVPlayer? {
        if let player {
            return player
        }
        // Midnight jumping up onto the sunny windowsill, as the website's hero does (Josh, 22 Oct: the launch
        // "looks awful ... look at the website animation ... with the housecat text next to it, nice and quick").
        guard let url = Bundle.main.url(forResource: "launch_window", withExtension: "mp4") else {
            return nil
        }
        let made = AVPlayer(url: url)
        made.isMuted = true
        made.preventsDisplaySleepDuringVideoPlayback = false
        made.playImmediately(atRate: Float(Tuning.Logo.launchRate))
        player = made
        state.holding = true
        Music.hush(.launchFilm, true)
        NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: made.currentItem,
            queue: .main
        ) { _ in
            Task { @MainActor in release() }
        }
        // However the film fares (paused in the background, say), the launch goes on.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Tuning.Logo.launchHoldMost))
            release()
        }
        return made
    }

    /// The launch's film is done with: it ended, or a tap skipped it.
    static func release() {
        state.holding = false
        Music.hush(.launchFilm, false)
    }

    /// Returns when the home should start being built: `lead` seconds before the launch film ends, so it is ready as
    /// the film finishes; at once when there is no film or it was skipped.
    static func buildTime(lead: TimeInterval) async {
        while let player, state.holding {
            if player.currentItem?.status == .failed {
                release()
                return
            }
            let length = player.currentItem?.duration.seconds ?? .nan
            if length.isFinite, length - player.currentTime().seconds <= lead {
                return
            }
            try? await Task.sleep(for: .seconds(0.1))
        }
    }

    /// The intro's film, a fresh player each time the landing page appears (nil when it is not in the app).
    static func intro() -> AVPlayer? {
        guard let url = Bundle.main.url(forResource: "intro_logo", withExtension: "mov") else { return nil }
        let made = AVPlayer(url: url)
        made.isMuted = true
        made.preventsDisplaySleepDuringVideoPlayback = false
        made.play()
        return made
    }

    /// The film's first frame is on screen.
    static func isShowing() {
        shown = true
        for continuation in waiting {
            continuation.resume()
        }
        waiting = []
    }

    /// Returns once the film is on screen (so it plays on while the caller builds the home), or after `limit` seconds
    /// at most, or at once when there is no film.
    static func onScreen(within limit: TimeInterval) async {
        // The curtain asks for the player as it appears, in the same pass as the caller.
        if player == nil {
            await Task.yield()
        }
        guard player != nil, !shown else { return }
        await withCheckedContinuation { continuation in
            waiting.append(continuation)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(limit))
                isShowing()
            }
        }
    }
}

/// A see-through view of a logo film (HEVC with transparency) at its own size.
struct LaunchFilmView: UIViewRepresentable {
    let player: AVPlayer

    final class FilmView: UIView {
        override static var layerClass: AnyClass {
            AVPlayerLayer.self
        }

        var filmLayer: AVPlayerLayer {
            // The layer class is set above.
            layer as! AVPlayerLayer // swiftlint:disable:this force_cast
        }

        private var ready: NSKeyValueObservation?

        func show(_ player: AVPlayer) {
            filmLayer.player = player
            filmLayer.videoGravity = .resize
            isOpaque = false
            backgroundColor = .clear
            filmLayer.backgroundColor = UIColor.clear.cgColor
            ready = filmLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { layer, _ in
                guard layer.isReadyForDisplay else { return }
                Task { @MainActor in LaunchFilm.isShowing() }
            }
        }
    }

    func makeUIView(context _: Context) -> FilmView {
        let view = FilmView()
        view.show(player)
        return view
    }

    func updateUIView(_: FilmView, context _: Context) {}
}
