import Foundation
import ImageIO
import SpriteKit

/// The app-sized art in the app bundle's `Art` folder (built from the masters by
/// tools/app-assets/build_app_art.py). Paths are the masters' paths relative to
/// `assets/`, so catalogue sprite paths work unchanged. Sizes are reported in
/// master pixels, the unit every scale in the data is written in.
@MainActor
public final class ArtLibrary {
    public struct Entry: Decodable, Sendable {
        /// The painted file's size in pixels.
        public var painted: [Double]
        public var scale: Double
        /// The reference room furniture was painted in ("grey" or "cream").
        public var ref: String?

        enum CodingKeys: String, CodingKey {
            case painted = "master", scale, ref
        }
    }

    private struct Index: Decodable {
        var files: [String: Entry]
    }

    public let root: URL
    private let entries: [String: Entry]
    private var textures: [String: SKTexture] = [:]
    private var images: [String: CGImage] = [:]

    public init(root: URL) throws {
        self.root = root
        let data = try Data(contentsOf: root.appendingPathComponent("art.json"))
        entries = try JSONDecoder().decode(Index.self, from: data).files
    }

    /// The `Art` folder in a bundle.
    public convenience init(bundle: Bundle) throws {
        guard let url = bundle.url(forResource: "Art", withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try self.init(root: url)
    }

    public func has(_ path: String) -> Bool {
        entries[path] != nil
    }

    /// The master's size in pixels.
    public func paintedSize(_ path: String) -> CGSize {
        guard let entry = entries[path], entry.painted.count == 2 else { return .zero }
        return CGSize(width: entry.painted[0], height: entry.painted[1])
    }

    /// The reference room a piece of furniture was painted in.
    public func referenceRoom(_ path: String) -> String? {
        entries[path]?.ref
    }

    public func image(_ path: String) -> CGImage? {
        if let cached = images[path] {
            return cached
        }
        let url = root.appendingPathComponent(path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        images[path] = image
        return image
    }

    public func texture(_ path: String) -> SKTexture {
        if let cached = textures[path] {
            return cached
        }
        let texture = image(path).map { SKTexture(cgImage: $0) } ?? SKTexture()
        texture.filteringMode = .linear
        textures[path] = texture
        return texture
    }

    /// A data file (rig, layout, fx anchors) decoded from JSON.
    public func data<T: Decodable>(_ path: String, as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: root.appendingPathComponent(path)))
    }
}
