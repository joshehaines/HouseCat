import HouseCatCore
import HouseCatUI
import SwiftUI

extension CatScreens {
    /// Everything there is to work towards today (HouseCatCore `GoalBoard`).
    static func goals() -> GoalBoard? {
        let session = GameSession.shared
        guard let objectives = session.content?.objectives else { return nil }
        let now = session.now()
        let state = session.state(at: now)
        return GoalBoard.make(state, objectives: objectives, on: state.clock.day(of: now), catName: session.cat?.name ?? "your cat")
    }

    /// Every goal met so far: the path's, today's, this week's and the achievements, for noticing a new one.
    static func goalsMet() -> Set<String> {
        GameSession.shared.goalsMet()
    }
}

/// How many goals had been met when the Goals page was last open, kept on this device: more met since puts a dot on
/// the menu.
enum GoalsSeen {
    static var count: Int {
        get { UserDefaults.standard.integer(forKey: "goalsSeen") }
        set { UserDefaults.standard.set(newValue, forKey: "goalsSeen") }
    }
}

/// The Goals page (Josh, 19 Oct: something to work towards): what it is all for along the top (the cat's trust, the
/// home, the level), then the path's chapter step by step, today's three goals and this week's three, with how far
/// along each is and what it pays, beside the milestones, each ladder of achievements at its next step with how many
/// of its steps are done. The rules count and pay them all; this is where they show.
struct GoalsView: View {
    let board: GoalBoard
    var catName = "Your cat"
    /// A room's name in this home.
    var roomTitle: (RoomID) -> String = { $0.rawValue.capitalized }
    let close: () -> Void

    @Environment(\.hudScale) private var scale
    @Environment(\.controlFeedback) private var feedback

    var body: some View {
        VStack(alignment: .leading, spacing: 10 * scale) {
            HStack(alignment: .firstTextBaseline) {
                Text("Goals").font(Theme.title(22 * scale)).foregroundStyle(Theme.ink)
                Text("\(board.achievementsDone) of \(board.achievementsTotal) milestones")
                    .font(.system(size: 12 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                Spacer()
                Button {
                    feedback.tap()
                    close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13 * scale, weight: .heavy))
                        .foregroundStyle(Theme.inkSoft)
                        .frame(width: 30 * scale, height: 30 * scale)
                        .background(Circle().fill(Theme.ink.opacity(0.07)))
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Close")
            }
            // The page scrolls under its title when it is taller than the screen (a phone on its side).
            ScrollView {
                VStack(alignment: .leading, spacing: 10 * scale) {
                    pillars
                    HStack(alignment: .top, spacing: 14 * scale) {
                        VStack(alignment: .leading, spacing: 6 * scale) {
                            if let chapter = board.chapter {
                                HStack(alignment: .firstTextBaseline, spacing: 6 * scale) {
                                    Text(chapter.name).font(Theme.title(15 * scale)).foregroundStyle(Theme.ink)
                                    Text("\(chapter.when) · \(chapter.done) of \(chapter.of)")
                                        .font(.system(size: 11 * scale, weight: .heavy, design: .rounded))
                                        .foregroundStyle(Theme.inkSoft)
                                }
                                ForEach(board.path) { row($0) }
                                Spacer().frame(height: 4 * scale)
                            }
                            heading("Today")
                            ForEach(board.today) { row($0) }
                            heading("This week").padding(.top, 4 * scale)
                            ForEach(board.week) { row($0) }
                        }
                        .frame(width: 270 * scale)
                        VStack(alignment: .leading, spacing: 6 * scale) {
                            heading("Milestones")
                            ForEach(board.milestones) { milestone in
                                row(milestone.next, steps: (milestone.stepsDone, milestone.steps))
                            }
                        }
                        .frame(width: 290 * scale)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .frame(width: (270 + 14 + 290) * scale)
        }
        .frame(width: (270 + 14 + 290) * scale)
        .padding(16 * scale)
        .containerRelativeFrame(.vertical) { height, _ in min(height - 64, 560 * scale) }
        .paper(RoundedRectangle(cornerRadius: 24 * scale, style: .continuous))
    }

    /// What the game is about: the cat's trust, the home, the level, each with what is next.
    private var pillars: some View {
        let pillars = board.pillars
        let trust = pillars.daysToNextTier.map { days in
            let next = TrustTier(rawValue: pillars.trust.rawValue + 1).map(ProfileText.trust) ?? ""
            return days == 1 ? "1 more day of care to \(next)" : "\(days) more days of care to \(next)"
        } ?? "As close as a cat gets"
        let level: String = if let room = pillars.nextRoom {
            pillars.level >= room.requiredLevel
                ? "The \(roomTitle(room).lowercased()) can open now"
                : "The \(roomTitle(room).lowercased()) opens at level \(room.requiredLevel)"
        } else {
            "Every room is open"
        }
        return HStack(spacing: 8 * scale) {
            pillar("trust_heart_with_a_paw_print", "\(catName)'s trust: \(ProfileText.trust(pillars.trust))", trust)
            pillar("house", "Your home: \(pillars.roomsOpen) of \(pillars.rooms) rooms", pillars.pieces == 1 ? "1 piece out" : "\(pillars.pieces) pieces out")
            pillar("xp_star", "Level \(pillars.level)", level)
        }
    }

    private func pillar(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 7 * scale) {
            PaintedIcon(icon, size: 30 * scale)
            VStack(alignment: .leading, spacing: 1 * scale) {
                Text(title)
                    .font(.system(size: 12 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(detail)
                    .font(.system(size: 10.5 * scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8 * scale)
        .padding(.vertical, 7 * scale)
        .frame(maxWidth: .infinity, minHeight: 50 * scale)
        .background(RoundedRectangle(cornerRadius: 14 * scale, style: .continuous).fill(Theme.ink.opacity(0.05)))
        .accessibilityElement(children: .combine)
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11 * scale, weight: .heavy, design: .rounded))
            .foregroundStyle(Theme.inkSoft)
            .textCase(.uppercase)
    }

    /// A goal: its name and what it asks, a bar of how far along, its Beans; ticked when met. A milestone shows its
    /// ladder's steps as pips.
    private func row(_ goal: GoalBoard.Goal, steps: (done: Int, of: Int)? = nil) -> some View {
        HStack(spacing: 8 * scale) {
            ZStack {
                Circle().fill(goal.done ? GameHUD.green : Theme.ink.opacity(0.08))
                if goal.done {
                    Image(systemName: "checkmark").font(.system(size: 11 * scale, weight: .black)).foregroundStyle(.white)
                } else {
                    PaintedIcon("objectives_clipboard_with_a_tick", size: 16 * scale)
                }
            }
            .frame(width: 26 * scale, height: 26 * scale)
            VStack(alignment: .leading, spacing: 2 * scale) {
                HStack(spacing: 4 * scale) {
                    Text(goal.name)
                        .font(.system(size: 13 * scale, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if let steps {
                        HStack(spacing: 2 * scale) {
                            ForEach(0 ..< steps.of, id: \.self) { index in
                                Circle()
                                    .fill(index < steps.done ? GameHUD.gold : Theme.ink.opacity(0.15))
                                    .frame(width: 6 * scale, height: 6 * scale)
                            }
                        }
                    }
                }
                Text(goal.text)
                    .font(.system(size: 11 * scale, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Capsule().fill(Theme.ink.opacity(0.1))
                    .frame(height: 6 * scale)
                    .overlay(alignment: .leading) {
                        GeometryReader { geometry in
                            Capsule()
                                .fill(goal.done ? GameHUD.green : GameHUD.gold)
                                .frame(width: geometry.size.width * goal.fraction)
                        }
                    }
            }
            VStack(alignment: .trailing, spacing: 1 * scale) {
                // Its Beans (or its XP, when it pays none), and a present when it gives an outfit or a piece.
                HStack(spacing: 2 * scale) {
                    if goal.gives {
                        PaintedIcon("gift_box_with_a_ribbon", size: 14 * scale)
                    }
                    if goal.beans > 0 {
                        PaintedIcon("bean_coin", size: 14 * scale)
                        Text("\(goal.beans)")
                    } else if goal.xp > 0 {
                        Text("+\(goal.xp) XP")
                    }
                }
                .font(.system(size: 12 * scale, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.ink)
                Text("\(goal.progress)/\(goal.target)")
                    .font(.system(size: 10 * scale, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.inkSoft)
            }
            .frame(width: 48 * scale, alignment: .trailing)
        }
        .padding(.horizontal, 8 * scale)
        .padding(.vertical, 6 * scale)
        .background(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous).fill(Theme.ink.opacity(goal.done ? 0.03 : 0.05)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(goal.name): \(goal.text) \(goal.progress) of \(goal.target)\(goal.done ? ", done" : ""). \(goal.beans) Beans\(goal.xp > 0 ? ", \(goal.xp) XP" : "")."
        )
    }
}
