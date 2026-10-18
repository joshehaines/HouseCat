import ActivityKit
import HouseCatCore
import HouseCatStore
import HouseCatUI
import SwiftUI
import UserNotifications

extension Notification.Name {
    /// Everything was deleted: the app goes back to its first screen.
    static let houseCatErased = Notification.Name("houseCatErased")
}

/// The player's data, theirs to take and to delete (UK GDPR; CLAUDE.md "Export my data", "Delete all my data").
/// HouseCat keeps no account and no server: the save, the widget's files and a few preferences on this phone,
/// the household in the person's own iCloud once sharing is on, and a mirror of what was bought (the purchases
/// themselves stay with the Apple Account).
@MainActor
enum YourData {
    /// The save as a JSON file to share.
    static func exportFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HouseCat save.json")
        try GameSession.shared.exportData().write(to: url, options: .atomic)
        return url
    }

    /// Deletes everything HouseCat keeps about the player, then starts again from the intro.
    static func deleteEverything() async {
        // The household in iCloud (when sharing is on), then this phone's save.
        await HouseholdSync.deleteHousehold()
        GameSession.shared.eraseEverything()
        // What the widget reads.
        if let root = WidgetFiles.root {
            try? FileManager.default.removeItem(at: root)
        }
        // Reminders waiting and shown, and a nap on the Lock Screen.
        let notifications = UNUserNotificationCenter.current()
        notifications.removeAllPendingNotificationRequests()
        notifications.removeAllDeliveredNotifications()
        for activity in Activity<NapAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        Naps.shared.forget()
        // The purchase mirror (Restore Purchases brings back what the Apple Account owns).
        KeychainEntitlementCache().clear()
        // Preferences: the App Group's and the app's own.
        UserDefaults(suiteName: WidgetFiles.appGroup)?.removePersistentDomain(forName: WidgetFiles.appGroup)
        if let bundle = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundle)
        }
        NotificationCenter.default.post(name: .houseCatErased, object: nil)
    }
}

/// In the cat's settings: export the save, delete everything, and the credits.
struct YourDataCard: View {
    let catName: String
    let deleted: () -> Void
    @State private var export: URL?
    @State private var problem: String?
    @State private var confirming = false
    @State private var finalCheck = false
    @State private var deleting = false
    @State private var credits = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                PaintedIcon("collection_book", size: 28)
                Text("Your data").font(.headline)
            }
            Text(
                "HouseCat has no account and no server. \(catName)'s home is kept on this phone (and in your iCloud when you share it). You can take a copy or delete it all."
            )
            .font(.subheadline)
            .foregroundStyle(Theme.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if let export {
                    ShareLink(item: export) {
                        Label("Share the copy", systemImage: "square.and.arrow.up").font(.subheadline.weight(.semibold))
                    }
                    .tint(Theme.accent)
                } else {
                    HUDButton("Export my data", symbol: "square.and.arrow.down") {
                        do {
                            export = try YourData.exportFile()
                        } catch {
                            problem = "The copy couldn't be made. Try again in a moment."
                        }
                    }
                }
                HUDButton(deleting ? "Deleting…" : "Delete all my data", symbol: "trash") { confirming = true }
                    .disabled(deleting)
            }
            Button("Licences and credits") { credits = true }
                .font(.subheadline.weight(.semibold))
                .tint(Theme.accent)
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paper(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .confirmationDialog("Delete all of \(catName)'s home?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) { finalCheck = true }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text(
                "\(catName), the home, the Beans, the streak, the book and your settings on this phone go, and the shared home in iCloud if you share it. Purchases stay with your Apple Account: Restore Purchases in the shop brings them back."
            )
        }
        .alert("This can't be undone", isPresented: $finalCheck) {
            Button("Delete", role: .destructive) {
                deleting = true
                Task {
                    await YourData.deleteEverything()
                    deleting = false
                    deleted()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Everything is deleted now and HouseCat starts again from the beginning.")
        }
        .sheet(isPresented: $credits) { CreditsView { credits = false } }
    }
}

/// Licences and credits: the recordings of real cats, Apple Weather, Apple Maps' place search; the paintings are
/// HouseCat's own.
struct CreditsView: View {
    let close: () -> Void

    private struct Sound: Decodable {
        var title: String
        var url: String
        var author: String
        var license: String
    }

    private var sounds: [(name: String, sound: Sound)] {
        guard let url = Bundle.main.url(forResource: "credits_sounds", withExtension: "json", subdirectory: "Content"),
              let data = try? Data(contentsOf: url),
              let all = try? JSONDecoder().decode([String: Sound].self, from: data) else { return [] }
        return all.map { ($0.key, $0.value) }.sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("The cat's voice") {
                    ForEach(sounds, id: \.name) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.sound.title).font(.subheadline)
                            Text("\(item.sound.author) · \(item.sound.license) · Wikimedia Commons").font(.caption)
                                .foregroundStyle(Theme.inkSoft)
                            if let link = URL(string: item.sound.url) {
                                Link("Source", destination: link).font(.caption)
                            }
                        }
                    }
                }
                Section("Weather and places") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Weather: \u{F8FF} Weather").font(.subheadline)
                        Link("Data sources", destination: RealWeather.attribution?.legal ?? Tuning.Store.weatherLegalURL).font(.caption)
                    }
                    Text("Place search: Apple Maps").font(.subheadline)
                }
                Section("Everything else") {
                    Text("The paintings, the room sounds and the game's own effects were made for HouseCat.").font(.subheadline)
                    Link("Terms of Use", destination: Tuning.Store.termsURL)
                    Link("Privacy Policy", destination: Tuning.Store.privacyURL)
                }
            }
            .navigationTitle("Licences and credits")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } }
        }
    }
}
