import SwiftUI

/// The decorate tray: the pieces owned but not placed (tap one to put it in the room), or the room's
/// wallpapers and floors (tap one to put it up).
public struct DecorateTray: View {
    public struct Entry: Identifiable {
        public var id: String
        public var name: String
        public var count: Int
        public var image: Image?
        /// The surface up now (walls and floors mode).
        public var selected: Bool

        public init(id: String, name: String, count: Int, image: Image?, selected: Bool = false) {
            self.id = id
            self.name = name
            self.count = count
            self.image = image
            self.selected = selected
        }
    }

    private let entries: [Entry]
    private let modes: [String]
    private let mode: Int
    private let selectMode: (Int) -> Void
    private let place: (String) -> Void

    public init(
        entries: [Entry],
        modes: [String] = [],
        mode: Int = 0,
        selectMode: @escaping (Int) -> Void = { _ in },
        place: @escaping (String) -> Void
    ) {
        self.entries = entries
        self.modes = modes
        self.mode = mode
        self.selectMode = selectMode
        self.place = place
    }

    public var body: some View {
        VStack(spacing: 8) {
            if modes.count > 1 {
                Picker("Tray", selection: Binding(get: { mode }, set: selectMode)) {
                    ForEach(Array(modes.enumerated()), id: \.offset) { index, title in
                        Text(title).tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
            }
            items
        }
    }

    private var items: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if entries.isEmpty {
                    Text("Everything you own is out. Store a piece to move it here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                }
                ForEach(entries) { entry in
                    Button {
                        place(entry.id)
                    } label: {
                        VStack(spacing: 4) {
                            (entry.image ?? Image(systemName: "shippingbox"))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 56, height: 48)
                            Text(entry.count > 1 ? "\(entry.name) ×\(entry.count)" : entry.name)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                        }
                        .frame(width: 84)
                        .padding(.vertical, 8)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.accentColor, lineWidth: entry.selected ? 3 : 0)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Place \(entry.name)")
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 96)
    }
}
