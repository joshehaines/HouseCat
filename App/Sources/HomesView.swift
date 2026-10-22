import HouseCatCore
import HouseCatUI
import SwiftUI

/// The house ladder as a place (Josh, 22 Oct: "the Pip's homes section needs some serious work, please do a full
/// rebuild ... user should be able to see the progress tree of the houses ... buy from there. Have a view of the
/// ladder and then your cat looking at the ladder with you"): a cosy room at golden hour (ui/homes/homes_room), the
/// cat on its cushion with its back to you, and on the corkboard the eight houses climbing from Puddlebury to London.
/// Where you live is marked, the next house opens out with what it still needs and Move in, and the houses above
/// wait, locked.
struct HomesView: View {
    let catName: String
    /// Called after a house is bought (the app moves in: the cold open at the new house).
    let movedIn: () -> Void
    let close: () -> Void

    @State private var state = GameSession.shared.state(at: GameSession.shared.now())

    private var today: GameDay {
        state.clock.day(of: GameSession.shared.now())
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                backdrop(size)
                // The cat on its cushion under the window, looking up at the board.
                if let look = GameSession.shared.cat?.look, let back = CatScreens.backView(look) {
                    Image(decorative: back, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(height: size.height * 0.34)
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 4)
                        .position(x: size.width * 0.3, y: size.height * 0.64)
                        .accessibilityLabel("\(catName), looking at the ladder")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(catName)'s homes").font(Theme.title(26)).foregroundStyle(Theme.cream)
                    Text("House \(state.rung) of \(HouseLadder.top) · \(state.homePlace.name)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.cream.opacity(0.9))
                }
                .shadow(color: .black.opacity(0.6), radius: 5)
                .padding(.leading, max(24, proxy.safeAreaInsets.leading + 8))
                .padding(.top, 18)
                board(size)
            }
        }
        .ignoresSafeArea()
        .background(Color(red: 0.3, green: 0.22, blue: 0.18).ignoresSafeArea())
        .overlay(alignment: .topTrailing) { CloseButton(action: close).padding(16) }
    }

    private func backdrop(_ size: CGSize) -> some View {
        Group {
            if let room = CatScreens.picture("ui/homes/homes_room.jpg") {
                room.resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(red: 0.96, green: 0.86, blue: 0.7), Color(red: 0.8, green: 0.6, blue: 0.42)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .accessibilityHidden(true)
    }

    // MARK: The board

    /// The ladder on the corkboard, bottom to top, opening on the next house up.
    private func board(_ size: CGSize) -> some View {
        ScrollViewReader { reader in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(HouseLadder.rungs.reversed()) { rung in
                        row(rung).id(rung.number)
                        if rung.number > 1 {
                            ladderStep(lit: rung.number <= state.rung)
                        }
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 12)
            }
            .frame(width: min(size.width * 0.5, 520), height: size.height * 0.84)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.paper.opacity(0.88))
                    .shadow(color: .black.opacity(0.28), radius: 10, y: 5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .position(x: size.width * 0.66, y: size.height * 0.5)
            .onAppear { reader.scrollTo(min(state.rung + 1, HouseLadder.top), anchor: .center) }
        }
    }

    /// A rung of the ladder between two houses: lit once climbed.
    private func ladderStep(lit: Bool) -> some View {
        HStack(spacing: 0) {
            Capsule().fill(lit ? GameHUD.green : GameHUD.lip.opacity(0.45)).frame(width: 4, height: 18)
            Capsule().fill(lit ? GameHUD.green : GameHUD.lip.opacity(0.45)).frame(width: 18, height: 4)
            Capsule().fill(lit ? GameHUD.green : GameHUD.lip.opacity(0.45)).frame(width: 4, height: 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 13)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func row(_ rung: Rung) -> some View {
        if rung.number == state.rung + 1 {
            nextCard(rung)
        } else {
            compactRow(rung)
        }
    }

    /// A house lived in already, the one you live in, or one further up.
    private func compactRow(_ rung: Rung) -> some View {
        let here = rung.number == state.rung
        let behind = rung.number < state.rung
        return HStack(spacing: 10) {
            marker(rung, here: here, behind: behind)
            picture(rung)
                .frame(width: 88, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .saturation(behind || here ? 1 : 0.3)
            VStack(alignment: .leading, spacing: 2) {
                Text(rung.name).font(.system(size: 15, weight: .heavy, design: .rounded)).lineLimit(1)
                Text(rung.place.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 0)
            if here {
                Text("You live here")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Theme.accent))
            } else if behind {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(GameHUD.green).font(.system(size: 20))
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 3) {
                        PaintedIcon("bean_coin", size: 14)
                        Text(rung.price.formatted()).font(.system(size: 13, weight: .heavy, design: .rounded))
                    }
                    Text("Level \(rung.level)").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.inkSoft)
                }
                Image(systemName: "lock.fill").foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(here ? Theme.cream : Theme.cream.opacity(0.65)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(here ? Theme.accent : .clear, lineWidth: 2.5))
        .accessibilityElement(children: .combine)
    }

    /// The house's number on the ladder: orange where you live, green once lived in.
    private func marker(_ rung: Rung, here: Bool, behind: Bool) -> some View {
        Text("\(rung.number)")
            .font(.system(size: 14, weight: .black, design: .rounded))
            .foregroundStyle(here || behind ? .white : Theme.ink)
            .frame(width: 30, height: 30)
            .background(Circle().fill(here ? Theme.accent : behind ? GameHUD.green : Theme.cream))
            .overlay(Circle().strokeBorder(GameHUD.lip.opacity(0.5), lineWidth: 2))
    }

    /// The next house up: what it still needs, ticked off, and Move in.
    private func nextCard(_ next: Rung) -> some View {
        let block = HouseLadder.block(above: state.rung, level: state.level, tasksDone: state.houseTasksDone, beans: state.beans)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                marker(next, here: false, behind: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text("NEXT HOME").font(.system(size: 11, weight: .black, design: .rounded)).tracking(0.8)
                        .foregroundStyle(Theme.accent)
                    Text("The \(next.name.lowercased()) in \(next.place.name)").font(Theme.title(20)).lineLimit(2)
                }
            }
            HStack(alignment: .top, spacing: 10) {
                picture(next)
                    .frame(width: 150, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text(next.style.blurb).font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    if let room = next.room {
                        Label("Comes with a \(Visit.title(of: room, upstairs: false).lowercased())", systemImage: "door.left.hand.open")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                if next.level > 1 {
                    need("Level \(next.level)", met: state.level >= next.level, have: "you are level \(state.level)")
                }
                if next.tasks > 0 {
                    need("House tasks", met: state.houseTasksDone >= next.tasks, have: "\(state.houseTasksDone) of \(next.tasks)")
                    ForEach(Array(state.houseTaskProgress(on: today).enumerated()), id: \.offset) { _, entry in
                        task(entry.task, done: entry.done)
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
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cream))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(GameHUD.deepGold, lineWidth: 3))
        .shadow(color: GameHUD.deepGold.opacity(0.35), radius: 8)
    }

    /// One of the house's tasks with its bar.
    private func task(_ task: HouseTask, done: Int) -> some View {
        let finished = done >= task.target
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: finished ? "checkmark.square.fill" : "square")
                    .foregroundStyle(finished ? GameHUD.green : Theme.inkSoft)
                Text(task.title.replacingOccurrences(of: "{cat}", with: catName))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
                Text("\(done)/\(task.target)").font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Theme.inkSoft)
            }
            ProgressView(value: Double(done), total: Double(max(1, task.target)))
                .tint(finished ? GameHUD.green : Theme.accent)
                .padding(.leading, 26)
        }
        .padding(.leading, 26)
        .accessibilityElement(children: .combine)
    }

    private func need(_ what: String, met: Bool, have: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(met ? GameHUD.green : Theme.inkSoft)
            Text(what).font(.system(size: 15, weight: .bold, design: .rounded))
            Text(have).font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
        }
        .accessibilityElement(children: .combine)
    }

    private func reason(_ block: HouseLadder.Block?) -> String {
        switch block {
        case let .needsLevel(level): "Reach level \(level)"
        case let .needsTasks(done, of): "House tasks: \(done) of \(of)"
        case let .needsBeans(price): "\((price - state.beans).formatted()) more Beans"
        case .atTheTop, nil: "At the top"
        }
    }

    /// The house's picture, its sky masked out over a painted one: the first house its run-down painting, the others
    /// their small built-in previews.
    private func picture(_ rung: Rung) -> some View {
        let path = rung.number == 1
            ? "world/scenes/\(Tuning.Cutscene.firstHouseScene)_city_autumn"
            : "world/previews/\(rung.style.rawValue)_\(rung.place.biome.rawValue)"
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
