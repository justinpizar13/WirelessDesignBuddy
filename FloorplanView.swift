import SwiftUI
import PhotosUI

/// Applies a high-priority gesture only when `shouldAttach` is true.
struct ConditionalHighPriorityGesture<G: Gesture>: ViewModifier {
    let shouldAttach: Bool
    let gesture: G

    func body(content: Content) -> some View {
        if shouldAttach {
            content.highPriorityGesture(gesture)
        } else {
            content
        }
    }
}

extension View {
    func conditionalHighPriorityGesture<G: Gesture>(
        shouldAttach: Bool,
        gesture: G
    ) -> some View {
        self.modifier(ConditionalHighPriorityGesture(shouldAttach: shouldAttach, gesture: gesture))
    }
}

struct FloorplanView: View {
    enum Mode { case select, drawWall, moveAP, setScale }

    // MARK: – STATE
    @State private var currentMode: Mode = .select

    @State private var floorplanImage: UIImage? = nil
    @State private var selectedItem: PhotosPickerItem? = nil

    @State private var scaleLine: (start: CGPoint, end: CGPoint)? = nil
    @State private var wallLine: (start: CGPoint, end: CGPoint)? = nil
    @State private var metersPerPixel: CGFloat = 0.0

    @State private var walls: [Wall] = []
    @State private var selectedMaterial: WallMaterial = .drywall

    @State private var accessPoints: [AccessPoint] = []

    @State private var zoomScale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    @State private var showHeatmap = false
    @State private var blendMode: HeatmapCanvasView.BlendMode = .combined
    @State private var thresholdEnabled = false
    @State private var rssiThreshold: CGFloat = -67

    // Prompt state
    @State private var promptMessage: String = ""
    @State private var promptResponse: String = ""
    @State private var isShowingPrompt: Bool = false
    @State private var promptContinuation: CheckedContinuation<String, Never>? = nil

    // Zoom limits
    private let zoomMin: CGFloat = 0.2
    private let zoomMax: CGFloat = 5.0

    private var imageLoaded: Bool { floorplanImage != nil }
    private var fullyInitialized: Bool { imageLoaded && metersPerPixel > 0 }

    private var modePickerEnabled: Bool {
        switch currentMode {
        case .setScale, .select: return imageLoaded
        default:                return fullyInitialized
        }
    }

    // MARK: – BODY
    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let img = floorplanImage {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)

                } else {
                    Color.white
                }
                           // 2. Heatmap
                           if showHeatmap && fullyInitialized {
                               HeatmapCanvasView(
                                   width: Int(geo.size.width),
                                   height: Int(geo.size.height),
                                   accessPoints: accessPoints,
                                   walls: walls,
                                   metersPerPixel: metersPerPixel,
                                   blendMode: blendMode,
                                   threshold: thresholdEnabled ? rssiThreshold : nil
                               )
                           }

                           // 3. Live scale line + label
                if let line = scaleLine {
                    let start = canvasPos(line.start)
                    let end = canvasPos(line.end)
                    Path { p in

                        p.move(to: start)
                        p.addLine(to: end)
                    }
                               .stroke(Color.blue,
                                       style: StrokeStyle(lineWidth: 2/zoomScale, dash: [5]))

                               let dx = line.end.x - line.start.x
                               let dy = line.end.y - line.start.y
                               let pxDist = sqrt(dx*dx + dy*dy)
                               let meters = metersPerPixel > 0 ? pxDist * metersPerPixel : 0
                               Text(String(format: "%.2f m", meters))
                                   .font(.caption2)
                                   .padding(4)
                                   .background(Color.white.opacity(0.8))
                                   .cornerRadius(4)
                                   .position(canvasPos(line.end))
                           }

                           // 4. Live wall line
                           if let w = wallLine {
                               Path { p in
                                   p.move(to: canvasPos(w.start))
                                   p.addLine(to: canvasPos(w.end))
                               }
                               .stroke(color(for: selectedMaterial),
                                       style: StrokeStyle(lineWidth: 2/zoomScale, lineCap: .round))
                           }

                           // 5. Existing walls + length labels
                ForEach(walls) { wall in
                    let start = canvasPos(wall.start)
                    let end = canvasPos(wall.end)
                    let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 - 12)

                    let dx = wall.end.x - wall.start.x
                    let dy = wall.end.y - wall.start.y
                    let dist = sqrt(dx * dx + dy * dy) * metersPerPixel
                    let label = String(format: "%.2f m", dist)

                    Group {
                        Path { p in
                            p.move(to: start)
                            p.addLine(to: end)
                        }
                        .stroke(color(for: wall.material),
                                style: StrokeStyle(lineWidth: 2/zoomScale, lineCap: .round))

                        Text(label)
                            .font(.caption2)
                            .padding(4)
                            .background(Color.white.opacity(0.8))
                            .cornerRadius(4)
                            .position(mid)
                    }
                }
                           // 6. Access points
                           ForEach(accessPoints.indices, id: \.self) { i in
                               Circle()
                                   .fill(Color.red)
                                   .frame(width: 16, height: 16)
                                   .position(canvasPos(accessPoints[i].location))
                                   .gesture(
                                       DragGesture()
                                           .onChanged { val in
                                               guard currentMode == .moveAP && fullyInitialized else { return }
                                               accessPoints[i].location = toCanvasPoint(val.location)
                                           }
                                   )
                           }
                       }
            .scaleEffect(zoomScale)
            .offset(panOffset)
            .coordinateSpace(name: "Canvas")
                       .gesture(                 // ← pan & zoom gesture on canvas
                           SimultaneousGesture(
                               MagnificationGesture()
                                   .onChanged { v in
                                       guard imageLoaded else { return }
                                       let newScale = lastScale * v
                                       zoomScale = min(max(newScale, zoomMin), zoomMax)
                                   }
                                   .onEnded { _ in lastScale = zoomScale },

                               DragGesture(minimumDistance: 0)
                                   .onChanged { g in
                                       guard imageLoaded else { return }
                                       panOffset = CGSize(
                                           width: lastOffset.width  + g.translation.width,
                                           height: lastOffset.height + g.translation.height
                                       )
                                   }
                                   .onEnded { _ in lastOffset = panOffset }
                           )
                       )
                       .gesture(
                           DragGesture(minimumDistance: 0)
                               .onEnded { value in
                                   let canvas = toCanvasPoint(value.location)
                                   accessPoints.append(AccessPoint(location: canvas, txPower: 9))
                               }
                       )
                       .conditionalHighPriorityGesture(
                           shouldAttach: currentMode == .setScale || currentMode == .drawWall,
                           gesture: dragForScaleOrWall(geo: geo)
                       )
            // Tap to add AP
            .simultaneousGesture(addTapGesture(geo: geo))
        }
        .overlay(alignment: .top)    { toolbarView() }
        .overlay(alignment: .bottomTrailing) { legendView() }
        .overlay { promptOverlay() }
        .ignoresSafeArea(.keyboard)   // ← add this so our overlay doesn’t fight the keyboard’s inputAccessoryView
        .onChange(of: selectedItem) { _ in loadImage() }
    }

    // MARK: – GESTURES

    private func dragForScaleOrWall(geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("Canvas"))
            .onChanged { v in
                let start = toCanvasPoint(v.startLocation)
                let curr  = toCanvasPoint(v.location)

                switch currentMode {
                case .setScale where imageLoaded:
                    if scaleLine == nil { scaleLine = (start: start, end: start) }
                    scaleLine!.end = curr

                case .drawWall where fullyInitialized:
                    if wallLine == nil { wallLine = (start: start, end: start) }
                    wallLine!.end = curr

                default: break
                }
            }
            .onEnded { _ in
                switch currentMode {
                case .setScale where imageLoaded:
                    if let line = scaleLine {
                        let dx = line.end.x - line.start.x
                        let dy = line.end.y - line.start.y
                        let pxDist = sqrt(dx*dx + dy*dy)
                        Task {
                            let input = await showTextPrompt("Enter distance (m):")
                            if let m = Double(input), m > 0 {
                                metersPerPixel = CGFloat(m) / pxDist
                            }
                        }
                    }
                    scaleLine = nil

                case .drawWall where fullyInitialized:
                    if let w = wallLine {
                        walls.append(Wall(start: w.start, end: w.end, material: selectedMaterial))
                    }
                    wallLine = nil

                default: break
                }
            }
    }

    private func panAndZoomGesture() -> some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .onChanged { v in
                    guard imageLoaded else { return }
                    let newScale = lastScale * v
                    zoomScale = min(max(newScale, zoomMin), zoomMax)
                }
                .onEnded { _ in
                    guard imageLoaded else { return }
                    lastScale = zoomScale
                },
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    guard imageLoaded else { return }
                    panOffset = CGSize(
                        width: lastOffset.width  + g.translation.width,
                        height: lastOffset.height + g.translation.height
                    )
                }
                .onEnded { _ in
                    guard imageLoaded else { return }
                    lastOffset = panOffset
                }
        )
    }

    private func addTapGesture(geo: GeometryProxy) -> some Gesture {
        TapGesture()
            .onEnded {
                guard currentMode == .moveAP && fullyInitialized else { return }
                // Place AP at center—for a real app you’d capture the actual tap point
                
                let tap = CGPoint(x: geo.frame(in: .named("Canvas")).midX,
                                 y: geo.frame(in: .named("Canvas")).midY)
                accessPoints.append(
                    AccessPoint(location: toCanvasPoint(tap), txPower: 9)
                )
            }
    }

    // MARK: – TOOLBAR
    @ViewBuilder private func toolbarView() -> some View {
        VStack(spacing: 4) {
            HStack {
                Picker("Mode", selection: $currentMode) {
                    Text("🖐 Select").tag(Mode.select)
                    Text("🧱 Wall").tag(Mode.drawWall)
                    Text("📍 AP").tag(Mode.moveAP)
                    Text("📏 Scale").tag(Mode.setScale)
                }
                .pickerStyle(.segmented)
                .disabled(!modePickerEnabled)

                if currentMode == .drawWall {
                    Picker("Material", selection: $selectedMaterial) {
                        ForEach(WallMaterial.allCases, id: \.self) {
                            Text($0.rawValue.capitalized).tag($0)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(!fullyInitialized)
                }

                Spacer()

                Toggle("Heatmap", isOn: $showHeatmap)
                    .disabled(!fullyInitialized)

                if showHeatmap {
                    Picker("Blend", selection: $blendMode) {
                        Text("Strongest").tag(HeatmapCanvasView.BlendMode.strongest)
                        Text("Combined").tag(HeatmapCanvasView.BlendMode.combined)
                    }
                    .pickerStyle(.segmented)
                    .disabled(!fullyInitialized)
                }

                PhotosPicker("🖼️ Upload", selection: $selectedItem, matching: .images)
            }
            .padding(.horizontal)

            if showHeatmap {
                Toggle("Threshold", isOn: $thresholdEnabled)
                    .disabled(!fullyInitialized)
                    .padding(.horizontal)
                if thresholdEnabled {
                    HStack {
                        Text("Min RSSI:")
                        Slider(value: $rssiThreshold, in: -100 ... -40, step: 1)
                        Text("\(Int(rssiThreshold)) dBm")
                            .font(.caption2)
                    }
                    .padding(.horizontal)
                }
            }

            Divider()
        }
        .padding(.top, 5)
        .background(.ultraThinMaterial)
    }

    // MARK: – LEGEND
    @ViewBuilder private func legendView() -> some View {
        if showHeatmap && fullyInitialized {
            VStack(alignment: .trailing, spacing: 2) {
                ForEach([-50, -60, -70, -80, -90, -100], id: \.self) { dbm in
                    HStack {
                        Rectangle()
                            .fill(legendColor(dbm))
                            .frame(width: 30, height: 8)
                        Text("\(dbm)dBm")
                            .font(.caption2)
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(6)
            .background(Color.black.opacity(0.6))
            .cornerRadius(6)
            .padding(8)
        }
    }

    // MARK: – PROMPT OVERLAY
    @ViewBuilder private func promptOverlay() -> some View {
        if isShowingPrompt {
            Color.black.opacity(0.4).ignoresSafeArea()
            PromptView(
                message: promptMessage,
                text: $promptResponse,
                onSubmit: {
                    isShowingPrompt = false
                    promptContinuation?.resume(returning: promptResponse)
                    promptContinuation = nil
                },
                onCancel: {
                    isShowingPrompt = false
                    promptContinuation?.resume(returning: "")
                    promptContinuation = nil
                }
            )
        }
    }

    // MARK: – HELPERS

    private func color(for material: WallMaterial) -> Color {
        switch material {
        case .drywall:  return Color("Tan")
        case .glass:    return .blue
        case .concrete: return Color.gray.opacity(0.7)
        case .metal:    return .purple
        }
    }

    private func legendColor(_ dbm: Int) -> Color {
        switch dbm {
        case let x where x >= -50: return .red
        case let x where x >= -60: return .orange
        case let x where x >= -70: return .yellow
        case let x where x >= -80: return .green
        case let x where x >= -90: return .cyan
        default:                  return .blue
        }
    }

    private func toCanvasPoint(_ loc: CGPoint) -> CGPoint {
        CGPoint(
            x: (loc.x - panOffset.width)  / zoomScale,
            y: (loc.y - panOffset.height) / zoomScale
        )
    }

    
private func canvasPos(_ pt: CGPoint) -> CGPoint {
    let x = pt.x * zoomScale + panOffset.width
    let y = pt.y * zoomScale + panOffset.height
    print("canvasPos: (\(pt.x), \(pt.y)) -> (\(x), \(y))")
    return CGPoint(x: x, y: y)
}


    private func loadImage() {
        Task {
            if let data = try? await selectedItem?.loadTransferable(type: Data.self),
               let ui   = UIImage(data: data) {
                floorplanImage = ui
            }
        }
    }

    func showTextPrompt(_ prompt: String) async -> String {
        await withCheckedContinuation { cont in
            promptMessage     = prompt
            promptResponse    = ""
            promptContinuation = cont
            isShowingPrompt   = true
        }
    }
}

// MARK: – PROMPT VIEW

struct PromptView: View {
    let message: String
    @Binding var text: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(message).font(.headline)

            // ──> Add the empty keyboard toolbar here <──
            TextField("Value…", text: $text)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
                .frame(width: 200)
              #if os(iOS)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) { }
                }
              #endif

            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                Button("OK", action: onSubmit)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(radius: 10)
    }
}

