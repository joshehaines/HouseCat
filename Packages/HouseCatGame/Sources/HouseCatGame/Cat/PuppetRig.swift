import CoreGraphics

/// The cat puppet rig (assets/cat/rig.json, set by eye with tools/asset-pipeline/puppet.py).
public struct PuppetRig: Decodable, Sendable {
    public struct Part: Decodable, Sendable {
        /// Where the part joins its parent, as a fraction of its own image (0,0 top-left).
        public var pivot: [Double]
        public var parent: String?
        /// The point on the parent it joins, as a fraction of the parent's image.
        public var at: [Double]
        /// Draw order within the cat; higher is in front.
        public var z: Double
        /// Rest angle in degrees, clockwise.
        public var angle: Double?
    }

    public struct Walk: Decodable, Sendable {
        public var legSwing: Double
        public var tailSway: Double
        public var headBob: Double
    }

    public struct View: Decodable, Sendable {
        /// The way the painted view faces: "left" or "front".
        public var facing: String
        public var parts: [String: Part]
        public var walk: Walk?
        /// The rest pose's size in part pixels.
        public var assembled: [Double]
        /// The painted standing reference's size; the resting poses share its scale.
        public var whole: [Double]
    }

    public var sets: [String: [String: View]]
}
