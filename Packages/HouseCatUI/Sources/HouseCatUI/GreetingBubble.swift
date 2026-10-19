import SwiftUI

/// The cat's line in a speech card at the top of the room (SPEC "The session loop" 3), with the cat's name.
public struct GreetingBubble: View {
    @Environment(\.hudScale) private var scale
    private let line: String
    private let name: String?
    private let pointsDown: Bool

    /// `pointsDown`: a tail under the bubble pointing at the cat it hangs over.
    public init(_ line: String, name: String? = nil, pointsDown: Bool = false) {
        self.line = line
        self.name = name
        self.pointsDown = pointsDown
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2 * scale) {
            if let name {
                Text(name)
                    .font(Theme.title(13 * scale))
                    .foregroundStyle(Theme.accent)
            }
            Text(line)
                .font(.system(size: 17 * scale, weight: .medium))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18 * scale)
        .padding(.vertical, 12 * scale)
        .frame(maxWidth: 440 * scale, alignment: .leading)
        .paper(RoundedRectangle(cornerRadius: 18 * scale, style: .continuous))
        .overlay(alignment: .bottom) {
            if pointsDown {
                Tail()
                    .fill(Theme.cream)
                    .frame(width: 22 * scale, height: 11 * scale)
                    .offset(y: 10 * scale)
                    .shadow(color: Theme.shadow.opacity(0.6), radius: 2, y: 2)
            }
        }
        .padding(.bottom, pointsDown ? 10 * scale : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name ?? "Your cat") says: \(line)")
    }
}

/// The speech bubble's tail: a soft point down at the speaker.
private struct Tail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.midX - rect.width * 0.12, y: rect.minY + rect.height * 0.5))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX + rect.width * 0.12, y: rect.minY + rect.height * 0.5))
        path.closeSubpath()
        return path
    }
}
