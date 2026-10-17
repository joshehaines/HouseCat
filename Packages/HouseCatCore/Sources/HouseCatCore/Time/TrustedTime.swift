import Foundation

/// A moment whose time came from a trusted source (a CloudKit record's
/// `modificationDate` or a StoreKit `signedDate`), paired with the system
/// uptime when it was read, so later elapsed time can be measured without
/// trusting the wall clock.
public struct TimeAnchor: Codable, Hashable, Sendable {
    public var trusted: Date
    public var uptime: TimeInterval
    /// Identifies the boot session; uptime only measures within one boot.
    public var bootID: String

    public init(trusted: Date, uptime: TimeInterval, bootID: String) {
        self.trusted = trusted
        self.uptime = uptime
        self.bootID = bootID
    }
}

/// Game time and whether it is following the wall clock.
public struct GameTime: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        /// The wall clock agrees with the anchor (or there is no anchor yet).
        case live
        /// The wall clock went backwards; game time holds still.
        case pausedBackwards
        /// The wall clock is more than a day ahead of the anchor; game time holds still.
        case pausedAhead
    }

    public var date: Date
    public var status: Status
}

/// Trusted-time rules (CLAUDE.md "Trusted time"): never trust `Date()` alone for
/// streaks, gifts or cooldowns. A backwards jump is ignored and a jump of more
/// than a day ahead of the anchor pauses game time instead of punishing.
public enum TrustedTime {
    /// - Parameters:
    ///   - wall: the device's wall clock now.
    ///   - uptime: system uptime now.
    ///   - bootID: the current boot session.
    ///   - anchor: the latest trusted anchor, if any.
    ///   - lastGameTime: the latest game time already used (the newest event).
    public static func now(
        wall: Date,
        uptime: TimeInterval,
        bootID: String,
        anchor: TimeAnchor?,
        lastGameTime: Date?
    ) -> GameTime {
        let floor = lastGameTime ?? .distantPast

        // What the anchor says the time is, if elapsed time is measurable.
        var expected: Date?
        if let anchor, anchor.bootID == bootID, uptime >= anchor.uptime {
            expected = anchor.trusted.addingTimeInterval(uptime - anchor.uptime)
        }

        if wall < floor {
            return GameTime(date: max(floor, expected ?? floor), status: .pausedBackwards)
        }
        if let expected {
            if wall.timeIntervalSince(expected) > Tuning.Time.maxClockLead {
                return GameTime(date: max(floor, expected), status: .pausedAhead)
            }
            if wall < expected.addingTimeInterval(-Tuning.Time.maxClockLead) {
                // The wall clock is far behind the trusted anchor: follow the anchor.
                return GameTime(date: max(floor, expected), status: .pausedBackwards)
            }
        }
        return GameTime(date: wall, status: .live)
    }
}
