import HouseCatCore
import SwiftUI

/// The profile's three tabs (`CatProfileView`): About, Wardrobe and Stats.
extension CatProfileView {
    // MARK: About

    var about: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Side by side, one above the other at the larger text sizes.
            if typeSize < .xxLarge {
                HStack(alignment: .top, spacing: 8) {
                    trustMeter
                    levelMeter
                }
            } else {
                VStack(spacing: 8) {
                    trustMeter
                    levelMeter
                }
            }
            if let contentment = profile.contentment {
                HStack(spacing: 8) {
                    PaintedIcon("trust_heart_with_a_paw_print", size: 26)
                    let wish = profile.wouldLove.map { " Would love \($0.phrase) at home." } ?? ""
                    Text("\(Text("\(profile.name) \(contentment.phrase).").bold())\(wish)")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(GameHUD.green.opacity(0.14)))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(GameHUD.green.opacity(0.3), lineWidth: 1))
                .accessibilityElement(children: .combine)
            }
            // Where home is, and moving it (Josh, 19 Oct: "no option for the user to move house").
            if let home, let moveHouse {
                HStack(spacing: 10) {
                    PaintedIcon("house", size: 30)
                    Text(home)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button {
                        feedback.tap()
                        moveHouse()
                    } label: {
                        Text("Move house")
                            .font(.system(.footnote, design: .rounded, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Theme.accent))
                    }
                    .buttonStyle(PressStyle())
                }
                .padding(10)
                .paper(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            if !ways.isEmpty {
                section("\(profile.name)'s ways")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                    ForEach(ways) { way in
                        VStack(spacing: 5) {
                            PaintedIcon(way.icon, size: 42)
                            Text(way.text)
                                .font(.system(.footnote, weight: .semibold))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 5)
                        .padding(.top, 8)
                        .padding(.bottom, 6)
                        .frame(maxWidth: .infinity, minHeight: 96)
                        .paper(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            section("Personality", note: ProfileText.personalityBlurb(profile.personality))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 7)], spacing: 7) {
                ForEach(Personality.allCases, id: \.self) { personality in
                    let chosen = personality == profile.personality
                    Button {
                        feedback.tap()
                        setPersonality(personality)
                    } label: {
                        HStack(spacing: 5) {
                            PaintedIcon(CatBuilderDrawer.icon(personality), size: 24)
                            Text(ProfileText.personality(personality))
                                .font(.system(.subheadline, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 6)
                        .paper(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Theme.accent, lineWidth: chosen ? 2.5 : 0)
                        )
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityAddTraits(chosen ? [.isSelected, .isButton] : .isButton)
                }
            }
        }
    }

    /// Trust: the tier, a pip for each of the seven, how many breakfasts to the next.
    private var trustMeter: some View {
        meter(icon: "trust_heart_with_a_paw_print", caption: "Trust", value: ProfileText.trust(profile.trust)) {
            HStack(spacing: 3) {
                ForEach(TrustTier.allCases, id: \.self) { tier in
                    Capsule()
                        .fill(tier <= profile.trust
                            ? AnyShapeStyle(LinearGradient(
                                colors: [Color(red: 0.95, green: 0.48, blue: 0.42), Color(red: 0.85, green: 0.31, blue: 0.27)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            : AnyShapeStyle(Theme.ink.opacity(0.12)))
                        .frame(height: 7)
                }
            }
            if let next = profile.careDaysToNextTier, let tier = TrustTier(rawValue: profile.trust.rawValue + 1) {
                Text("\(next) more \(next == 1 ? "day" : "days") of breakfast to \(ProfileText.trust(tier))")
            } else {
                Text("As close as a cat can be")
            }
        }
    }

    /// The level: its title, the XP bar and what is left to the next.
    private var levelMeter: some View {
        meter(icon: "xp_star", caption: levelTitle ?? "Level", value: "Level \(level.level)") {
            let fraction = Double(level.intoLevel) / Double(max(1, level.intoLevel + level.toNext))
            Capsule().fill(Theme.ink.opacity(0.12))
                .frame(height: 8)
                .overlay(alignment: .leading) {
                    GeometryReader { bar in
                        Capsule()
                            .fill(LinearGradient(colors: [GameHUD.gold, GameHUD.deepGold], startPoint: .top, endPoint: .bottom))
                            .frame(width: bar.size.width * max(0.06, min(1, fraction)))
                    }
                }
            Text("\(level.toNext) XP to level \(level.level + 1)")
        }
    }

    private func meter(icon: String, caption: String, value: String, @ViewBuilder detail: () -> some View) -> some View {
        HStack(spacing: 8) {
            PaintedIcon(icon, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(caption.uppercased())
                    .font(.system(.caption2, design: .rounded, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
                Text(value)
                    .font(.system(.title3, design: .serif, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                VStack(alignment: .leading, spacing: 3) {
                    detail()
                }
                .font(.caption2)
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 2)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.rim, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func section(_ title: String, note: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).font(.system(.headline, design: .serif, weight: .bold)).accessibilityAddTraits(.isHeader)
            if let note {
                Text(note).font(.caption).foregroundStyle(Theme.inkSoft).lineLimit(2)
            }
        }
        .padding(.top, 4)
        .padding(.horizontal, 2)
    }

    /// Its ways, each with its picture: the favourite spot, the quirks and its hours.
    private var ways: [WayIcon.Way] {
        guard let identity = profile.identity else {
            return profile.ways.map { WayIcon.Way(icon: "cat_face", text: $0) }
        }
        return [WayIcon.Way(icon: WayIcon.spot(identity.favouriteSpot), text: identity.favouriteSpot.phrase)]
            + identity.quirks.map { WayIcon.Way(icon: WayIcon.quirk($0), text: $0.phrase) }
            + [WayIcon.Way(icon: WayIcon.hours(identity.hours), text: identity.hours.phrase)]
    }

    // MARK: Wardrobe

    /// The outfits the cat can wear: tap one to put it on, tap it again (or Take off) to take it off.
    var wardrobeView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                section(
                    wardrobe.count == 1 ? "1 outfit" : "\(wardrobe.count) outfits",
                    note: wardrobe.isEmpty ? nil : "Tap one to put it on"
                )
                Spacer(minLength: 6)
                if worn != nil {
                    Button {
                        feedback.tap()
                        wear?(nil)
                    } label: {
                        Text("Take off")
                            .font(.system(.footnote, design: .rounded, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Theme.accent))
                    }
                    .buttonStyle(PressStyle())
                }
            }
            if wardrobe.isEmpty {
                HStack(spacing: 10) {
                    PaintedIcon("creator_hanger", size: 40)
                    Text("No outfits yet. Hats, glasses and scarves come from the shop, the season pass and presents.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .paper(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 12) {
                    ForEach(wardrobe) { item in
                        let chosen = item.id == worn
                        Button {
                            feedback.tap()
                            wear?(chosen ? nil : item.id)
                        } label: {
                            VStack(spacing: 3) {
                                Group {
                                    if let image = item.image {
                                        Image(decorative: image, scale: 1).resizable().interpolation(.high).scaledToFit()
                                    } else {
                                        Image(systemName: "tshirt").resizable().scaledToFit().padding(12)
                                    }
                                }
                                .frame(width: 64, height: 54)
                                .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
                                Text(item.name)
                                    .font(.system(.caption, weight: .bold))
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.8)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, minHeight: 96)
                            .paper(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(
                                Theme.accent,
                                lineWidth: chosen ? 3 : 0
                            ))
                            .overlay(alignment: .top) {
                                if chosen {
                                    Ribbon("Wearing", colour: Theme.accent).scaleEffect(0.8).offset(y: -10)
                                }
                            }
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel(item.name + (chosen ? ", wearing" : ""))
                        .accessibilityAddTraits(chosen ? [.isSelected, .isButton] : .isButton)
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    // MARK: Stats

    var stats: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                stat("Days together", profile.togetherDays, icon: "calendar")
                stat("Visits", profile.visits, icon: "house")
                stat("Meals", profile.meals, icon: "feed_bowl")
                stat("Pets", profile.pets, icon: "petting_hand")
                stat("Gifts found", profile.giftsFound, icon: "gift_box_with_a_ribbon")
                stat("Rooms opened", profile.roomsOpened, icon: "sofa_for_furniture")
                stat("Streak", profile.currentStreak, icon: "streak_paw_print_with_a_small_flame")
                stat("Longest streak", profile.longestStreak, icon: "level_up_arrow")
            }
            if !profile.badges.isEmpty {
                section("Badges")
                HStack(spacing: 8) {
                    ForEach(profile.badges, id: \.self) { badge in
                        HStack(spacing: 5) {
                            PaintedIcon("xp_star", size: 22)
                            Text(ProfileText.badge(badge)).font(.system(.footnote, design: .rounded, weight: .heavy))
                        }
                        .foregroundStyle(Color(red: 0.42, green: 0.26, blue: 0.06))
                        .padding(.leading, 6)
                        .padding(.trailing, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(LinearGradient(
                            colors: [Color(red: 1, green: 0.9, blue: 0.6), Color(red: 0.95, green: 0.75, blue: 0.31)],
                            startPoint: .top,
                            endPoint: .bottom
                        )))
                        .overlay(Capsule().strokeBorder(Color(red: 0.78, green: 0.56, blue: 0.12), lineWidth: 1))
                    }
                }
            }
        }
    }

    private func stat(_ title: String, _ value: Int, icon: String) -> some View {
        VStack(spacing: 2) {
            PaintedIcon(icon, size: 32)
            Text(value.formatted())
                .font(.system(.title3, design: .rounded, weight: .heavy))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 92)
        .paper(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The painted picture for each of a cat's ways (assets/ui/icon_way_*.png, 19 Oct).
enum WayIcon {
    struct Way: Identifiable {
        let icon: String
        let text: String
        var id: String {
            text
        }
    }

    static func spot(_ spot: CatIdentity.Spot) -> String {
        switch spot {
        case .high: "way_cat_tree"
        case .soft: "way_cushion"
        case .hidden: "way_box"
        case .sunny: "way_sun"
        case .window: "way_window"
        case .nearYou: "way_slippers"
        }
    }

    static func quirk(_ quirk: CatIdentity.Quirk) -> String {
        switch quirk {
        case .chattersAtBirds: "way_robin"
        case .tuckedLoaf: "way_loaf"
        case .followsYou: "group_of_three_paw_prints"
        case .lovesBoxes: "way_box"
        case .sunWorshipper: "way_sun"
        case .chatty: "way_chatter"
        case .curlsTight: "way_bun"
        }
    }

    static func hours(_ hours: CatIdentity.Hours) -> String {
        switch hours {
        case .morning: "way_sunrise"
        case .nightOwl: "way_owl"
        }
    }
}
