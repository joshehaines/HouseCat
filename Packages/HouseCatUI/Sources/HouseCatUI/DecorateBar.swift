import SwiftUI

/// The decorate controls: a button to start, and while decorating Done plus, with a piece picked up,
/// Turn and Store (SPEC "The session loop" 7).
public struct DecorateBar: View {
    private let decorating: Bool
    private let hasSelection: Bool
    private let toggle: () -> Void
    private let turn: () -> Void
    private let store: () -> Void

    public init(
        decorating: Bool,
        hasSelection: Bool,
        toggle: @escaping () -> Void,
        turn: @escaping () -> Void,
        store: @escaping () -> Void
    ) {
        self.decorating = decorating
        self.hasSelection = hasSelection
        self.toggle = toggle
        self.turn = turn
        self.store = store
    }

    public var body: some View {
        HStack(spacing: 10) {
            if decorating, hasSelection {
                button("Turn", systemImage: "arrow.triangle.2.circlepath", action: turn)
                button("Store", systemImage: "tray.and.arrow.down", action: store)
            }
            button(decorating ? "Done" : "Decorate", systemImage: decorating ? "checkmark" : "hammer", action: toggle)
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
