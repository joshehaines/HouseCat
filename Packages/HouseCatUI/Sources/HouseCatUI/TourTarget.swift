import SwiftUI

/// Where the controls the room tour points at are on screen (the Feed button, the first piece in the tray...):
/// each marks itself with `.tourTarget(id)` and the tour's overlay reads their frames.
public struct TourTargets: PreferenceKey {
    public static let defaultValue: [String: Anchor<CGRect>] = [:]

    public static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

public extension View {
    /// Marks a control the tour can point at.
    func tourTarget(_ id: String) -> some View {
        anchorPreference(key: TourTargets.self, value: .bounds) { [id: $0] }
    }
}
