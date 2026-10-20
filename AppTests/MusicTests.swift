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

    @Test func aGameOverTheGamesMenuKeepsTheMusicHushed() {
        Music.hush(.miniGame, true)
        Music.hush(.miniGame, true)
        Music.hush(.miniGame, false)
        #expect(Music.isHushed(by: .miniGame))
        Music.hush(.miniGame, false)
        #expect(!Music.isHushed(by: .miniGame))
        Music.hush(.miniGame, false)
        Music.hush(.miniGame, true)
        #expect(Music.isHushed(by: .miniGame))
        Music.hush(.miniGame, false)
    }

    /// In a defaults suite of its own, new each run: the app's real setting on the simulator is never touched, and a
    /// removal still pending from the last run cannot leave this one starting with the music off.
    @Test func musicIsOnUntilTurnedOff() throws {
        let suite = "MusicTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(Music.isOn(in: defaults))
        defaults.set(false, forKey: Music.onKey)
        #expect(!Music.isOn(in: defaults))
    }
}
