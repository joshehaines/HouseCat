import HouseCatCore
import HouseCatGame
import HouseCatUI
import SwiftUI
import UIKit

/// What a tap on a goal in the tracker does: show where it is done (a paw on the button, or the place itself).
enum GoalAction: Equatable {
    /// A paw bounces on one of the room's controls (`tourTarget`): "feed".
    case point(String)
    /// A paw on the cat: a stroke, or a present waiting.
    case cat
    case play, nap, wardrobe, map, book, pass, streak, road, goals
    /// Decorate, in this room when it is open.
    case decorate(RoomID?)
    /// Go to the room, or offer to open it.
    case room(RoomID)

    /// Where `entry` is done.
    @MainActor static func of(_ entry: GoalTracker.Entry) -> GoalAction {
        if entry.kind == .room, let room = entry.room {
            return entry.id.hasSuffix(".level") ? .road : .room(room)
        }
        guard let metric = entry.metric else { return .goals }
        switch metric {
        case .feed, .feedBefore9, .totalFeeds, .careDays, .trustTier: return .point("feed")
        case .pet, .totalPets: return .cat
        case .playMinigame, .winMinigame, .threeStarMinigame, .gamesPlayed, .minigameWins, .threeStarGames: return .play
        case .nap, .naps: return .nap
        case .roomPieces: return .decorate(entry.room)
        case .placeItem, .itemsOwned, .roomsFurnished, .catUsedItems, .changeSurface, .surfacesChanged, .buyItemBeans: return .decorate(nil)
        case .openRoom, .roomsOpened: return GameSession.shared.nextRoom.map { .room($0) } ?? .goals
        case .level: return .road
        case .wearOutfit, .outfitsWorn: return .wardrobe
        case .screenSeen, .seasonChanged, .homeMoved, .homesVisited: return entry.screen == "map" || entry.screen == nil ? .map : .goals
        case .findGift, .totalGifts: return GameSession.shared.giftWaiting ? .cat : .book
        case .distinctGifts, .legendaryGifts: return .book
        case .passTiersClaimed, .seasonsCompleted: return .pass
        case .visitDay, .daysVisited, .longestStreak: return .streak
        default: return .goals
        }
    }
}

extension GameSession {
    /// The next room to open, as the tracker's room goal names it.
    var nextRoom: RoomID? {
        let state = state(at: now())
        return RoomID.allCases.filter { !state.openedRooms.contains($0) }.min { $0.requiredLevel < $1.requiredLevel }
    }

    /// A present is on the floor or due.
    var giftWaiting: Bool {
        !state(at: now()).waitingGifts(at: now()).isEmpty
    }
}

/// The tracker's state over a visit: what it shows, the goal being celebrated, a chapter just finished. Read from
/// the save every moment it is on screen (cheap: the save is folded as it grows), so it never misses a goal met by
/// a widget, the Watch or another owner.
@MainActor
@Observable
final class GoalTrackerModel {
    /// What is on the card: the tracker as it was, held while a goal on it is celebrated.
    private(set) var tracker: GoalTracker?
    /// Goals on the card just met: drawn green and ticked, with what they paid floating up.
    private(set) var celebrating: [String: GoalReward] = [:]
    /// A chapter of the path just finished: its card.
    var chapterDone: GoalReward?
    /// The control a tap asked to be shown (a paw bounces on it for a moment).
    var pointing: GoalAction?
    @ObservationIgnored private var met: Set<String>?
    @ObservationIgnored private var holdUntil = Date.distantPast
    @ObservationIgnored private var roomTitle: (RoomID) -> String = { $0.rawValue.capitalized }

    /// Reads the save again: a goal on the card met is celebrated, then the card moves on; any other goal met gets a
    /// note over the room; a chapter finished gets its card.
    func refresh(visit: Visit, roomTitle: @escaping (RoomID) -> String) {
        self.roomTitle = roomTitle
        let session = GameSession.shared
        let now = session.goalsMet()
        let fresh = session.goalTracker(roomTitle: roomTitle)
        defer { met = now }
        guard let before = met else {
            tracker = fresh
            return
        }
        let new = now.subtracting(before)
        if !new.isEmpty {
            // The room's own readouts follow (Beans, XP), whatever met it.
            visit.refreshStats()
            let shown = Set(tracker?.entries.map(\.id) ?? [])
            var noted = false
            for id in new.sorted() {
                guard let reward = session.reward(for: id) else { continue }
                if reward.chapter {
                    chapterDone = reward
                    Sound.play("ui_streak_milestone", volume: Tuning.Goals.chapterVolume)
                } else if shown.contains(id) {
                    celebrating[id] = reward
                } else if !noted {
                    noted = true
                    visit.notify(Self.paid(reward), icon: "objectives_clipboard_with_a_tick")
                }
            }
            if celebrating.keys.contains(where: new.contains) {
                Sound.play("ui_bean_chime", volume: Tuning.Goals.doneVolume)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                holdUntil = Date().addingTimeInterval(Tuning.Goals.celebrationSeconds)
                // The card stays as it was, ticked, then moves on.
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(Tuning.Goals.celebrationSeconds))
                    guard let self else { return }
                    withAnimation(.spring(duration: 0.45)) {
                        self.celebrating = [:]
                        self.tracker = GameSession.shared.goalTracker(roomTitle: self.roomTitle)
                    }
                }
            }
        }
        guard Date() >= holdUntil else {
            // Mid-celebration: only the progress and the chapter's count move.
            if var held = tracker, let fresh {
                held.chapter = fresh.chapter ?? held.chapter
                for index in held.entries.indices {
                    if let now = fresh.entries.first(where: { $0.id == held.entries[index].id }) {
                        held.entries[index].progress = now.progress
                    } else if celebrating[held.entries[index].id] != nil {
                        held.entries[index].progress = held.entries[index].target
                    }
                }
                tracker = held
            }
            return
        }
        if fresh != tracker {
            withAnimation(.spring(duration: 0.45)) { tracker = fresh }
        }
    }

    #if DEBUG
        /// Screenshot runs: the first goal on the card shown met (HOUSECAT_SCREEN=goaldone), held.
        func showMet() {
            guard let entry = tracker?.entries.first, let reward = GameSession.shared.reward(for: entry.id) else { return }
            celebrating[entry.id] = reward
            holdUntil = .distantFuture
        }
    #endif

    /// "Make it cosy · +30 Beans, +15 XP".
    static func paid(_ reward: GoalReward) -> String {
        var parts: [String] = []
        if reward.beans > 0 {
            parts.append("+\(reward.beans) Beans")
        }
        if reward.xp > 0 {
            parts.append("+\(reward.xp) XP")
        }
        return parts.isEmpty ? reward.name : "\(reward.name) · \(parts.joined(separator: ", "))"
    }
}

/// The goal tracker on the room (Josh, 19 Oct: "i have been playing for 5 mins and dont know what to do"): top middle,
/// between the player's badge and the Beans, the path's chapter and its next two goals with how far along each is
/// and what it pays; after the path, today's goal nearest done and the next big one. A tap on a goal shows where it
/// is done; All goals opens the Goals page. A goal met goes green and ticks, its Beans and XP float up, and the next
/// slides in.
struct GoalTrackerLayer: View {
    let visit: Visit
    let targets: [String: Anchor<CGRect>]
    /// Out of the way (decorating, a look on trial, the menu open, the tour but for its goals step). While hidden it
    /// does not read the save, so a goal met meanwhile (the third piece put out while decorating) is celebrated when
    /// it comes back.
    let hidden: Bool
    /// The room's own controls: open the game picker, the map, the wardrobe...
    let open: (GoalAction) -> Void
    let roomTitle: (RoomID) -> String
    @State private var model = GoalTrackerModel()
    @Environment(\.hudScale) private var scale

    var body: some View {
        GeometryReader { proxy in
            let frame = cardFrame(in: proxy)
            ZStack(alignment: .topLeading) {
                if !hidden, let tracker = model.tracker, !tracker.entries.isEmpty {
                    GoalTrackerCard(tracker: tracker, celebrating: model.celebrating, width: frame.width / scale) { entry in
                        tapped(entry)
                    } all: {
                        open(.goals)
                    }
                    .zoomed(scale)
                    .tourTarget("goals")
                    .offset(x: frame.minX, y: frame.minY)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let pointing = model.pointing, !hidden {
                    pointer(pointing, in: proxy)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(.spring(duration: 0.4), value: hidden)
        }
        .ignoresSafeArea()
        .overlay {
            if let chapter = model.chapterDone, !hidden {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea().onTapGesture { model.chapterDone = nil }
                    ChapterDoneCard(reward: chapter) { model.chapterDone = nil }
                        .padding(24)
                        .zoomed(scale)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: model.chapterDone?.id)
        .task(id: hidden) {
            #if DEBUG
                // Screenshot runs: HOUSECAT_SCREEN=chapter (Moving in done), goaldone (the first goal ticked).
                let screen = ProcessInfo.processInfo.environment["HOUSECAT_SCREEN"]
                if screen == "chapter" || screen == "goaldone" {
                    model.refresh(visit: visit, roomTitle: roomTitle)
                    try? await Task.sleep(for: .seconds(3))
                    if screen == "chapter" {
                        model.chapterDone = GameSession.shared.reward(for: "path_moving_in")
                    } else {
                        model.showMet()
                    }
                    return
                }
            #endif
            // Read the save while the room is up: every goal is counted there, whatever met it.
            guard !hidden else { return }
            while !Task.isCancelled {
                model.refresh(visit: visit, roomTitle: roomTitle)
                try? await Task.sleep(for: .seconds(Tuning.Goals.refreshSeconds))
            }
        }
        .onChange(of: visit.stats) {
            if !hidden {
                model.refresh(visit: visit, roomTitle: roomTitle)
            }
        }
    }

    /// Between the badge (its anchor) and the Beans, as wide as fits up to the card's own width, centred in the gap.
    private func cardFrame(in proxy: GeometryProxy) -> CGRect {
        let edge = CGFloat(Tuning.Stage.hudEdge)
        let left = targets["plaque"].map { proxy[$0].maxX } ?? (edge + 250 * scale)
        let right = proxy.size.width - edge - CGFloat(Tuning.Goals.beansReserve) * scale
        let gap = CGFloat(Tuning.Goals.cardGap) * scale
        let width = min(CGFloat(Tuning.Goals.cardWidth) * scale, max(CGFloat(Tuning.Goals.cardSmallest) * scale, right - left - 2 * gap))
        let x = min(max(left + gap, (left + right) / 2 - width / 2), proxy.size.width - edge - width)
        return CGRect(x: x, y: CGFloat(Tuning.Stage.hudTop), width: width, height: 0)
    }

    private func tapped(_ entry: GoalTracker.Entry) {
        let action = GoalAction.of(entry)
        switch action {
        case .point, .cat:
            model.pointing = action
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(Tuning.Goals.pointerSeconds))
                if model.pointing == action {
                    model.pointing = nil
                }
            }
        default:
            model.pointing = nil
            open(action)
        }
    }

    /// The paw over the control (or the cat) a tap asked about, bobbing, as the tour's does.
    @ViewBuilder
    private func pointer(_ action: GoalAction, in proxy: GeometryProxy) -> some View {
        switch action {
        case let .point(target):
            if let anchor = targets[target] {
                GoalPaw(rect: proxy[anchor], size: proxy.size)
            }
        case .cat:
            TimelineView(.animation) { _ in
                if let point = visit.catPoint {
                    GoalPaw(rect: CGRect(x: point.x - 30, y: point.y - 50, width: 60, height: 100), size: proxy.size)
                }
            }
            .allowsHitTesting(false)
        default:
            EmptyView()
        }
    }
}

/// The paw that points at a control, from below it (or above, near the bottom of the screen).
private struct GoalPaw: View {
    let rect: CGRect
    let size: CGSize

    var body: some View {
        let below = rect.maxY + 60 < size.height
        TimelineView(.animation) { timeline in
            let bob = sin(timeline.date.timeIntervalSinceReferenceDate * 5) * 7
            if let paw = CatScreens.picture("fx/reactions/fx_reactions_paw.png") {
                paw.resizable().scaledToFit()
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(below ? 180 : 0))
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
                    .position(x: rect.midX, y: below ? rect.maxY + 30 + bob : rect.minY - 30 - bob)
            }
        }
        .allowsHitTesting(false)
    }
}

/// The card itself, drawn for a phone (the layer zooms it on an iPad).
struct GoalTrackerCard: View {
    let tracker: GoalTracker
    let celebrating: [String: GoalReward]
    let width: CGFloat
    let tap: (GoalTracker.Entry) -> Void
    let all: () -> Void
    @Environment(\.controlFeedback) private var feedback

    var body: some View {
        VStack(spacing: 4) {
            Button {
                feedback.tap()
                all()
            } label: {
                HStack(spacing: 5) {
                    PaintedIcon("objectives_clipboard_with_a_tick", size: 17)
                    Text(tracker.chapter?.name ?? "Goals")
                        .font(Theme.title(14))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if let chapter = tracker.chapter {
                        Text("\(chapter.done) of \(chapter.of)")
                            .font(.system(size: 11, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(Theme.inkSoft)
                            .contentTransition(.numericText())
                    }
                    Spacer(minLength: 4)
                    Text("All goals")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(GameHUD.deepGold)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(GameHUD.deepGold)
                }
                .padding(.horizontal, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(tracker.chapter.map { "\($0.name), \($0.done) of \($0.of) done. All goals." } ?? "All goals")
            ForEach(tracker.entries) { entry in
                GoalRow(entry: entry, reward: celebrating[entry.id]) {
                    feedback.tap()
                    tap(entry)
                }
                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            }
        }
        .padding(.horizontal, 7)
        .padding(.top, 6)
        .padding(.bottom, 7)
        .frame(width: width)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.cream))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(GameHUD.lip.opacity(0.3), lineWidth: 1))
        .shadow(color: Theme.shadow, radius: 4, y: 2)
        .animation(.spring(duration: 0.4), value: tracker.entries.map(\.id))
    }
}

/// One goal: its picture, name and what it asks, a bar of how far along, what it pays. Met: green, ticked, with what
/// it paid floating up.
private struct GoalRow: View {
    let entry: GoalTracker.Entry
    /// Met just now: what it paid.
    let reward: GoalReward?
    let action: () -> Void
    @State private var rise = false

    var body: some View {
        let done = reward != nil
        Button(action: action) {
            HStack(spacing: 7) {
                ZStack {
                    Circle().fill(done ? GameHUD.green : Color(red: 1, green: 0.965, blue: 0.89))
                    if done {
                        Image(systemName: "checkmark").font(.system(size: 13, weight: .black)).foregroundStyle(.white)
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
                    } else {
                        PaintedIcon(Self.icon(entry), size: 22)
                    }
                }
                .frame(width: 28, height: 28)
                .overlay(Circle().strokeBorder(done ? .clear : GameHUD.deepGold.opacity(0.35), lineWidth: 1.5))
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.name)
                        .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(entry.text)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Capsule().fill(Theme.ink.opacity(0.1))
                        .frame(height: 5)
                        .overlay(alignment: .leading) {
                            GeometryReader { geometry in
                                Capsule()
                                    .fill(done ? GameHUD.green : GameHUD.gold)
                                    .frame(width: max(5, geometry.size.width * (done ? 1 : entry.fraction)))
                                    .animation(.spring(duration: 0.6), value: entry.fraction)
                            }
                        }
                        .padding(.top, 2)
                }
                VStack(alignment: .trailing, spacing: 1) {
                    if entry.beans > 0 {
                        HStack(spacing: 2) {
                            PaintedIcon("bean_coin", size: 14)
                            Text("\(entry.beans)")
                                .font(.system(size: 11.5, weight: .black, design: .rounded).monospacedDigit())
                                .foregroundStyle(Theme.ink)
                        }
                    } else if entry.outfit != nil || entry.item != nil {
                        PaintedIcon("gift_box_with_a_ribbon", size: 16)
                    }
                    Text(done ? "Done!" : progressText)
                        .font(.system(size: 9.5, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(done ? GameHUD.green : Theme.inkSoft)
                        .lineLimit(1)
                }
                .fixedSize()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(done ? GameHUD.green.opacity(0.18) : Theme.ink.opacity(0.055)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .overlay(alignment: .topTrailing) {
            if let reward {
                // What it paid, floating up towards the Beans.
                HStack(spacing: 3) {
                    if reward.beans > 0 {
                        PaintedIcon("bean_coin", size: 16)
                        Text("+\(reward.beans)")
                    }
                    if reward.xp > 0 {
                        PaintedIcon("xp_star", size: 15)
                        Text("+\(reward.xp) XP")
                    }
                }
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
                .offset(x: rise ? 18 : 0, y: rise ? -34 : 0)
                .opacity(rise ? 0 : 1)
                .onAppear {
                    withAnimation(.easeOut(duration: Tuning.Goals.celebrationSeconds)) { rise = true }
                }
                .allowsHitTesting(false)
            }
        }
        .animation(.spring(duration: 0.35), value: done)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows where to do it.")
    }

    private var progressText: String {
        var text = entry.target > 1 && entry.kind != .room ? "\(entry.progress)/\(entry.target)" : ""
        if entry.xp > 0 {
            text += text.isEmpty ? "+\(entry.xp) XP" : " · +\(entry.xp) XP"
        }
        if text.isEmpty, entry.kind == .room {
            text = entry.id.hasSuffix(".open") ? "\(entry.progress.formatted())/\(entry.target.formatted())" : "\(Int(entry.fraction * 100))%"
        }
        return text
    }

    private var accessibility: String {
        var parts = ["\(entry.name): \(entry.text)"]
        if reward != nil {
            parts.append("Done")
        } else if entry.target > 1 {
            parts.append("\(entry.progress) of \(entry.target)")
        }
        if entry.beans > 0 {
            parts.append("\(entry.beans) Beans")
        }
        if entry.xp > 0 {
            parts.append("\(entry.xp) XP")
        }
        return parts.joined(separator: ". ")
    }

    /// The painted icon for what a goal asks.
    static func icon(_ entry: GoalTracker.Entry) -> String {
        if entry.kind == .room {
            return entry.id.hasSuffix(".level") ? "level_up_arrow" : "padlock"
        }
        guard let metric = entry.metric else { return "objectives_clipboard_with_a_tick" }
        switch metric {
        case .feed, .feedBefore9, .totalFeeds: return "feed_bowl"
        case .careDays, .trustTier: return "trust_heart_with_a_paw_print"
        case .pet, .totalPets: return "petting_hand"
        case .playMinigame, .winMinigame, .threeStarMinigame, .gamesPlayed, .minigameWins, .threeStarGames: return "play_laser_dot"
        case .nap, .naps: return "nap_moon"
        case .roomPieces, .placeItem, .itemsOwned, .roomsFurnished, .buyItemBeans: return "sofa_for_furniture"
        case .catUsedItems: return "cat_face"
        case .changeSurface, .surfacesChanged: return "wallpaper_roll"
        case .openRoom, .roomsOpened: return "padlock"
        case .level: return "level_up_arrow"
        case .wearOutfit, .outfitsWorn: return "cat_face"
        case .screenSeen, .seasonChanged, .homeMoved, .homesVisited: return "map_pin"
        case .findGift, .totalGifts, .legendaryGifts: return "gift_box_with_a_ribbon"
        case .distinctGifts: return "collection_book"
        case .passTiersClaimed, .seasonsCompleted: return "season_pass_ticket"
        case .visitDay, .daysVisited, .longestStreak: return "streak_paw_print_with_a_small_flame"
        case .tapWindow: return "weather_sun_and_cloud"
        default: return "objectives_clipboard_with_a_tick"
        }
    }
}

/// A chapter of the path finished: what it was, what it paid, and what comes next.
struct ChapterDoneCard: View {
    let reward: GoalReward
    let close: () -> Void

    /// The outfit and the piece it gives, by name.
    private var gifts: [String] {
        let content = GameWorld.content
        return [
            reward.outfit.flatMap { id in content?.outfits.outfits.first { $0.id == id }?.name },
            reward.item.flatMap { id in content?.catalogue.items.first { $0.id == id }?.name },
        ].compactMap(\.self)
    }

    var body: some View {
        VStack(spacing: 10) {
            PaintedIcon("objectives_clipboard_with_a_tick", size: 54)
            Text("\(reward.name): done!")
                .font(Theme.title(24))
                .foregroundStyle(Theme.ink)
            if let line = reward.line {
                Text(line)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
            }
            HStack(spacing: 16) {
                if reward.beans > 0 {
                    HStack(spacing: 4) {
                        PaintedIcon("bean_coin", size: 26)
                        Text("+\(reward.beans)")
                    }
                }
                if reward.xp > 0 {
                    HStack(spacing: 4) {
                        PaintedIcon("xp_star", size: 24)
                        Text("+\(reward.xp) XP")
                    }
                }
                ForEach(gifts, id: \.self) { name in
                    HStack(spacing: 4) {
                        PaintedIcon("gift_box_with_a_ribbon", size: 24)
                        Text(name)
                    }
                }
            }
            .font(.system(size: 17, weight: .black, design: .rounded))
            .foregroundStyle(Theme.ink)
            if let next = reward.next {
                Text("Next: \(next)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 2)
            }
            ChunkyButton("Lovely", action: close)
                .padding(.top, 4)
        }
        .multilineTextAlignment(.center)
        .padding(22)
        .frame(maxWidth: 380)
        .paper(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
