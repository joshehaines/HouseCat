import CoreGraphics
import HouseCatCore
import SwiftUI

/// The words the profile and builder use for the cat's numbers and nature.
public enum ProfileText {
    public static func personality(_ p: Personality) -> String {
        switch p {
        case .aloof: "Aloof"
        case .velcro: "Velcro"
        case .gremlin: "Gremlin"
        case .loaf: "Loaf"
        }
    }

    public static func personalityBlurb(_ p: Personality) -> String {
        switch p {
        case .aloof: "Fond of you, on its own terms."
        case .velcro: "Never more than a metre away."
        case .gremlin: "Chaos first, then a nap."
        case .loaf: "Asleep, mostly. Beautifully."
        }
    }

    public static func trust(_ tier: TrustTier) -> String {
        switch tier {
        case .newcomer: "New here"
        case .wary: "Wary"
        case .curious: "Curious"
        case .comfortable: "Comfortable"
        case .bonded: "Bonded"
        case .devoted: "Devoted"
        case .soulmate: "Soulmate"
        }
    }

    /// "Together 43 days", "Together 1 year, 12 days".
    public static func together(_ days: Int) -> String {
        if days == 0 {
            return "Together since today"
        }
        let years = days / 365, rest = days % 365
        guard years > 0 else {
            return "Together \(days) \(days == 1 ? "day" : "days")"
        }
        let y = "\(years) \(years == 1 ? "year" : "years")"
        return rest == 0 ? "Together \(y)" : "Together \(y), \(rest) \(rest == 1 ? "day" : "days")"
    }

    /// "14 weeks old", "5 months old", "2 years, 3 months old".
    public static func age(_ days: Int) -> String {
        let years = days / 365, months = (days % 365) / 30
        if years == 0 {
            if days < 26 * 7 {
                let weeks = days / 7
                return "\(weeks) \(weeks == 1 ? "week" : "weeks") old"
            }
            return "\(months) \(months == 1 ? "month" : "months") old"
        }
        let y = "\(years) \(years == 1 ? "year" : "years")"
        return months == 0 ? "\(y) old" : "\(y), \(months) \(months == 1 ? "month" : "months") old"
    }

    public static func badge(_ badge: CatProfile.Badge) -> String {
        switch badge {
        case .hundredDays: "100 days"
        case let .years(n): n == 1 ? "1 year" : "\(n) years"
        }
    }
}

/// The cat's profile (SPEC "Age and time together"): its picture, how long you have had it and its age,
/// its trust, badges and lifetime stats; Edit look, Rename and Personality change it again, free.
public struct CatProfileView: View {
    private let profile: CatProfile
    private let portrait: CGImage?
    private let level: (level: Int, intoLevel: Int, toNext: Int)
    private let editLook: () -> Void
    private let rename: (String) -> String?
    private let setPersonality: (Personality) -> Void
    private let close: () -> Void
    @State private var naming = false
    @State private var newName = ""
    @State private var nameProblem: String?

    /// `rename` returns a problem with the name, or nil when it was taken.
    public init(
        profile: CatProfile,
        portrait: CGImage?,
        xp: Int,
        editLook: @escaping () -> Void,
        rename: @escaping (String) -> String?,
        setPersonality: @escaping (Personality) -> Void,
        close: @escaping () -> Void
    ) {
        self.profile = profile
        self.portrait = portrait
        level = LevelCurve.progress(xp: xp)
        self.editLook = editLook
        self.rename = rename
        self.setPersonality = setPersonality
        self.close = close
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(spacing: 10) {
                Group {
                    if let portrait {
                        Image(decorative: portrait, scale: 1).resizable().scaledToFit()
                    } else {
                        Image(systemName: "cat").resizable().scaledToFit().padding(30)
                    }
                }
                .frame(maxHeight: 220)
                Button("Edit look", systemImage: "paintbrush", action: editLook)
                    .buttonStyle(.bordered)
            }
            .frame(width: 220)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    trust
                    if !profile.badges.isEmpty {
                        HStack {
                            ForEach(profile.badges, id: \.self) { badge in
                                Label(ProfileText.badge(badge), systemImage: "rosette")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(.yellow.opacity(0.25), in: Capsule())
                            }
                        }
                    }
                    stats
                    personality
                }
                .padding(.vertical, 8)
            }
        }
        .padding(24)
        .overlay(alignment: .topTrailing) {
            Button(action: close) {
                Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(14)
            .accessibilityLabel("Close")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if naming {
                    TextField("Name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .font(.title2)
                        .onSubmit(commitName)
                    Button("Save", action: commitName).buttonStyle(.borderedProminent)
                } else {
                    Text(profile.name).font(.largeTitle.weight(.bold))
                    Button {
                        newName = profile.name
                        naming = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("Rename")
                }
            }
            if let nameProblem {
                Text(nameProblem).font(.footnote).foregroundStyle(.red)
            }
            Text(ProfileText.together(profile.togetherDays)).font(.title3.weight(.semibold))
            Text((profile.isKitten ? "Kitten, " : "") + ProfileText.age(profile.ageDays) + " · " + ProfileText
                .personality(profile.personality))
                .foregroundStyle(.secondary)
        }
    }

    private func commitName() {
        nameProblem = rename(newName)
        if nameProblem == nil {
            naming = false
        }
    }

    private var trust: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Trust: \(ProfileText.trust(profile.trust))").font(.headline)
                Spacer()
                Text("Level \(level.level)").font(.headline)
            }
            if let next = profile.careDaysToNextTier, let tier = TrustTier(rawValue: profile.trust.rawValue + 1) {
                Text("\(next) more \(next == 1 ? "day" : "days") of breakfast to \(ProfileText.trust(tier)).")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(level.intoLevel), total: Double(max(1, level.intoLevel + level.toNext)))
            Text("\(level.toNext) XP to level \(level.level + 1)").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var stats: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
            stat("Days together", profile.togetherDays)
            stat("Visits", profile.visits)
            stat("Meals", profile.meals)
            stat("Pets", profile.pets)
            stat("Gifts found", profile.giftsFound)
            stat("Rooms opened", profile.roomsOpened)
            stat("Streak", profile.currentStreak)
            stat("Longest streak", profile.longestStreak)
        }
    }

    private func stat(_ title: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.title2.weight(.bold)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private var personality: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Personality").font(.headline)
            Picker("Personality", selection: Binding(get: { profile.personality }, set: setPersonality)) {
                ForEach(Personality.allCases, id: \.self) { p in
                    Text(ProfileText.personality(p)).tag(p)
                }
            }
            .pickerStyle(.segmented)
            Text(ProfileText.personalityBlurb(profile.personality)).font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// The collection book (SPEC "Gifts"): every gift the cat can bring, found ones in colour with their count.
public struct GiftBookView: View {
    public struct Entry: Identifiable {
        public var id: String
        public var name: String
        public var description: String
        public var rarity: GiftRarity
        public var count: Int
        public var image: CGImage?

        public init(id: String, name: String, description: String, rarity: GiftRarity, count: Int, image: CGImage?) {
            self.id = id
            self.name = name
            self.description = description
            self.rarity = rarity
            self.count = count
            self.image = image
        }
    }

    private let entries: [Entry]
    private let close: () -> Void
    @State private var chosen: String?

    public init(entries: [Entry], close: @escaping () -> Void) {
        self.entries = entries
        self.close = close
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("The book").font(.largeTitle.weight(.bold))
                Text("\(entries.filter { $0.count > 0 }.count) of \(entries.count) found").foregroundStyle(.secondary)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            if let entry = entries.first(where: { $0.id == chosen }), entry.count > 0 {
                HStack {
                    Text(entry.name).font(.headline)
                    Text(entry.description).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 10) {
                    ForEach(entries) { entry in
                        Button {
                            chosen = entry.id
                        } label: {
                            VStack(spacing: 2) {
                                Group {
                                    if let image = entry.image {
                                        Image(decorative: image, scale: 1).resizable().scaledToFit()
                                    } else {
                                        Image(systemName: "gift").resizable().scaledToFit().padding(14)
                                    }
                                }
                                .frame(width: 64, height: 64)
                                .saturation(entry.count > 0 ? 1 : 0)
                                .brightness(entry.count > 0 ? 0 : -0.6)
                                .opacity(entry.count > 0 ? 1 : 0.35)
                                Text(entry.count > 0 ? entry.name : "?").font(.caption2).lineLimit(1)
                                if entry.count > 1 {
                                    Text("×\(entry.count)").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 84, height: 100)
                            .background(
                                rarityColour(entry.rarity).opacity(entry.count > 0 ? 0.18 : 0.06),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(24)
    }

    private func rarityColour(_ rarity: GiftRarity) -> Color {
        switch rarity {
        case .common: .gray
        case .uncommon: .green
        case .rare: .blue
        case .legendary: .orange
        }
    }
}
