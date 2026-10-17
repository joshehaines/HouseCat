import SwiftUI

/// The inventory while decorating: the pieces owned but not placed, tap one to put it in the room.
public struct DecorateTray: View {
    public struct Entry: Identifiable {
        public var id: String
        public var name: String
        public var count: Int
        public var image: Image?

        public init(id: String, name: String, count: Int, image: Image?) {
            self.id = id
            self.name = name
            self.count = count
            self.image = image
        }
    }

    private let entries: [Entry]
    private let place: (String) -> Void

    public init(entries: [Entry], place: @escaping (String) -> Void) {
        self.entries = entries
        self.place = place
    }

    public var body: some View {
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
