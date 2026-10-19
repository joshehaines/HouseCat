import HouseCatCore
import SpriteKit

/// The painted world map wrapped round a sphere seen from afar (the map screen and the intro). One sprite covers
/// the view; its shader does, for every pixel, the sums HouseCatCore's `GlobeOrientation` does for pins and taps.
/// Lit from the upper left, with a blue haze at the rim. The background is clear: the app draws the sky behind.
@MainActor
public final class GlobeScene: SKScene {
    /// Asked every frame: the disc (centre and radius in the scene's points, y up) and how it is turned.
    public var pose: (@MainActor (CGSize) -> (centre: CGPoint, radius: CGFloat, orientation: GlobeOrientation))?

    private let sprite = SKSpriteNode()
    private let full: SKTexture
    private let small: SKTexture
    private let globeShader: SKShader
    private let centreUniform = SKUniform(name: "u_centre", vectorFloat2: .zero)
    private let radiusUniform = SKUniform(name: "u_radius", float: 1)
    private let turnUniform = SKUniform(name: "u_turn", vectorFloat2: .zero)
    private let sizeUniform = SKUniform(name: "u_size", vectorFloat2: .zero)
    private let mapUniform: SKUniform

    /// `map` is the equirectangular painting (longitude -180 to 180 left to right, latitude 90 at the top);
    /// a half-size copy is used when the globe is small, so it does not shimmer as it turns.
    public init(size: CGSize, map: CGImage) {
        full = SKTexture(cgImage: map)
        small = SKTexture(cgImage: Self.halved(map) ?? map)
        full.filteringMode = .linear
        small.filteringMode = .linear
        mapUniform = SKUniform(name: "u_map", texture: small)
        globeShader = SKShader(source: """
        void main() {
            vec2 d = (v_tex_coord * u_size - u_centre) / u_radius;
            float r = length(d);
            vec4 colour = vec4(0.0);
            // Off the disc (most of an iPad's screen when it is far out) nothing is worked out.
            if (r < 1.0 + 2.0 / u_radius) {
                float z = sqrt(max(0.0, 1.0 - r * r));
                vec3 v = vec3(d.x, d.y, z);
                float a = -u_turn.x;
                vec3 q = vec3(v.x, cos(a) * v.y - sin(a) * v.z, sin(a) * v.y + cos(a) * v.z);
                float b = u_turn.y;
                vec3 p = vec3(cos(b) * q.x + sin(b) * q.z, q.y, -sin(b) * q.x + cos(b) * q.z);
                float lat = asin(clamp(p.y, -1.0, 1.0));
                float lon = atan(p.x, p.z);
                vec2 uv = vec2(lon / 6.2831853 + 0.5, 0.5 + lat / 3.14159265);
                vec3 paint = texture2D(u_map, uv).rgb;
                // The painting's top and bottom rows meet in a point at the poles and streak like a starburst:
                // near a pole the paint fades into the colour of the row round it.
                float pole = smoothstep(0.975, 0.997, abs(p.y));
                if (pole > 0.0) {
                    float row = mix(0.015, 0.985, step(0.0, p.y));
                    vec3 ring = texture2D(u_map, vec2(0.0, row)).rgb + texture2D(u_map, vec2(0.25, row)).rgb
                        + texture2D(u_map, vec2(0.5, row)).rgb + texture2D(u_map, vec2(0.75, row)).rgb;
                    paint = mix(paint, ring * 0.25, pole);
                }
                vec3 light = normalize(vec3(-0.5, 0.55, 0.7));
                float shade = 0.5 + 0.62 * max(dot(v, light), 0.0);
                vec3 lit = paint * shade;
                float haze = pow(1.0 - z, 2.2);
                lit = mix(lit, vec3(0.64, 0.82, 1.0), haze * 0.6);
                // Off the disc the alpha is nought; a soft edge a point and a half wide.
                float alpha = clamp((1.0 - r) * u_radius / 1.5, 0.0, 1.0);
                colour = vec4(lit * alpha, alpha);
            }
            gl_FragColor = colour;
        }
        """)
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
        anchorPoint = .zero
        sprite.anchorPoint = .zero
        sprite.color = .white
        sprite.shader = globeShader
        globeShader.uniforms = [centreUniform, radiusUniform, turnUniform, sizeUniform, mapUniform]
        addChild(sprite)
        fit()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override public func didChangeSize(_: CGSize) {
        fit()
    }

    private func fit() {
        sprite.size = size
        sizeUniform.vectorFloat2Value = SIMD2(Float(size.width), Float(size.height))
    }

    override public func update(_: TimeInterval) {
        guard let pose = pose?(size) else { return }
        centreUniform.vectorFloat2Value = SIMD2(Float(pose.centre.x), Float(pose.centre.y))
        radiusUniform.floatValue = Float(pose.radius)
        let rad = Double.pi / 180
        turnUniform.vectorFloat2Value = SIMD2(Float(pose.orientation.latitude * rad), Float(pose.orientation.longitude * rad))
        // Close in, the full painting; further out, the smaller one.
        #if os(iOS)
            let pixels = view?.contentScaleFactor ?? 2
        #else
            let pixels: CGFloat = 2
        #endif
        let wanted = 2 * .pi * pose.radius * pixels > 3600 ? full : small
        if mapUniform.textureValue !== wanted {
            mapUniform.textureValue = wanted
        }
    }

    private static func halved(_ image: CGImage) -> CGImage? {
        let width = image.width / 2, height = image.height / 2
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
