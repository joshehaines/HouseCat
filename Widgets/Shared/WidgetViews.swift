import HouseCatCore
import HouseCatUI
import SwiftUI
import WidgetKit
#if canImport(UIKit)
    import UIKit
#endif

/// One widget entry: the scene, and what to write on it. `scene` is nil before the app has first run.
struct WidgetEntry: TimelineEntry {
    var date: Date
    var scene: WidgetScene?
    var catName: String
    var caption: String?
    var kit: WidgetKitInfo?

    /// "Day 14 · fed" (SPEC "Widgets": the rectangular Lock Screen widget).
    var status: String {
        guard let state = scene?.state else { return "Open HouseCat" }
        let day = "Day \(state.streak)"
        if state.fedToday {
            return day + " · fed"
        }
        return day + (state.visitedToday ? " · visited" : " · waiting")
    }
}

/// The kit's pictures (made by the app for the player's cat and home), loaded once a process.
@MainActor
enum WidgetPictures {
    private static var cache: [String: Image] = [:]

    static func image(_ name: String) -> Image? {
        if let cached = cache[name] {
            return cached
        }
        #if canImport(UIKit)
            guard let url = WidgetFiles.kitFile(name), let picture = UIImage(contentsOfFile: url.path) else { return nil }
            let image = Image(uiImage: picture)
            cache[name] = image
            return image
        #else
            return nil
        #endif
    }
}

/// The window: the home's sky, terrain and weather behind the glass, the frame, the cat on the sill.
struct WidgetWindow: View {
    let entry: WidgetEntry
    let wide: Bool
    /// StandBy at night: the room is dark and the sky is night whatever the hour.
    var night = false

    var body: some View {
        GeometryReader { geometry in
            if let scene = entry.scene, let kit = entry.kit {
                let size = geometry.size
                let frame = frameRect(in: size)
                let box = wide ? kit.glassWide : kit.glass
                let glass = CGRect(
                    x: frame.minX + box.x * frame.width,
                    y: frame.minY + box.y * frame.height,
                    width: box.width * frame.width,
                    height: box.height * frame.height
                )
                let sky = night ? SkyPhase.night : scene.sky
                ZStack(alignment: .topLeading) {
                    outside(scene, sky: sky, glass: glass)
                    WidgetPictures.image(wide ? "frame_wide.png" : "frame.png")?
                        .resizable()
                        .colorMultiply(colour(Tuning.Widget.roomGrade[sky]))
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                    cat(scene, kit: kit, size: size, frame: frame, glass: glass, grade: colour(Tuning.Widget.roomGrade[sky]))
                }
            } else {
                Color(red: 0.98, green: 0.95, blue: 0.91)
            }
        }
    }

    /// The frame picture drawn to fill the widget, centred (a wider widget crops its top and bottom).
    private func frameRect(in size: CGSize) -> CGRect {
        let aspect = wide ? Tuning.Widget.wideFrameAspect : 1
        let width = max(size.width, size.height * aspect)
        let height = width / aspect
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    private func colour(_ rgb: [Double]?) -> Color {
        let c = rgb ?? [1, 1, 1]
        return Color(red: c[0], green: c[1], blue: c[2])
    }

    @ViewBuilder
    private func outside(_ scene: WidgetScene, sky: SkyPhase, glass: CGRect) -> some View {
        let grade = colour(Tuning.Sky.grade[sky])
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [colour(Tuning.Sky.top[sky]), colour(Tuning.Sky.bottom[sky])], startPoint: .top, endPoint: .bottom)
                .frame(width: glass.width, height: glass.height)
                .position(x: glass.midX, y: glass.midY)
            if let terrain = WidgetPictures.image("terrain_\(scene.season.rawValue).png") {
                let width = glass.width * Tuning.Widget.terrainOverhang
                let height = width / Tuning.Widget.terrainAspect
                terrain.resizable()
                    .colorMultiply(grade)
                    .frame(width: width, height: height)
                    .position(x: glass.midX, y: glass.maxY - height / 2 + glass.height * Tuning.Widget.terrainDrop)
            }
            WidgetWeather(weather: scene.weather, glass: glass, grade: grade)
        }
        .mask(Rectangle().frame(width: glass.width, height: glass.height).position(x: glass.midX, y: glass.midY))
    }

    /// The sill's top on screen: the frame's own line, else just under the glass.
    private func sill(_ name: String, frame: CGRect, glass: CGRect) -> CGFloat {
        guard let lines = Tuning.Widget.sill[name] else { return glass.maxY + frame.height * 0.06 }
        return frame.minY + frame.height * (wide ? lines[1] : lines[0])
    }

    @ViewBuilder
    private func cat(_ scene: WidgetScene, kit: WidgetKitInfo, size: CGSize, frame: CGRect, glass: CGRect, grade: Color) -> some View {
        if let picture = WidgetPictures.image(WidgetFiles.catFile(scene.catPose)),
           let pixels = kit.poses[scene.catPose.rawValue], let sit = kit.poses[CatPose.sitFront.rawValue]
        {
            // Every pose at the scale that makes a sitting cat this tall.
            let scale = size.height * (wide ? Tuning.Widget.catHeightWide : Tuning.Widget.catHeight) / sit[1]
            let width = pixels[0] * scale, height = pixels[1] * scale
            let feet = sill(scene.frame, frame: frame, glass: glass)
            let x = wide ? glass.minX + glass.width * Tuning.Widget.catXWide : glass.midX
            picture.resizable()
                .colorMultiply(grade)
                .frame(width: width, height: height)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                .position(x: x, y: feet - height / 2)
            if scene.state.pose == .holdingGift, let gift = WidgetPictures.image("icon_gift_box_with_a_ribbon.png") {
                gift.resizable()
                    .frame(width: height * 0.38, height: height * 0.38)
                    .position(x: x + width * 0.42, y: feet - height * 0.17)
            }
        }
    }
}

/// The weather as a still: a wash, clouds, rain streaks, snow or mist (the widget cannot animate).
struct WidgetWeather: View {
    let weather: Weather
    let glass: CGRect
    /// The sky's light, so clouds darken at night like the land.
    var grade: Color = .white

    var body: some View {
        let veil = veilColour
        ZStack(alignment: .topLeading) {
            if veil[3] > 0 {
                Color(red: veil[0], green: veil[1], blue: veil[2]).opacity(veil[3])
                    .frame(width: glass.width, height: glass.height)
                    .position(x: glass.midX, y: glass.midY)
            }
            if [.cloud, .rain, .storm, .snow, .wind].contains(weather), let cloud = WidgetPictures.image("cloud.png") {
                ForEach(0 ..< 3, id: \.self) { i in
                    let width = glass.width * (0.42 + Double(i % 2) * 0.16)
                    cloud.resizable()
                        .colorMultiply(weather == .storm || weather == .rain ? Color(white: 0.72) : .white)
                        .colorMultiply(grade)
                        .frame(width: width, height: width * 0.72)
                        .position(
                            x: glass.minX + glass.width * (0.12 + Double(i) * 0.38),
                            y: glass.minY + glass.height * (0.12 + Double(i % 2) * 0.1)
                        )
                }
            }
            Canvas { context, _ in
                switch weather {
                case .rain, .storm:
                    for i in 0 ..< (weather == .storm ? 46 : 30) {
                        let x = glass.minX + glass.width * fraction(i, 3571), y = glass.minY + glass.height * fraction(i, 7919)
                        var line = Path()
                        line.move(to: CGPoint(x: x, y: y))
                        line.addLine(to: CGPoint(x: x - glass.height * 0.03, y: y + glass.height * 0.11))
                        context.stroke(line, with: .color(.white.opacity(0.55)), lineWidth: 1)
                    }
                case .snow:
                    for i in 0 ..< 40 {
                        let x = glass.minX + glass.width * fraction(i, 3571), y = glass.minY + glass.height * fraction(i, 7919)
                        let r = 1 + fraction(i, 104_729) * 1.6
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.9)))
                    }
                case .fog:
                    let mist = Gradient(colors: [.white.opacity(0.75), .white.opacity(0)])
                    context.fill(
                        Path(CGRect(x: glass.minX, y: glass.midY - glass.height * 0.1, width: glass.width, height: glass.height * 0.6)),
                        with: .linearGradient(
                            mist,
                            startPoint: CGPoint(x: 0, y: glass.maxY),
                            endPoint: CGPoint(x: 0, y: glass.midY - glass.height * 0.1)
                        )
                    )
                default:
                    break
                }
            }
        }
    }

    /// A fixed scatter (by index), the same at every redraw.
    private func fraction(_ i: Int, _ prime: Int) -> Double {
        Double((i * prime) % 1000) / 1000
    }

    private var veilColour: [Double] {
        switch weather {
        case .cloud: Tuning.Weather.overcastVeil
        case .rain: Tuning.Weather.rainVeil
        case .storm: Tuning.Weather.stormVeil
        case .snow: Tuning.Weather.snowVeil
        case .fog: Tuning.Weather.fogVeil
        case .heat: Tuning.Weather.heatVeil
        case .sun, .wind: [0, 0, 0, 0]
        }
    }
}

/// The streak as a paw-print count on cream paper.
struct WidgetStreak: View {
    let streak: Int
    var size: CGFloat = 15

    var body: some View {
        HStack(spacing: 3) {
            WidgetPictures.image("icon_streak_paw_print_with_a_small_flame.png")?
                .resizable()
                .frame(width: size * 1.35, height: size * 1.35)
            Text("\(streak)")
                .font(.system(size: size, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .padding(.vertical, 2)
        .background(Capsule().fill(Theme.cream.opacity(0.94)))
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        .accessibilityLabel("Visit streak, \(streak) days")
    }
}

/// A round painted button on the widget (Feed, Pet) or a link (Visit).
struct WidgetButton<Label: View>: View {
    let label: Label

    var body: some View {
        label
            .frame(width: 38, height: 38)
            .background(Circle().fill(Theme.cream.opacity(0.95)))
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
    }
}

/// Every widget size, drawn from one entry.
struct HouseCatWidgetView: View {
    let entry: WidgetEntry
    let family: WidgetFamily
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: Label(entry.status, systemImage: "pawprint.fill")
        case .systemMedium: medium
        default: small
        }
    }

    private var streak: Int {
        entry.scene?.state.streak ?? 0
    }

    /// The window and the streak. In StandBy (no container background) the room is at night.
    private var small: some View {
        ZStack(alignment: .topLeading) {
            WidgetWindow(entry: entry, wide: false, night: !showsBackground)
            WidgetStreak(streak: streak, size: showsBackground ? 15 : 12).padding(10)
        }
        .widgetURL(URL(string: "housecat://visit"))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.catName). \(entry.status)")
    }

    /// The wide window, the streak, the cat's line, and Feed, Pet and Visit.
    private var medium: some View {
        ZStack(alignment: .topLeading) {
            WidgetWindow(entry: entry, wide: true)
            WidgetStreak(streak: streak).padding(10)
            VStack(spacing: 7) {
                Button(intent: FeedCatIntent()) {
                    WidgetButton(label: WidgetPictures.image("icon_feed_bowl.png")?.resizable().frame(width: 28, height: 28))
                }
                .accessibilityLabel("Feed \(entry.catName)")
                Button(intent: PetCatIntent()) {
                    WidgetButton(label: WidgetPictures.image("icon_petting_hand.png")?.resizable().frame(width: 28, height: 28))
                }
                .accessibilityLabel("Pet \(entry.catName)")
                Link(destination: URL(string: "housecat://visit")!) {
                    WidgetButton(label: WidgetPictures.image("icon_house.png")?.resizable().frame(width: 28, height: 28))
                }
                .accessibilityLabel("Visit \(entry.catName)")
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(.trailing, 10)
            if let caption = entry.caption {
                Text(caption)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.cream.opacity(0.94)))
                    .frame(maxWidth: 230, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(10)
            }
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "pawprint.fill").font(.system(size: 14, weight: .bold))
                Text("\(streak)").font(.system(size: 20, weight: .heavy, design: .rounded))
            }
        }
        .widgetAccentable()
        .accessibilityLabel("Visit streak, \(streak) days")
    }

    private var rectangular: some View {
        HStack(spacing: 6) {
            if let scene = entry.scene, let picture = WidgetPictures.image(WidgetFiles.catFile(scene.catPose)) {
                picture.resizable().renderingMode(.template).scaledToFit().frame(width: 38, height: 44)
                    .widgetAccentable()
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.catName).font(.headline).widgetAccentable()
                Text(entry.status).font(.caption)
            }
            Spacer(minLength: 0)
        }
    }
}
