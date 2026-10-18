import SwiftUI

/// The cat's line in a speech card at the top of the room (SPEC "The session loop" 3), with the cat's name.
public struct GreetingBubble: View {
    @Environment(\.hudScale) private var scale
    private let line: String
    private let name: String?

    public init(_ line: String, name: String? = nil) {
        self.line = line
        self.name = name
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name ?? "Your cat") says: \(line)")
    }
}
