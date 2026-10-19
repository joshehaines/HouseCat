import CoreGraphics
import Foundation
import HouseCatCore
@testable import HouseCatGame
import ImageIO
import Testing
import UniformTypeIdentifiers

private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

/// Blinks drawn from the eye masks: a sprite with eyes gets a picture with them shut, the same size, differing
/// only round the eyes; one without (asleep, from behind) gets none.
@MainActor
@Suite("Blinks")
struct BlinkTests {
    let catArt: CatArt

    init() throws {
        catArt = try CatArt(art: ArtLibrary(root: repo.appendingPathComponent("App/Art")))
    }

    @Test(arguments: ["short_slim", "persian", "sphynx", "mainecoon"])
    func aFaceBlinksAndASleeperOrABackDoesNot(body: String) throws {
        let look = catArt.builder.normalized(CatLook(body: body, coat: .named("ginger")))
        for pose in ["sit_front", "sit_tqfront", "loaf_side"] {
            let sprite = catArt.builder.pose(pose, look: look)
            let open = try #require(catArt.image(sprite, look: look))
            let shut = try #require(catArt.blinkTexture(sprite, look: look), "\(body) \(pose)")
            #expect(Int(shut.size().width) == open.width && Int(shut.size().height) == open.height)
            if let dump = ProcessInfo.processInfo.environment["HOUSECAT_BLINK_DUMP"], let image = shut.cgImage() as CGImage? {
                let url = URL(fileURLWithPath: dump).appendingPathComponent("blink_\(body)_\(pose).png")
                if let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
                    CGImageDestinationAddImage(destination, image, nil)
                    CGImageDestinationFinalize(destination)
                }
            }
        }
        #expect(catArt.blinkTexture(catArt.builder.pose("sit_back", look: look), look: look) == nil)
        #expect(catArt.blinkTexture(catArt.builder.part("head", view: "tqfront", look: look), look: look) != nil)
    }
}
