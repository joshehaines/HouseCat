import SwiftUI

/// The cat's line in a text box at the bottom of the room (SPEC "The session loop" 3).
public struct GreetingBubble: View {
    private let line: String

    public init(_ line: String) {
        self.line = line
    }

    public var body: some View {
        Text(line)
            .font(.body.weight(.medium))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: 420)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
            .accessibilityLabel("Your cat says: \(line)")
    }
}
