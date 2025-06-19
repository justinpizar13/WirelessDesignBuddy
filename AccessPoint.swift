import Foundation
import CoreGraphics

struct AccessPoint: Identifiable, Codable {
    let id: UUID
    var location: Point
    var txPower: CGFloat
    var isEnabled: Bool

    init(id: UUID = UUID(), location: Point, txPower: CGFloat, isEnabled: Bool = true) {
        self.id = id
        self.location = location
        self.txPower = txPower
        self.isEnabled = isEnabled
    }
}

extension AccessPoint: Equatable {
    static func == (lhs: AccessPoint, rhs: AccessPoint) -> Bool {
        lhs.id == rhs.id
    }
}
