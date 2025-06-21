import SwiftUI
import CoreGraphics

struct HeatmapCanvasView: View {
    enum BlendMode { case strongest, combined }
    var width: Int
    var height: Int
    var accessPoints: [AccessPoint]
    var walls: [Wall]
    var metersPerPixel: CGFloat
    var blendMode: BlendMode
    var threshold: CGFloat?

    let frequencyMHz: CGFloat = 2400

    var body: some View {
        if let img = generateHeatmap() {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .allowsHitTesting(false)
        }
    }

    func generateHeatmap() -> UIImage? {
        let w = width, h = height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * w
        let data = UnsafeMutablePointer<UInt8>.allocate(capacity: w * h * 4)
        defer { data.deallocate() }

        for y in 0..<h {
            for x in 0..<w {
                let pt = CGPoint(x: CGFloat(x), y: CGFloat(y))
                var combinedRSSI: CGFloat

                switch blendMode {
                case .strongest:
                    combinedRSSI = -150
                    for ap in accessPoints where ap.isEnabled {
                        combinedRSSI = max(combinedRSSI,
                                          RFModel.calculateRSSI(ap: ap, receiver: pt,
                                                                frequencyMHz: frequencyMHz,
                                                                walls: walls,
                                                                metersPerPixel: metersPerPixel))
                    }
                case .combined:
                    var linearSum: CGFloat = 0
                    for ap in accessPoints where ap.isEnabled {
                        let rssi = RFModel.calculateRSSI(ap: ap, receiver: pt,
                                                         frequencyMHz: frequencyMHz,
                                                         walls: walls,
                                                         metersPerPixel: metersPerPixel)
                        linearSum += pow(10, rssi / 10)
                    }
                    combinedRSSI = linearSum > 0 ? 10 * log10(linearSum) : -150
                }

                let color = colorForRSSI(combinedRSSI, threshold: threshold)
                let idx = (y * w + x) * 4
                data[idx] = color.red
                data[idx + 1] = color.green
                data[idx + 2] = color.blue
                data[idx + 3] = 150
            }
        }

        let ctx = CGContext(data: data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: bytesPerRow, space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let cg = ctx?.makeImage() else { return nil }
        return UIImage(cgImage: cg)
    }

    func colorForRSSI(_ r: CGFloat, threshold: CGFloat?) -> (red: UInt8, green: UInt8, blue: UInt8) {
        if let t = threshold {
            return r >= t ? (0, 255, 0) : (255, 0, 0)
        }
        switch r {
        case let x where x >= -50:     return (255, 0, 0)
        case let x where x >= -60:     return (255, 165, 0)
        case let x where x >= -70:     return (255, 255, 0)
        case let x where x >= -80:     return (0, 255, 0)
        case let x where x >= -90:     return (0, 255, 255)
        default:                       return (0, 0, 255)
        }
    }
}
//
//  HeatmapCanvasView.swift
//  WirelessDesigner
//
//  Created by jupizarr on 6/13/25.
//

