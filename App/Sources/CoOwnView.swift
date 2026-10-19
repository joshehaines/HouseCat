import CloudKit
import HouseCatCore
import HouseCatUI
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// Sharing the cat with someone (SPEC step 8, co-owning): a one-time invite link to send; whoever opens it
/// looks after the same cat, and either of you visiting keeps the streak. Once someone has joined, the card shows
/// who and what can be done about it instead (co-owning is for two). Shown only once iCloud is set up for the app
/// (HouseholdSync.isEnabled; SettingsView leaves it out until then).
struct CoOwnCard: View {
    let catName: String
    @State private var link: URL?
    @State private var code: String?
    @State private var typed = ""
    @State private var looking = false
    @State private var making = false
    @State private var problem: String?
    @State private var other = GameSession.shared.otherOwner
    @State private var hidden = HouseholdSync.hidden

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                PaintedIcon("group_of_three_paw_prints", size: 28)
                Text("Share \(catName)").font(.headline)
            }
            if let other {
                SharingControls(catName: catName, other: other, hidden: $hidden) { self.other = GameSession.shared.otherOwner }
            } else {
                invite
            }
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paper(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder private var invite: some View {
        Text(
            "Someone you live with, or love, can look after \(catName) too. You both see the same cat and home, and either of your visits keeps the streak."
        )
        .font(.subheadline).foregroundStyle(Theme.inkSoft)
        .fixedSize(horizontal: false, vertical: true)
        if let link {
            ShareLink(
                item: link,
                subject: Text("Share \(catName)"),
                message: Text("Come and look after \(catName) with me in HouseCat.")
            ) {
                Label("Send the invite", systemImage: "square.and.arrow.up")
            }
            Text("The link works once, for one person.").font(.caption).foregroundStyle(Theme.inkSoft)
            if let code {
                // Finch's friend code: read it out, or type it on the other phone.
                HStack(spacing: 8) {
                    Text("Or give them this code:").font(.subheadline)
                    Text(FriendCode.display(code))
                        .font(.system(size: 20, weight: .heavy, design: .monospaced))
                        .textSelection(.enabled)
                }
                Text("It works for \(Tuning.Coop.friendCodeHours / 24) days.").font(.caption).foregroundStyle(Theme.inkSoft)
            }
        } else {
            HUDButton(making ? "Making the link…" : "Make an invite link", icon: "share_arrow", prominent: true) {
                Task { await makeLink() }
            }
            .disabled(making)
        }
        // Someone gave you a code.
        HStack(spacing: 8) {
            TextField("Have a friend code?", text: $typed)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .frame(maxWidth: 200)
            HUDButton(looking ? "Looking…" : "Join") {
                Task { await join() }
            }
            .disabled(FriendCode.normalised(typed) == nil || looking)
        }
    }

    private func makeLink() async {
        making = true
        defer { making = false }
        do {
            let url = try await HouseholdSync.invite()
            link = url
            code = try? await HouseholdSync.friendCode(for: url)
        } catch {
            problem = "The invite couldn't be made. Check you're signed in to iCloud, then try again."
        }
    }

    /// A friend code typed in: the invite it stands for opens the usual join screen.
    private func join() async {
        looking = true
        defer { looking = false }
        do {
            Invites.shared.pending = try await HouseholdSync.invite(forCode: typed)
        } catch {
            problem = "That code didn't work. Codes last \(Tuning.Coop.friendCodeHours / 24) days; ask for a new one."
        }
    }
}

/// Who else looks after the cat, and what this phone can do about them (App Review 1.2; CLAUDE.md "Leaving and
/// removing"): hide their name here, report them to safety@, and stop sharing (the owner) or leave (a co-owner).
/// In the Together card, and in Settings' sharing card once someone has joined.
struct SharingControls: View {
    let catName: String
    /// The other owner's actor key ("co:Sam", or "owner" seen from a co-owner's phone).
    let other: String
    /// Who is hidden on this phone (`HouseholdSync.hidden`), shared with the card around so its names follow.
    @Binding var hidden: Set<String>
    /// The household changed (sharing stopped): whoever shows this closes or redraws.
    let changed: () -> Void
    @State private var confirming = false
    @State private var working = false
    /// The cat waiting on this device, read when Leave is pressed (it means reading the set-aside save).
    @State private var waitingCat: String?

    private var isCoOwner: Bool {
        HouseholdSync.isCoOwner
    }

    /// A co-owner has a name they chose; the owner, seen from a co-owner's phone, has none.
    private var hasName: Bool {
        other.hasPrefix("co:")
    }

    private var realName: String {
        OwnerName.display(other, otherwise: "\(catName)'s owner")
    }

    private var shown: String {
        OwnerName.display(other, otherwise: isCoOwner ? "\(catName)'s owner" : "\(catName)'s other owner", hidden: hidden)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isCoOwner ? "\(catName) is shared with you by \(shown)." : "You share \(catName) with \(shown).")
                .font(.subheadline.weight(.semibold))
            if hidden.contains(other) {
                Text("Their name, paw prints and presents aren't shown on this device.")
                    .font(.caption).foregroundStyle(Theme.inkSoft)
            }
            HStack(spacing: 10) {
                if hasName {
                    HUDButton(hidden.contains(other) ? "Show their name" : "Hide \(realName)", symbol: "eye.slash") {
                        hidden.formSymmetricDifference([other])
                        HouseholdSync.hidden = hidden
                    }
                }
                ReportButton(about: hasName ? [.name, .catName, .present, .other] : [.catName, .present, .other], reported: hasName ? realName : "\(catName)'s owner", catName: catName)
                HUDButton(working ? "One moment…" : isCoOwner ? "Leave" : "Stop sharing", symbol: isCoOwner ? "rectangle.portrait.and.arrow.right" : "person.badge.minus") {
                    if isCoOwner {
                        waitingCat = GameSession.shared.setAsideCatName
                    }
                    confirming = true
                }
                .disabled(working)
            }
        }
        .confirmationDialog(isCoOwner ? "Leave \(catName)'s home?" : "Stop sharing \(catName)?", isPresented: $confirming, titleVisibility: .visible) {
            Button(isCoOwner ? "Leave" : "Stop sharing", role: .destructive) {
                working = true
                Task {
                    if isCoOwner {
                        await HouseholdSync.leave()
                    } else {
                        await HouseholdSync.stopSharing()
                    }
                    working = false
                    changed()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmation)
        }
    }

    private var confirmation: String {
        if isCoOwner {
            let own = waitingCat.map { "\($0) comes back to this device." } ?? "You can adopt a cat of your own."
            return "\(catName) stays with \(shown). The Beans you earned or bought while sharing, and the presents you gave, stay in \(catName)'s home. \(own)"
        }
        return "\(shown) can't visit \(catName) any more, and invite links not yet used stop working. \(catName), the home, the streak and the Beans stay with you, and the visits \(shown) made still count."
    }
}

/// Reporting the other owner (App Review 1.2): the person picks what it is about, and their mail app opens with a
/// message to safety@ already filled in (the household's reference, who, the cat). With no mail app, the address
/// is shown to copy.
struct ReportButton: View {
    let about: [SafetyReport.About]
    /// The other owner as named in the report (their real name, even if hidden here).
    let reported: String
    let catName: String
    var present: String?
    var compact = false
    @State private var asking = false
    @State private var noMail = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if compact {
                Button("Report") { asking = true }
                    .font(.subheadline.weight(.semibold))
                    .tint(Theme.accent)
            } else {
                HUDButton("Report", symbol: "flag") { asking = true }
            }
        }
        .confirmationDialog("What would you like to report?", isPresented: $asking, titleVisibility: .visible) {
            ForEach(about, id: \.self) { kind in
                Button(Self.label(kind, reported: reported)) { send(kind) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your mail app opens with a message to HouseCat's safety team, with this household's reference filled in. We read every report.")
        }
        .alert("Email \(Tuning.Store.safetyEmail)", isPresented: $noMail) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("There's no mail app set up on this device. Write to \(Tuning.Store.safetyEmail) and include this reference: \(GameSession.shared.householdReference.replacingOccurrences(of: "-", with: "\u{2011}")).")
        }
    }

    private static func label(_ kind: SafetyReport.About, reported: String) -> String {
        switch kind {
        case .name: "\(reported)'s name"
        case .catName: "The cat's name"
        case .present: "A present"
        case .other: "Something else"
        }
    }

    private func send(_ kind: SafetyReport.About) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let report = SafetyReport(
            about: kind,
            reported: reported,
            catName: catName,
            household: GameSession.shared.householdReference,
            present: kind == .present ? present : nil,
            appVersion: version
        )
        guard let url = report.mailto() else {
            noMail = true
            return
        }
        openURL(url) { accepted in
            if !accepted {
                noMail = true
            }
        }
    }
}

/// Opening someone's invite on this phone: a name to be known by, then the shared cat. The name can't be
/// changed later (it is how the household tells its owners apart), and the card doesn't say it can.
struct JoinView: View {
    let join: (String) async throws -> Void
    let done: () -> Void
    @State private var name = ""
    @State private var joining = false
    @State private var problem: String?
    private let blocked = HouseholdSync.joinBlocked
    private let ownCat = GameSession.shared.cat?.name

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("You're invited to share a cat").font(Theme.title(26))
            if let blocked {
                Text(blocked).font(.subheadline).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    HUDButton("OK", action: done)
                }
            } else {
                Text("Choose the name the other owner will see. It isn't your Apple Account name.")
                    .font(.subheadline).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                if let ownCat {
                    Text("\(ownCat) waits on this device and comes back if you leave, though \(ownCat)'s streak won't keep going while you're away.")
                        .font(.subheadline).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                TextField("Your name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                    .onChange(of: name) { _, typed in
                        // The cap as you type, as the builder's name field has it.
                        if typed.count > Tuning.Cat.nameMaxLength {
                            name = String(typed.prefix(Tuning.Cat.nameMaxLength))
                        }
                    }
                if let problem {
                    Text(problem).font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    HUDButton("Not now", action: done)
                    HUDButton(joining ? "Joining…" : "Join", icon: "house", prominent: true) {
                        Task { await accept() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || joining)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 520)
        .paper(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .foregroundStyle(Theme.ink)
    }

    private func accept() async {
        joining = true
        defer { joining = false }
        // The other owner sees this name: through the same word filter and length as a cat's.
        let checked: String
        switch CatNames.check(name, filter: GameWorld.content?.names ?? NameFilter()) {
        case let .ok(name): checked = name
        case .empty: return
        case .tooLong:
            problem = "Up to \(Tuning.Cat.nameMaxLength) characters."
            return
        case .blocked:
            problem = "Try another name."
            return
        }
        do {
            try await join(checked)
            done()
        } catch {
            problem = "That invite couldn't be opened. It may have been used already."
        }
    }
}

/// What happened to the household, said once over the new first screen (left, or the owner stopped sharing).
struct SharingNotice: View {
    let text: String
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                PaintedIcon("group_of_three_paw_prints", size: 32)
                Text("Sharing has ended").font(Theme.title(24))
            }
            Text(text).font(.subheadline).foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                ChunkyButton("OK", action: close)
            }
        }
        .padding(24)
        .frame(maxWidth: 460)
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
        /// Debug: HOUSECAT_SCREEN=join shows the join card for a made-up household (`HouseholdSync.debugJoin`).
        var debugJoin = false
        /// Said once after the household changed (`SharingNotice`).
        var notice: String?
    }

    final class HouseCatAppDelegate: NSObject, UIApplicationDelegate {
        /// The Watch link starts at launch, so a tap on the Watch can wake the app in the background.
        func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
            WatchLink.shared.start()
            return true
        }

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
            // Never while sharing is off (nothing about it is shown then).
            guard HouseholdSync.isEnabled else { return }
            Task { @MainActor in Invites.shared.pending = metadata }
        }
    }
#endif
