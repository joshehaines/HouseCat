import HouseCatCore
import HouseCatUI
import Observation
import SwiftUI

/// The host's first-use tips (Content/intro.json "tips"; Josh, 25 Oct, after the onboarding research: the tour was
/// read out control by control, so those lines come later, where they are used). After the tour, one tip a visit
/// points at its control without dimming the room, until each has been seen or its control used. Where they got to
/// is kept on the device.
@MainActor
@Observable
final class FirstTips {
    static let shared = FirstTips()

    @ObservationIgnored private let defaults = UserDefaults(suiteName: WidgetFiles.appGroup) ?? .standard
    /// The tip on screen now.
    private(set) var current: IntroFile.Tip?

    private init() {}

    private var tips: [IntroFile.Tip] {
        GameWorld.content?.intro.tips ?? []
    }

    private var seen: Set<String> {
        get { Set(defaults.stringArray(forKey: "tips.seen") ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: "tips.seen") }
    }

    /// The next tip not yet seen whose control is on screen now.
    func showNext(on screen: Set<String>) {
        guard current == nil else { return }
        let seen = seen
        current = tips.first { !seen.contains($0.id) && screen.contains($0.target) }
    }

    /// A control was used: its tip has done its job, shown or not.
    func used(_ target: String) {
        let ids = tips.filter { $0.target == target }.map(\.id)
        guard !ids.isEmpty else { return }
        seen.formUnion(ids)
        if let current, ids.contains(current.id) {
            withAnimation(.easeOut(duration: 0.25)) { self.current = nil }
        }
    }

    func dismiss() {
        guard let current else { return }
        seen.insert(current.id)
        withAnimation(.easeOut(duration: 0.25)) { self.current = nil }
    }

    /// From Settings: the tips again from the first.
    func reset() {
        seen = []
        current = nil
    }
}

/// The tip on screen: a ring round its control and the host's line at the top, with Got it. The room stays lit and
/// touchable (a tip is a word in passing, not a step to do).
struct FirstTipOverlay: View {
    let tip: IntroFile.Tip
    let catName: String
    let host: String
    let targets: [String: Anchor<CGRect>]
    @Environment(\.hudScale) private var scale

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let anchor = targets[tip.target] {
                    let frame = proxy[anchor].insetBy(dx: -8, dy: -8)
                    TimelineView(.animation) { timeline in
                        let pulse = 0.5 + 0.5 * sin(timeline.date.timeIntervalSinceReferenceDate * 4)
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Theme.cream, lineWidth: 3 + 2 * pulse)
                            .shadow(color: Theme.accent.opacity(0.8), radius: 6 + 6 * pulse)
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                    }
                    .allowsHitTesting(false)
                }
                VStack {
                    HostBubble(
                        name: host,
                        text: tip.text(cat: catName, you: PlayerName.current),
                        button: "Got it",
                        compact: true
                    ) {
                        Sound.tap()
                        FirstTips.shared.dismiss()
                    }
                    .frame(maxWidth: 420)
                    .zoomed(scale)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 6)
                .frame(maxWidth: .infinity)
            }
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }
}
