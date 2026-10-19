import AVFoundation
import Foundation
@testable import HouseCat
import HouseCatCore
import Testing

/// The background music (Shared/Sources/Music.swift): the calmer track from dusk, both in the app, both long loops.
@MainActor
@Suite("Music")
struct MusicTests {
    @Test func theNightTrackPlaysFromDusk() {
        #expect(Music.Track.for(.dawn) == .day)
        #expect(Music.Track.for(.day) == .day)
        #expect(Music.Track.for(.dusk) == .night)
        #expect(Music.Track.for(.night) == .night)
    }

    @Test(arguments: [Music.Track.day, .night])
    func eachTrackShipsAsALongLoop(_ track: Music.Track) throws {
        let url = try #require(Bundle.main.url(forResource: track.rawValue, withExtension: "m4a", subdirectory: "Audio"))
        let player = try AVAudioPlayer(contentsOf: url)
        #expect(player.duration > 60 && player.duration < 120)
        #expect(player.numberOfChannels == 2)
    }

    @Test func musicIsOnUntilTurnedOff() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: Music.onKey)
        defer { defaults.set(saved, forKey: Music.onKey) }
        defaults.removeObject(forKey: Music.onKey)
        #expect(Music.isOn)
        defaults.set(false, forKey: Music.onKey)
        #expect(!Music.isOn)
    }
}
