#if DEBUG
    import HouseCatCore
    import HouseCatUI
    import SwiftUI
    import WidgetKit

    /// Debug (HOUSECAT_SCREEN=widgets): every widget size, then every pose and some weather, drawn by the
    /// widget's own views from what the app left in the App Group, so they can be checked without a Home
    /// Screen. HOUSECAT_GALLERY=poses or weather shows that page.
    struct WidgetGallery: View {
        @State private var world: WidgetWorld?
        private let page = ProcessInfo.processInfo.environment["HOUSECAT_GALLERY"] ?? "sizes"

        var body: some View {
            Group {
                if let world, world.kit != nil, let now = world.scenes(from: Date()).first {
                    switch page {
                    case "poses": poses(world, now)
                    case "weather": weather(world, now)
                    default: sizes(world, now)
                    }
                } else {
                    ProgressView("Making the widget's pictures")
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.36, green: 0.5, blue: 0.62).ignoresSafeArea())
            .task {
                // Once the kit for this cat and home is finished (an old one may still be on disk).
                try? await Task.sleep(for: .seconds(1))
                while WidgetBridge.isMakingKit {
                    try? await Task.sleep(for: .seconds(0.5))
                }
                while world?.kit == nil {
                    world = WidgetWorld.load()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }

        private func entry(_ world: WidgetWorld, _ scene: WidgetScene) -> WidgetEntry {
            WidgetEntry(date: scene.state.date, scene: scene, catName: world.catName, caption: world.caption(scene), kit: world.kit)
        }

        private func card(_ entry: WidgetEntry, _ family: WidgetFamily, width: CGFloat, height: CGFloat) -> some View {
            HouseCatWidgetView(entry: entry, family: family)
                .frame(width: width, height: height)
                .background(Theme.paper)
                .clipShape(RoundedRectangle(cornerRadius: height < 100 ? 14 : 22, style: .continuous))
        }

        private func sizes(_ world: WidgetWorld, _ now: WidgetScene) -> some View {
            HStack(alignment: .top, spacing: 18) {
                card(entry(world, now), .systemSmall, width: 170, height: 170)
                card(entry(world, now), .systemMedium, width: 364, height: 170)
                VStack(alignment: .leading, spacing: 12) {
                    card(entry(world, now), .accessoryCircular, width: 76, height: 76)
                    card(entry(world, now), .accessoryRectangular, width: 172, height: 76)
                    HouseCatWidgetView(entry: entry(world, now), family: .accessoryInline).foregroundStyle(.white)
                }
            }
        }

        /// The small widget in every pose (asleep at night, the rest by day).
        private func poses(_ world: WidgetWorld, _ now: WidgetScene) -> some View {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(118), spacing: 10), count: 6), spacing: 10) {
                ForEach(WidgetPose.allCases, id: \.self) { pose in
                    let scene = with(now) {
                        $0.state.pose = pose
                        $0.catPose = pose.catPose
                        $0.sky = pose == .asleep || pose == .stillWaiting ? .night : pose == .zoomies ? .dusk : .day
                        $0.state.lineContext = pose == .stillWaiting ? WidgetRules.stillWaitingLine : nil
                    }
                    VStack(spacing: 3) {
                        card(entry(world, scene), .systemSmall, width: 118, height: 118)
                        Text(pose.rawValue).font(.caption2).foregroundStyle(.white)
                    }
                }
            }
        }

        /// The medium widget in each weather, at different times.
        private func weather(_ world: WidgetWorld, _ now: WidgetScene) -> some View {
            let skies: [SkyPhase] = [.day, .dusk, .night, .dawn]
            return LazyVGrid(columns: Array(repeating: GridItem(.fixed(250), spacing: 12), count: 3), spacing: 12) {
                // Drawn at a real medium's size and shrunk, so the buttons sit as they do on the Home Screen.
                ForEach(Array(Weather.allCases.enumerated()), id: \.offset) { index, weather in
                    let scene = with(now) {
                        $0.weather = weather
                        $0.sky = skies[index % skies.count]
                    }
                    VStack(spacing: 2) {
                        card(entry(world, scene), .systemMedium, width: 364, height: 170)
                            .scaleEffect(250 / 364)
                            .frame(width: 250, height: 117)
                        Text("\(weather.rawValue), \(scene.sky.rawValue)").font(.caption2).foregroundStyle(.white)
                    }
                }
            }
        }

        private func with(_ scene: WidgetScene, _ change: (inout WidgetScene) -> Void) -> WidgetScene {
            var scene = scene
            change(&scene)
            return scene
        }
    }
#endif
