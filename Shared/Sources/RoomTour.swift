import Foundation
import HouseCatCore
import Observation

/// The guided tour of the room after the first arrival (Content/intro.json "room"; a builder game's tutorial in
/// the house style): one thing at a time, the host pointing at it, going on when the player has done it (or on
/// Next), ending with the welcome Beans (`tourFinished`). Skippable at every step. Where it got to is kept on
/// the device, so a tour cut short picks up again.
@MainActor
@Observable
final class RoomTour {
    static let shared = RoomTour()

    /// What the player did, as the tour hears it.
    enum Heard {
        case fed, petted, placed
        case decorating(Bool)
        /// A control the tour points at was used (Play, the nap, the menu, the shop).
        case opened(String)
    }

    @ObservationIgnored private let defaults = UserDefaults(suiteName: WidgetFiles.appGroup) ?? .standard
    private(set) var index: Int?
    /// The welcome Beans just landed (the overlay shows them).
    private(set) var rewarded: Int?
    var steps: [IntroFile.RoomStep] {
        GameWorld.content?.intro.room ?? []
    }

    var step: IntroFile.RoomStep? {
        index.flatMap { steps.indices.contains($0) ? steps[$0] : nil }
    }

    var isRunning: Bool {
        step != nil
    }

    var isDone: Bool {
        defaults.bool(forKey: "tour.done")
    }

    private init() {}

    /// From the start, or where it was left.
    func start() {
        guard !isDone, !steps.isEmpty else { return }
        let saved = defaults.integer(forKey: "tour.step")
        index = steps.indices.contains(saved) ? saved : 0
    }

    /// Next, for a step that only asks to be read.
    func next() {
        guard let index else { return }
        if step?.reward == true {
            finish()
            return
        }
        move(to: index + 1)
    }

    /// The player did something: the step waiting for it is done.
    func heard(_ event: Heard) {
        // A step that is only read and points at this control: using it goes on, as Next does (Josh's iPad, 19 Oct:
        // Play, the nap and the shop did nothing while the tour pointed at them).
        if case let .opened(target) = event {
            if let step, step.waitFor == nil, step.target == target {
                next()
            }
            return
        }
        guard let wait = step?.waitFor else { return }
        let matches = switch (wait, event) {
        case (.fed, .fed), (.petted, .petted), (.placed, .placed), (.decorating, .decorating(true)), (.decorated, .decorating(false)): true
        default: false
        }
        if matches, let index {
            move(to: index + 1)
        } else if case .decorating(false) = event, wait == .placed, let index {
            // Done before placing anything: on past the placing.
            move(to: index + 2)
        }
    }

    func skip() {
        Analytics.track(.tourSkipped)
        finish()
    }

    private func move(to next: Int) {
        if steps.indices.contains(next) {
            index = next
            defaults.set(next, forKey: "tour.step")
            if steps[next].reward == true {
                reward()
            }
        } else {
            finish()
        }
    }

    /// The welcome Beans, once (the reducer pays `tourFinished` once a household).
    private func reward() {
        Analytics.track(.tourFinished)
        let session = GameSession.shared
        let before = session.state(at: session.now()).beans
        session.append(.tourFinished, at: session.now())
        rewarded = session.state(at: session.now()).beans - before
    }

    private func finish() {
        if rewarded == nil {
            reward()
        }
        index = nil
        defaults.set(true, forKey: "tour.done")
        defaults.removeObject(forKey: "tour.step")
    }

    #if DEBUG
        /// Screenshot runs (HOUSECAT_SCREEN=tour): from the top, whatever happened before.
        func restart(at step: Int = 0) {
            defaults.set(false, forKey: "tour.done")
            defaults.set(step, forKey: "tour.step")
            rewarded = nil
            start()
        }
    #endif
}
