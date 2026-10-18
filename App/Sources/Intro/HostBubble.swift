import HouseCatCore
import HouseCatUI
import SwiftUI

/// The intro's host speaking: the mascot peeking over the top of a paper card with her name and line, and the
/// button that moves on (none while the player has something to do).
struct HostBubble: View {
    let name: String
    let text: String
    var button: String?
    /// Smaller, for a hint on a busy screen.
    var compact = false
    var action: (() -> Void)?
    @State private var shown = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(Theme.title(17)).foregroundStyle(Theme.accent)
                Text(text)
                    .font(.system(size: compact ? 14 : 17, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
            .padding(.leading, compact ? 66 : 86)
            Spacer(minLength: 0)
            if let button, let action {
                if compact {
                    HUDButton(button, symbol: "checkmark", action: action)
                } else {
                    ChunkyButton(button, action: action)
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.trailing, 14)
        .frame(maxWidth: 640, alignment: .leading)
        .paper(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            // The mascot, paws over the edge of the card.
            if let soot = CatScreens.picture("brand/icon/AppIcon_layer2_cat.png") {
                soot.resizable().scaledToFit()
                    .frame(width: compact ? 70 : 92, height: compact ? 70 : 92)
                    .offset(x: -4, y: -18)
                    .rotationEffect(.degrees(shown ? 0 : -8), anchor: .bottom)
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.5, bounce: 0.5)) { shown = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name): \(text)")
    }
}

/// The host's word on an onboarding screen (the builder, the globe, the homes), until "Got it".
struct HostHint: View {
    let text: KeyPath<IntroFile, String>
    let width: CGFloat
    @State private var hidden = false

    init(_ text: KeyPath<IntroFile, String>, width: CGFloat = 440) {
        self.text = text
        self.width = width
    }

    var body: some View {
        if !hidden, let intro = GameWorld.content?.intro {
            HostBubble(name: intro.host, text: intro[keyPath: text], button: "Got it", compact: true) {
                withAnimation(.easeOut(duration: 0.25)) { hidden = true }
            }
            .frame(maxWidth: width)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }
}
