import SwiftUI

/// The level (with how far into it), Beans and streak, top right. Each part opens its own page when given an
/// action: the level its road, the Beans the shop's packs, the streak its card.
public struct StatusPill: View {
    @Environment(\.hudScale) private var scale
    private let level: Int
    /// How far into the level, 0 to 1.
    private let progress: Double
    private let beans: Int
    private let streak: Int
    private let onLevel: (() -> Void)?
    private let onBeans: (() -> Void)?
    private let onStreak: (() -> Void)?

    public init(
        level: Int,
        progress: Double = 0,
        beans: Int,
        streak: Int,
        onLevel: (() -> Void)? = nil,
        onBeans: (() -> Void)? = nil,
        onStreak: (() -> Void)? = nil
    ) {
        self.level = level
        self.progress = progress
        self.beans = beans
        self.streak = streak
        self.onLevel = onLevel
        self.onBeans = onBeans
        self.onStreak = onStreak
    }

    public var body: some View {
        HStack(spacing: 12 * scale) {
            part(onLevel, label: "Level \(level), \(Int(progress * 100)) percent to the next. Shows the road ahead.") {
                HStack(spacing: 4 * scale) {
                    PaintedIcon("xp_star", size: 30 * scale)
                    VStack(alignment: .leading, spacing: 2 * scale) {
                        value("\(level)")
                        // The XP bar: how far into this level.
                        Capsule().fill(Theme.rim)
                            .frame(width: 34 * scale, height: 5 * scale)
                            .overlay(alignment: .leading) {
                                Capsule().fill(Theme.accent).frame(width: 34 * scale * max(0.06, min(1, progress)))
                            }
                            .animation(.spring(duration: 0.6), value: progress)
                    }
                }
            }
            part(onBeans, label: "\(beans) Beans. Get more.") {
                HStack(spacing: 4 * scale) {
                    PaintedIcon("bean_coin", size: 30 * scale)
                    value(beans.formatted())
                }
            }
            part(onStreak, label: "\(streak) day streak. Shows the streak.") {
                HStack(spacing: 4 * scale) {
                    PaintedIcon("streak_paw_print_with_a_small_flame", size: 30 * scale)
                    value("\(streak)")
                }
            }
        }
        .padding(.horizontal, 12 * scale)
        .padding(.vertical, 4 * scale)
        .paper(Capsule())
    }

    private func value(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16 * scale, weight: .bold).monospacedDigit())
            .foregroundStyle(Theme.ink)
            .contentTransition(.numericText())
    }

    @ViewBuilder
    private func part(_ action: (() -> Void)?, label: String, @ViewBuilder content: () -> some View) -> some View {
        if let action {
            Button(action: action) { content().contentShape(Rectangle()) }
                .buttonStyle(PressStyle())
                .accessibilityLabel(label)
        } else {
            content().accessibilityElement(children: .ignore).accessibilityLabel(label)
        }
    }
}
