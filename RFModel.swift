import Foundation
import CoreGraphics

struct RFModel {
    static func calculateRSSI(
        ap: AccessPoint,
        receiver: Point,
        frequencyMHz: CGFloat,
        walls: [Wall],
        metersPerPixel: CGFloat
    ) -> CGFloat {
        let dx = receiver.x - ap.location.x
        let dy = receiver.y - ap.location.y
        let distPx = sqrt(dx*dx + dy*dy)
        let distM = distPx * metersPerPixel
        let distKm = max(distM / 1000.0, 0.0001)

        let fspl = 20 * log10(distKm) + 20 * log10(frequencyMHz) + 32.45
        let wallLoss = walls
            .filter { intersects(p1: ap.location, p2: receiver, q1: $0.start, q2: $0.end) }
            .reduce(0) { $0 + $1.material.attenuation }

        return ap.txPower - fspl - wallLoss
    }

    static func intersects(p1: Point, p2: Point, q1: Point, q2: Point) -> Bool {
        func ccw(_ a: Point, _ b: Point, _ c: Point) -> Bool {
            (c.y - a.y) * (b.x - a.x) > (b.y - a.y) * (c.x - a.x)
        }
        return ccw(p1, q1, q2) != ccw(p2, q1, q2) && ccw(p1, p2, q1) != ccw(p1, p2, q2)
    }
}
