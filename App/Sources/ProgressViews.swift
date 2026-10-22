import HouseCatCore
import HouseCatUI
import SwiftUI

/// A piece's name and picture from the catalogue, for the level and pass cards.
@MainActor
enum Pieces {
    static func item(_ id: String) -> CatalogueFile.Item? {
        GameWorld.content?.catalogue.items.first { $0.id == id }
    }

    static func picture(_ id: String) -> Image? {
        guard let item = item(id), let sprite = item.sprites["R"] ?? item.sprites.values.first else { return nil }
        return CatScreens.picture(sprite)
    }

    static func roomName(_ room: RoomID) -> String {
        Visit.title(of: room, upstairs: false)
    }
}

/// "+12 XP" rising from the level and fading, each time XP is earned.
struct XPFloat: View {
    let amount: Int
    @State private var risen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 3) {
            PaintedIcon("xp_star", size: 18)
            Text("+\(amount) XP").font(.system(size: 15, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .paper(Capsule())
        .offset(y: risen || reduceMotion ? 0 : 14)
        .opacity(risen ? 1 : 0)
        .onAppear { withAnimation(.spring(duration: 0.45, bounce: 0.4)) { risen = true } }
        .accessibilityLabel("\(amount) XP earned")
    }
}

/// A level reached (Josh, 18 Oct; a builder game's level-up): the number over a sunburst, its title, everything
/// it brought (Beans, a piece, rooms that can open, pieces now in the Bean shop) and the next room to aim for.
struct LevelUpCard: View {
    let stop: RoadmapStop
    let next: (level: Int, room: RoomID)?
    let road: () -> Void
    let close: () -> Void
    @State private var shown = false

    var body: some View {
        VStack(spacing: 9) {
            ZStack {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 92))
                    .foregroundStyle(Color(red: 1, green: 0.86, blue: 0.5).opacity(0.5))
                    .rotationEffect(.degrees(shown ? 30 : 0))
                VStack(spacing: 0) {
                    Text("LEVEL").font(.system(size: 14, weight: .heavy, design: .rounded)).tracking(2).foregroundStyle(Theme.inkSoft)
                    Text("\(stop.level)").font(Theme.title(52)).foregroundStyle(Theme.accent)
                }
                .scaleEffect(shown ? 1 : 0.4)
            }
            .frame(height: 92)
            Text(stop.title).font(Theme.title(22))
            HStack(alignment: .top, spacing: 12) {
                reward(icon: "bean_coin", title: "+\(stop.beans) Beans", detail: nil)
                if let gift = stop.gift, let item = Pieces.item(gift) {
                    reward(picture: Pieces.picture(gift), title: item.name, detail: "In your things")
                }
                ForEach(stop.rooms, id: \.self) { room in
                    reward(icon: "house", title: "The \(Pieces.roomName(room).lowercased())", detail: "Can open now")
                }
                if !stop.pieces.isEmpty {
                    reward(icon: "sofa_for_furniture", title: "\(stop.pieces.count) new pieces", detail: "In the Bean shop")
                }
            }
            if let next {
                Text("Next room: the \(Pieces.roomName(next.room).lowercased()) at level \(next.level).")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            HStack(spacing: 10) {
                HUDButton("The road ahead", icon: "xp_star", action: road)
                ChunkyButton("Lovely", action: close)
            }
        }
        .padding(18)
        .frame(maxWidth: 560)
        .paper(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .foregroundStyle(Theme.ink)
        .onAppear { withAnimation(.spring(duration: 0.6, bounce: 0.45)) { shown = true } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Level \(stop.level), \(stop.title)")
    }

    private func reward(icon: String? = nil, picture: Image? = nil, title: String, detail: String?) -> some View {
        VStack(spacing: 4) {
            Group {
                if let picture {
                    picture.resizable().interpolation(.high).scaledToFit()
                } else if let icon {
                    PaintedIcon(icon, size: 44)
                }
            }
            .frame(width: 64, height: 50)
            Text(title).font(.caption.weight(.bold)).multilineTextAlignment(.center).lineLimit(2)
            if let detail {
                Text(detail).font(.caption2).foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(width: 96)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.cream))
    }
}

/// The road ahead (Josh, 18 Oct: show what each level opens, so the gate is a goal): the level and its XP bar,
/// then the next levels side by side, each with its Beans, piece, rooms and new shop pieces; the next level that
/// opens a room is marked.
struct RoadmapView: View {
    let info: GameSession.LevelInfo
    let stops: [RoadmapStop]
    let close: () -> Void

    private var nextRoom: Int? {
        LevelRoadmap.nextRoomLevel(after: info.level)?.level
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Level \(info.level) · \(info.title)").font(Theme.title(24))
                    ProgressView(value: Double(info.intoLevel), total: Double(max(1, info.intoLevel + info.toNext)))
                        .tint(Theme.accent)
                        .frame(width: 260)
                    Text("\(info.toNext) XP to level \(info.level + 1). XP comes from feeding, stroking, playing, gifts and each day's visit.")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                CloseButton(action: close)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(stops) { stop in
                        stopCard(stop, isNextRoom: stop.level == nextRoom)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 2)
            }
        }
        .padding(20)
        .frame(maxWidth: 760)
        .paper(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .foregroundStyle(Theme.ink)
    }

    private func stopCard(_ stop: RoadmapStop, isNextRoom: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Level \(stop.level)").font(.system(size: 17, weight: .heavy, design: .rounded))
            Text(stop.title).font(.caption).foregroundStyle(Theme.inkSoft).lineLimit(1)
            line("bean_coin", "+\(stop.beans) Beans")
            if let gift = stop.gift, let item = Pieces.item(gift) {
                HStack(spacing: 4) {
                    Pieces.picture(gift).map { $0.resizable().interpolation(.high).scaledToFit().frame(width: 24, height: 22) }
                    Text(item.name).font(.caption.weight(.semibold)).lineLimit(1)
                }
            }
            ForEach(stop.rooms, id: \.self) { room in
                line("house", "The \(Pieces.roomName(room).lowercased())")
            }
            if !stop.pieces.isEmpty {
                line("sofa_for_furniture", "\(stop.pieces.count) shop pieces")
            }
            Spacer(minLength: 0)
            Text("\(stop.xp.formatted()) XP").font(.caption2).foregroundStyle(Theme.inkSoft)
        }
        .padding(10)
        .frame(width: 136, height: 178, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(isNextRoom ? Theme.accent.opacity(0.14) : Theme.cream))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(isNextRoom ? Theme.accent : Theme.rim, lineWidth: isNextRoom ? 2.5 : 1))
        .overlay(alignment: .top) {
            if isNextRoom {
                Ribbon("Next room").scaleEffect(0.78).offset(y: -11)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func line(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            PaintedIcon(icon, size: 18)
            Text(text).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}

/// The streak (Josh, 18 Oct: gentle streaks, Finch's repair and Alma's vacation mode): the run and the best, a
/// broken run mended by a day of care within a few days (never bought), and a holiday that pauses it.
struct StreakCard: View {
    let catName: String
    let close: () -> Void
    @State private var info = GameSession.shared.streakInfo
    @State private var pauseDays = 7
    @Environment(\.controlFeedback) private var feedback

    var body: some View {
        // Duolingo-sized (Josh, 22 Oct: "lets make the streak a bigger deal, think how Duolingo does their streaks"):
        // the flame and the number big, the week's days lit, the next milestone and what it pays, then the safety nets.
        PaintedPanel(corner: 24) {
            PanelHeader("Your streak", subtitle: "Best: \(days(info.longest))", icon: "streak_paw_print_with_a_small_flame", close: close)
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    hero
                    weekStrip
                    if let next = info.nextMilestone {
                        milestone(next)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "shield.lefthalf.filled").foregroundStyle(Color(red: 0.3, green: 0.55, blue: 0.85))
                        Text(info.graceUsed ? "This week's free miss is used." : "One missed day a week is forgiven.")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    if info.repairable > 0, info.repairUntil != nil {
                        repair
                    }
                    holiday
                }
                .padding(18)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: 560)
        .containerRelativeFrame(.vertical) { height, _ in min(height - 48, 620) }
        .foregroundStyle(Theme.ink)
    }

    private func days(_ n: Int) -> String {
        n == 1 ? "1 day" : "\(n) days"
    }

    /// The flame and the run, as big as Duolingo makes them.
    private var hero: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(RadialGradient(colors: [GameHUD.gold.opacity(0.55), .clear], center: .center, startRadius: 4, endRadius: 60))
                    .frame(width: 120, height: 120)
                PaintedIcon("streak_paw_print_with_a_small_flame", size: 84)
                    .grayscale(info.current == 0 ? 1 : 0)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(info.current)")
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [GameHUD.gold, Theme.accent], startPoint: .top, endPoint: .bottom))
                    .shadow(color: Theme.accent.opacity(0.3), radius: 0, y: 3)
                    .contentTransition(.numericText())
                Text(info.current == 1 ? "day streak" : "day streak").font(Theme.title(20))
                Text(info.visitedToday ? "\(catName) saw you today. Come back tomorrow to make it \(info.current + 1)." :
                    "Visit \(catName) today to keep it burning.")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Monday to Sunday: a flame on each day kept, a shield on a forgiven one, today ringed.
    private var weekStrip: some View {
        HStack(spacing: 6) {
            ForEach(Array(info.week.enumerated()), id: \.offset) { index, entry in
                VStack(spacing: 4) {
                    Text(["M", "T", "W", "T", "F", "S", "S"][index])
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(entry.today ? Theme.accent : Theme.inkSoft)
                    ZStack {
                        Circle().fill(entry.kept ? AnyShapeStyle(LinearGradient(colors: [GameHUD.gold, Theme.accent], startPoint: .top, endPoint: .bottom)) :
                            AnyShapeStyle(Theme.ink.opacity(0.08)))
                        if entry.forgiven {
                            Image(systemName: "shield.lefthalf.filled").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                        } else if entry.kept {
                            Image(systemName: "flame.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .overlay(Circle().strokeBorder(entry.today ? Theme.accent : .clear, lineWidth: 2.5).padding(-3))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cream))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week: \(info.week.filter(\.kept).count) days kept")
    }

    /// The next milestone and its Beans, with how far there is to go.
    private func milestone(_ next: (days: Int, beans: Int)) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Next: a \(next.days)-day streak").font(.system(size: 15, weight: .heavy, design: .rounded))
                Spacer()
                PaintedIcon("bean_coin", size: 18)
                Text("+\(next.beans)").font(.system(size: 14, weight: .heavy, design: .rounded))
            }
            ProgressView(value: Double(info.current), total: Double(next.days)).tint(Theme.accent)
            Text("\(days(next.days - info.current)) to go").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cream))
    }

    /// A broken run, mendable: what is left to do today, then Mend it.
    private var repair: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(catName) kept your \(info.repairable) days safe").font(Theme.title(19))
            Text("Look after \(catName) today and they come back" + (info.repairUntil.map { ", until \($0.date.day) \(ShopView.monthName($0.month))." } ?? "."))
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
            HStack(spacing: 14) {
                task("Feed \(catName)", done: !info.repairLeft.contains("feed"))
                task("Play a game", done: !info.repairLeft.contains("play"))
            }
            if info.canRepair {
                ChunkyButton("Mend the streak") {
                    GameSession.shared.repairStreak()
                    info = GameSession.shared.streakInfo
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cream))
    }

    private func task(_ text: String, done: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle").foregroundStyle(done ? Theme.accent : Theme.inkSoft)
            Text(text).font(.subheadline.weight(.semibold)).strikethrough(done, color: Theme.inkSoft)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text + (done ? ", done" : ""))
    }

    /// Holiday mode: days that neither count nor break the run, a few a quarter.
    @ViewBuilder
    private var holiday: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Going away?").font(Theme.title(19))
            if let paused = info.paused {
                Text("The streak is paused until \(paused.until.date.day) \(ShopView.monthName(paused.until.month)). \(catName) will be fine.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
                HUDButton("I'm back") {
                    GameSession.shared.endPause()
                    info = GameSession.shared.streakInfo
                }
            } else if info.pauseDaysLeft > 0 {
                Text("Pause the streak while you're away: \(info.pauseDaysLeft) days left this quarter.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
                HStack(spacing: 12) {
                    Stepper("\(pauseDays) days", value: $pauseDays, in: 1 ... max(1, info.pauseDaysLeft))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: 220)
                    HUDButton("Pause it", icon: "nap_moon") {
                        feedback.tap()
                        GameSession.shared.startPause(days: pauseDays)
                        info = GameSession.shared.streakInfo
                    }
                }
            } else {
                Text("This quarter's pause days are used. They come back on the first of the next quarter.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .onAppear { pauseDays = min(7, max(1, info.pauseDaysLeft)) }
    }
}

/// The day's streak, celebrated on the first visit of the day as Duolingo does (Josh, 22 Oct: "make the streak a
/// bigger deal"): the flame swells, the number ticks up from yesterday's, and the week lights today's day.
struct StreakCelebration: View {
    let catName: String
    let done: () -> Void
    @State private var info = GameSession.shared.streakInfo
    @State private var shown = 0
    @State private var flame = 0.4

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture(perform: done)
            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(RadialGradient(colors: [GameHUD.gold.opacity(0.7), .clear], center: .center, startRadius: 6, endRadius: 110))
                        .frame(width: 220, height: 220)
                    PaintedIcon("streak_paw_print_with_a_small_flame", size: 140)
                        .scaleEffect(flame)
                }
                Text("\(shown)")
                    .font(.system(size: 88, weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [GameHUD.gold, Theme.accent], startPoint: .top, endPoint: .bottom))
                    .contentTransition(.numericText(value: Double(shown)))
                    .shadow(color: .black.opacity(0.35), radius: 0, y: 4)
                Text("day streak!").font(Theme.title(30)).foregroundStyle(.white)
                Text("\(catName) is so glad you came back.").font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                ChunkyButton("Keep it up", action: done).frame(maxWidth: 240).padding(.top, 6)
            }
            .multilineTextAlignment(.center)
        }
        .onAppear {
            shown = max(0, info.current - 1)
            Sound.play("ui_streak_milestone", volume: Tuning.Sound.levelUp)
            withAnimation(.spring(duration: 0.7, bounce: 0.5)) { flame = 1 }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.7))
                withAnimation(.spring(duration: 0.5)) { shown = info.current }
            }
        }
    }
}
