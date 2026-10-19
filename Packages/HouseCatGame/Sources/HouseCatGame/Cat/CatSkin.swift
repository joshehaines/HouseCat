import CoreGraphics
import Foundation
import SpriteKit

/// A painted part that bends rather than being cut at its joints (Josh, 19 Oct: "the connection between body and the
/// legs still looks strange - in turn the walking looks robotic ... full rebuild"): a grid over its picture whose
/// points move each frame (SpriteKit's warp geometry), so a hind leg bends at the hock like fur over a joint, the
/// body arches and its shoulders and haunches move with the legs under them, and the tail sways along its length.
struct Skin {
    let columns: Int
    let rows: Int
    /// The grid over the picture, as SpriteKit takes it: fractions, origin bottom left, row by row from the bottom.
    let source: [SIMD2<Float>]
    /// The same points in the node's frame (points from its anchor), unbent.
    let points: [CGPoint]
    let size: CGSize
    let anchor: CGPoint

    init(size: CGSize, anchor: CGPoint, columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
        self.size = size
        self.anchor = anchor
        var source: [SIMD2<Float>] = [], points: [CGPoint] = []
        for row in 0 ... rows {
            for column in 0 ... columns {
                let u = CGFloat(column) / CGFloat(columns), v = CGFloat(row) / CGFloat(rows)
                source.append(SIMD2(Float(u), Float(v)))
                points.append(CGPoint(x: (u - anchor.x) * size.width, y: (v - anchor.y) * size.height))
            }
        }
        self.source = source
        self.points = points
    }

    /// A grid point as a fraction of the picture, origin top left (as the joints are found).
    func fraction(_ index: Int) -> CGPoint {
        CGPoint(x: CGFloat(source[index].x), y: 1 - CGFloat(source[index].y))
    }

    /// The grid with its points moved to `moved` (the node's frame).
    func warp(_ moved: [CGPoint]) -> SKWarpGeometryGrid {
        let destination = moved.map {
            SIMD2<Float>(Float($0.x / size.width + anchor.x), Float($0.y / size.height + anchor.y))
        }
        return SKWarpGeometryGrid(columns: columns, rows: rows, sourcePositions: source, destinationPositions: destination)
    }

    /// The point of the picture at `fraction` (origin top left) in the node's frame.
    func point(_ fraction: CGPoint) -> CGPoint {
        CGPoint(x: (fraction.x - anchor.x) * size.width, y: (1 - fraction.y - anchor.y) * size.height)
    }
}

/// A tail's bones along its length, found from its outline: the distance from the root inside the tail (so a curl
/// is followed round, not cut across) split into equal lengths, each length's middle a joint. Each grid point bends
/// with the bone it is on, blended with the next across a joint.
struct TailChain {
    /// The joints from the root to the tip, in the tail node's frame.
    let joints: [CGPoint]
    /// Each grid point's bone and how much of the next bone it takes (0 to 1).
    let bone: [Int]
    let blend: [CGFloat]
    /// How far the tail turns at each joint as painted (radians, anticlockwise), so it can be uncurled.
    let curl: [CGFloat]

    init?(image: CGImage, root: CGPoint, bones: Int, skin: Skin) {
        let width = image.width, height = image.height
        guard bones > 1, width > 4, height > 4, let alpha = CatLimb.alphaPlane(image) else { return nil }
        let solid = alpha.map { $0 > 60 }
        // The root: the solid pixels nearest the tail's pivot.
        let rx = root.x * CGFloat(width), ry = root.y * CGFloat(height)
        var nearest = CGFloat.greatestFiniteMagnitude
        for index in 0 ..< width * height where solid[index] {
            nearest = min(nearest, hypot(CGFloat(index % width) - rx, CGFloat(index / width) - ry))
        }
        guard nearest < CGFloat(max(width, height)) else { return nil }
        let reach = nearest + CGFloat(max(width, height)) * 0.06
        // Distances inside the tail from the root (Dial's algorithm: 5 a step across, 7 diagonally).
        let unknown = Int.max
        var distance = [Int](repeating: unknown, count: width * height)
        var buckets: [[Int]] = [[]]
        for index in 0 ..< width * height where solid[index] {
            if hypot(CGFloat(index % width) - rx, CGFloat(index / width) - ry) <= reach {
                distance[index] = 0
                buckets[0].append(index)
            }
        }
        var level = 0
        while level < buckets.count {
            var queue = buckets[level]
            buckets[level] = []
            while let index = queue.popLast() {
                guard distance[index] == level else { continue }
                let x = index % width, y = index / width
                for dy in -1 ... 1 {
                    for dx in -1 ... 1 where dx != 0 || dy != 0 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                        let next = ny * width + nx
                        guard solid[next] else { continue }
                        let d = level + (dx != 0 && dy != 0 ? 7 : 5)
                        if d < distance[next] {
                            distance[next] = d
                            while buckets.count <= d {
                                buckets.append([])
                            }
                            buckets[d].append(next)
                        }
                    }
                }
            }
            level += 1
        }
        let reached = (0 ..< width * height).filter { distance[$0] != unknown }
        guard let longest = reached.map({ distance[$0] }).max(), longest > 0 else { return nil }
        let step = CGFloat(longest) / CGFloat(bones)
        // Each joint: the middle of the tail where it is a whole number of bones from the root.
        var joints: [CGPoint] = []
        for k in 0 ... bones {
            let at = CGFloat(k) * step
            var sx: CGFloat = 0, sy: CGFloat = 0, count: CGFloat = 0
            for index in reached where abs(CGFloat(distance[index]) - at) <= step * (k == 0 || k == bones ? 0.25 : 0.5) {
                sx += CGFloat(index % width)
                sy += CGFloat(index / width)
                count += 1
            }
            if count == 0 {
                guard let last = joints.last else { return nil }
                joints.append(last)
                continue
            }
            joints.append(skin.point(CGPoint(x: (sx / count + 0.5) / CGFloat(width), y: (sy / count + 0.5) / CGFloat(height))))
        }
        // The root joint where the tail meets the body.
        joints[0] = skin.point(root)
        // Each grid point's place along the tail: its own pixel's, or the nearest pixel of the tail's.
        let sample = reached.enumerated().filter { $0.offset % 3 == 0 }.map(\.element)
        var bone: [Int] = [], blend: [CGFloat] = []
        for index in skin.points.indices {
            let f = skin.fraction(index)
            let x = min(width - 1, max(0, Int(f.x * CGFloat(width)))), y = min(height - 1, max(0, Int(f.y * CGFloat(height))))
            var along = distance[y * width + x]
            if along == unknown {
                var best = CGFloat.greatestFiniteMagnitude
                for candidate in sample {
                    let d = hypot(CGFloat(candidate % width - x), CGFloat(candidate / width - y))
                    if d < best {
                        best = d
                        along = distance[candidate]
                    }
                }
            }
            let place = CGFloat(along == unknown ? 0 : along) / step - 0.5
            let first = min(bones - 1, max(0, Int(place.rounded(.down))))
            bone.append(first)
            blend.append(first >= bones - 1 || place < 0 ? 0 : min(1, max(0, place - CGFloat(first))))
        }
        var curl: [CGFloat] = [0]
        for k in 1 ..< bones {
            let a = joints[k], b = joints[k + 1], c = joints[k - 1]
            let turn = atan2(b.y - a.y, b.x - a.x) - atan2(a.y - c.y, a.x - c.x)
            curl.append(atan2(sin(turn), cos(turn)))
        }
        self.joints = joints
        self.bone = bone
        self.blend = blend
        self.curl = curl
    }

    /// The grid's points with each joint turned by `turns` (radians, anticlockwise, from the root's).
    func bent(_ turns: [CGFloat], skin: Skin) -> [CGPoint] {
        let count = joints.count - 1
        // Each bone's turn from the root and where its joint has gone.
        var total: [CGFloat] = [], placed: [CGPoint] = [joints[0]]
        var angle: CGFloat = 0
        for k in 0 ..< count {
            angle += k < turns.count ? turns[k] : 0
            total.append(angle)
            let a = joints[k], b = joints[k + 1], c = cos(angle), s = sin(angle)
            let from = placed[k]
            placed.append(CGPoint(x: from.x + (b.x - a.x) * c - (b.y - a.y) * s, y: from.y + (b.x - a.x) * s + (b.y - a.y) * c))
        }
        func moved(_ p: CGPoint, by k: Int) -> CGPoint {
            let a = joints[k], c = cos(total[k]), s = sin(total[k])
            return CGPoint(
                x: placed[k].x + (p.x - a.x) * c - (p.y - a.y) * s,
                y: placed[k].y + (p.x - a.x) * s + (p.y - a.y) * c
            )
        }
        return skin.points.indices.map { index in
            let p = skin.points[index], k = bone[index], w = blend[index]
            let one = moved(p, by: k)
            guard w > 0, k + 1 < count else { return one }
            let two = moved(p, by: k + 1)
            return CGPoint(x: one.x + (two.x - one.x) * w, y: one.y + (two.y - one.y) * w)
        }
    }
}

/// A film frame's picture handed back from tinting off the main thread.
struct FilmImage: @unchecked Sendable {
    let image: CGImage?

    init(_ image: CGImage?) {
        self.image = image
    }
}

extension CatLimb {
    /// A near leg drawn in front of the body, its top faded out into the fur over it (Josh, 19 Oct: the join between
    /// body and legs looked strange): clear down to `clear` (fractions of the picture's height from the top), whole
    /// from `whole`, so the body's lower edge never shows as a line across the top of the leg.
    static func fadedTop(_ image: CGImage, clear: CGFloat, whole: CGFloat) -> CGImage? {
        let width = image.width, height = image.height
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        return pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: info
            ) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let bytes = buffer.bindMemory(to: UInt8.self)
            for row in 0 ..< height {
                // The buffer's rows run top down, as the fractions do.
                let f = (CGFloat(row) + 0.5) / CGFloat(height)
                guard f < whole else { break }
                let t = max(0, min(1, (f - clear) / max(0.001, whole - clear)))
                let keep = t * t * (3 - 2 * t)
                for column in 0 ..< width {
                    let at = (row * width + column) * 4
                    for channel in 0 ..< 4 {
                        bytes[at + channel] = UInt8(CGFloat(bytes[at + channel]) * keep)
                    }
                }
            }
            return context.makeImage()
        }
    }

    /// The middle of a leg's outline across a row (fractions of the picture, origin top left).
    static func middle(of image: CGImage, at row: CGFloat) -> CGFloat? {
        let width = image.width, height = image.height
        guard let alpha = alphaPlane(image) else { return nil }
        let y = min(height - 1, max(0, Int(row * CGFloat(height))))
        var low = -1, high = -1
        for column in 0 ..< width where alpha[y * width + column] > 128 {
            if low < 0 {
                low = column
            }
            high = column
        }
        return low < 0 ? nil : (CGFloat(low + high) / 2 + 0.5) / CGFloat(width)
    }

    /// The highest the body's lower edge comes over a span of its picture (fractions, origin top left): the lowest
    /// solid row of each column, the highest of those. Nil where the body has no edge over the span.
    static func underside(of image: CGImage, from left: CGFloat, to right: CGFloat) -> CGFloat? {
        let width = image.width, height = image.height
        guard let alpha = alphaPlane(image) else { return nil }
        let first = max(0, Int(left * CGFloat(width))), last = min(width - 1, Int(right * CGFloat(width)))
        guard first <= last else { return nil }
        var highest: Int?
        for column in first ... last {
            var lowest: Int?
            for row in stride(from: height - 1, through: 0, by: -1) where alpha[row * width + column] > 128 {
                lowest = row
                break
            }
            if let lowest {
                highest = min(highest ?? lowest, lowest)
            }
        }
        return highest.map { CGFloat($0) / CGFloat(height) }
    }
}
