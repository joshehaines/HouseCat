import HouseCatCore
import HouseCatGame
import HouseCatUI
import SwiftUI

/// The room view's one menu (Josh, 19 Oct: the room was crowded with controls, and the room arrows went): the
/// home's rooms to go to, then the map, the gift book, the pass, the gift track and the together quest.
/// Redrawn as a builder game's menu (Josh, 19 Oct: "the menu UI needs a full re-design as well to suit the app
/// more"): a painted card with a warm band, the home you live in (its painting, its place on the ladder and its rooms
/// as chips; the dollhouse it replaced looked crude, Josh 22 Oct), and the other places as chunky tiles. Both lists come from the app, so
/// a new place is one more item.
struct RoomMenu: View {
    /// What opening a closed room takes: the house up the ladder it comes with (docs/LADDER.md).
    struct Lock {
        let house: String
    }

    struct Room: Identifiable {
        let id: RoomID
        let storey: Int
        let title: String
        let lock: Lock?
        /// Its wallpaper and floor (surface ids, as the room draws them).
        let wall: String
        let floor: String
        /// A garden, balcony or terrace: drawn beside the house, under the sky.
        let outdoor: Bool
        let here: Bool
        let catHere: Bool
    }

    struct Item: Identifiable {
        let id: String
        let title: String
        let icon: String
        var dot = false
        let action: () -> Void
    }

    let catName: String
    let rooms: [Room]
    let items: [Item]
    let choose: (RoomID) -> Void
    let close: () -> Void

    @Environment(\.hudScale) private var scale
    @Environment(\.controlFeedback) private var feedback

    var body: some View {
        // Drawn for a phone on its side and enlarged whole on an iPad.
        PaintedPanel(corner: 24) {
            HStack(spacing: 8) {
                PaintedIcon("house", size: 34)
                    .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1.5)
                Text("\(catName)'s home")
                    .font(Theme.title(21))
                    .foregroundStyle(.white)
                    .shadow(color: Color(red: 0.47, green: 0.24, blue: 0.04).opacity(0.35), radius: 0, y: 2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 12)
                Button {
                    feedback.tap()
                    close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 30, height: 30)
                        .paper(Circle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Close")
            }
            .padding(.leading, 12)
            .padding(.trailing, 9)
            .frame(height: 46)
        } content: {
            HStack(alignment: .top, spacing: 14) {
                HomeCard(catName: catName, rooms: rooms) { room in
                    feedback.tap()
                    choose(room)
                }
                // Two abreast; three once there are more than six (Outside, 20 Oct, made a seventh possible), so the
                // card never runs past a phone's height.
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(80), spacing: 9), count: items.count > 6 ? 3 : 2), spacing: 13) {
                    ForEach(items) { item in
                        ChunkyTile(item.title, icon: item.icon, waiting: item.dot, action: item.action)
                    }
                }
                .padding(.top, 2)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .fixedSize()
        .zoomed(scale)
    }
}

/// The home you live in for the menu (Josh, 22 Oct: "the menu section needs to look a lot better, currently the house
/// looks awful"): the house's own painting in its town, its name and place, how far up the ladder it is, and its
/// rooms as chips to go to (a closed one says the house it comes with).
private struct HomeCard: View {
    let catName: String
    let rooms: [RoomMenu.Room]
    let choose: (RoomID) -> Void

    var body: some View {
        let state = GameSession.shared.state(at: GameSession.shared.now())
        let rung = state.currentRung
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                housePicture(rung)
                    .frame(width: 260, height: 146)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(rung.name).font(Theme.title(17)).foregroundStyle(.white)
                    Text("\(rung.place.name) · house \(rung.number) of \(HouseLadder.top)")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .shadow(color: .black.opacity(0.7), radius: 3)
                .padding(8)
            }
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.cream, lineWidth: 3))
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            // How far up the ladder: a dot a house, lit to here.
            HStack(spacing: 5) {
                ForEach(HouseLadder.rungs) { step in
                    Circle()
                        .fill(step.number <= rung.number ? Theme.accent : GameHUD.lip.opacity(0.25))
                        .frame(width: step.number == rung.number ? 12 : 9, height: step.number == rung.number ? 12 : 9)
                }
                Spacer(minLength: 0)
                Text("London").font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(Theme.inkSoft)
            }
            .frame(width: 260)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("House \(rung.number) of \(HouseLadder.top) on the way to London")
            // The rooms: open ones to go to, closed ones with their house.
            LazyVGrid(columns: [GridItem(.fixed(126), spacing: 8), GridItem(.fixed(126), spacing: 8)], alignment: .leading, spacing: 6) {
                ForEach(rooms) { room in
                    roomChip(room)
                }
            }
            .frame(width: 260, alignment: .leading)
        }
    }

    private func roomChip(_ room: RoomMenu.Room) -> some View {
        Button {
            if room.lock == nil {
                choose(room.id)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: room.lock == nil ? (room.here ? "location.fill" : "door.left.hand.open") : "lock.fill")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(room.lock == nil ? Theme.accent : Theme.inkSoft)
                VStack(alignment: .leading, spacing: 0) {
                    Text(room.title).font(.system(size: 12, weight: .heavy, design: .rounded)).lineLimit(1)
                    if let lock = room.lock {
                        Text("with the \(lock.house.lowercased())").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                Spacer(minLength: 0)
                if room.catHere {
                    Image(systemName: "pawprint.fill").font(.system(size: 10)).foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(width: 126, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(room.here ? Theme.cream : Theme.cream.opacity(room.lock == nil ? 0.8 : 0.45)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(room.here ? Theme.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(PressStyle())
        .disabled(room.lock != nil)
        .accessibilityLabel(room.lock.map { "\(room.title), closed, comes with the \($0.house)" } ?? room.title)
    }

    /// The house's painting: the first house's run-down one, the others their small built-in previews, the sky
    /// painted in behind.
    private func housePicture(_ rung: Rung) -> some View {
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
