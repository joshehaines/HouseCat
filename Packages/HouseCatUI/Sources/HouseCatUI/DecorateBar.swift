import SwiftUI

/// The room controls: Feed, Decorate (and while decorating Done plus, with a piece picked up, Turn
/// and Store; SPEC "The session loop" 5 and 7), and the stairs between storeys. Pet is a tap on the cat.
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
                button("Turn", systemImage: "arrow.triangle.2.circlepath", action: turn)
                button("Store", systemImage: "tray.and.arrow.down", action: store)
            }
            if !decorating, let storeyTitle {
                button(storeyTitle, systemImage: storeyTitle == "Upstairs" ? "arrow.up.square" : "arrow.down.square", action: changeStorey)
            }
            if canDecorate || decorating {
                button(decorating ? "Done" : "Decorate", systemImage: decorating ? "checkmark" : "hammer", action: toggle)
            }
            if !decorating, canDecorate, let feed {
                button("Feed", systemImage: "fork.knife", action: feed)
            }
        }
        .animation(.easeOut(duration: 0.2), value: hasSelection)
    }

    private func button(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
