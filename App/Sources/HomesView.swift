import HouseCatCore
import HouseCatUI
import SwiftUI

/// The house ladder as a journey (Josh, 23 Oct: "redo the UI for the ladder 'home' menu, looks poor right now"): the
/// eight homes left to right along a dotted road from Puddlebury to London, each a painted tile (lived in, home, next,
/// or still to come with its level), and under them the chosen home opened out: its picture, what it comes with, the
/// level, the house tasks and the Beans it needs as three chips, the tasks themselves, and Move in. The next home is
/// chosen to begin with; tapping any other shows it.
struct HomesView: View {
    let catName: String
    /// Called after a house is bought (the app moves in: the cold open at the new house).
    let movedIn: () -> Void
    let close: () -> Void

    @State private var state = GameSession.shared.state(at: GameSession.shared.now())
    @State private var chosen: Int?

    private var today: GameDay {
        state.clock.day(of: GameSession.shared.now())
    }

    /// The home shown in the panel: the one tapped, else the next one up (or the top, once there).
    private var shown: Rung {
        HouseLadder.rung(chosen ?? min(state.rung + 1, HouseLadder.top))
    }

    var body: some View {
        ZStack {
            GeometryReader { proxy in backdrop(proxy.size) }.ignoresSafeArea()
            GeometryReader { proxy in
                // Drawn for a landscape phone (956 × 440 points) and scaled up on a bigger screen; held upright (an
                // iPad), by the width, with the cat under the homes looking up at them.
                let upright = proxy.size.height > proxy.size.width
                let s = upright
                    ? min(max(proxy.size.width / 740, 1), 1.75)
                    : min(max(min(proxy.size.height / 440, proxy.size.width / 956), 1), 1.75)
                VStack(alignment: .leading, spacing: 10 * s) {
                    header(s)
                    journey(s)
                    panel(shown, s: s, upright: upright)
                    if upright {
                        cat(height: proxy.size.height * 0.3)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 8 * s)
                .padding(.horizontal, 14 * s)
            }
        }
        .background(Color(red: 0.3, green: 0.22, blue: 0.18).ignoresSafeArea())
        // As in the room: an iPhone on its side hides the clock itself, iPhone Duo's inner screen does not.
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    /// The cat on its cushion with its back to you, looking up at the homes.
    @ViewBuilder
    private func cat(height: CGFloat) -> some View {
        if let look = GameSession.shared.cat?.look, let back = CatScreens.backView(look) {
            Image(decorative: back, scale: 1)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: height)
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("\(catName), looking at the homes")
        }
    }

    /// The cosy room at golden hour, softened so the homes stand out.
    private func backdrop(_ size: CGSize) -> some View {
        ZStack {
            if let room = CatScreens.picture("ui/homes/homes_room.jpg") {
                room.resizable().scaledToFill().blur(radius: 6).scaleEffect(1.08)
            }
            LinearGradient(
                colors: [Color(red: 0.2, green: 0.13, blue: 0.1).opacity(0.55), Color(red: 0.28, green: 0.18, blue: 0.12).opacity(0.8)],
                startPoint: .top, endPoint: .bottom
            )
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .accessibilityHidden(true)
    }

    // MARK: Header

    private func header(_ s: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 12 * s) {
            VStack(alignment: .leading, spacing: 2 * s) {
                Text("\(catName)'s homes").font(Theme.title(24 * s)).foregroundStyle(Theme.cream)
                Text("Home \(state.rung) of \(HouseLadder.top) · \(state.homePlace.name)")
                    .font(.system(size: 13 * s, weight: .bold, design: .rounded))
                    .foregroundStyle(GameHUD.gold)
            }
            Spacer(minLength: 0)
            progressPips(s)
            CloseButton(action: close)
        }
    }

    /// One pip a home: gold up to where you live.
    private func progressPips(_ s: CGFloat) -> some View {
        HStack(spacing: 4 * s) {
            ForEach(HouseLadder.rungs) { rung in
                Capsule()
                    .fill(rung.number <= state.rung ? GameHUD.gold : Theme.cream.opacity(0.25))
                    .frame(width: 18 * s, height: 6 * s)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Home \(state.rung) of \(HouseLadder.top)")
    }

    // MARK: The journey

    /// The eight homes along a dotted road, scrolled so the next one is in view.
    private func journey(_ s: CGFloat) -> some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(HouseLadder.rungs) { rung in
                        tile(rung, s: s).id(rung.number)
                        if rung.number < HouseLadder.top {
                            road(lit: rung.number < state.rung, s: s)
                        }
                    }
                }
                .padding(.vertical, 6 * s)
                .padding(.horizontal, 4 * s)
            }
            .onAppear { reader.scrollTo(min(state.rung + 1, HouseLadder.top), anchor: .center) }
        }
        .frame(height: 128 * s)
    }

    /// The road between two homes: gold dashes once travelled.
    private func road(lit: Bool, s: CGFloat) -> some View {
        HStack(spacing: 4 * s) {
            ForEach(0 ..< 3, id: \.self) { _ in
                Capsule().fill(lit ? GameHUD.gold : Theme.cream.opacity(0.35)).frame(width: 7 * s, height: 4 * s)
            }
        }
        .padding(.horizontal, 5 * s)
        .offset(y: -14 * s)
        .accessibilityHidden(true)
    }

    private enum Stage {
        case lived, home, next, ahead
    }

    private func stage(_ rung: Rung) -> Stage {
        if rung.number < state.rung { return .lived }
        if rung.number == state.rung { return .home }
        return rung.number == state.rung + 1 ? .next : .ahead
    }

    /// A home on the road: its picture, number, name and town, and where it stands.
    private func tile(_ rung: Rung, s: CGFloat) -> some View {
        let stage = stage(rung)
        let selected = rung.number == shown.number
        return Button {
            Sound.tap()
            withAnimation(.easeOut(duration: 0.2)) { chosen = rung.number }
        } label: {
            VStack(spacing: 5 * s) {
                ZStack(alignment: .topLeading) {
                    picture(rung)
                        .frame(width: 112 * s, height: 72 * s)
                        .clipShape(RoundedRectangle(cornerRadius: 14 * s, style: .continuous))
                        .saturation(stage == .ahead ? 0.25 : 1)
                        .brightness(stage == .ahead ? -0.08 : 0)
                    Text("\(rung.number)")
                        .font(.system(size: 12 * s, weight: .black, design: .rounded))
                        .foregroundStyle(stage == .ahead ? Theme.ink : .white)
                        .frame(width: 22 * s, height: 22 * s)
                        .background(Circle().fill(badgeColour(stage)))
                        .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1.5 * s))
                        .padding(5 * s)
                }
                .overlay(alignment: .bottomTrailing) { corner(rung, stage: stage, s: s) }
                .overlay(
                    RoundedRectangle(cornerRadius: 14 * s, style: .continuous)
                        .strokeBorder(selected ? GameHUD.gold : stage == .home ? Theme.accent : .white.opacity(0.35),
                                      lineWidth: (selected ? 3.5 : 2) * s)
                )
                .shadow(color: selected ? GameHUD.gold.opacity(0.6) : .black.opacity(0.35), radius: selected ? 10 * s : 5 * s, y: 3 * s)
                VStack(spacing: 0) {
                    Text(rung.place.name).font(.system(size: 13 * s, weight: .heavy, design: .rounded)).foregroundStyle(Theme.cream)
                    Text(caption(rung, stage: stage))
                        .font(.system(size: 10.5 * s, weight: .bold, design: .rounded))
                        .foregroundStyle(stage == .next ? GameHUD.gold : Theme.cream.opacity(0.7))
                }
                .lineLimit(1)
            }
            .frame(width: 116 * s)
            .scaleEffect(selected ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(rung.name) in \(rung.place.name), \(caption(rung, stage: stage))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func badgeColour(_ stage: Stage) -> Color {
        switch stage {
        case .lived: GameHUD.green
        case .home: Theme.accent
        case .next: GameHUD.deepGold
        case .ahead: Theme.cream
        }
    }

    private func caption(_ rung: Rung, stage: Stage) -> String {
        switch stage {
        case .lived: "Lived here"
        case .home: "Home"
        case .next: "Next"
        case .ahead: "Level \(rung.level)"
        }
    }

    /// The tile's corner: a tick once lived in, the cat at home, a padlock further up.
    @ViewBuilder
    private func corner(_ rung: Rung, stage: Stage, s: CGFloat) -> some View {
        switch stage {
        case .lived:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 20 * s)).foregroundStyle(.white, GameHUD.green).padding(5 * s)
        case .home:
            if let look = GameSession.shared.cat?.look, let face = CatScreens.portrait(look) {
                Image(decorative: face, scale: 1).resizable().interpolation(.high).scaledToFit()
                    .frame(width: 44 * s, height: 44 * s)
                    .offset(x: 8 * s, y: 10 * s)
                    .shadow(color: .black.opacity(0.4), radius: 3 * s)
            }
        case .next:
            Image(systemName: "sparkles").font(.system(size: 16 * s, weight: .bold)).foregroundStyle(GameHUD.gold).padding(6 * s)
        case .ahead:
            Image(systemName: "lock.fill").font(.system(size: 13 * s, weight: .bold)).foregroundStyle(Theme.cream)
                .padding(6 * s).background(Circle().fill(.black.opacity(0.45))).padding(5 * s)
        }
    }

    // MARK: The panel

    /// The chosen home opened out.
    private func panel(_ rung: Rung, s: CGFloat, upright: Bool) -> some View {
        let stage = stage(rung)
        // Held upright the picture goes across the top of the panel; on its side, down its left.
        let layout = upright ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12 * s)) : AnyLayout(HStackLayout(alignment: .top, spacing: 14 * s))
        return layout {
            VStack(alignment: .leading, spacing: 8 * s) {
                picture(rung)
                    .frame(width: upright ? nil : 180 * s, height: (upright ? 150 : 108) * s)
                    .frame(maxWidth: upright ? .infinity : nil)
                    .clipShape(RoundedRectangle(cornerRadius: 16 * s, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16 * s, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: 2 * s))
                if let room = rung.room {
                    Label("Comes with a \(Visit.title(of: room, upstairs: false).lowercased())", systemImage: "door.left.hand.open")
                        .font(.system(size: 12 * s, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                } else if rung.number == HouseLadder.top {
                    Label("The top of the ladder", systemImage: "crown.fill")
                        .font(.system(size: 12 * s, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                }
            }
            .frame(width: upright ? nil : 180 * s)
            VStack(alignment: .leading, spacing: 8 * s) {
                VStack(alignment: .leading, spacing: 2 * s) {
                    Text(kicker(stage)).font(.system(size: 10.5 * s, weight: .black, design: .rounded)).tracking(0.9)
                        .foregroundStyle(stage == .next ? Theme.accent : Theme.inkSoft)
                    Text("The \(rung.name.lowercased()) in \(rung.place.name)").font(Theme.title(19 * s)).foregroundStyle(Theme.ink)
                        .lineLimit(1).minimumScaleFactor(0.75)
                    Text(rung.style.blurb).font(.system(size: 12 * s)).foregroundStyle(Theme.inkSoft).lineLimit(2)
                }
                switch stage {
                case .lived:
                    note("You lived here. Your furniture came with you.", icon: "heart.fill", s: s)
                case .home:
                    note("\(catName) lives here now. Every home's furniture moves with you.", icon: "house.fill", s: s)
                case .next, .ahead:
                    needs(rung, s: s)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14 * s)
        .background(RoundedRectangle(cornerRadius: 22 * s, style: .continuous).fill(Theme.cream))
        .overlay(RoundedRectangle(cornerRadius: 22 * s, style: .continuous).strokeBorder(stage == .next ? GameHUD.deepGold : GameHUD.lip.opacity(0.35), lineWidth: 2.5 * s))
        .shadow(color: .black.opacity(0.35), radius: 12 * s, y: 6 * s)
    }

    private func kicker(_ stage: Stage) -> String {
        switch stage {
        case .lived: "LIVED HERE"
        case .home: "YOUR HOME"
        case .next: "NEXT HOME"
        case .ahead: "STILL TO COME"
        }
    }

    private func note(_ text: String, icon: String, s: CGFloat) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 13 * s, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.ink)
            .padding(10 * s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12 * s, style: .continuous).fill(Theme.paper))
    }

    /// What a home up the ladder needs: three chips, the house tasks (for the next one), and Move in.
    private func needs(_ rung: Rung, s: CGFloat) -> some View {
        let isNext = rung.number == state.rung + 1
        let block = isNext ? HouseLadder.block(above: state.rung, level: state.level, tasksDone: state.houseTasksDone, beans: state.beans) : nil
        let tasksDone = isNext ? state.houseTasksDone : 0
        return VStack(alignment: .leading, spacing: 8 * s) {
            HStack(spacing: 8 * s) {
                chip("Level \(rung.level)", detail: "You're \(state.level)", progress: Double(state.level) / Double(max(1, rung.level)), icon: "star.fill", s: s)
                if rung.tasks > 0 {
                    chip("House tasks", detail: isNext ? "\(tasksDone) of \(rung.tasks)" : "\(rung.tasks) to do there",
                         progress: isNext ? Double(tasksDone) / Double(rung.tasks) : 0, icon: "checklist", s: s)
                }
                chip("\(rung.price.formatted()) Beans", detail: "You have \(state.beans.formatted())",
                     progress: Double(state.beans) / Double(max(1, rung.price)), painted: "bean_coin", s: s)
            }
            if isNext {
                HStack(alignment: .bottom, spacing: 12 * s) {
                    if rung.tasks > 0 {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10 * s), GridItem(.flexible())], alignment: .leading, spacing: 4 * s) {
                            ForEach(Array(state.houseTaskProgress(on: today).enumerated()), id: \.offset) { _, entry in
                                task(entry.task, done: entry.done, s: s)
                            }
                        }
                    } else {
                        Spacer(minLength: 0)
                    }
                    moveIn(rung, block: block, s: s)
                }
            } else {
                note("Move into the home before it first.", icon: "lock.fill", s: s)
            }
        }
    }

    private func moveIn(_ rung: Rung, block: HouseLadder.Block?, s: CGFloat) -> some View {
        ChunkyButton(block == nil ? "Move in for \(rung.price.formatted()) Beans" : reason(block), colour: block == nil ? GameHUD.green : Theme.accent) {
            guard block == nil, GameSession.shared.buyNextHouse() else { return }
            Sound.play("door_open", volume: Tuning.Sound.door)
            movedIn()
        }
        .disabled(block != nil)
        .opacity(block == nil ? 1 : 0.65)
        .accessibilityIdentifier("buyNextHouse")
        .frame(width: 170 * s)
    }

    /// One thing a home needs, with how far along you are.
    private func chip(_ title: String, detail: String, progress: Double, icon: String? = nil, painted: String? = nil, s: CGFloat) -> some View {
        let met = progress >= 1
        return VStack(alignment: .leading, spacing: 4 * s) {
            HStack(spacing: 5 * s) {
                if let painted {
                    PaintedIcon(painted, size: 15 * s)
                } else if let icon {
                    Image(systemName: icon).font(.system(size: 12 * s, weight: .bold)).foregroundStyle(met ? GameHUD.green : Theme.accent)
                }
                Text(title).font(.system(size: 13 * s, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink).lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if met {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 14 * s)).foregroundStyle(GameHUD.green)
                }
            }
            ProgressView(value: min(1, max(0, progress))).tint(met ? GameHUD.green : Theme.accent)
            Text(detail).font(.system(size: 11 * s, weight: .semibold, design: .rounded)).foregroundStyle(Theme.inkSoft).lineLimit(1)
        }
        .padding(8 * s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12 * s, style: .continuous).fill(met ? GameHUD.green.opacity(0.12) : Theme.paper))
        .accessibilityElement(children: .combine)
    }

    /// One of the house's tasks.
    private func task(_ task: HouseTask, done: Int, s: CGFloat) -> some View {
        let finished = done >= task.target
        return HStack(spacing: 6 * s) {
            Image(systemName: finished ? "checkmark.square.fill" : "square")
                .font(.system(size: 13 * s)).foregroundStyle(finished ? GameHUD.green : Theme.inkSoft)
            Text(task.title.replacingOccurrences(of: "{cat}", with: catName))
                .font(.system(size: 12 * s, weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            Text("\(min(done, task.target))/\(task.target)").font(.system(size: 11 * s, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(Theme.inkSoft)
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
