import SwiftUI

/// The decorate tray: the pieces owned but not placed (tap one to put it in the room), the Bean shop
/// (each piece with its price; tap to buy it straight into the room), or the room's wallpapers and floors
/// (tap one to put it up).
public struct DecorateTray: View {
    public struct Entry: Identifiable {
        public var id: String
        public var name: String
        public var count: Int
        public var image: Image?
        /// The surface up now (walls and floors mode).
        public var selected: Bool
        /// In the shop: the price, or what it needs ("Level 6"), and whether it can be bought now.
        public var price: String?
        public var enabled: Bool

        public init(
            id: String,
            name: String,
            count: Int,
            image: Image?,
            selected: Bool = false,
            price: String? = nil,
            enabled: Bool = true
        ) {
            self.id = id
            self.name = name
            self.count = count
            self.image = image
            self.selected = selected
            self.price = price
            self.enabled = enabled
        }
    }

    /// A tray tab: its word and its painted icon.
    public struct Mode: Hashable {
        public var title: String
        public var icon: String

        public init(_ title: String, icon: String) {
            self.title = title
            self.icon = icon
        }
    }

    @Environment(\.hudScale) private var scale
    private let entries: [Entry]
    private let modes: [Mode]
    private let mode: Int
    private let selectMode: (Int) -> Void
    private let place: (String) -> Void
    private let empty: String

    public init(
        entries: [Entry],
        modes: [Mode] = [],
        mode: Int = 0,
        selectMode: @escaping (Int) -> Void = { _ in },
        empty: String = "Everything you own is out. Store a piece to move it here.",
        place: @escaping (String) -> Void
    ) {
        self.empty = empty
        self.entries = entries
        self.modes = modes
        self.mode = mode
        self.selectMode = selectMode
        self.place = place
    }

    /// The tray's height on screen, for the scene to frame the room above it.
    public static func height(scale: CGFloat) -> CGFloat {
        (cardHeight + 20) * scale
    }

    static let cardHeight: CGFloat = 96

    public var body: some View {
        HStack(alignment: .center, spacing: 6 * scale) {
            if modes.count > 1 {
                // The tabs as a column of painted icons down the tray's left edge.
                VStack(spacing: 2 * scale) {
                    ForEach(Array(modes.enumerated()), id: \.offset) { index, tab in
                        Button {
                            selectMode(index)
                        } label: {
                            HStack(spacing: 3 * scale) {
                                PaintedIcon(tab.icon, size: 20 * scale)
                                Text(tab.title).font(.system(size: 12 * scale, weight: .semibold))
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(index == mode ? Theme.ink : Theme.inkSoft)
                            .padding(.horizontal, 6 * scale)
                            .frame(width: 84 * scale, height: 22 * scale)
                            .background(Capsule().fill(index == mode ? Theme.cream : Color.clear))
                            .overlay(Capsule().strokeBorder(index == mode ? Theme.rim : .clear, lineWidth: 1))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityAddTraits(index == mode ? .isSelected : [])
                    }
                }
                .padding(.leading, 10 * scale)
            }
            items
        }
        .frame(height: Self.height(scale: scale))
        // A dock: the paper runs on under the home indicator and out to the screen's edges.
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 22 * scale, topTrailingRadius: 22 * scale)
                .fill(Theme.paper)
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 22 * scale, topTrailingRadius: 22 * scale).strokeBorder(
                    Theme.rim,
                    lineWidth: 1
                ))
                .shadow(color: Theme.shadow, radius: 8, y: -2)
                .ignoresSafeArea(edges: [.bottom, .horizontal])
        }
    }

    private var items: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8 * scale) {
                if entries.isEmpty {
                    Text(empty)
                        .font(.system(size: 14 * scale))
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.horizontal, 8 * scale)
                        .frame(height: Self.cardHeight * scale)
                }
                ForEach(entries) { entry in
                    Button {
                        place(entry.id)
                    } label: {
                        VStack(spacing: 2 * scale) {
                            (entry.image ?? Image(systemName: "shippingbox"))
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .frame(width: 60 * scale, height: 50 * scale)
                            Text(entry.count > 1 ? "\(entry.name) ×\(entry.count)" : entry.name)
                                .font(.system(size: 11 * scale, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            if let price = entry.price {
                                HStack(spacing: 2 * scale) {
                                    if price.hasSuffix("Beans") {
                                        PaintedIcon("bean_coin", size: 14 * scale)
                                    } else {
                                        PaintedIcon("padlock", size: 14 * scale)
                                    }
                                    Text(price.replacingOccurrences(of: " Beans", with: ""))
                                        .font(.system(size: 12 * scale, weight: .bold).monospacedDigit())
                                        .foregroundStyle(entry.enabled ? Theme.accent : Theme.inkSoft)
                                }
                            }
                        }
                        .frame(width: 86 * scale, height: Self.cardHeight * scale)
                        .opacity(entry.enabled ? 1 : 0.55)
                        .paper(RoundedRectangle(cornerRadius: 14 * scale, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                                .strokeBorder(Theme.accent, lineWidth: entry.selected ? 3 : 0)
                        )
                    }
                    .buttonStyle(PressStyle())
                    .disabled(!entry.enabled)
                    .accessibilityLabel(entry.price.map { "Buy \(entry.name), \($0)" } ?? "Place \(entry.name)")
                }
            }
            .padding(.horizontal, 8 * scale)
            .padding(.vertical, 10 * scale)
        }
    }
}
