import HouseCatCore
import HouseCatUI
import SwiftUI

/// The house ladder (docs/LADDER.md; Josh, 22 Oct: "house progression should be the main objective ... it costs a lot of
/// beans to buy the house progressively ... cannot skip houses"): where you live, the next house up with what it takes
/// and its Buy button, and every house above it.
struct HomesView: View {
    let catName: String
    /// Called after a house is bought (the app moves in: the cold open at the new house).
    let movedIn: () -> Void
    let close: () -> Void

    @Environment(\.controlFeedback) private var feedback
    @State private var state = GameSession.shared.state(at: GameSession.shared.now())
    private var today: GameDay {
        state.clock.day(of: GameSession.shared.now())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    PaintedIcon("house", size: 34)
                    Text("\(catName)'s homes").font(Theme.title(28))
                }
                Text("You live in the \(state.currentRung.name.lowercased()) in \(state.homePlace.name). House \(state.rung) of \(HouseLadder.top).")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                if let next = state.nextRung {
                    nextCard(next)
                } else {
                    Text("You made it to London. The top of the ladder.")
                        .font(Theme.title(22))
                }
                if state.rung + 1 < HouseLadder.top {
                    Text("Further up").font(Theme.title(20)).padding(.top, 6)
                    ForEach(HouseLadder.rungs.filter { $0.number > state.rung + 1 }) { rung in
                        laterRow(rung)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.paper.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .overlay(alignment: .topTrailing) { CloseButton(action: close).padding(16) }
    }

    private func nextCard(_ next: Rung) -> some View {
        let block = HouseLadder.block(above: state.rung, level: state.level, tasksDone: state.houseTasksDone, beans: state.beans)
        return VStack(alignment: .leading, spacing: 12) {
            picture(next)
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text("Next: the \(next.name.lowercased()) in \(next.place.name)").font(Theme.title(22))
            Text(next.style.blurb).font(.system(size: 15)).foregroundStyle(Theme.inkSoft)
            if let room = next.room {
                Label("Opens the \(Visit.title(of: room, upstairs: false).lowercased())", systemImage: "door.left.hand.open")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            VStack(alignment: .leading, spacing: 6) {
                if next.level > 1 {
                    need("Level \(next.level)", met: state.level >= next.level, have: "you are level \(state.level)")
                }
                if next.tasks > 0 {
                    need("\(next.tasks) house tasks", met: state.houseTasksDone >= next.tasks, have: "\(state.houseTasksDone) done")
                    // The tasks themselves, counted since moving in here.
                    ForEach(Array(state.houseTaskProgress(on: today).enumerated()), id: \.offset) { _, entry in
                        HStack(spacing: 8) {
                            Image(systemName: entry.done >= entry.task.target ? "checkmark.square.fill" : "square")
                                .foregroundStyle(entry.done >= entry.task.target ? GameHUD.green : Theme.inkSoft)
                            Text(entry.task.title.replacingOccurrences(of: "{cat}", with: catName))
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            Spacer(minLength: 0)
                            Text("\(entry.done)/\(entry.task.target)").font(.system(size: 13, weight: .bold, design: .rounded))
                                .monospacedDigit().foregroundStyle(Theme.inkSoft)
                        }
                        .padding(.leading, 28)
                        .accessibilityElement(children: .combine)
                    }
                }
                need("\(next.price.formatted()) Beans", met: state.beans >= next.price, have: "you have \(state.beans.formatted())")
            }
            ChunkyButton(block == nil ? "Move in for \(next.price.formatted()) Beans" : reason(block)) {
                guard block == nil, GameSession.shared.buyNextHouse() else { return }
                Sound.play("door_open", volume: Tuning.Sound.door)
                movedIn()
            }
            .disabled(block != nil)
            .opacity(block == nil ? 1 : 0.6)
            .accessibilityIdentifier("buyNextHouse")
        }
        .padding(16)
        .paper(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func need(_ what: String, met: Bool, have: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(met ? GameHUD.green : Theme.inkSoft)
            Text(what).font(.system(size: 15, weight: .bold, design: .rounded))
            Text(have).font(.system(size: 14)).foregroundStyle(Theme.inkSoft)
        }
        .accessibilityElement(children: .combine)
    }

    private func reason(_ block: HouseLadder.Block?) -> String {
        switch block {
        case let .needsLevel(level): "Reach level \(level)"
        case let .needsTasks(done, of): "Finish the house tasks (\(done) of \(of))"
        case let .needsBeans(price): "\((price - state.beans).formatted()) more Beans"
        case .atTheTop, nil: "At the top"
        }
    }

    private func laterRow(_ rung: Rung) -> some View {
        HStack(spacing: 12) {
            picture(rung)
                .frame(width: 96, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .saturation(0.4)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(rung.name) · \(rung.place.name)").font(.system(size: 16, weight: .bold, design: .rounded))
                Text("\(rung.price.formatted()) Beans · level \(rung.level)").font(.system(size: 14)).foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 0)
            Image(systemName: "lock.fill").foregroundStyle(Theme.inkSoft)
        }
        .accessibilityElement(children: .combine)
    }

    /// The house's small built-in preview, its sky masked out over a painted one.
    private func picture(_ rung: Rung) -> some View {
        let path = "world/previews/\(rung.style.rawValue)_\(rung.place.biome.rawValue)"
        return ZStack {
            LinearGradient(colors: [Color(red: 0.62, green: 0.78, blue: 0.93), Color(red: 0.95, green: 0.9, blue: 0.82)],
                           startPoint: .top, endPoint: .bottom)
            if let picture = CatScreens.picture(path + ".jpg") {
                picture.resizable().scaledToFill()
                    .mask {
                        if let land = CatScreens.picture(path + "_land.png") {
                            land.resizable().scaledToFill().luminanceToAlpha()
                        } else {
                            Rectangle()
                        }
                    }
            }
        }
    }
}
