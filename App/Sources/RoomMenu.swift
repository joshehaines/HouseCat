import HouseCatCore
import HouseCatGame
import HouseCatUI
import SwiftUI

/// The room view's one menu (Josh, 19 Oct: the room was crowded with controls, and the room arrows went): the
/// home's rooms to go to, then the map, the gift book, the pass, the gift track and the together quest.
/// Redrawn as a builder game's menu (Josh, 19 Oct: "the menu UI needs a full re-design as well to suit the app
/// more"): a painted card with a warm band, the home as a dollhouse cut open floor by floor under its roof (each
/// room its own wallpaper and floor, the closed ones dark with a padlock and what opening them takes, a garden or
/// balcony beside the house under the sky), and the other places as chunky tiles. Both lists come from the app, so
/// a new place is one more item.
struct RoomMenu: View {
    /// What opening a closed room takes.
    struct Lock {
        let level: Int
        let beans: Int
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
                Dollhouse(catName: catName, rooms: rooms) { room in
                    feedback.tap()
                    choose(room)
                }
                LazyVGrid(columns: [GridItem(.fixed(80), spacing: 9), GridItem(.fixed(80))], spacing: 13) {
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

/// The home cut open like a dollhouse: its storeys top to bottom, each room side by side in a timber frame on a
/// beam, the roof over the top (a single room up there sits in the gable), the garden or balcony beside its storey,
/// all on a strip of grass under a pale sky.
private struct Dollhouse: View {
    let catName: String
    let rooms: [RoomMenu.Room]
    let choose: (RoomID) -> Void

    private let tile = CGSize(width: 96, height: 62)
    private let gap: CGFloat = 4
    private let overhang: CGFloat = 10
    private static let timber = Color(red: 0.48, green: 0.29, blue: 0.17)

    var body: some View {
        let storeys = Set(rooms.map(\.storey)).sorted(by: >)
        let widest = max(1, storeys.map { indoor($0).count }.max() ?? 1)
        let width = CGFloat(widest) * tile.width + CGFloat(widest - 1) * gap + gap * 2
        let top = storeys.first ?? 0
        // A single room on the top floor, nothing beside it, sits in the gable rather than under the roof.
        let gable = storeys.count > 1 && indoor(top).count == 1 && outdoor(top).isEmpty
        VStack(alignment: .leading, spacing: 0) {
            Roof()
                .frame(width: width + overhang * 2, height: gable ? 94 : 44)
                .overlay(alignment: .bottom) {
                    if gable, let room = indoor(top).first {
                        RoomTile(room: room, size: tile, catName: catName, choose: choose)
                            .padding([.horizontal, .top], gap)
                            .background { Self.timber }
                    }
                }
            ForEach(storeys.filter { !(gable && $0 == top) }, id: \.self) { storey in
                HStack(alignment: .bottom, spacing: 6) {
                    VStack(spacing: 0) {
                        HStack(spacing: gap) {
                            ForEach(indoor(storey)) { RoomTile(room: $0, size: tile, catName: catName, choose: choose) }
                        }
                        .padding([.horizontal, .top], gap)
                        .frame(width: width)
                        .background { Self.timber }
                        beam(width, colours: [Color(red: 0.6, green: 0.39, blue: 0.25), Color(red: 0.43, green: 0.25, blue: 0.14)])
                    }
                    if !outdoor(storey).isEmpty {
                        VStack(spacing: 0) {
                            HStack(spacing: gap) {
                                ForEach(outdoor(storey)) { RoomTile(room: $0, size: tile, catName: catName, choose: choose) }
                            }
                            beam(nil, colours: [Color(red: 0.55, green: 0.6, blue: 0.35), Color(red: 0.37, green: 0.44, blue: 0.22)])
                        }
                    }
                }
                .padding(.leading, overhang)
            }
            // The grass the house stands on.
            LinearGradient(
                colors: [Color(red: 0.53, green: 0.76, blue: 0.37), Color(red: 0.37, green: 0.6, blue: 0.27)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 12)
            .padding(.horizontal, -10)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .background(alignment: .top) { sky }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.rim, lineWidth: 1))
    }

    private func indoor(_ storey: Int) -> [RoomMenu.Room] {
        rooms.filter { $0.storey == storey && !$0.outdoor }
    }

    private func outdoor(_ storey: Int) -> [RoomMenu.Room] {
        rooms.filter { $0.storey == storey && $0.outdoor }
    }

    private func beam(_ width: CGFloat?, colours: [Color]) -> some View {
        LinearGradient(colors: colours, startPoint: .top, endPoint: .bottom)
            .frame(width: width, height: 7)
    }

    /// A pale sky with a few soft clouds.
    private var sky: some View {
        LinearGradient(
            colors: [
                Color(red: 0.75, green: 0.88, blue: 0.94),
                Color(red: 0.89, green: 0.94, blue: 0.95),
                Color(red: 0.95, green: 0.92, blue: 0.86),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(alignment: .topLeading) { cloud.offset(x: 22, y: 12) }
        .overlay(alignment: .topTrailing) { cloud.scaleEffect(1.15).offset(x: -24, y: 34) }
        .accessibilityHidden(true)
    }

    private var cloud: some View {
        ZStack(alignment: .bottomLeading) {
            Capsule().frame(width: 46, height: 14)
            Capsule().frame(width: 22, height: 16).offset(x: 13, y: -7)
        }
        .foregroundStyle(.white.opacity(0.85))
    }
}

/// A terracotta gable: rows of round tiles, a darker edge and a chimney.
private struct Roof: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            // The chimney first, behind the slope.
            let chimney = CGRect(x: w * 0.72, y: h * 0.1, width: 16, height: h * 0.55)
            context.fill(Path(chimney), with: .color(Color(red: 0.66, green: 0.34, blue: 0.23)))
            context.fill(
                Path(roundedRect: CGRect(x: chimney.minX - 3, y: chimney.minY - 3, width: 22, height: 7), cornerRadius: 2),
                with: .color(Color(red: 0.49, green: 0.24, blue: 0.16))
            )
            var gable = Path()
            gable.move(to: CGPoint(x: 0, y: h))
            gable.addLine(to: CGPoint(x: w / 2, y: 2))
            gable.addLine(to: CGPoint(x: w, y: h))
            gable.closeSubpath()
            context.fill(gable, with: .linearGradient(
                Gradient(colors: [Color(red: 0.85, green: 0.45, blue: 0.29), Color(red: 0.72, green: 0.36, blue: 0.22)]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: h)
            ))
            // The rows of round tiles, clipped to the gable.
            var tiles = context
            tiles.clip(to: gable)
            var rows = Path()
            for (row, y) in stride(from: CGFloat(12), through: h, by: 11).enumerated() {
                for x in stride(from: CGFloat(row % 2) * -9, through: w, by: 18) {
                    rows.move(to: CGPoint(x: x, y: y))
                    rows.addQuadCurve(to: CGPoint(x: x + 18, y: y), control: CGPoint(x: x + 9, y: y - 8))
                }
            }
            tiles.stroke(rows, with: .color(Color(red: 0.6, green: 0.27, blue: 0.15).opacity(0.85)), lineWidth: 1.8)
            context.stroke(
                gable,
                with: .color(Color(red: 0.49, green: 0.24, blue: 0.16)),
                style: StrokeStyle(lineWidth: 4, lineJoin: .round)
            )
        }
        .accessibilityHidden(true)
    }
}

/// A room as a dollhouse room: its wallpaper on the back wall, its floor going away from you, its name on a plaque;
/// the room you are in ringed in gold, the cat's marked with its face, a closed one dark with a padlock and what
/// opening it takes.
private struct RoomTile: View {
    let room: RoomMenu.Room
    let size: CGSize
    let catName: String
    let choose: (RoomID) -> Void

    var body: some View {
        let wallHeight = size.height * 0.6
        Button {
            choose(room.id)
        } label: {
            ZStack(alignment: .top) {
                picture("rooms/walls/\(room.wall).png")
                    .frame(width: size.width, height: wallHeight)
                    .clipped()
                picture("rooms/floors/\(room.floor).png")
                    .frame(width: size.width * 1.7, height: size.height * 0.62)
                    .rotation3DEffect(.degrees(46), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.85)
                    .frame(width: size.width, height: size.height - wallHeight, alignment: .top)
                    .clipped()
                    .offset(y: wallHeight)
                // The skirting, and the light from the top left.
                Rectangle().fill(.white.opacity(0.75)).frame(height: 2.5).offset(y: wallHeight - 2)
                    .shadow(color: .black.opacity(0.15), radius: 0, y: 1)
                LinearGradient(
                    colors: [
                        Color(red: 1, green: 0.95, blue: 0.8).opacity(0.3),
                        .clear,
                        Color(red: 0.16, green: 0.08, blue: 0.04).opacity(0.18),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottom
                )
                if let lock = room.lock {
                    closed(lock)
                } else {
                    plaque
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .overlay {
                if room.here {
                    Rectangle().strokeBorder(GameHUD.gold, lineWidth: 3.5)
                        .shadow(color: GameHUD.gold.opacity(0.8), radius: 4)
                }
            }
            .overlay(alignment: .topTrailing) {
                if room.catHere {
                    PaintedIcon("cat_face", size: 21)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Theme.cream))
                        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                        .padding(4)
                }
            }
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(
            room.title + (room.lock.map { ", closed: level \($0.level), \($0.beans.formatted()) Beans" } ?? "")
                + (room.here ? ", you're here" : "") + (room.catHere ? ", \(catName) is here" : "")
        )
    }

    private func picture(_ path: String) -> some View {
        (CatScreens.picture(path) ?? Image(systemName: "square"))
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            // A closed room's surfaces are greyed under its veil.
            .saturation(room.lock == nil ? 1 : 0.3)
    }

    private var plaque: some View {
        Text(room.title)
            .font(.system(.caption2, design: .rounded, weight: .heavy))
            .foregroundStyle(room.here ? Color(red: 0.42, green: 0.26, blue: 0.06) : Theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(room.here
                    ? AnyShapeStyle(LinearGradient(
                        colors: [Color(red: 1, green: 0.9, blue: 0.6), Color(red: 0.95, green: 0.75, blue: 0.31)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    : AnyShapeStyle(Theme.cream.opacity(0.95))))
            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
            .padding(.horizontal, 4)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 4)
    }

    /// Dark, with the padlock, its name and what opening it takes: the level and the Beans.
    private func closed(_ lock: RoomMenu.Lock) -> some View {
        ZStack(alignment: .top) {
            Color(red: 0.16, green: 0.11, blue: 0.2).opacity(0.5)
            VStack(spacing: 0) {
                PaintedIcon("padlock", size: 22).padding(.top, 3)
                Text(room.title)
                    .font(.system(.caption2, design: .rounded, weight: .heavy))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 1.5, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    PaintedIcon("xp_star", size: 12)
                    Text("\(lock.level)")
                    PaintedIcon("bean_coin", size: 12).padding(.leading, 3)
                    Text(lock.beans.formatted())
                }
                .font(.system(size: 10, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(.black.opacity(0.55)))
                .padding(.bottom, 4)
            }
            .padding(.horizontal, 3)
        }
    }
}
