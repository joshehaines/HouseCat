import HouseCatCore
import HouseCatGame
import HouseCatUI
import SwiftUI

/// Onboarding's house step (SPEC "The session loop": cat, geography, house, first arrival): the eight homes,
/// each painted where you pinned yours, a summer picture. The London terrace's exteriors are in the app; the
/// others arrive as a download (HomePacks), and until then the visit simply starts inside.
struct HomePicker: View {
    let biome: Biome
    let place: String
    let done: (HouseStyle) -> Void
    @State private var chosen: HouseStyle = .londonTerrace
    @Environment(\.controlFeedback) private var feedback

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                PaintedIcon("house", size: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Which home?").font(Theme.title(30))
                    // Where it is, and the host's word on what the choice means.
                    Text(GameWorld.content.map { "\(place) · \($0.intro.homes)" } ?? place)
                        .font(.subheadline).foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                HUDButton("Make it home", icon: "house", prominent: true) { done(chosen) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(HouseStyle.allCases) { style in
                        card(style)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
            .scrollClipDisabled()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.paper.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
    }

    static func colour(_ rgb: [Double]?) -> Color {
        let c = rgb ?? [1, 1, 1]
        return Color(red: c[0], green: c[1], blue: c[2])
    }

    private func card(_ style: HouseStyle) -> some View {
        let selected = style == chosen
        return Button {
            feedback.tap()
            withAnimation(.spring(duration: 0.3)) { chosen = style }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    // The painting's sky is cut out: a day sky behind it, as outside the house.
                    LinearGradient(
                        colors: [Self.colour(Tuning.Sky.top[.day]), Self.colour(Tuning.Sky.bottom[.day])],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    if let picture = CatScreens.picture("world/previews/\(style.rawValue)_\(biome.rawValue).jpg"),
                       let land = CatScreens.picture("world/previews/\(style.rawValue)_\(biome.rawValue)_land.png")
                    {
                        picture.resizable().interpolation(.high).scaledToFill()
                            .mask { land.resizable().scaledToFill().luminanceToAlpha() }
                    }
                }
                .frame(width: 300, height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text(style.name).font(Theme.title(19))
                Text(style.blurb).font(.caption).foregroundStyle(Theme.inkSoft).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(width: 320, alignment: .leading)
            .paper(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.accent, lineWidth: selected ? 4 : 0))
            .scaleEffect(selected ? 1.03 : 1)
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
