import SwiftUI

struct CanvasTransform: Codable {
    var scale: CGFloat
    var offsetX: CGFloat
    var offsetY: CGFloat

    static let identity = CanvasTransform(scale: 1.0, offsetX: 0.0, offsetY: 0.0)
}


private var canvasTransform = CanvasTransform.identity

var zoomScale: CGFloat {
    get { canvasTransform.scale }
    set { canvasTransform.scale = newValue }
}

var panOffset: CGSize {
    get { CGSize(width: canvasTransform.offsetX, height: canvasTransform.offsetY) }
    set {
        canvasTransform.offsetX = newValue.width
        canvasTransform.offsetY = newValue.height
    }
}

//
//  CanvasTransform.swift
//  WirelessDesigner
//
//  Created by jupizarr on 6/13/25.
//

