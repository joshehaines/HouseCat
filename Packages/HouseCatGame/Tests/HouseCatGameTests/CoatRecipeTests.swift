import CoreGraphics
import Foundation
@testable import HouseCatCore
@testable import HouseCatGame
import Testing

private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
private let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/coat")

private struct Cases: Decodable {
    struct Case: Decodable {
        var name: String
        var preset: String
        var sprite: String
    }

    struct Preset: Decodable {
        var sprite: String
        var cells: [[Double]?]
    }

    var cases: [Case]
    var presets: [String: Preset]
}

private func cases() throws -> Cases {
    try JSONDecoder().decode(Cases.self, from: Data(contentsOf: fixtures.appendingPathComponent("cases.json")))
}

private func catArt() throws -> CatArt {
    try CatArt(root: repo.appendingPathComponent("App/Art/cat/custom"))
}

/// The tinted sprite against tools/asset-pipeline/tint.py's maths on exactly the same inputs: pixel for pixel
/// (within one level, for float rounding before tint.py's truncation).
@Test func theCoatRecipeMatchesTintPyPixelForPixel() throws {
    let art = try catArt()
    for test in try cases().cases {
        func plane(_ suffix: String) -> Raster? {
            Raster.read(fixtures.appendingPathComponent("\(test.name)_\(suffix).png"))
        }
        let rgb = try #require(plane("rgb"))
        let alpha = try #require(plane("alpha"))
        let painting = CoatRecipe.Planes(
            width: rgb.width,
            height: rgb.height,
            r: Raster.floats(rgb.planes[0]),
            g: Raster.floats(rgb.planes[1]),
            b: Raster.floats(rgb.planes[2]),
            alpha: alpha.planes[0]
        )
        let features = plane("features")
        let masks = CoatRecipe.Masks(
            fur: plane("fur").map { Raster.floats($0.planes[0], scale: 1 / 255) },
            pattern: plane("pattern").map { Raster.floats($0.planes[0], scale: 1 / 255) },
            white: plane("white").map { Raster.floats($0.planes[0], scale: 1 / 255) },
            irisLeft: features.map { Raster.floats($0.planes[0], scale: 1 / 255) },
            irisRight: features.map { Raster.floats($0.planes[1], scale: 1 / 255) },
            nose: features.map { Raster.floats($0.planes[2], scale: 1 / 255) }
        )
        let look = try #require(art.builder.preset(test.preset)).look
        let out = CoatRecipe.render(painting, masks: masks, look: art.recipeLook(look))
        let expected = try #require(plane("expected"))
        var worst = 0
        var off = 0
        for (got, want) in zip([out.r, out.g, out.b], expected.planes) {
            for (a, b) in zip(got, want) {
                let d = abs(Int(a) - Int(b))
                worst = max(worst, d)
                off += d > 0 ? 1 : 0
            }
        }
        #expect(worst <= 1, "\(test.name): off by up to \(worst)")
        #expect(Double(off) / Double(3 * out.r.count) < 0.02, "\(test.name): \(off) values off by one")
        #expect(out.alpha == alpha.planes[0])
    }
}

/// Every preset, rendered by the app from the bundled art, matches presetsheet.py's render of it (tint.py on
/// the masters, scaled to the app's size) cell by cell.
@Test func everyPresetMatchesThePresetSheet() throws {
    let art = try catArt()
    let reference = try cases().presets
    #expect(reference.count == art.builder.data.presets.count)
    for preset in art.builder.data.presets {
        let want = try #require(reference[preset.id])
        let sprite = art.builder.pose("sit_tqfront", look: preset.look)
        #expect(sprite.path == want.sprite)
        let out = try #require(art.render(sprite, look: preset.look))
        #expect(art.image(sprite, look: preset.look) != nil)
        let got = signature(Raster(width: out.width, height: out.height, planes: [out.r, out.g, out.b, out.alpha]))
        var worst = 0.0
        var total = 0.0
        var cells = 0
        for (g, w) in zip(got, want.cells) {
            guard let g, let w else { continue }
            let off = zip(g, w).map { abs($0 - $1) }.max() ?? 0
            worst = max(worst, off)
            total += off
            cells += 1
        }
        // The app's masks are half the sprite's size in 16 levels (build_cat_art.py): fine pattern edges soften
        // a little, so a busy cell (a tortie tail) can drift a few levels; the cat as a whole may not.
        #expect(total / Double(max(1, cells)) < 4, "\(preset.id): off by \(total / Double(max(1, cells))) on average")
        #expect(worst < 12, "\(preset.id): a cell is off by \(worst)")
    }
}

private func signature(_ raster: Raster, grid: Int = 4) -> [[Double]?] {
    let w = raster.width, h = raster.height
    var cells: [[Double]?] = []
    for gy in 0 ..< grid {
        for gx in 0 ..< grid {
            var sum = [0.0, 0.0, 0.0]
            var n = 0
            for y in gy * h / grid ..< (gy + 1) * h / grid {
                for x in gx * w / grid ..< (gx + 1) * w / grid where raster.planes[3][y * w + x] > 128 {
                    let i = y * w + x
                    sum[0] += Double(raster.planes[0][i])
                    sum[1] += Double(raster.planes[1][i])
                    sum[2] += Double(raster.planes[2][i])
                    n += 1
                }
            }
            cells.append(n > 20 ? sum.map { $0 / Double(n) } : nil)
        }
    }
    return cells
}

@Test func theEyeAndWhiskerSlidersChangeOnlyTheHead() throws {
    let art = try catArt()
    var look = CatLook.midnight
    let sprite = art.builder.part("head", view: "front", look: look)
    let painted = try #require(art.image(sprite, look: look).flatMap(Raster.init))
    look.eyeSize = 1
    look.whiskerLength = 0
    let changed = try #require(art.image(sprite, look: look).flatMap(Raster.init))
    #expect(changed.planes[3].reduce(0) { $0 + Int($1) } < painted.planes[3].reduce(0) { $0 + Int($1) })
    #expect(changed.planes[0] != painted.planes[0])
    // The torso has no eyes or whiskers: the sliders leave it alone.
    let torso = art.builder.part("torso", view: "front", look: look)
    #expect(art.image(torso, look: look).flatMap(Raster.init)?.planes[0] == art.image(torso, look: .midnight).flatMap(Raster.init)?
        .planes[0])
}

@Test func aWholeCatRendersQuickly() throws {
    let art = try catArt()
    let look = try #require(art.builder.preset("calico")).look
    let start = Date()
    var sprites = 0
    for view in ["side", "tqfront", "front"] {
        for part in [
            "head",
            "ear_far",
            "ear_near",
            "torso",
            "leg_front_far",
            "leg_front_near",
            "leg_back_far",
            "leg_back_near",
            "tail_up",
        ] {
            _ = art.image(art.builder.part(part, view: view, look: look), look: look)
            sprites += 1
        }
    }
    for pose in CatPose.allCases {
        _ = art.image(art.builder.pose(pose.rawValue, look: look), look: look)
        sprites += 1
    }
    let seconds = Date().timeIntervalSince(start)
    print("rendered \(sprites) sprites in \(String(format: "%.2f", seconds)) s")
    #expect(seconds < 10)
}
