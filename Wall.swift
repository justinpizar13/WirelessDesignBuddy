import Foundation
import CoreGraphics

enum WallMaterial: String, CaseIterable, Codable {
    case drywall, concrete, glass, metal
    var attenuation: CGFloat {
        switch self {
        case .drywall: return 3
        case .concrete: return 8
        case .glass: return 6
        case .metal: return 12
        }
    }
}

struct Wall: Identifiable, Codable {
    let id: UUID
    var start: Point
    var end: Point
    var material: WallMaterial

    init(id: UUID = UUID(), start: Point, end: Point, material: WallMaterial) {
        self.id = id
        self.start = start
        self.end = end
        self.material = material
    }
}

extension Wall: Equatable {
    static func == (lhs: Wall, rhs: Wall) -> Bool {
        lhs.id == rhs.id
    }
}
