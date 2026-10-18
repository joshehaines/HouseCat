import HouseCatCore
import SpriteKit

/// The weather and the season over a picture (SPEC "Sky, season, weather and windows": rain, snow, fog, sun
/// and overcast as particles and tints, with season particles: blossom, falling leaves, snow), made from the
/// painted particles in assets/world/weather. One layer covers the exterior; a small one plays in each
/// window, so every room shows the weather outside.
@MainActor
public enum WeatherLayer {
    /// What a weather and season put in the air.
    struct Recipe: Equatable {
        enum Fall: Equatable {
            case rain(heavy: Bool)
            case snow
            case leaves
            case petals
        }

        var falls: [Fall] = []
        var fog = false
        var clouds = 0
        var lightning = false
        /// A wash over the picture: colour and strength (0 = as painted).
        var veil: [Double] = [0, 0, 0, 0]
    }

    static func recipe(weather: Weather, season: NatureSeason) -> Recipe {
        var r = Recipe()
        switch weather {
        case .sun: break
        case .cloud:
            r.clouds = 4
            r.veil = Tuning.Weather.overcastVeil
        case .rain:
            r.falls = [.rain(heavy: false)]
            r.clouds = 3
            r.veil = Tuning.Weather.rainVeil
        case .storm:
            r.falls = [.rain(heavy: true)]
            r.clouds = 5
            r.lightning = true
            r.veil = Tuning.Weather.stormVeil
        case .snow:
            r.falls = [.snow]
            r.clouds = 2
            r.veil = Tuning.Weather.snowVeil
        case .fog:
            r.fog = true
            r.veil = Tuning.Weather.fogVeil
        case .wind:
            r.falls = [.leaves]
            r.clouds = 3
        case .heat:
            r.veil = Tuning.Weather.heatVeil
        }
        // The season's own particles, when nothing heavier is falling.
        if r.falls.isEmpty, !r.fog {
            switch season {
            case .spring: r.falls = [.petals]
            case .autumn: r.falls = [.leaves]
            case .summer, .winter: break
            }
        }
        return r
    }

    /// The air in front of a picture covering `size` (its origin at the bottom-left): what falls, fog, the wash
    /// and lightning. `unit` is the size particles are drawn at (a raindrop streak is about this long): the
    /// exterior passes view points, a window its own room units.
    public static func node(weather: Weather, season: NatureSeason, size: CGSize, unit: CGFloat, art: ArtLibrary) -> SKNode {
        let layer = SKNode()
        layer.name = "weather"
        let recipe = recipe(weather: weather, season: season)
        let rect = CGRect(origin: .zero, size: size)
        if recipe.veil[3] > 0 {
            let veil = SKSpriteNode(
                color: SKColor(red: recipe.veil[0], green: recipe.veil[1], blue: recipe.veil[2], alpha: 1),
                size: size
            )
            veil.anchorPoint = .zero
            veil.alpha = recipe.veil[3]
            veil.zPosition = 0
            layer.addChild(veil)
        }
        if recipe.fog {
            layer.addChild(mist(in: rect))
        }
        for fall in recipe.falls {
            layer.addChild(emitter(fall, in: rect, unit: unit, art: art))
        }
        if recipe.lightning {
            let flash = SKSpriteNode(color: .white, size: size)
            flash.anchorPoint = .zero
            flash.alpha = 0
            flash.blendMode = .add
            flash.zPosition = 5
            flash.run(.repeatForever(.sequence([
                .wait(forDuration: Tuning.Weather.lightningEvery, withRange: Tuning.Weather.lightningEvery),
                .fadeAlpha(to: 0.55, duration: 0.05), .fadeAlpha(to: 0, duration: 0.12),
                .fadeAlpha(to: 0.35, duration: 0.05), .fadeAlpha(to: 0, duration: 0.3),
            ])))
            layer.addChild(flash)
        }
        return layer
    }

    /// Clouds drifting across the top of a picture, to go behind a painting whose sky is cut out (so they
    /// only show in the sky).
    public static func clouds(weather: Weather, season: NatureSeason, size: CGSize, unit: CGFloat, art: ArtLibrary) -> SKNode {
        let layer = SKNode()
        layer.name = "clouds"
        let recipe = recipe(weather: weather, season: season)
        let rect = CGRect(origin: .zero, size: size)
        let grey = Tuning.Weather.cloudGrey[weather.rawValue] ?? 0
        for i in 0 ..< recipe.clouds {
            let cloud = cloud(index: i, of: recipe.clouds, in: rect, unit: unit, art: art)
            if let sprite = cloud as? SKSpriteNode, grey > 0 {
                sprite.color = SKColor(red: 0.45, green: 0.48, blue: 0.58, alpha: 1)
                sprite.colorBlendFactor = grey
            }
            layer.addChild(cloud)
        }
        return layer
    }

    /// A rain streak: a thin line, bright at the head, made in code (the painted drop reads as a blob this small).
    private static let streak: SKTexture = {
        let w = 8, h = 64
        let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let colours = [CGColor(red: 0.85, green: 0.9, blue: 1, alpha: 0), CGColor(red: 0.9, green: 0.95, blue: 1, alpha: 0.9)]
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colours as CFArray, locations: [0, 1])!
        ctx.addPath(CGPath(
            roundedRect: CGRect(x: 1.5, y: 0, width: 3, height: CGFloat(h)),
            cornerWidth: 1.5,
            cornerHeight: 1.5,
            transform: nil
        ))
        ctx.clip()
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: .zero, options: [])
        return SKTexture(cgImage: ctx.makeImage()!)
    }()

    /// A soft mist rising from the ground: white at the bottom fading out half way up.
    private static func mist(in rect: CGRect) -> SKNode {
        let w = 4, h = 128
        let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let colours = [CGColor(red: 0.94, green: 0.95, blue: 0.98, alpha: 0.85), CGColor(red: 0.94, green: 0.95, blue: 0.98, alpha: 0)]
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colours as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: h), options: [])
        let node = SKSpriteNode(texture: SKTexture(cgImage: ctx.makeImage()!), size: CGSize(width: rect.width, height: rect.height * 0.8))
        node.run(.repeatForever(.sequence([.fadeAlpha(to: 0.8, duration: 6), .fadeAlpha(to: 1, duration: 6)])))
        node.anchorPoint = .zero
        node.position = CGPoint(x: rect.minX, y: rect.minY)
        node.zPosition = 3
        return node
    }

    private static func emitter(_ fall: Recipe.Fall, in rect: CGRect, unit: CGFloat, art: ArtLibrary) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particlePositionRange = CGVector(dx: rect.width * 1.3, dy: 0)
        e.position = CGPoint(x: rect.midX, y: rect.maxY + unit)
        e.particleColorBlendFactor = 0
        e.zPosition = 2
        let area = rect.width / unit
        switch fall {
        case let .rain(heavy):
            e.particleTexture = streak
            e.particleBirthRate = area * (heavy ? 9 : 5)
            e.particleSpeed = unit * 30
            e.particleSpeedRange = unit * 6
            e.emissionAngle = -.pi / 2 - (heavy ? 0.22 : 0.1)
            e.particleRotation = heavy ? 0.22 : 0.1
            e.particleScale = unit / 64
            e.particleScaleRange = unit * 0.3 / 64
            e.particleAlpha = heavy ? 0.85 : 0.7
            e.particleAlphaRange = 0.2
            e.particleLifetime = (rect.height + unit * 2) / (unit * 30)
        case .snow:
            e.particleTexture = art.texture("world/weather/snowflake.png")
            e.particleBirthRate = area * 1.5
            e.particleSpeed = unit * 1.6
            e.particleSpeedRange = unit * 0.8
            e.emissionAngle = -.pi / 2
            e.emissionAngleRange = 0.5
            e.xAcceleration = unit * 0.3
            e.particleScale = unit * 0.6 / 470
            e.particleScaleRange = unit * 0.35 / 470
            e.particleRotationRange = .pi
            e.particleRotationSpeed = 0.6
            e.particleAlpha = 0.9
            e.particleLifetime = (rect.height + unit * 2) / (unit * 1.2)
        case .leaves, .petals:
            let leaves = fall == .leaves
            e.particleTexture = art.texture(leaves ? "world/weather/leaf.png" : "world/weather/petal.png")
            e.particleBirthRate = area * (leaves ? 0.12 : 0.18)
            e.particleSpeed = unit * 1.8
            e.particleSpeedRange = unit
            e.emissionAngle = -.pi / 2 - 0.5
            e.emissionAngleRange = 0.6
            e.xAcceleration = -unit * 0.4
            e.particleScale = unit * (leaves ? 0.5 : 0.35) / 425
            e.particleScaleRange = unit * 0.2 / 425
            e.particleRotationRange = .pi * 2
            e.particleRotationSpeed = 1.2
            e.particleAlpha = 0.95
            e.particleLifetime = (rect.height + unit * 2) / (unit * 1.2)
        }
        // Already falling when the picture appears.
        e.advanceSimulationTime(TimeInterval(e.particleLifetime))
        return e
    }

    /// A cloud drifting across the top of the picture.
    private static func cloud(index: Int, of count: Int, in rect: CGRect, unit: CGFloat, art: ArtLibrary) -> SKNode {
        let node = SKSpriteNode(texture: art.texture("world/weather/cloud.png"))
        let width = unit * CGFloat(6 + (index * 5) % 5)
        node.size = CGSize(width: width, height: width * 356 / 493)
        node.alpha = 0.9
        node.zPosition = 1
        let y = rect.maxY - unit * CGFloat(1 + (index * 3) % 3) - node.size.height * 0.2
        let start = rect.minX + rect.width * CGFloat(index) / CGFloat(max(1, count))
        node.position = CGPoint(x: start, y: y)
        let travel = rect.width + width * 2
        let speed = unit * CGFloat(0.5 + Double(index % 3) * 0.2)
        let toEdge = SKAction.moveTo(x: rect.maxX + width, duration: TimeInterval((rect.maxX + width - start) / speed))
        let wrap = SKAction.sequence([
            .moveTo(x: rect.minX - width, duration: 0),
            .moveTo(x: rect.maxX + width, duration: TimeInterval(travel / speed)),
        ])
        node.run(.sequence([toEdge, .repeatForever(wrap)]))
        return node
    }
}
