import CoreGraphics
import Foundation
import HouseCatCore
import HouseCatGame
import ImageIO
import UniformTypeIdentifiers
import WidgetKit

/// Keeps the widget's side of the App Group current (CLAUDE.md "The widget scene"): the save's state after
/// every change, a kit of pictures made for the player's cat and home whenever either changes (the widget
/// cannot run the coat shader), and the widget's own Feed and Pet folded back into the save.
@MainActor
enum WidgetBridge {
    private static var pending: Task<Void, Never>?
    private static var making: Task<Void, Never>?

    /// The kit is being made (the gallery waits for it).
    static var isMakingKit: Bool {
        making != nil
    }

    /// Hosted tests run the session without touching the App Group.
    private static let enabled = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil

    /// After a change: write once things settle (a burst of placements writes once), then redraw.
    static func changed() {
        guard enabled else { return }
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(Tuning.Widget.publishDelaySeconds))
            guard !Task.isCancelled else { return }
            publish()
        }
    }

    /// The snapshot now, the kit if the cat or the home changed, the reminders, and a redraw.
    static func publish() {
        guard enabled else { return }
        let session = GameSession.shared
        let state = session.current
        try? WidgetFiles.write(WidgetSnapshot(state: state, writtenAt: Date()), to: WidgetFiles.snapshot)
        makeKitIfNeeded(state: state)
        Reminders.reschedule()
        WidgetCenter.shared.reloadAllTimelines()
        #if os(iOS)
            WatchLink.shared.send(state)
        #endif
    }

    /// The widget's taps since the app was last open go into the save (they count as those days' visits).
    static func importInbox() {
        guard enabled else { return }
        let events = WidgetInbox.pending()
        guard !events.isEmpty else { return }
        GameSession.shared.importEvents(events)
        WidgetInbox.remove(events)
    }

    // MARK: The kit

    private static func kitKey(_ state: HouseholdState) -> String {
        let look = state.cats.first.flatMap { try? JSONEncoder().encode($0.look) }.map { String(decoding: $0, as: UTF8.self) } ?? ""
        let place = state.home.place ?? .london
        let outfit = state.cats.first?.outfitID ?? ""
        return [Tuning.Widget.kitVersion, GameWorld.style(state).rawValue, place.biome.rawValue, look, outfit].joined(separator: "|")
    }

    private static func makeKitIfNeeded(state: HouseholdState) {
        let key = kitKey(state)
        guard WidgetFiles.read(WidgetKitInfo.self, from: WidgetFiles.kitFile("kit.json"))?.key != key, making == nil,
              let art = GameWorld.art, let catArt = GameWorld.catArt, let cat = state.cats.first, let kit = WidgetFiles.kit
        else { return }
        let frame = GameWorld.style(state).widgetFrame
        let biome = (state.home.place ?? .london).biome
        // What to copy as it is, by its file in the app's art.
        var copies: [String: URL] = [
            "frame.png": art.url("widget/widget_\(frame).png"),
            "frame_wide.png": art.url("widget/widget_\(frame)_wide.png"),
            "cloud.png": art.url("world/weather/cloud.png"),
        ]
        for season in NatureSeason.allCases {
            copies["terrain_\(season.rawValue).png"] = art.url("world/terrain/terr_\(biome.rawValue)_\(season.rawValue).png")
        }
        for icon in ["streak_paw_print_with_a_small_flame", "feed_bowl", "petting_hand", "house", "gift_box_with_a_ribbon"] {
            copies["icon_\(icon).png"] = art.url("ui/icon_\(icon).png")
        }
        let look = cat.look
        let stretch = catArt.builder.torsoStretch(look)
        let poses = CatPose.allCases.map { pose in
            let sprite = catArt.builder.pose(pose.rawValue, look: look)
            return (pose, sprite, catArt.paintedSize(sprite.path))
        }
        // What the cat has on, in each pose's view (OutfitFit draws it on the pose).
        let worn = GameSession.shared.wornOutfit
        let kind = worn.flatMap(OutfitFit.kind)
        let tall = worn.map { OutfitFit.tallEars(look, wearing: $0) } ?? OutfitFit.tallEars(look)
        let covers = worn.map(OutfitFit.coversEars) ?? false
        var outfitPictures: [CatPose: (CGImage, OutfitShape, String)] = [:]
        // A body garment: its picture for each pose, where it goes on the pose's painting, and whether only where the
        // cat is (an ear or tail variant's painting, as the room draws it).
        var garments: [CatPose: (CGImage, CGRect, Bool)] = [:]
        if let worn, worn.slot == .body {
            for (pose, sprite, _) in poses {
                if let path = OutfitFit.garment(worn, body: look.body, pose: pose), art.has(path), let picture = art.image(path) {
                    let base = "poses/cat_\(look.body)_\(pose.rawValue).png"
                    garments[pose] = (picture, GarmentPlacement.frame(drawn: sprite.path, base: base, catArt: catArt, art: art), sprite.path != base)
                }
            }
        } else if let worn {
            for pose in CatPose.allCases {
                if let view = OutfitFit.view(for: pose), let path = worn.sprites[view], let picture = art.image(path),
                   let shape = OutfitShapes.shape(path, art: art)
                {
                    outfitPictures[pose] = (picture, shape, view)
                }
            }
        }
        making = Task.detached(priority: .utility) {
            let files = FileManager.default
            try? files.createDirectory(at: kit, withIntermediateDirectories: true)
            for (name, source) in copies {
                let target = kit.appendingPathComponent(name)
                try? files.removeItem(at: target)
                try? files.copyItem(at: source, to: target)
            }
            var sizes: [String: [Double]] = [:]
            for (pose, sprite, painted) in poses {
                guard var image = catArt.image(sprite, look: look) else { continue }
                // A hat may stand above the picture: the canvas grows, and the third size is the cat's own height
                // (what the widget scales every pose by).
                var grown = 1.0
                if let kind, let (picture, shape, view) = outfitPictures[pose], let face = catArt.face(sprite.path),
                   let dressed = OutfitFit.compose(
                       image,
                       face: face,
                       outfit: picture,
                       shape: shape,
                       kind: kind,
                       view: view,
                       size: worn?.fit,
                       tallEars: tall,
                       pose: pose,
                       coversEars: covers
                   )
                {
                    grown = Double(image.height + dressed.extra) / Double(max(1, image.height))
                    image = dressed.image
                }
                if let (garment, frame, clipped) = garments[pose], let dressed = OutfitFit.dress(image, garment: garment, frame: frame, clipped: clipped) {
                    image = dressed
                }
                write(
                    scaled(image, height: Int((Double(Tuning.Widget.catPixels) * grown).rounded())),
                    to: kit.appendingPathComponent(WidgetFiles.catFile(pose))
                )
                sizes[pose.rawValue] = [Double(painted.width) * stretch, Double(painted.height) * grown, Double(painted.height)]
            }
            let info = WidgetKitInfo(
                key: key,
                glass: glassBox(kit.appendingPathComponent("frame.png")),
                glassWide: glassBox(kit.appendingPathComponent("frame_wide.png")),
                poses: sizes
            )
            try? WidgetFiles.write(info, to: kit.appendingPathComponent("kit.json"))
            await MainActor.run {
                making = nil
                WidgetCenter.shared.reloadAllTimelines()
                #if os(iOS)
                    WatchLink.shared.sendKit()
                #endif
            }
        }
    }

    /// The see-through part of a window frame: its glass, as fractions of the picture.
    private nonisolated static func glassBox(_ url: URL) -> WidgetKitInfo.Box {
        let fallback = WidgetKitInfo.Box(x: 0.2, y: 0.12, width: 0.6, height: 0.6)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil), let raster = Raster(image)
        else { return fallback }
        let alpha = raster.planes[3]
        var minX = raster.width, minY = raster.height, maxX = -1, maxY = -1
        for y in 0 ..< raster.height {
            for x in 0 ..< raster.width where alpha[y * raster.width + x] < 16 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX > minX, maxY > minY else { return fallback }
        let w = Double(raster.width), h = Double(raster.height)
        return .init(x: Double(minX) / w, y: Double(minY) / h, width: Double(maxX - minX + 1) / w, height: Double(maxY - minY + 1) / h)
    }

    private nonisolated static func scaled(_ image: CGImage, height: Int) -> CGImage {
        guard image.height > height else { return image }
        let width = Int((Double(image.width) * Double(height) / Double(image.height)).rounded())
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    private nonisolated static func write(_ image: CGImage, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
