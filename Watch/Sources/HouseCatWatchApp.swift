import HouseCatCore
import SwiftUI
import WidgetKit

/// The Watch app (SPEC "Watch"): the cat as the widget shows it, its streak, and Feed and Stroke, which count as
/// the day's visit from the Watch. Everything comes from the iPhone; nothing here needs the network.
@main
struct HouseCatWatchApp: App {
    init() {
        PhoneLink.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
                if ProcessInfo.processInfo.environment["HOUSECAT_SCREEN"] == "complications" {
                    ComplicationGallery()
                } else {
                    CatScreen()
                }
            #else
                CatScreen()
            #endif
        }
    }
}

#if DEBUG
    /// HOUSECAT_SCREEN=complications: the complication in every family, drawn from what is here now (a face
    /// can't be edited from the command line).
    private struct ComplicationGallery: View {
        var body: some View {
            let world = WidgetWorld.load()
            let entry = StreakEntry(
                date: Date(),
                name: world?.catName,
                state: world.map { WidgetRules.state(at: Date(), save: $0.state, context: $0.context) }
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        StreakView(entry: entry, family: .accessoryCircular)
                            .frame(width: 50, height: 50)
                        StreakView(entry: entry, family: .accessoryCorner)
                            .frame(width: 40, height: 40)
                    }
                    StreakView(entry: entry, family: .accessoryInline)
                        .font(.footnote)
                    StreakView(entry: entry, family: .accessoryRectangular)
                        .frame(height: 64)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
            }
        }
    }
#endif
