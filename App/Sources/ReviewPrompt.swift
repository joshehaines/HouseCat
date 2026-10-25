import Foundation

/// When to ask for an App Store rating (Josh, 25 Oct, from the ASO playbook: ratings move rankings, so ask at a happy
/// moment): only after a streak cheered or a move into a new home, never in the first days together, and at most once
/// every few months (iOS itself shows the prompt at most three times a year).
enum ReviewPrompt {
    static let minimumDaysTogether = 5
    static let daysBetween = 120.0
    private static let key = "reviewAskedAt"

    static func isDue(daysTogether: Int, now: Date = Date()) -> Bool {
        #if DEBUG
            // Seeded screenshot and UI-test runs are not real players.
            if ProcessInfo.processInfo.environment["HOUSECAT_HOUSE"] != nil { return false }
        #endif
        guard daysTogether >= minimumDaysTogether else { return false }
        let last = UserDefaults.standard.double(forKey: key)
        return last == 0 || now.timeIntervalSince1970 - last >= daysBetween * 86400
    }

    static func markAsked(now: Date = Date()) {
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: key)
    }
}
