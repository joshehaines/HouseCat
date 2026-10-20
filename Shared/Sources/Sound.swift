import AVFoundation
import Foundation
import HouseCatCore
#if canImport(UIKit)
    import UIKit
#endif

/// The app's sounds (App/Audio, built from assets/audio by tools/app-assets/build_app_audio.sh): one-shots
/// and loops at the volumes in Tuning.Sound. Ambient session, so it mixes with the player's music and
/// respects the silent switch.
@MainActor
enum Sound {
    private static var players: [String: AVAudioPlayer] = [:]
    private static var configured = false

    private static func player(_ name: String) -> AVAudioPlayer? {
        if let player = players[name] {
            return player
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "m4a", subdirectory: "Audio"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        players[name] = player
        return player
    }

    static func configure() {
        guard !configured else { return }
        configured = true
        #if os(iOS)
            try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        #endif
    }

    static func play(_ name: String, volume: Double) {
        configure()
        guard let player = player(name) else { return }
        player.numberOfLoops = 0
        player.currentTime = 0
        player.volume = Float(volume)
        player.play()
    }

    static func loop(_ name: String, volume: Double) {
        configure()
        guard let player = player(name), !player.isPlaying else { return }
        player.numberOfLoops = -1
        player.volume = 0
        player.play()
        player.setVolume(Float(volume), fadeDuration: Tuning.Sound.fadeSeconds)
    }

    // MARK: The games' cat noises

    /// Its own player of the purr, so a game's purr and the room's never stop each other.
    private static var gamePurr: AVAudioPlayer?
    private static var gamePurrEnd: Task<Void, Never>?
    private static var lastVoice: Date?

    /// A hit in a game, as the cat hears it (Josh, 20 Oct: "the meow sound effect is strange when done quickly,
    /// maybe we do a purr instead"): a purr swells in and dies away after the last hit, and hits close together keep
    /// the one purr going instead of starting a chirp over and over.
    static func purr() {
        configure()
        if gamePurr == nil, let url = Bundle.main.url(forResource: "cat_purr_loop", withExtension: "m4a", subdirectory: "Audio") {
            gamePurr = try? AVAudioPlayer(contentsOf: url)
            gamePurr?.numberOfLoops = -1
            gamePurr?.prepareToPlay()
        }
        guard let player = gamePurr else { return }
        let s = Tuning.Sound.self
        if !player.isPlaying {
            // Somewhere in the recording, so one purr is not the same as the last.
            player.currentTime = Double.random(in: 0 ..< max(0.01, player.duration - s.gamePurrSeconds - s.gamePurrFadeOut))
            player.volume = 0
            player.play()
        }
        player.setVolume(Float(s.gamePurr), fadeDuration: s.gamePurrFadeIn)
        gamePurrEnd?.cancel()
        gamePurrEnd = Task { @MainActor in
            try? await Task.sleep(for: .seconds(s.gamePurrSeconds))
            guard !Task.isCancelled else { return }
            player.setVolume(0, fadeDuration: s.gamePurrFadeOut)
            try? await Task.sleep(for: .seconds(s.gamePurrFadeOut))
            guard !Task.isCancelled else { return }
            player.stop()
        }
    }

    /// The cat's voice in a game (a chirp at the count, a meow as it comes out, the meow with a line): never within
    /// `Tuning.Sound.voiceGapSeconds` of the last, so two never run into each other.
    static func voice(_ name: String, volume: Double = Tuning.Sound.meow) {
        let now = Date()
        if let last = lastVoice, now.timeIntervalSince(last) < Tuning.Sound.voiceGapSeconds {
            return
        }
        lastVoice = now
        play(name, volume: volume)
    }

    static func stop(_ name: String, after delay: TimeInterval = 0) {
        guard let player = players[name] else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            player.setVolume(0, fadeDuration: Tuning.Sound.fadeSeconds)
            try? await Task.sleep(for: .seconds(Tuning.Sound.fadeSeconds))
            player.stop()
        }
    }

    /// The meow a line pack asks for (Content/lines.json), as a sound name.
    static func meow(_ kind: LinesFile.Line.Meow?) -> String? {
        switch kind {
        case .short: "cat_meow_short"
        case .long: "cat_meow_long"
        case .chirp: "cat_chirp"
        case .trill: "cat_trill"
        case .grumble: "cat_grumble"
        case .purr: "cat_purr_loop"
        case .silent, .none: nil
        }
    }

    /// The weather's own sound under everything: rain on the glass, the wind, the hush of snow.
    static func weather(_ weather: Weather) {
        let loops: [Weather: String] = [.rain: "rain_loop", .storm: "rain_loop", .wind: "wind_loop", .snow: "snow_hush_loop"]
        for name in Set(loops.values) where name != loops[weather] {
            stop(name)
        }
        if let name = loops[weather] {
            loop(name, volume: weather == .storm ? Tuning.Sound.storm : Tuning.Sound.weather)
        }
    }

    /// A control pressed: a soft tap and a tick under the finger.
    static func tap() {
        play("ui_tap", volume: Tuning.Sound.tap)
        #if canImport(UIKit) && !os(watchOS)
            UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    /// The room's ambience for the sky: crickets at night, birds in the morning, the fire when one is lit.
    static func ambience(for sky: SkyPhase, fire: Bool) {
        stop("night_crickets_loop")
        stop("dawn_birds_loop")
        switch sky {
        case .night, .dusk: loop("night_crickets_loop", volume: Tuning.Sound.ambience)
        case .dawn: loop("dawn_birds_loop", volume: Tuning.Sound.ambience)
        case .day: break
        }
        if fire {
            loop("fire_crackle_loop", volume: Tuning.Sound.fire)
        }
    }
}
