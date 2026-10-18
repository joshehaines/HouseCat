import SwiftUI

/// The room controls: Feed, Decorate (and while decorating Done plus, with a piece picked up, Turn
/// and Store; SPEC "The session loop" 5 and 7), and the stairs between storeys. Pet is a tap on the cat.
/// `RoomSwitcher` moves between the open rooms.
public struct DecorateBar: View {
    private let decorating: Bool
    private let hasSelection: Bool
    private let storeyTitle: String?
    private let canDecorate: Bool
    private let toggle: () -> Void
    private let turn: () -> Void
    private let store: () -> Void
    private let changeStorey: () -> Void
    private let feed: (() -> Void)?

    public init(
        decorating: Bool,
        hasSelection: Bool,
        storeyTitle: String? = nil,
        canDecorate: Bool = true,
        toggle: @escaping () -> Void,
        turn: @escaping () -> Void,
        store: @escaping () -> Void,
        changeStorey: @escaping () -> Void = {},
        feed: (() -> Void)? = nil
    ) {
        self.decorating = decorating
        self.hasSelection = hasSelection
        self.storeyTitle = storeyTitle
        self.canDecorate = canDecorate
        self.toggle = toggle
        self.turn = turn
        self.store = store
        self.changeStorey = changeStorey
        self.feed = feed
    }

    public var body: some View {
        HStack(spacing: 10) {
            if decorating, hasSelection {
                HUDButton("Turn", symbol: "arrow.triangle.2.circlepath", action: turn)
                HUDButton("Store", icon: "sofa_for_furniture", action: store)
            }
            if !decorating, let storeyTitle {
                HUDButton(storeyTitle, symbol: storeyTitle == "Upstairs" ? "arrow.up" : "arrow.down", action: changeStorey)
            }
            if canDecorate || decorating {
                if decorating {
                    HUDButton("Done", symbol: "checkmark", prominent: true, action: toggle)
                } else {
                    HUDButton("Decorate", icon: "decorate_paintbrush", action: toggle)
                }
            }
            if !decorating, canDecorate, let feed {
                HUDButton("Feed", icon: "feed_bowl", action: feed)
            }
        }
        .animation(.easeOut(duration: 0.2), value: hasSelection)
        .animation(.easeOut(duration: 0.2), value: decorating)
    }
}

/// The room you are in, with arrows to the next and previous open rooms (a tap on a room goes there too).
public struct RoomSwitcher: View {
    private let title: String
    private let canStep: Bool
    private let step: (Int) -> Void

    public init(title: String, canStep: Bool, step: @escaping (Int) -> Void) {
        self.title = title
        self.canStep = canStep
        self.step = step
    }

    @Environment(\.hudScale) private var scale
    @Environment(\.controlFeedback) private var feedback

    public var body: some View {
        HStack(spacing: 2 * scale) {
            if canStep {
                arrow("chevron.left", label: "Previous room") { step(-1) }
            }
            Text(title)
                .font(Theme.title(16 * scale))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, canStep ? 2 : 16 * scale)
                .contentTransition(.opacity)
            if canStep {
                arrow("chevron.right", label: "Next room") { step(1) }
            }
        }
        .padding(.vertical, 6 * scale)
        .padding(.horizontal, 4 * scale)
        .paper(Capsule())
        .animation(.easeOut(duration: 0.2), value: title)
    }

    private func arrow(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            feedback.tap()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15 * scale, weight: .bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 36 * scale, height: 32 * scale)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}
