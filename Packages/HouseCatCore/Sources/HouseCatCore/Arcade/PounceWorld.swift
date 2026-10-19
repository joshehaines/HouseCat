import Foundation

/// The physics Catapult runs on: boxes and balls in two dimensions, in metres and seconds, stepped at a fixed rate
/// so the same pounce does the same thing on every device and at any frame rate (and a level's solution can be
/// checked in a test). After Erin Catto's Box2D Lite: contacts found each step, impulses accumulated over a few
/// passes and carried from step to step (so towers stand), a little push apart where pieces overlap.
public struct Vec2: Equatable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec2(0, 0)

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static func * (s: Double, a: Vec2) -> Vec2 { Vec2(s * a.x, s * a.y) }
    public static prefix func - (a: Vec2) -> Vec2 { Vec2(-a.x, -a.y) }
    public static func += (a: inout Vec2, b: Vec2) { a = a + b }
    public static func -= (a: inout Vec2, b: Vec2) { a = a - b }

    public var length: Double { (x * x + y * y).squareRoot() }
    func dot(_ b: Vec2) -> Double { x * b.x + y * b.y }
    /// The 2D cross product (a scalar).
    func cross(_ b: Vec2) -> Double { x * b.y - y * b.x }
    var abs: Vec2 { Vec2(Swift.abs(x), Swift.abs(y)) }
}

/// w × v and v × s, as Box2D writes them.
private func cross(_ s: Double, _ v: Vec2) -> Vec2 { Vec2(-s * v.y, s * v.x) }
private func cross(_ v: Vec2, _ s: Double) -> Vec2 { Vec2(s * v.y, -s * v.x) }

struct Mat22 {
    var col1: Vec2
    var col2: Vec2

    init(angle: Double) {
        let c = cos(angle), s = sin(angle)
        col1 = Vec2(c, s)
        col2 = Vec2(-s, c)
    }

    init(_ col1: Vec2, _ col2: Vec2) {
        self.col1 = col1
        self.col2 = col2
    }

    var transpose: Mat22 { Mat22(Vec2(col1.x, col2.x), Vec2(col1.y, col2.y)) }
    var abs: Mat22 { Mat22(col1.abs, col2.abs) }
    static func * (m: Mat22, v: Vec2) -> Vec2 { Vec2(m.col1.x * v.x + m.col2.x * v.y, m.col1.y * v.x + m.col2.y * v.y) }
    static func * (a: Mat22, b: Mat22) -> Mat22 { Mat22(a * b.col1, a * b.col2) }
}

public enum PounceShape: Equatable, Sendable {
    /// Half its width and height.
    case box(Vec2)
    case ball(Double)
}

public struct PounceBody: Sendable, Identifiable {
    public let id: Int
    public var shape: PounceShape
    public var position: Vec2
    public var rotation: Double
    public var velocity = Vec2.zero
    public var spin = 0.0
    public let mass: Double
    let invMass: Double
    let inertia: Double
    let invInertia: Double
    public var friction: Double
    public var bounce: Double
    /// What it is in the level (the scene picks its picture by this): "ground", "ledge", "cat", "mouse", or a piece.
    public var role: String

    public init(id: Int, shape: PounceShape, position: Vec2, rotation: Double = 0, density: Double, friction: Double = 0.6,
                bounce: Double = 0, role: String)
    {
        self.id = id
        self.shape = shape
        self.position = position
        self.rotation = rotation
        self.friction = friction
        self.bounce = bounce
        self.role = role
        if density.isInfinite {
            mass = .infinity
            invMass = 0
            inertia = .infinity
            invInertia = 0
        } else {
            switch shape {
            case let .box(h):
                mass = density * 4 * h.x * h.y
                inertia = mass * (4 * h.x * h.x + 4 * h.y * h.y) / 12
            case let .ball(r):
                mass = density * Double.pi * r * r
                inertia = mass * r * r / 2
            }
            invMass = 1 / mass
            invInertia = 1 / inertia
        }
    }

    public var isStatic: Bool {
        invMass == 0
    }

    /// How far the body reaches from its middle, any way round.
    var reach: Double {
        switch shape {
        case let .box(h): h.length
        case let .ball(r): r
        }
    }

    /// The lowest point of the body, for "it has reached the ground".
    public var bottom: Double {
        switch shape {
        case let .ball(r): return position.y - r
        case let .box(h):
            let c = Swift.abs(cos(rotation)), s = Swift.abs(sin(rotation))
            return position.y - (s * h.x + c * h.y)
        }
    }
}

struct PounceContact {
    var position: Vec2
    var normal: Vec2
    var separation: Double
    var feature: Int
    var pn = 0.0
    var pt = 0.0
    var massNormal = 0.0
    var massTangent = 0.0
    var bias = 0.0
}

struct PounceArbiter {
    let a: Int
    let b: Int
    var contacts: [PounceContact]
    let friction: Double
    let bounce: Double
}

public struct PounceWorld: Sendable {
    public var bodies: [PounceBody] = []
    var arbiters: [Int: PounceArbiter] = [:]
    public var gravity = Vec2(0, -Tuning.Arcade.Catapult.gravity)
    /// Pairs that touched in the last step (body ids, smaller first).
    public private(set) var touching: Set<[Int]> = []
    private var nextID = 0

    public init() {}

    @discardableResult
    public mutating func add(_ shape: PounceShape, at position: Vec2, rotation: Double = 0, density: Double,
                             friction: Double = 0.6, bounce: Double = 0, role: String) -> Int
    {
        let body = PounceBody(id: nextID, shape: shape, position: position, rotation: rotation, density: density,
                              friction: friction, bounce: bounce, role: role)
        nextID += 1
        bodies.append(body)
        return body.id
    }

    public mutating func remove(_ id: Int) {
        bodies.removeAll { $0.id == id }
        arbiters = arbiters.filter { $0.value.a != id && $0.value.b != id }
    }

    public func body(_ id: Int) -> PounceBody? {
        bodies.first { $0.id == id }
    }

    /// Slows a body that has landed: its speed scaled by `keeping` each step, no spin.
    mutating func land(_ id: Int, keeping: Double) {
        if let i = bodies.firstIndex(where: { $0.id == id }) {
            bodies[i].velocity = keeping * bodies[i].velocity
            bodies[i].spin = 0
        }
    }

    public mutating func setVelocity(_ id: Int, _ velocity: Vec2) {
        if let i = bodies.firstIndex(where: { $0.id == id }) { bodies[i].velocity = velocity }
    }

    /// The fastest anything is moving (metres a second, spin counted at a body's edge).
    public var fastest: Double {
        bodies.filter { !$0.isStatic }.map { body -> Double in
            let reach: Double = switch body.shape {
            case let .box(h): h.length
            case let .ball(r): r
            }
            return body.velocity.length + Swift.abs(body.spin) * reach
        }.max() ?? 0
    }

    /// One fixed step.
    public mutating func step(_ dt: Double) {
        let invDt = dt > 0 ? 1 / dt : 0
        let c = Tuning.Arcade.Catapult.self
        // Contacts.
        var seen = Set<Int>()
        touching = []
        for i in 0 ..< bodies.count {
            for j in (i + 1) ..< bodies.count {
                let bi = bodies[i], bj = bodies[j]
                if bi.isStatic, bj.isStatic { continue }
                let key = bi.id * 100_000 + bj.id
                let gap = bi.position - bj.position, reach = bi.reach + bj.reach
                if gap.x * gap.x + gap.y * gap.y > reach * reach {
                    arbiters[key] = nil
                    continue
                }
                let found = Self.collide(bi, bj)
                if found.isEmpty {
                    arbiters[key] = nil
                    continue
                }
                seen.insert(key)
                touching.insert([bi.id, bj.id])
                var arbiter = PounceArbiter(a: i, b: j, contacts: found, friction: (bi.friction * bj.friction).squareRoot(),
                                            bounce: max(bi.bounce, bj.bounce))
                // Warm start from last step's matching contacts.
                if let old = arbiters[key] {
                    for k in 0 ..< arbiter.contacts.count {
                        if let match = old.contacts.first(where: { $0.feature == arbiter.contacts[k].feature }) {
                            arbiter.contacts[k].pn = match.pn
                            arbiter.contacts[k].pt = match.pt
                        }
                    }
                }
                arbiters[key] = arbiter
            }
        }
        arbiters = arbiters.filter { seen.contains($0.key) }
        // Forces.
        for i in bodies.indices where !bodies[i].isStatic {
            bodies[i].velocity += dt * gravity
            bodies[i].velocity = (1 - c.linearDamping * dt) * bodies[i].velocity
            bodies[i].spin *= 1 - c.angularDamping * dt
        }
        // Prepare.
        let keys = arbiters.keys.sorted()
        for key in keys {
            guard var arbiter = arbiters[key] else { continue }
            let a = bodies[arbiter.a], b = bodies[arbiter.b]
            for k in 0 ..< arbiter.contacts.count {
                var ct = arbiter.contacts[k]
                let r1 = ct.position - a.position, r2 = ct.position - b.position
                let rn1 = r1.dot(ct.normal), rn2 = r2.dot(ct.normal)
                var kNormal = a.invMass + b.invMass
                kNormal += a.invInertia * (r1.dot(r1) - rn1 * rn1) + b.invInertia * (r2.dot(r2) - rn2 * rn2)
                ct.massNormal = 1 / kNormal
                let tangent = cross(ct.normal, 1.0)
                let rt1 = r1.dot(tangent), rt2 = r2.dot(tangent)
                var kTangent = a.invMass + b.invMass
                kTangent += a.invInertia * (r1.dot(r1) - rt1 * rt1) + b.invInertia * (r2.dot(r2) - rt2 * rt2)
                ct.massTangent = 1 / kTangent
                ct.bias = -c.biasFactor * invDt * min(0, ct.separation + c.allowedPenetration)
                if arbiter.bounce > 0 {
                    let dv = b.velocity + cross(b.spin, r2) - a.velocity - cross(a.spin, r1)
                    let vn = dv.dot(ct.normal)
                    if vn < -c.bounceFrom { ct.bias = max(ct.bias, -arbiter.bounce * vn) }
                }
                // Apply last step's impulse.
                let p = ct.pn * ct.normal + ct.pt * tangent
                bodies[arbiter.a].velocity -= a.invMass * p
                bodies[arbiter.a].spin -= a.invInertia * r1.cross(p)
                bodies[arbiter.b].velocity += b.invMass * p
                bodies[arbiter.b].spin += b.invInertia * r2.cross(p)
                arbiter.contacts[k] = ct
            }
            arbiters[key] = arbiter
        }
        // Impulses.
        for _ in 0 ..< c.iterations {
            for key in keys {
                guard var arbiter = arbiters[key] else { continue }
                for k in 0 ..< arbiter.contacts.count {
                    var ct = arbiter.contacts[k]
                    var a = bodies[arbiter.a], b = bodies[arbiter.b]
                    let r1 = ct.position - a.position, r2 = ct.position - b.position
                    var dv = b.velocity + cross(b.spin, r2) - a.velocity - cross(a.spin, r1)
                    let vn = dv.dot(ct.normal)
                    var dPn = ct.massNormal * (-vn + ct.bias)
                    let pn0 = ct.pn
                    ct.pn = max(pn0 + dPn, 0)
                    dPn = ct.pn - pn0
                    let pn = dPn * ct.normal
                    a.velocity -= a.invMass * pn
                    a.spin -= a.invInertia * r1.cross(pn)
                    b.velocity += b.invMass * pn
                    b.spin += b.invInertia * r2.cross(pn)
                    dv = b.velocity + cross(b.spin, r2) - a.velocity - cross(a.spin, r1)
                    let tangent = cross(ct.normal, 1.0)
                    let vt = dv.dot(tangent)
                    var dPt = ct.massTangent * -vt
                    let maxPt = arbiter.friction * ct.pn
                    let pt0 = ct.pt
                    ct.pt = min(max(pt0 + dPt, -maxPt), maxPt)
                    dPt = ct.pt - pt0
                    let pt = dPt * tangent
                    a.velocity -= a.invMass * pt
                    a.spin -= a.invInertia * r1.cross(pt)
                    b.velocity += b.invMass * pt
                    b.spin += b.invInertia * r2.cross(pt)
                    bodies[arbiter.a].velocity = a.velocity
                    bodies[arbiter.a].spin = a.spin
                    bodies[arbiter.b].velocity = b.velocity
                    bodies[arbiter.b].spin = b.spin
                    arbiter.contacts[k] = ct
                }
                arbiters[key] = arbiter
            }
        }
        // Move.
        for i in bodies.indices where !bodies[i].isStatic {
            bodies[i].position += dt * bodies[i].velocity
            bodies[i].rotation += dt * bodies[i].spin
        }
    }

    // MARK: Collision

    static func collide(_ a: PounceBody, _ b: PounceBody) -> [PounceContact] {
        switch (a.shape, b.shape) {
        case let (.box(ha), .box(hb)): boxBox(a, ha, b, hb)
        case let (.ball(ra), .ball(rb)): ballBall(a, ra, b, rb)
        case let (.box(h), .ball(r)): boxBall(a, h, b, r, flip: false)
        case let (.ball(r), .box(h)): boxBall(b, h, a, r, flip: true)
        }
    }

    static func ballBall(_ a: PounceBody, _ ra: Double, _ b: PounceBody, _ rb: Double) -> [PounceContact] {
        let d = b.position - a.position
        let dist = d.length
        guard dist < ra + rb else { return [] }
        let normal = dist > 1e-9 ? (1 / dist) * d : Vec2(0, 1)
        return [PounceContact(position: a.position + ra * normal, normal: normal, separation: dist - ra - rb, feature: 1)]
    }

    /// A box and a ball; the normal points from the first body to the second, so a ball first flips it.
    static func boxBall(_ box: PounceBody, _ h: Vec2, _ ball: PounceBody, _ r: Double, flip: Bool) -> [PounceContact] {
        let rot = Mat22(angle: box.rotation)
        let local = rot.transpose * (ball.position - box.position)
        let clamped = Vec2(min(max(local.x, -h.x), h.x), min(max(local.y, -h.y), h.y))
        var normalLocal: Vec2, pointLocal: Vec2, separation: Double
        if clamped == local {
            // The ball's middle is inside the box: out through the nearest side.
            let dx = h.x - Swift.abs(local.x), dy = h.y - Swift.abs(local.y)
            if dx < dy {
                normalLocal = Vec2(local.x >= 0 ? 1 : -1, 0)
                pointLocal = Vec2(normalLocal.x * h.x, local.y)
                separation = -dx - r
            } else {
                normalLocal = Vec2(0, local.y >= 0 ? 1 : -1)
                pointLocal = Vec2(local.x, normalLocal.y * h.y)
                separation = -dy - r
            }
        } else {
            let d = local - clamped
            let dist = d.length
            guard dist < r else { return [] }
            normalLocal = (1 / dist) * d
            pointLocal = clamped
            separation = dist - r
        }
        var normal = rot * normalLocal
        let point = box.position + rot * pointLocal
        if flip { normal = -normal }
        return [PounceContact(position: point, normal: normal, separation: separation, feature: 2)]
    }

    /// Box2D Lite's box against box: the axis of least overlap, the incident edge clipped against the reference
    /// face's sides, up to two contact points.
    static func boxBox(_ bodyA: PounceBody, _ hA: Vec2, _ bodyB: PounceBody, _ hB: Vec2) -> [PounceContact] {
        let posA = bodyA.position, posB = bodyB.position
        let rotA = Mat22(angle: bodyA.rotation), rotB = Mat22(angle: bodyB.rotation)
        let rotAT = rotA.transpose, rotBT = rotB.transpose
        let dp = posB - posA
        let dA = rotAT * dp, dB = rotBT * dp
        let c = rotAT * rotB
        let absC = c.abs, absCT = absC.transpose
        let faceA = dA.abs - hA - absC * hB
        if faceA.x > 0 || faceA.y > 0 { return [] }
        let faceB = dB.abs - absCT * hA - hB
        if faceB.x > 0 || faceB.y > 0 { return [] }
        enum Axis { case faceAX, faceAY, faceBX, faceBY }
        var axis = Axis.faceAX
        var separation = faceA.x
        var normal = dA.x > 0 ? rotA.col1 : -rotA.col1
        let relTol = 0.95, absTol = 0.01
        if faceA.y > relTol * separation + absTol * hA.y {
            axis = .faceAY
            separation = faceA.y
            normal = dA.y > 0 ? rotA.col2 : -rotA.col2
        }
        if faceB.x > relTol * separation + absTol * hB.x {
            axis = .faceBX
            separation = faceB.x
            normal = dB.x > 0 ? rotB.col1 : -rotB.col1
        }
        if faceB.y > relTol * separation + absTol * hB.y {
            axis = .faceBY
            separation = faceB.y
            normal = dB.y > 0 ? rotB.col2 : -rotB.col2
        }
        // The reference face and the incident edge.
        var frontNormal: Vec2, sideNormal: Vec2
        var incident: [(Vec2, Int)]
        var front: Double, negSide: Double, posSide: Double
        var negEdge: Int, posEdge: Int
        switch axis {
        case .faceAX:
            frontNormal = normal
            front = posA.dot(frontNormal) + hA.x
            sideNormal = rotA.col2
            let side = posA.dot(sideNormal)
            negSide = -side + hA.y
            posSide = side + hA.y
            negEdge = 3
            posEdge = 1
            incident = incidentEdge(hB, posB, rotB, frontNormal)
        case .faceAY:
            frontNormal = normal
            front = posA.dot(frontNormal) + hA.y
            sideNormal = rotA.col1
            let side = posA.dot(sideNormal)
            negSide = -side + hA.x
            posSide = side + hA.x
            negEdge = 2
            posEdge = 4
            incident = incidentEdge(hB, posB, rotB, frontNormal)
        case .faceBX:
            frontNormal = -normal
            front = posB.dot(frontNormal) + hB.x
            sideNormal = rotB.col2
            let side = posB.dot(sideNormal)
            negSide = -side + hB.y
            posSide = side + hB.y
            negEdge = 3
            posEdge = 1
            incident = incidentEdge(hA, posA, rotA, frontNormal)
        case .faceBY:
            frontNormal = -normal
            front = posB.dot(frontNormal) + hB.y
            sideNormal = rotB.col1
            let side = posB.dot(sideNormal)
            negSide = -side + hB.x
            posSide = side + hB.x
            negEdge = 2
            posEdge = 4
            incident = incidentEdge(hA, posA, rotA, frontNormal)
        }
        guard let clip1 = clip(incident, -sideNormal, negSide, negEdge), clip1.count == 2,
              let clip2 = clip(clip1, sideNormal, posSide, posEdge), clip2.count == 2 else { return [] }
        var contacts: [PounceContact] = []
        for (point, feature) in clip2 {
            let sep = frontNormal.dot(point) - front
            if sep <= 0 {
                // Slid onto the reference face, as Box2D Lite does.
                contacts.append(PounceContact(position: point - sep * frontNormal, normal: normal, separation: sep,
                                              feature: feature * 10 + (axis == .faceAX || axis == .faceAY ? 0 : 1)))
            }
        }
        return contacts
    }

    /// The edge of a box most against `normal`, as two points with feature numbers.
    private static func incidentEdge(_ h: Vec2, _ pos: Vec2, _ rot: Mat22, _ normal: Vec2) -> [(Vec2, Int)] {
        let n = -(rot.transpose * normal)
        let nAbs = n.abs
        var v1: Vec2, v2: Vec2, f1: Int, f2: Int
        if nAbs.x > nAbs.y {
            if n.x > 0 {
                v1 = Vec2(h.x, -h.y); v2 = Vec2(h.x, h.y); f1 = 3; f2 = 4
            } else {
                v1 = Vec2(-h.x, h.y); v2 = Vec2(-h.x, -h.y); f1 = 1; f2 = 2
            }
        } else {
            if n.y > 0 {
                v1 = Vec2(h.x, h.y); v2 = Vec2(-h.x, h.y); f1 = 4; f2 = 1
            } else {
                v1 = Vec2(-h.x, -h.y); v2 = Vec2(h.x, -h.y); f1 = 2; f2 = 3
            }
        }
        return [(pos + rot * v1, f1), (pos + rot * v2, f2)]
    }

    /// Sutherland–Hodgman against one side line.
    private static func clip(_ points: [(Vec2, Int)], _ normal: Vec2, _ offset: Double, _ edge: Int) -> [(Vec2, Int)]? {
        var out: [(Vec2, Int)] = []
        let d0 = normal.dot(points[0].0) - offset, d1 = normal.dot(points[1].0) - offset
        if d0 <= 0 { out.append(points[0]) }
        if d1 <= 0 { out.append(points[1]) }
        if d0 * d1 < 0 {
            let t = d0 / (d0 - d1)
            let p = points[0].0 + t * (points[1].0 - points[0].0)
            out.append((p, d0 > 0 ? points[0].1 * 100 + edge : points[1].1 * 100 + edge))
        }
        return out
    }
}
