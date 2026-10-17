import SwiftUI

/// Level, Beans and the visit streak at a glance (a stand-in until the UI design pass).
public struct StatusPill: View {
    private let level: Int
    private let beans: Int
    private let streak: Int

    public init(level: Int, beans: Int, streak: Int) {
        self.level = level
        self.beans = beans
        self.streak = streak
    }

    public var body: some View {
        HStack(spacing: 12) {
            Label("Level \(level)", systemImage: "star.fill")
            Label("\(beans)", systemImage: "circle.hexagongrid.fill")
            Label("\(streak)", systemImage: "pawprint.fill")
        }
        .font(.subheadline.weight(.semibold).monospacedDigit())
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Level \(level), \(beans) Beans, \(streak) day streak")
    }
}
