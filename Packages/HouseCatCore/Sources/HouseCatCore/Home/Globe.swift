import Foundation

/// The world drawn as a globe (the map screen and the intro): an orthographic view of a sphere turned so that
/// `centre` faces the viewer. The painted equirectangular map is wrapped round it by the app's shader, which
/// does the same sums per pixel; these turn places into points on screen and taps back into places.
public struct GlobeOrientation: Equatable, Sendable {
    /// The place at the middle of the disc, in degrees.
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Where a place sits on the disc: x and y from -1 to 1 (y up), and whether it faces the viewer (`depth` is
    /// how squarely: 1 at the middle, 0 at the rim, negative round the back).
    public func project(latitude lat: Double, longitude lon: Double) -> (x: Double, y: Double, depth: Double) {
        let rad = Double.pi / 180
        let (p0, p1, p2) = (cos(lat * rad) * sin(lon * rad), sin(lat * rad), cos(lat * rad) * cos(lon * rad))
        // Turn the globe by -longitude about the pole, then by latitude about the horizontal.
        let b = -longitude * rad
        let q0 = cos(b) * p0 + sin(b) * p2, q2 = -sin(b) * p0 + cos(b) * p2
        let a = latitude * rad
        let y = cos(a) * p1 - sin(a) * q2, z = sin(a) * p1 + cos(a) * q2
        return (q0, y, z)
    }

    /// The place under a point on the disc (x and y from -1 to 1, y up), or nil off the disc.
    public func place(x: Double, y: Double) -> (latitude: Double, longitude: Double)? {
        let r2 = x * x + y * y
        guard r2 <= 1 else { return nil }
        let z = (1 - r2).squareRoot()
        let rad = Double.pi / 180
        let a = -latitude * rad
        let v1 = cos(a) * y - sin(a) * z, v2 = sin(a) * y + cos(a) * z
        let b = longitude * rad
        let p0 = cos(b) * x + sin(b) * v2, p2 = -sin(b) * x + cos(b) * v2
        let lat = asin(min(1, max(-1, v1))) / rad
        let lon = atan2(p0, p2) / rad
        return (lat, lon)
    }

    /// Turned by a drag of `dx`, `dy` (fractions of the disc's radius; y down, as on screen): the surface follows
    /// the finger. Latitude stays within the tilt limit; longitude wraps.
    public func dragged(dx: Double, dy: Double) -> GlobeOrientation {
        let degrees = 180 / Double.pi
        var lon = longitude - dx * degrees
        lon = (lon + 540).truncatingRemainder(dividingBy: 360) - 180
        let limit = Tuning.World.globeTiltLimit
        return GlobeOrientation(latitude: min(limit, max(-limit, latitude + dy * degrees)), longitude: lon)
    }

    /// Part of the way from here to another view (0 here, 1 there), the short way round.
    public func blended(to other: GlobeOrientation, by t: Double) -> GlobeOrientation {
        var dLon = other.longitude - longitude
        if dLon > 180 {
            dLon -= 360
        }
        if dLon < -180 {
            dLon += 360
        }
        var lon = longitude + dLon * t
        lon = (lon + 540).truncatingRemainder(dividingBy: 360) - 180
        return GlobeOrientation(latitude: latitude + (other.latitude - latitude) * t, longitude: lon)
    }
}
