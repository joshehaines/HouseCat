import HouseCatCore
import HouseCatUI
import SwiftUI

/// The room tour on screen: the room dimmed but for the control it is about (lit, with a paw pointing at it),
/// and the host saying what to do. Only that control can be touched; a step that is read goes on with Next, or
/// when the control it points at is used. Skip ends the tour (the welcome Beans still come).
struct RoomTourOverlay: View {
    let tour: RoomTour
    let catName: String
    let host: String
    let targets: [String: Anchor<CGRect>]
    /// Where the cat is now, for a step about the cat.
    var catPoint: () -> CGPoint? = { nil }
    @Environment(\.hudScale) private var scale

    var body: some View {
        GeometryReader { proxy in
            if let step = tour.step {
                let frame = step.target.flatMap { targets[$0] }.map { proxy[$0] }
                ZStack {
                    shade(step: step, hole: frame.map { $0.insetBy(dx: -8, dy: -8) }, in: proxy.size)
                    if let frame {
                        ring(frame.insetBy(dx: -8, dy: -8))
                        paw(at: frame, in: proxy.size)
                    } else if step.waitFor == .petted {
                        // The cat moves: the paw follows it.
                        TimelineView(.animation) { _ in
                            if let point = catPoint() {
                                paw(at: CGRect(x: point.x - 30, y: point.y - 50, width: 60, height: 100), in: proxy.size)
                            }
                        }
                        .allowsHitTesting(false)
                    }
                    VStack(spacing: 8) {
                        // Away from what it points at; at the top when the player must touch the room (the cat
                        // eats at the front of it), under the player's plaque rather than over it (the host's head
                        // stands about 32 points above the card).
                        if frame.map({ $0.midY > proxy.size.height / 2 }) ?? (step.waitFor != nil) {
                            bubble(step)
                                .padding(.top, targets["plaque"].map { max(0, proxy[$0].maxY + 26 * scale) } ?? 0)
                            Spacer()
                        } else {
                            Spacer()
                            bubble(step)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                }
                .animation(.easeOut(duration: 0.3), value: step.id)
            }
        }
        .ignoresSafeArea()
    }

    /// Dark all over but the hole, and the parts of the room the player may not touch now: all of it while a step
    /// with nothing to point at is read; round the hole when it points at a control (Josh's iPad, 19 Oct: Play, the
    /// nap and the shop did nothing while the tour pointed at them); nothing while stroking the cat or arranging a
    /// piece just placed. The blockers are always the same four views, resized and switched on or off
    /// without animation: a blocker swapped out with a fade stayed behind, invisible, over the whole room after the
    /// first step (Josh's iPad, 19 Oct: "Tap Feed" did nothing and no touch reached the room).
    private func shade(step: IntroFile.RoomStep, hole: CGRect?, in size: CGSize) -> some View {
        let full = CGRect(origin: .zero, size: size)
        let blocked: [CGRect] = if step.waitFor == nil, hole == nil {
            [full]
        } else if let hole, step.waitFor != .decorated {
            Self.around(hole, in: full)
        } else {
            []
        }
        let dim = Path { p in
            if let hole {
                p.addRect(full)
                p.addRoundedRect(in: hole, cornerSize: CGSize(width: 16, height: 16))
            } else if step.waitFor == nil {
                p.addRect(full)
            }
        }
        return ZStack {
            dim.fill(Color.black.opacity(hole == nil ? 0.35 : 0.5), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
            ForEach(0 ..< 4, id: \.self) { index in
                let block = index < blocked.count ? blocked[index] : .zero
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .frame(width: block.width, height: block.height)
                    .position(x: block.midX, y: block.midY)
                    .allowsHitTesting(index < blocked.count)
            }
        }
        .transaction { $0.animation = nil }
    }

    /// The parts of `full` round `hole`: above, below, and either side of it.
    static func around(_ hole: CGRect, in full: CGRect) -> [CGRect] {
        let hole = hole.intersection(full)
        guard !hole.isNull else { return [full] }
        return [
            CGRect(x: full.minX, y: full.minY, width: full.width, height: hole.minY - full.minY),
            CGRect(x: full.minX, y: hole.maxY, width: full.width, height: full.maxY - hole.maxY),
            CGRect(x: full.minX, y: hole.minY, width: hole.minX - full.minX, height: hole.height),
            CGRect(x: hole.maxX, y: hole.minY, width: full.maxX - hole.maxX, height: hole.height),
        ].filter { $0.width > 0 && $0.height > 0 }
    }

    private func ring(_ rect: CGRect) -> some View {
        TimelineView(.animation) { timeline in
            let pulse = 0.5 + 0.5 * sin(timeline.date.timeIntervalSinceReferenceDate * 4)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.cream, lineWidth: 3 + 2 * pulse)
                .shadow(color: Theme.accent.opacity(0.8), radius: 6 + 6 * pulse)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
        .allowsHitTesting(false)
    }

    /// The paw points at the control from below it (or above, near the bottom of the screen), always the right way up
    /// (Josh's iPad, 20 Oct: turned over under the cat at its bowl it was "up side down").
    private func paw(at rect: CGRect, in size: CGSize) -> some View {
        let below = rect.maxY + 60 < size.height
        return TimelineView(.animation) { timeline in
            let bob = sin(timeline.date.timeIntervalSinceReferenceDate * 5) * 7
            if let paw = CatScreens.picture("fx/reactions/fx_reactions_paw.png") {
                paw.resizable().scaledToFit()
                    .frame(width: 44, height: 44)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
                    .position(x: rect.midX, y: below ? rect.maxY + 30 + bob : rect.minY - 30 - bob)
            }
        }
        .allowsHitTesting(false)
    }

    private func bubble(_ step: IntroFile.RoomStep) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            HostBubble(name: host, text: text(step), button: button(step)) {
                Sound.tap()
                tour.next()
            }
            .id(step.id)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            if step.reward != true {
                Button("Skip the tour") { tour.skip() }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.cream)
                    .shadow(color: .black.opacity(0.6), radius: 2)
            }
        }
        .frame(maxWidth: 640)
        // Larger on an iPad, with the controls.
        .zoomed(scale)
    }

    private func text(_ step: IntroFile.RoomStep) -> String {
        let text = step.text(cat: catName)
        if step.reward == true, let beans = tour.rewarded, beans > 0 {
            return text + " +\(beans) Beans."
        }
        return text
    }

    private func button(_ step: IntroFile.RoomStep) -> String? {
        guard step.waitFor == nil else { return nil }
        return step.reward == true ? "Thank you" : "Next"
    }
}
