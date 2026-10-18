import AppIntents
import Foundation
import HouseCatCore

/// The cat, as Siri and Shortcuts know it, so a phrase can use its own name ("Feed Pip in HouseCat").
struct CatEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Cat"
    static let defaultQuery = CatQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct CatQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [CatEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [CatEntity] {
        (WidgetWorld.load()?.state.cats ?? []).map { CatEntity(id: $0.id, name: $0.name) }
    }
}

/// What Siri says about the cat after an action or when asked: how it is, and the streak.
private enum CatNews {
    static func now() -> (name: String, state: WidgetState)? {
        guard let world = WidgetWorld.load(), world.state.cats.first != nil else { return nil }
        return (world.catName, WidgetRules.state(at: Date(), save: world.state, context: world.context))
    }

    static func days(_ n: Int) -> String {
        n == 1 ? "1 day" : "\(n) days"
    }
}

/// Siri and Shortcuts (SPEC "Siri and Shortcuts"): feed the cat. Like the widget's button, it counts as today's
/// visit.
struct FeedCatShortcut: AppIntent {
    static let title: LocalizedStringResource = "Feed your cat"
    static let description = IntentDescription("Fills the bowl. It counts as today's visit.")

    @Parameter(title: "Cat") var cat: CatEntity?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let before = CatNews.now() else { return .result(dialog: "Open HouseCat first to meet your cat.") }
        if before.state.fedToday {
            return .result(dialog: "\(before.name) has had breakfast already today.")
        }
        try WidgetActions.run(.feed, source: .siri)
        let streak = CatNews.now()?.state.streak ?? before.state.streak
        return .result(dialog: "\(before.name) is tucking in. That's \(CatNews.days(streak)) in a row.")
    }
}

/// A stroke from Siri or a shortcut; it counts as today's visit.
struct PetCatShortcut: AppIntent {
    static let title: LocalizedStringResource = "Stroke your cat"
    static let description = IntentDescription("A stroke without opening the app. It counts as today's visit.")

    @Parameter(title: "Cat") var cat: CatEntity?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let before = CatNews.now() else { return .result(dialog: "Open HouseCat first to meet your cat.") }
        try WidgetActions.run(.pet, source: .siri)
        return .result(dialog: "\(before.name) purrs.")
    }
}

/// "How's my cat?": the widget's own answer (waiting, glad, missed you) and the streak.
struct CatStatusShortcut: AppIntent {
    static let title: LocalizedStringResource = "How's your cat?"
    static let description = IntentDescription("Whether your cat has seen you today, and your streak.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let (name, state) = CatNews.now() else { return .result(dialog: "Open HouseCat first to meet your cat.") }
        let mood = switch state.mood {
        case .content: state.fedToday ? "\(name) is fed and content." : "\(name) is glad you came by today."
        case .waiting: "\(name) is waiting for you."
        case .lastChance: "\(name) is still waiting up for you, \(state.hoursLeft.map { $0 == 1 ? "with an hour" : "with \($0) hours" } ?? "with a little time") left today."
        case .sulking: "\(name) missed you yesterday."
        }
        return .result(dialog: "\(mood) Your streak is \(CatNews.days(state.streak)).")
    }
}

/// The phrases Siri knows (each must name the app; the cat's own name comes from `CatEntity`).
struct HouseCatShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FeedCatShortcut(),
            phrases: [
                "Feed \(\.$cat) in \(.applicationName)",
                "Feed my cat in \(.applicationName)",
                "Feed the cat in \(.applicationName)",
            ],
            shortTitle: "Feed the cat",
            systemImageName: "pawprint.fill"
        )
        AppShortcut(
            intent: PetCatShortcut(),
            phrases: [
                "Stroke \(\.$cat) in \(.applicationName)",
                "Stroke my cat in \(.applicationName)",
                "Pet my cat in \(.applicationName)",
            ],
            shortTitle: "Stroke the cat",
            systemImageName: "hand.raised.fill"
        )
        AppShortcut(
            intent: CatStatusShortcut(),
            phrases: [
                "How is my cat in \(.applicationName)",
                "Check on my cat in \(.applicationName)",
            ],
            shortTitle: "How's my cat?",
            systemImageName: "heart.fill"
        )
    }
}
