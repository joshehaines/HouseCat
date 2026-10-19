import HouseCatCore
import HouseCatGame
import HouseCatUI
import SwiftUI

/// The room view's one menu (Josh, 19 Oct: the room was crowded with controls, and the room arrows went): the
/// home's rooms to go to, floor by floor, each on its own floor with the closed ones bare and showing what opening
/// them takes, then the map, the gift book, the pass, the gift track and the together quest.
struct RoomMenu: View {
    struct Room: Identifiable {
        let id: RoomID
        let storey: Int
        let title: String
        /// What opening it takes ("Level 6 · 800 Beans"), when it is closed.
        let lock: String?
        /// The floor it shows (its own, or bare boards while closed).
        let floor: String
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
        let storeys = Set(rooms.map(\.storey)).sorted()
        VStack(alignment: .leading, spacing: 8 * scale) {
            HStack {
                Text("Rooms").font(Theme.title(18 * scale)).foregroundStyle(Theme.ink)
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
            HStack(alignment: .top, spacing: 14 * scale) {
                // The rooms, floor by floor.
                VStack(alignment: .leading, spacing: 8 * scale) {
                    ForEach(storeys, id: \.self) { storey in
                        VStack(alignment: .leading, spacing: 4 * scale) {
                            if storeys.count > 1 {
                                Text(storey == 0 ? "Downstairs" : storey == 1 ? "Upstairs" : "Top floor")
                                    .font(.system(size: 11 * scale, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Theme.inkSoft)
                                    .textCase(.uppercase)
                            }
                            HStack(spacing: 6 * scale) {
                                ForEach(rooms.filter { $0.storey == storey }) { room in
                                    tile(room)
                                }
                            }
                        }
                    }
                }
                Rectangle().fill(Theme.ink.opacity(0.1)).frame(width: 1)
                // The other places, down the side.
                VStack(spacing: 6 * scale) {
                    ForEach(items) { item in
                        Button {
                            feedback.tap()
                            item.action()
                        } label: {
                            HStack(spacing: 6 * scale) {
                                PaintedIcon(item.icon, size: 30 * scale)
                                    .overlay(alignment: .topTrailing) {
                                        if item.dot {
                                            Circle().fill(Theme.accent)
                                                .frame(width: 10 * scale, height: 10 * scale)
                                                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                                                .offset(x: 3 * scale, y: -2 * scale)
                                        }
                                    }
                                Text(item.title)
                                    .font(.system(size: 13 * scale, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8 * scale)
                            .frame(width: 112 * scale, height: 44 * scale)
                            .background(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous).fill(Theme.ink.opacity(0.05)))
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel(item.title + (item.dot ? ", something waiting" : ""))
                    }
                }
            }
        }
        .padding(14 * scale)
        .paper(RoundedRectangle(cornerRadius: 24 * scale, style: .continuous))
        .fixedSize()
    }

    /// A room as its floor, its name over it; the room you are in ringed, the cat's marked, a closed one locked.
    private func tile(_ room: Room) -> some View {
        Button {
            feedback.tap()
            choose(room.id)
        } label: {
            ZStack(alignment: .bottomLeading) {
                (CatScreens.picture("rooms/floors/\(room.floor).png") ?? Image(systemName: "square"))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: 92 * scale, height: 62 * scale)
                    .saturation(room.lock == nil ? 1 : 0.35)
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 1 * scale) {
                    Text(room.title)
                        .font(.system(size: 13 * scale, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    if let lock = room.lock {
                        Text(lock)
                            .font(.system(size: 10 * scale, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    } else if room.here {
                        Text("You're here")
                            .font(.system(size: 10 * scale, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                .padding(6 * scale)
            }
            .frame(width: 92 * scale, height: 62 * scale)
            .overlay(alignment: .topTrailing) {
                if room.lock != nil {
                    PaintedIcon("padlock", size: 18 * scale).padding(4 * scale)
                } else if room.catHere {
                    PaintedIcon("cat_face", size: 20 * scale).padding(3 * scale)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14 * scale, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                    .strokeBorder(room.here ? GameHUD.gold : Theme.ink.opacity(0.12), lineWidth: room.here ? 3 : 1)
            )
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(
            room.title + (room.lock.map { ", closed: \($0)" } ?? "") + (room.here ? ", you're here" : "")
                + (room.catHere ? ", \(catName) is here" : "")
        )
    }
}
