import AVFoundation
import Foundation
import HouseCatCore
#if canImport(UIKit)
    import UIKit
#endif

/// The background music (App/Audio/music_*.m4a, composed for HouseCat by tools/app-assets/make_music.py): a quiet
/// loop under the room's ambience, the brighter one by day and the calmer one at night. It plays in the room and the
/// intro, fades out behind the launch film and for the mini-games, and stays silent while another app plays (the
/// player's own music, a podcast: `secondaryAudioShouldBeSilencedHint`). Settings turns it off or down, kept on
/// this device. iPhone and iPad only.
@MainActor
enum Music {
    enum Track: String {
        case day = "music_windowsill"
        case night = "music_lullaby"

        /// The calmer track from dusk, when the crickets start.
        static func `for`(_ sky: SkyPhase) -> Track {
            sky == .night || sky == .dusk ? .night : .day
        }
    }

    /// What quietens the music for a while.
    enum Hush: Hashable {
        case launchFilm
        case miniGame
        case otherAudio
    }

    static let onKey = "musicOn"
    static let volumeKey = "musicVolume"

    /// Music on (Settings).
    static var isOn: Bool {
        UserDefaults.standard.object(forKey: onKey) as? Bool ?? true
    }

    /// The player's own level, 0–1, of `Tuning.Sound.music` (Settings).
    static var volume: Double {
        UserDefaults.standard.object(forKey: volumeKey) as? Double ?? 1
    }

    private static var wanted: Track?
    private static var hushes: Set<Hush> = []
    private static var players: [Track: AVAudioPlayer] = [:]
    private static var observing = false

    /// Plays the track for the sky (the room, the intro).
    static func play(for sky: SkyPhase) {
        wanted = .for(sky)
        refresh()
    }

    static func hush(_ reason: Hush, _ on: Bool) {
        if on {
            hushes.insert(reason)
        } else {
            hushes.remove(reason)
        }
        refresh()
    }

    /// Brings the music in line with what is wanted, what hushes it and the player's settings: the track playing
    /// fades to its level, any other fades out and pauses where it was, to carry on from there.
    static func refresh(fade: TimeInterval = Tuning.Sound.musicFadeSeconds) {
        #if os(iOS)
            Sound.configure()
            observe()
            let playing = isOn && hushes.isEmpty ? wanted : nil
            for (track, player) in players where track != playing && player.isPlaying {
                player.setVolume(0, fadeDuration: Tuning.Sound.musicFadeSeconds)
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(Tuning.Sound.musicFadeSeconds))
                    if player.volume == 0 {
                        player.pause()
                    }
                }
            }
            guard let playing, let player = player(playing) else { return }
            if !player.isPlaying {
                player.volume = 0
                player.play()
            }
            player.setVolume(Float(Tuning.Sound.music * volume), fadeDuration: fade)
        #endif
    }

    private static func player(_ track: Track) -> AVAudioPlayer? {
        if let player = players[track] {
            return player
        }
        guard let url = Bundle.main.url(forResource: track.rawValue, withExtension: "m4a", subdirectory: "Audio"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.numberOfLoops = -1
        player.prepareToPlay()
        players[track] = player
        return player
    }

    #if os(iOS)
        /// Listens for other apps' audio starting and stopping, and for the app coming back (after a call, say).
        private static func observe() {
            guard !observing else { return }
            observing = true
            let session = AVAudioSession.sharedInstance()
            if session.secondaryAudioShouldBeSilencedHint {
                hushes.insert(.otherAudio)
            }
            NotificationCenter.default.addObserver(
                forName: AVAudioSession.silenceSecondaryAudioHintNotification,
                object: session,
                queue: .main
            ) { note in
                let begins = (note.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt)
                    .flatMap(AVAudioSession.SilenceSecondaryAudioHintType.init) == .begin
                Task { @MainActor in hush(.otherAudio, begins) }
            }
            NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { _ in
                Task { @MainActor in refresh() }
            }
            // The hint is not sent while the app is away, so it is asked again on the way back.
            NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in hush(.otherAudio, AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint) }
            }
        }
    #endif
}
