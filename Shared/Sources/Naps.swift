#if os(iOS)
    import ActivityKit
#endif
import Foundation
import HouseCatCore
import Observation

/// The nap (SPEC "Care": a 20-minute wind-down timer as a Live Activity; complete it for XP). The player starts
/// it; the cat curls up in the room and on the Lock Screen; when the time is up (checked whenever the app is
/// open) `napCompleted` is recorded at the moment it ended. Waking the cat early pays nothing. The nap in
/// progress is kept in the App Group so it survives the app being closed.
@MainActor
@Observable
final class Naps {
    static let shared = Naps()

    @ObservationIgnored private let defaults = UserDefaults(suiteName: WidgetFiles.appGroup) ?? .standard
    private(set) var startedAt: Date?

    var endsAt: Date? {
        startedAt.map(NapRules.end(of:))
    }

    var isNapping: Bool {
        startedAt != nil
    }

    private init() {
        startedAt = defaults.object(forKey: "napStartedAt") as? Date
    }

    func start(catName: String) {
        guard !isNapping else { return }
        var now = Date()
        #if DEBUG
            // Screenshot runs: HOUSECAT_NAP_SECONDS=<n> starts the nap that many seconds from its end.
            if let left = ProcessInfo.processInfo.environment["HOUSECAT_NAP_SECONDS"].flatMap(Double.init) {
                now = now.addingTimeInterval(left - Tuning.Nap.minutes * 60)
            }
        #endif
        startedAt = now
        defaults.set(now, forKey: "napStartedAt")
        #if os(iOS)
            let attributes = NapAttributes(catName: catName, startedAt: now)
            let state = NapAttributes.ContentState(endsAt: NapRules.end(of: now), awake: false)
            // Live Activities may be turned off: the nap still runs in the app.
            _ = try? Activity.request(attributes: attributes, content: .init(state: state, staleDate: NapRules.end(of: now)), pushType: nil)
        #endif
    }

    /// Woken early: the nap ends and pays nothing.
    func wake() {
        finish(completed: false)
    }

    /// A nap whose time is up is recorded and ended. Returns whether it paid (once a day).
    @discardableResult
    func check(at date: Date = Date()) -> Bool {
        guard let start = startedAt, NapRules.isComplete(startedAt: start, at: date) else { return false }
        let paid = GameSession.shared.completeNap(endedAt: NapRules.end(of: start))
        Analytics.track(.napFinished)
        finish(completed: true)
        return paid
    }

    private func finish(completed: Bool) {
        let end = endsAt ?? Date()
        startedAt = nil
        defaults.removeObject(forKey: "napStartedAt")
        #if os(iOS)
            let final = NapAttributes.ContentState(endsAt: end, awake: true)
            Task {
                for activity in Activity<NapAttributes>.activities {
                    await activity.end(
                        .init(state: final, staleDate: nil),
                        dismissalPolicy: completed ? .after(Date().addingTimeInterval(Tuning.Nap.lingerMinutes * 60)) : .immediate
                    )
                }
            }
        #endif
    }
}
