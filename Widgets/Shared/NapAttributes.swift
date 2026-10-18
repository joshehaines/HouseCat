#if canImport(ActivityKit)
    import ActivityKit
    import Foundation

    /// The nap on the Lock Screen and in the Dynamic Island (SPEC "Live Activity": the 20-minute wind-down timer;
    /// the cat curls up; complete it for XP). Started by the player in the app, never on its own.
    struct NapAttributes: ActivityAttributes {
        struct ContentState: Codable, Hashable {
            var endsAt: Date
            /// Woken early, or finished: the activity's last word.
            var awake: Bool
        }

        var catName: String
        var startedAt: Date
    }
#endif
