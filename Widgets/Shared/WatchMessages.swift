import Foundation
import HouseCatCore

/// What the iPhone and the Watch say to each other (CLAUDE.md "Watch"). The iPhone sends the widget's snapshot
/// (the save's state) as its application context, with the kit's key; the Watch asks for the kit's pictures,
/// Watch-sized, one message each, and keeps them in its own App Group, where the Watch app and its complication
/// read them as the widget does; it sends back the events its Feed and Stroke append. Compiled into both.
enum WatchMessages {
    /// The snapshot, as `WidgetSnapshot` JSON.
    static let snapshot = "snapshot"
    /// One `GameEvent`, as JSON.
    static let event = "event"
    /// A kit file: its name (in the Watch's request) and its bytes (in the iPhone's reply).
    static let file = "file"
    static let data = "data"
    /// The kit's key next to the snapshot (the Watch asks for the pictures when its own differ), and in the
    /// Watch's request for them.
    static let kitKey = "kitKey"

    /// The longest side of a picture on the Watch, in pixels (the cat is drawn about 90 points high).
    static let pictureCatPixels = 220
    static let pictureIconPixels = 72

    /// The kit files the Watch gets: the cat in every pose and the buttons' painted icons.
    static var kitFiles: [String] {
        CatPose.allCases.map(WidgetFiles.catFile) + ["kit.json", "icon_feed_bowl.png", "icon_petting_hand.png", "icon_streak_paw_print_with_a_small_flame.png"]
    }

    static func encode(_ value: some Encodable) -> Data? {
        try? JSONEncoder().encode(value)
    }

    static func event(in message: [String: Any]) -> GameEvent? {
        (message[event] as? Data).flatMap { try? JSONDecoder().decode(GameEvent.self, from: $0) }
    }
}
