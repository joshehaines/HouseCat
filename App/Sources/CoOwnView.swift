import CloudKit
import HouseCatCore
import HouseCatUI
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// Sharing the cat with someone (SPEC step 8, co-owning): a one-time invite link to send; whoever opens it
/// looks after the same cat, and either of you visiting keeps the streak. Off until iCloud is set up for the
/// app (HouseholdSync.isEnabled), and the card says so rather than offering a link that cannot work.
struct CoOwnCard: View {
    let catName: String
    @State private var link: URL?
    @State private var making = false
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                PaintedIcon("group_of_three_paw_prints", size: 28)
                Text("Share \(catName)").font(.headline)
            }
            Text(
                "Someone you live with, or love, can look after \(catName) too. You both see the same cat and home, and either of your visits keeps the streak."
            )
            .font(.subheadline).foregroundStyle(Theme.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
            if !HouseholdSync.isEnabled {
                Text("Sharing needs iCloud, which is switched on with the App Store build.")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
            } else if let link {
                ShareLink(
                    item: link,
                    subject: Text("Share \(catName)"),
                    message: Text("Come and look after \(catName) with me in HouseCat.")
                ) {
                    Label("Send the invite", systemImage: "square.and.arrow.up")
                }
                Text("The link works once, for one person.").font(.caption).foregroundStyle(Theme.inkSoft)
            } else {
                HUDButton(making ? "Making the link…" : "Make an invite link", icon: "share_arrow", prominent: true) {
                    Task { await makeLink() }
                }
                .disabled(making)
            }
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paper(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func makeLink() async {
        making = true
        defer { making = false }
        do {
            link = try await HouseholdSync.invite()
        } catch {
            problem = "The invite couldn't be made. Check you're signed in to iCloud, then try again."
        }
    }
}

/// Opening someone's invite on this phone: a name to be known by, then the shared cat.
struct JoinView: View {
    let metadata: CKShare.Metadata
    let done: () -> Void
    @State private var name = ""
    @State private var joining = false
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("You're invited to share a cat").font(Theme.title(26))
            Text("Choose the name the other owner will see. It isn't your Apple Account name, and you can change it later.")
                .font(.subheadline).foregroundStyle(Theme.inkSoft)
            TextField("Your name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                HUDButton("Not now", action: done)
                HUDButton(joining ? "Joining…" : "Join", icon: "house", prominent: true) {
                    Task {
                        joining = true
                        defer { joining = false }
                        do {
                            try await HouseholdSync.accept(metadata, as: name.trimmingCharacters(in: .whitespaces))
                            done()
                        } catch {
                            problem = "That invite couldn't be opened. It may have been used already."
                        }
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || joining)
            }
        }
        .padding(24)
        .frame(maxWidth: 520)
        .paper(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .foregroundStyle(Theme.ink)
    }
}

#if canImport(UIKit)
    /// The system hands an opened invite to the scene; the app shows JoinView for it.
    @MainActor
    @Observable
    final class Invites {
        static let shared = Invites()
        var pending: CKShare.Metadata?
    }

    final class HouseCatAppDelegate: NSObject, UIApplicationDelegate {
        func application(
            _: UIApplication,
            configurationForConnecting session: UISceneSession,
            options _: UIScene.ConnectionOptions
        ) -> UISceneConfiguration {
            let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
            configuration.delegateClass = HouseCatSceneDelegate.self
            return configuration
        }
    }

    final class HouseCatSceneDelegate: NSObject, UIWindowSceneDelegate {
        func windowScene(_: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
            Task { @MainActor in Invites.shared.pending = metadata }
        }
    }
#endif
