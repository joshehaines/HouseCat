import SwiftUI

/// Level, Beans and the visit streak at a glance, each with its painted icon.
public struct StatusPill: View {
    @Environment(\.hudScale) private var scale
    private let level: Int
    private let beans: Int
    private let streak: Int

    public init(level: Int, beans: Int, streak: Int) {
        self.level = level
        self.beans = beans
        self.streak = streak
    }

    public var body: some View {
        HStack(spacing: 12 * scale) {
            item("xp_star", "\(level)")
            item("bean_coin", beans.formatted())
            item("streak_paw_print_with_a_small_flame", "\(streak)")
        }
        .padding(.horizontal, 12 * scale)
        .padding(.vertical, 4 * scale)
        .paper(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Level \(level), \(beans) Beans, \(streak) day streak")
    }

    private func item(_ icon: String, _ value: String) -> some View {
        HStack(spacing: 4 * scale) {
            PaintedIcon(icon, size: 30 * scale)
            Text(value)
                .font(.system(size: 16 * scale, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
        }
    }
}
