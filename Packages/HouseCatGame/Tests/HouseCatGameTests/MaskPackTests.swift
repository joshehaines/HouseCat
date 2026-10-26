import Foundation
@testable import HouseCatGame
import Testing

private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
private let custom = repo.appendingPathComponent("App/Art/cat/custom")

/// The masks packed one file a kind in the built app (tools/app-assets/pack_cat_masks.py; Josh, 26 Oct: the app's size)
/// read back as the loose files do, pixel for pixel, and CatArt draws the same cat from either.
@Suite struct MaskPackTests {
    /// A pack in the script's format, written here from loose masks.
    private func pack(_ kind: String, _ paths: [String], into folder: URL) throws {
        var index: [String: [Int]] = [:]
        var blob = Data()
        for path in paths {
            let bytes = try Data(contentsOf: custom.appendingPathComponent("masks/\(kind)/\(path)"))
            index[path] = [blob.count, bytes.count]
            blob.append(bytes)
        }
        let head = try JSONEncoder().encode(index)
        var file = Data("HCMP".utf8)
        withUnsafeBytes(of: UInt32(head.count).littleEndian) { file.append(contentsOf: $0) }
        file.append(head)
        file.append(blob)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try file.write(to: folder.appendingPathComponent("\(kind).pack"))
    }

    private func paths(_ kind: String, limit: Int) throws -> [String] {
        let folder = custom.appendingPathComponent("masks/\(kind)")
        let found = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?
            .compactMap { ($0 as? URL)?.path }
            .filter { $0.hasSuffix(".png") }
            .map { String($0.dropFirst(folder.path.count + 1)) }
            .sorted() ?? []
        return Array(found.prefix(limit))
    }

    @Test func aPackedMaskReadsAsItsFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("maskpack-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        for kind in ["fur", "tabby_classic", "features", "uv"] {
            let picked = try paths(kind, limit: 12)
            #expect(!picked.isEmpty, "\(kind)")
            try pack(kind, picked, into: folder)
            let pack = try #require(MaskPack(url: folder.appendingPathComponent("\(kind).pack")))
            for path in picked {
                let loose = try #require(Raster.read(custom.appendingPathComponent("masks/\(kind)/\(path)")))
                let packed = try #require(pack.raster(path), "\(kind)/\(path)")
                #expect(packed.width == loose.width && packed.height == loose.height && packed.planes == loose.planes, "\(kind)/\(path)")
            }
            #expect(pack.raster("no/such.png") == nil)
        }
        #expect(MaskPack(url: folder.appendingPathComponent("missing.pack")) == nil)
    }

    /// HOUSECAT_PACKED_MASKS=<a built app's masks folder>: every packed mask against App/Art's loose one.
    @Test func everyPackedMaskMatchesItsFile() throws {
        guard let built = ProcessInfo.processInfo.environment["HOUSECAT_PACKED_MASKS"] else { return }
        let packs = try FileManager.default.contentsOfDirectory(atPath: built).filter { $0.hasSuffix(".pack") }
        #expect(packs.count >= 16)
        var checked = 0
        for name in packs {
            let kind = String(name.dropLast(".pack".count))
            let pack = try #require(MaskPack(url: URL(fileURLWithPath: built).appendingPathComponent(name)))
            for path in try paths(kind, limit: .max) {
                let loose = try #require(Raster.read(custom.appendingPathComponent("masks/\(kind)/\(path)")))
                let packed = try #require(pack.raster(path), "\(kind)/\(path)")
                #expect(packed.planes == loose.planes, "\(kind)/\(path)")
                checked += 1
            }
        }
        #expect(checked > 40000)
    }
}
