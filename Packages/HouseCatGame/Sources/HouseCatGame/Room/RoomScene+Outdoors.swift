import CoreGraphics
import HouseCatCore
import SpriteKit

/// The outside comes alive (Josh, 19 Oct: moving parts to the outside world, trees in the wind): the trees, grasses
/// and flowers round the house bend in the wind, harder when it blows or rains; leaves drift from the trees in their
/// autumn dress and petals from blossom in spring; on a fine day the shadows of clouds slide across the ground; and
/// now and then a few birds fly over.
extension RoomScene {
    /// The weather and the season outside, as every room has them.
    private var outside: (weather: Weather, season: NatureSeason) {
        (house.rooms.first?.model.weather ?? .sun, house.rooms.first?.model.season ?? .summer)
    }

    /// How hard the wind blows: the sway's strength.
    static func wind(_ weather: Weather) -> Float {
        switch weather {
        case .storm: Float(Tuning.Outdoors.windStorm)
        case .wind: Float(Tuning.Outdoors.windGusty)
        case .rain, .snow: Float(Tuning.Outdoors.windRain)
        default: Float(Tuning.Outdoors.windCalm)
        }
    }

    /// Bends a piece from its foot: the higher up its picture, the further it moves, so a crown sways and a trunk's
    /// base stays put. One shader for each give and phase (`a` and `p`, four phases so neighbours differ), the sky's
    /// grade applied as the colour blend would be.
    func swayShaders(grade: SKColor) -> (_ sway: Double, _ phase: Int) -> SKShader {
        var red: CGFloat = 1, green: CGFloat = 1, blue: CGFloat = 1, alpha: CGFloat = 1
        grade.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let wind = Self.wind(outside.weather)
        var made: [String: SKShader] = [:]
        return { sway, phase in
            let key = "\(sway)/\(phase)"
            if let shader = made[key] {
                return shader
            }
            let shader = SKShader(source: """
            void main() {
                float h = v_tex_coord.y;
                float t = u_time * (0.9 + u_phase * 0.1) + u_phase * 1.5708;
                float bend = u_sway * u_wind * h * h;
                float dx = bend * (u_reach * sin(t) + u_reach * 0.45 * sin(t * 2.3 + 1.7));
                vec2 uv = vec2(v_tex_coord.x + dx, v_tex_coord.y);
                vec4 c = (uv.x < 0.0 || uv.x > 1.0) ? vec4(0.0) : texture2D(u_texture, uv);
                gl_FragColor = c * u_grade;
            }
            """, uniforms: [
                SKUniform(name: "u_wind", float: wind),
                SKUniform(name: "u_sway", float: Float(sway)),
                SKUniform(name: "u_phase", float: Float(phase)),
                SKUniform(name: "u_reach", float: Float(Tuning.Outdoors.swayReach)),
                SKUniform(name: "u_grade", vectorFloat4: SIMD4(Float(red), Float(green), Float(blue), 1)),
            ])
            made[key] = shader
            return shader
        }
    }

    /// A scenery piece bends in the wind, and drops its leaves or petals in their season.
    func bringToLife(_ node: SKSpriteNode, piece: OutdoorPiece, shaders: (Double, Int) -> SKShader) {
        if piece.sway > 0 {
            // The same piece always sways the same way: its phase from where it stands.
            let phase = Int(abs(piece.u * 7.31 + piece.v * 3.17)) % 4
            node.shader = shaders(piece.sway, phase)
        }
        if let sheds = piece.sheds {
            node.addChild(fall(sheds, from: node.size, weather: outside.weather))
        }
    }

    /// Leaves or petals drifting down from a crown to the ground under it, turning as they go.
    private func fall(_ kind: String, from size: CGSize, weather: Weather) -> SKEmitterNode {
        let t = Tuning.Outdoors.self
        let emitter = SKEmitterNode()
        emitter.name = "falling"
        emitter.particleTexture = art.texture("world/weather/\(kind).png")
        let drop = size.height * 0.6
        let speed = CGFloat(t.fallSpeed)
        emitter.position = CGPoint(x: 0, y: size.height * 0.68)
        emitter.particlePositionRange = CGVector(dx: size.width * 0.55, dy: size.height * 0.2)
        emitter.particleBirthRate = CGFloat(t.fallRate) * (size.width / 300)
        emitter.particleLifetime = drop / speed
        emitter.particleLifetimeRange = emitter.particleLifetime * 0.3
        emitter.emissionAngle = -.pi / 2
        emitter.emissionAngleRange = 0.6
        emitter.particleSpeed = speed
        emitter.particleSpeedRange = speed * 0.4
        emitter.xAcceleration = CGFloat(Self.wind(weather)) * CGFloat(t.fallDrift)
        emitter.particleRotationRange = .pi * 2
        emitter.particleRotationSpeed = 1.6
        emitter.particleSize = CGSize(width: t.fallSize, height: t.fallSize)
        emitter.particleScaleRange = 0.35
        emitter.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 1, 1, 0], times: [0, 0.1, 0.8, 1])
        emitter.zPosition = 1
        emitter.advanceSimulationTime(Double(emitter.particleLifetime))
        return emitter
    }

    /// Cloud shadows on a fine day, and the odd flock of birds by day.
    func startSkyLife() {
        world.childNode(withName: "cloudShadows")?.removeFromParent()
        removeAction(forKey: "birds")
        let (weather, _) = outside
        let fine = [Weather.sun, .heat, .wind].contains(weather)
        if fine, house.sky == .day {
            addCloudShadows()
        }
        if house.sky != .night, ![Weather.rain, .storm, .snow, .fog].contains(weather) {
            let t = Tuning.Outdoors.self
            run(.repeatForever(.sequence([
                .wait(forDuration: t.birdsEvery, withRange: t.birdsEvery * 0.8),
                .run { [weak self] in self?.flyBirds() },
            ])), withKey: "birds")
        }
    }

    /// A few soft shadows drifting across the ground with the wind, back round again once past the house.
    private func addCloudShadows() {
        let t = Tuning.Outdoors.self
        let layer = SKNode()
        layer.name = "cloudShadows"
        layer.zPosition = -CGFloat(Tuning.House.storeyBand) + 10
        world.addChild(layer)
        let span = CGFloat(t.reach + Double(Tuning.Room.gridWidth) * 2)
        let texture = Self.softShadow
        for index in 0 ..< t.cloudShadows {
            let shadow = SKSpriteNode(texture: texture)
            let width = grid.cellHalfWidth * 2 * CGFloat(t.cloudShadowCells) * (0.8 + 0.25 * CGFloat(index % 3))
            shadow.size = CGSize(width: width, height: width * 0.5)
            shadow.alpha = CGFloat(t.cloudShadowAlpha)
            let v = CGFloat(index) / CGFloat(t.cloudShadows) * span - span / 4
            let from = grid.floor(-span / 2, v), to = grid.floor(span, v)
            let seconds = Double(span * 1.5) / t.cloudShadowSpeed / Double(Self.wind(outside.weather))
            shadow.position = from
            layer.addChild(shadow)
            let drift = SKAction.sequence([.move(to: to, duration: seconds), .move(to: from, duration: 0)])
            shadow.run(.sequence([
                .wait(forDuration: seconds * Double(index) / Double(t.cloudShadows)),
                .repeatForever(drift),
            ]))
        }
    }

    /// A round soft shadow, dark in the middle, gone at the edge.
    private static let softShadow: SKTexture = {
        let size = 128
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let gradient = CGGradient(
            colorsSpace: space,
            colors: [
                CGColor(red: 0.12, green: 0.12, blue: 0.22, alpha: 1),
                CGColor(red: 0.12, green: 0.12, blue: 0.22, alpha: 0),
            ] as CFArray,
            locations: [0, 1]
        ) else { return SKTexture() }
        let middle = CGPoint(x: size / 2, y: size / 2)
        context.drawRadialGradient(
            gradient,
            startCenter: middle,
            startRadius: 0,
            endCenter: middle,
            endRadius: CGFloat(size) / 2,
            options: []
        )
        return context.makeImage().map { SKTexture(cgImage: $0) } ?? SKTexture()
    }()

    /// Three to five birds across the top of the view, wings beating, a little out of step.
    private func flyBirds() {
        guard size.width > 0 else { return }
        let t = Tuning.Outdoors.self
        let count = 3 + Int.random(in: 0 ... 2)
        let leftward = Bool.random()
        let height = size.height * CGFloat.random(in: 0.62 ... 0.85)
        let seconds = Double.random(in: t.birdSeconds * 0.8 ... t.birdSeconds * 1.2)
        let flock = SKNode()
        flock.zPosition = 950_000
        flock.position = CGPoint(x: leftward ? size.width + 40 : -40, y: height)
        addChild(flock)
        for index in 0 ..< count {
            let bird = SKShapeNode(path: Self.birdPath)
            bird.strokeColor = SKColor(red: 0.22, green: 0.2, blue: 0.26, alpha: 0.85)
            bird.lineWidth = 2.2
            bird.lineCap = .round
            bird.position = CGPoint(x: CGFloat(index) * (leftward ? 22 : -22), y: CGFloat(index % 2) * 12 - CGFloat(index) * 3)
            bird.setScale(CGFloat.random(in: 0.8 ... 1.1))
            let beat = SKAction.sequence([.scaleY(to: -0.4, duration: 0.16), .scaleY(to: 1, duration: 0.16)])
            bird.run(.sequence([.wait(forDuration: Double(index) * 0.07), .repeatForever(beat)]))
            flock.addChild(bird)
        }
        let travel = (leftward ? -1 : 1) * (size.width + 160)
        flock.run(.sequence([
            .group([.moveBy(x: travel, y: CGFloat.random(in: -30 ... 40), duration: seconds), .sequence([
                .fadeIn(withDuration: 0.4),
                .wait(forDuration: seconds - 0.8),
                .fadeOut(withDuration: 0.4),
            ])]),
            .removeFromParent(),
        ]))
    }

    /// A bird far off: two arched wings.
    private static let birdPath: CGPath = {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -9, y: 2))
        path.addQuadCurve(to: CGPoint(x: 0, y: -1), control: CGPoint(x: -4, y: 6))
        path.addQuadCurve(to: CGPoint(x: 9, y: 2), control: CGPoint(x: 4, y: 6))
        return path
    }()
}
