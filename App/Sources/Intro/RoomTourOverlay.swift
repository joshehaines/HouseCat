import HouseCatCore
import HouseCatUI
import SwiftUI

/// The room tour on screen: the room dimmed but for the control it is about (lit, with a paw pointing at it),
/// and the host saying what to do. While a step waits for the player only that control can be touched; a step
/// that is read goes on with Next. Skip ends the tour (the welcome Beans still come).
struct RoomTourOverlay: View {
    let tour: RoomTour
    let catName: String
    let host: String
    let targets: [String: Anchor<CGRect>]
    /// Where the cat is now, for a step about the cat.
    var catPoint: () -> CGPoint? = { nil }

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
                        // eats at the front of it).
                        if frame.map({ $0.midY > proxy.size.height / 2 }) ?? (step.waitFor != nil) {
                            bubble(step)
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

    /// Dark all over but the hole. Touches go through the hole only while the step waits for the player there;
    /// a step with nothing to touch (stroke the cat) leaves the room free.
    @ViewBuilder
    private func shade(step: IntroFile.RoomStep, hole: CGRect?, in size: CGSize) -> some View {
        let full = CGRect(origin: .zero, size: size)
        if let hole {
            let path = Path { p in
                p.addRect(full)
                p.addRoundedRect(in: hole, cornerSize: CGSize(width: 16, height: 16))
            }
            path.fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
                .contentShape(step.waitFor == nil ? Path(full) : path, eoFill: step.waitFor != nil)
                .onTapGesture {}
                // Arranging the piece just placed: the room stays free to drag in.
                .allowsHitTesting(step.waitFor != .decorated)
        } else if step.waitFor == nil {
            Color.black.opacity(0.35).contentShape(Rectangle()).onTapGesture {}
        }
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

    /// The paw points at the control from below it (or above, near the bottom of the screen).
    private func paw(at rect: CGRect, in size: CGSize) -> some View {
        let below = rect.maxY + 60 < size.height
        return TimelineView(.animation) { timeline in
            let bob = sin(timeline.date.timeIntervalSinceReferenceDate * 5) * 7
            if let paw = CatScreens.picture("fx/reactions/fx_reactions_paw.png") {
                paw.resizable().scaledToFit()
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(below ? 180 : 0))
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
