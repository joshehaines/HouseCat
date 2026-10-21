import Foundation
import ImageIO
import SpriteKit
#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

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
        /// The file, when it is not at the master's path (opaque pictures are stored as HEIC).
        public var file: String?
        /// The iPad's sharper copy, when it has one.
        public var pad: Pad?

        enum CodingKeys: String, CodingKey {
            case painted = "master", scale, ref, file, pad
        }
    }

    /// A sharper copy for the iPad's larger screen: a data set in the app's iPad-only asset catalog
    /// (App/Resources/ArtPad.xcassets, which App Store thinning leaves out of an iPhone's download) and its scale.
    public struct Pad: Decodable, Sendable {
        public var asset: String
        public var scale: Double
    }

    /// Where the iPad's sharper copies come from: the app's asset catalog, or the catalog's folder (tests and renders).
    public enum PadSource {
        case catalog(Bundle)
        case folder(URL)
    }

    private struct Index: Decodable {
        var files: [String: Entry]
    }

    public let root: URL
    private var entries: [String: Entry]
    /// Where each master path's file is (this library's folder, or an asset pack's added later).
    private var roots: [String: URL] = [:]
    private var textures: [String: SKTexture] = [:]
    private var images: [String: CGImage] = [:]
    private var thumbnails: [String: CGImage] = [:]
    private var thumbnailsPending: Set<String> = []
    private var thumbnailWork: Task<Void, Never>?
    /// Set on an iPad: the scenes draw the sharper copy of each picture that has one (`Entry.pad`). The pictures in
    /// the controls (`image`) stay the standard copies, which are big enough there and cost a third of the memory.
    public var pad: PadSource?

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
        #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .pad {
                pad = .catalog(bundle)
            }
        #endif
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

    /// The file a master path is stored in.
    public func url(_ path: String) -> URL {
        (roots[path] ?? root).appendingPathComponent(entries[path]?.file ?? path)
    }

    /// Adds the art of an asset pack (a home's exteriors) that has arrived: its own art.json, its files.
    public func add(packAt packRoot: URL) throws {
        let data = try Data(contentsOf: packRoot.appendingPathComponent("art.json"))
        for (path, entry) in try JSONDecoder().decode(Index.self, from: data).files {
            entries[path] = entry
            roots[path] = packRoot
        }
    }

    public func image(_ path: String) -> CGImage? {
        if let cached = images[path] {
            return cached
        }
        let url = url(path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        images[path] = image
        return image
    }

    /// A small copy of a picture for a list of cards (the decorate tray), at most `pixels` on its longer side, decoded
    /// when made and kept. A picture from `image(_:)` is decoded only as it is drawn, and SwiftUI draws a list's pictures
    /// on several threads at once: with the tray's 72 HEIC shop pieces (the season pass's sets, 21 Oct) the simulator's
    /// HEVC decoder deadlocked and the app hung with the main thread waiting on it; decoded on the main thread instead,
    /// they held it for seconds. So the tray's pictures are made off the main thread, one at a time (`makeThumbnails`),
    /// and a card shows its picture once it is here. This one makes it now, on this thread (tests and renders).
    public func thumbnail(_ path: String, pixels: Int) -> CGImage? {
        let key = Self.thumbnailKey(path, pixels)
        if let cached = thumbnails[key] {
            return cached
        }
        let image = Self.decodeThumbnail(url(path), pixels: pixels)
        thumbnails[key] = image
        return image
    }

    /// The small copy if it has been made.
    public func cachedThumbnail(_ path: String, pixels: Int) -> CGImage? {
        thumbnails[Self.thumbnailKey(path, pixels)]
    }

    /// Makes the small copies not made yet off the main thread, one picture at a time and after any asked for before
    /// (never two HEIC pictures decoding together), and calls `ready` on the main actor as each few arrive.
    public func makeThumbnails(_ paths: [String], pixels: Int, batch: Int = 6, ready: @escaping @MainActor () -> Void) {
        let jobs = paths.compactMap { path -> (String, URL)? in
            let key = Self.thumbnailKey(path, pixels)
            guard thumbnails[key] == nil, !thumbnailsPending.contains(key), has(path) else { return nil }
            thumbnailsPending.insert(key)
            return (key, url(path))
        }
        guard !jobs.isEmpty else { return }
        let previous = thumbnailWork
        thumbnailWork = Task { [weak self] in
            await previous?.value
            for start in stride(from: 0, to: jobs.count, by: max(1, batch)) {
                let some = Array(jobs[start ..< min(jobs.count, start + max(1, batch))])
                let made = await Task.detached(priority: .userInitiated) {
                    some.compactMap { key, url in ArtLibrary.decodeThumbnail(url, pixels: pixels).map { (key, $0) } }
                }.value
                guard let self else { return }
                for (key, image) in made {
                    self.thumbnails[key] = image
                }
                for (key, _) in some {
                    self.thumbnailsPending.remove(key)
                }
                ready()
            }
        }
    }

    private static func thumbnailKey(_ path: String, _ pixels: Int) -> String {
        "\(path)@\(pixels)"
    }

    /// A picture's small copy, decoded now and redrawn into plain pixels: a picture straight from ImageIO, even one
    /// already decoded, goes back to its HEIC reader each time SwiftUI draws it (the samples of the hang showed dozens
    /// of SwiftUI's threads in the HEIC decoder for the tray's thumbnails), and plain pixels are only copied.
    nonisolated static func decodeThumbnail(_ url: URL, pixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let small = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let space = small.colorSpace.flatMap { $0.supportsOutput ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)
        guard let space, let context = CGContext(
            data: nil,
            width: small.width,
            height: small.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(small, in: CGRect(x: 0, y: 0, width: small.width, height: small.height))
        return context.makeImage()
    }

    /// A picture as a texture for the scenes: on an iPad its sharper copy where it has one. The picture is not kept
    /// as well (the texture holds its pixels; keeping both doubled the art's memory).
    public func texture(_ path: String) -> SKTexture {
        if let cached = textures[path] {
            return cached
        }
        func uncached(_ source: CGImageSource) -> CGImage? {
            CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
        }
        let image = padSource(path).flatMap(uncached) ?? images[path] ?? CGImageSourceCreateWithURL(url(path) as CFURL, nil)
            .flatMap(uncached)
        let texture = image.map { SKTexture(cgImage: $0) } ?? SKTexture()
        texture.filteringMode = .linear
        textures[path] = texture
        return texture
    }

    /// The iPad's sharper copy of a picture, when this library draws them and the picture has one.
    private func padSource(_ path: String) -> CGImageSource? {
        guard let pad, let asset = entries[path]?.pad?.asset else { return nil }
        switch pad {
        case let .catalog(bundle):
            return NSDataAsset(name: asset, bundle: bundle).flatMap { CGImageSourceCreateWithData($0.data as CFData, nil) }
        case let .folder(catalog):
            let files = try? FileManager.default.contentsOfDirectory(
                at: catalog.appendingPathComponent(asset + ".dataset"),
                includingPropertiesForKeys: nil
            )
            return files?.first { $0.pathExtension == "heic" }.flatMap { CGImageSourceCreateWithURL($0 as CFURL, nil) }
        }
    }

    /// A data file (rig, layout, fx anchors) decoded from JSON.
    public func data<T: Decodable>(_ path: String, as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: root.appendingPathComponent(path)))
    }
}
