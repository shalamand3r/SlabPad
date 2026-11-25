// PressurePlayground.swift
// cool way to interact w/ force touch trackpad

import SwiftUI
import AppKit

private struct Shockwave {
    static let duration: TimeInterval = 1.25

    let center: CGPoint
    let start: Date
}

private struct ShockwaveRing {
    let center: CGPoint
    let radius: CGFloat
    let amplitude: CGFloat

    func strength(atDistance distance: CGFloat) -> CGFloat {
        let distanceFromRing = abs(distance - radius)
        guard distanceFromRing < 40 else { return 0 }
        return cos(distanceFromRing / 40 * .pi / 2) * amplitude
    }
}

private final class RenderState {
    var currentLoc: CGPoint = CGPoint(x: 150, y: 50)
    var currentPres: CGFloat = 0
    var shockwaves: [Shockwave] = []
    var lastFrame: Date?
    var animationEnd = Date.distantPast
    private var cachedSize: CGSize?
    private var cachedGridPoints: [[CGPoint]] = []

    func gridPoints(for size: CGSize) -> [[CGPoint]] {
        guard cachedSize != size else {
            return cachedGridPoints
        }

        cachedSize = size
        let spacing: CGFloat = 14
        cachedGridPoints = stride(from: -spacing, through: size.height + spacing, by: spacing).map { y in
            stride(from: -spacing, through: size.width + spacing, by: spacing).map { x in
                CGPoint(x: x, y: y)
            }
        }
        return cachedGridPoints
    }
}

@available(macOS 12.0, *)
struct PressurePlayground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var appearance
    @State private var pressure: CGFloat = 0
    @State private var location: CGPoint?
    @State private var settleTask: Task<Void, Never>?
    @State private var renderState = RenderState()

    let onExit: () -> Void

    private var isAnimating: Bool { settleTask != nil }

    var body: some View {
        ZStack {
            PressureSensitiveArea(onPressureUpdate: updatePressure)

            grid
                .allowsHitTesting(false)

            ZStack {
                Button(action: onExit) {
                    PopoverIcon(symbol: "xmark", size: 24)
                }
                .buttonStyle(PopButtonStyle())
                .help(Text(LocalizedStringKey("close_playground")))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                
                // pressure meter
                Text(Double(pressure), format: .percent.precision(.fractionLength(0)).rounded(rule: .down))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(PopoverSurface(shape: Capsule()))
                    .opacity(pressure > 0 ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: pressure > 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: reduceMotion) { enabled in
            if enabled { stopAnimation() }
        }
        .onDisappear(perform: stopAnimation)
    }

    @ViewBuilder
    private var grid: some View {
        let lineColor = PopoverPalette(scheme: appearance).accent
        if !reduceMotion && (isAnimating || location == nil) {
            let frameInterval: TimeInterval? = isAnimating ? nil : 1.0 / 24
            TimelineView(.animation(minimumInterval: frameInterval)) { (timeline: TimelineViewDefaultContext) in
                Canvas { context, size in
                    drawGrid(in: context, size: size, at: timeline.date, animate: true, color: lineColor)
                }
            }
        } else {
            Canvas { context, size in
                drawGrid(in: context, size: size, at: Date(), animate: false, color: lineColor)
            }
        }
    }

    private func updatePressure(location: CGPoint?, pressure: CGFloat, didForceClick: Bool) {
        guard location != self.location || pressure != self.pressure || didForceClick else { return }
        self.location = location
        self.pressure = pressure

        guard !reduceMotion else { return }
        let now = Date()
        let showShockwave = didForceClick && SlabPadManager.shared.isHapticsEnabled == true
        if showShockwave, let location {
            renderState.shockwaves.append(Shockwave(center: location, start: now))
        }
        let duration = showShockwave ? Shockwave.duration : 0.8
        renderState.animationEnd = max(renderState.animationEnd, now.addingTimeInterval(duration))

        guard settleTask == nil else { return }
        renderState.lastFrame = now
        settleTask = Task { @MainActor in
            // Fresh input extends the deadline while this task sleeps.
            while !Task.isCancelled {
                let remaining = renderState.animationEnd.timeIntervalSinceNow
                guard remaining > 0 else {
                    settleTask = nil
                    return
                }
                let delay = min(remaining, Shockwave.duration)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    private func stopAnimation() {
        settleTask?.cancel()
        settleTask = nil
        renderState.lastFrame = nil
        renderState.animationEnd = .distantPast
        renderState.shockwaves.removeAll()
    }

    private func drawGrid(in context: GraphicsContext, size: CGSize, at date: Date, animate: Bool, color: Color) {
        let time = date.timeIntervalSinceReferenceDate
        let isFloating = animate && location == nil
        var target = location ?? CGPoint(x: size.width / 2, y: size.height / 2)
        if isFloating {
            target.x += cos(time * 0.7) * 50
            target.y += sin(time * 1.1) * 25
        }
        let targetPressure: CGFloat = isFloating ? 0.08 : pressure
        let elapsed = min(max(date.timeIntervalSince(renderState.lastFrame ?? date), 0), 0.1)
        renderState.lastFrame = animate ? date : nil

        let locationFactor = animate ? 1 - exp(-elapsed * (isFloating ? 4 : 12)) : 1
        let pressureFactor = animate ? 1 - exp(-elapsed * (isFloating ? 4 : 8)) : 1
        renderState.currentLoc.x += (target.x - renderState.currentLoc.x) * locationFactor
        renderState.currentLoc.y += (target.y - renderState.currentLoc.y) * locationFactor
        renderState.currentPres += (targetPressure - renderState.currentPres) * pressureFactor

        renderState.shockwaves.removeAll { date.timeIntervalSince($0.start) >= Shockwave.duration }
        let rings = renderState.shockwaves.map { wave in
            let progress = max(date.timeIntervalSince(wave.start), 0) / Shockwave.duration
            return ShockwaveRing(center: wave.center, radius: progress * 400, amplitude: 1 - progress)
        }

        let center = renderState.currentLoc
        let pressure = renderState.currentPres
        let radius = 60 + pressure * 60
        let falloff = 2 * radius * radius
        let strength = (8 + 40 * pressure) / 50
        let remaining = date.distance(to: renderState.animationEnd)
        let rippleAmplitude: CGFloat = isFloating ? 1 : CGFloat(min(max(remaining / 0.25, 0), 1))
        let ripplePhase = CGFloat(time * 2)

        let points = renderState.gridPoints(for: size).map { row in
            row.map { point in
                let dx = point.x - center.x
                let dy = point.y - center.y
                let distanceSquared = dx * dx + dy * dy
                let warp = exp(-distanceSquared / falloff)
                var x = point.x - dx * warp * strength
                var y = point.y - dy * warp * strength

                if animate && rippleAmplitude > 0 {
                    let distance = sqrt(distanceSquared)
                    let ripple = sin(distance * 0.04 - ripplePhase) * (1 + pressure * 2)
                    y += ripple * min(distance / 30, 1) * rippleAmplitude * warp
                }

                for ring in rings {
                    let ringDX = point.x - ring.center.x
                    let ringDY = point.y - ring.center.y
                    let distance = sqrt(ringDX * ringDX + ringDY * ringDY)
                    let displacement = ring.strength(atDistance: distance) * 20
                    guard distance > 0, displacement > 0 else { continue }
                    x += ringDX / distance * displacement
                    y += ringDY / distance * displacement
                }

                return CGPoint(x: x, y: y)
            }
        }

        for y in points.indices {
            for x in points[y].indices {
                let point = points[y][x]
                var path = Path()
                if x + 1 < points[y].count {
                    path.move(to: point)
                    path.addLine(to: points[y][x + 1])
                }
                if y + 1 < points.count {
                    path.move(to: point)
                    path.addLine(to: points[y + 1][x])
                }
                guard !path.isEmpty else { continue }

                let dx = point.x - center.x
                let dy = point.y - center.y
                let distanceSquared = dx * dx + dy * dy
                let intensity: CGFloat = exp(-distanceSquared / falloff)
                let highlight = rings.reduce(CGFloat.zero) { sum, ring in
                    let ringDX = point.x - ring.center.x
                    let ringDY = point.y - ring.center.y
                    return sum + ring.strength(atDistance: sqrt(ringDX * ringDX + ringDY * ringDY))
                }
                let alpha = 0.08 + intensity * 0.45 + highlight * 0.5
                let style = StrokeStyle(lineWidth: 0.3 + intensity * 1.7 + highlight * 2, lineCap: .round)
                context.stroke(path, with: .color(color.opacity(alpha)), style: style)
            }
        }
    }
}

private struct PressureSensitiveArea: NSViewRepresentable {
    var onPressureUpdate: (CGPoint?, CGFloat, Bool) -> Void

    func makeNSView(context: Context) -> PressureNSView {
        let view = PressureNSView()
        view.onPressureUpdate = onPressureUpdate
        return view
    }

    func updateNSView(_ nsView: PressureNSView, context: Context) {
        nsView.onPressureUpdate = onPressureUpdate
    }
}

private final class PressureNSView: NSView {
    override var isFlipped: Bool { true }
    
    var onPressureUpdate: ((CGPoint?, CGFloat, Bool) -> Void)?
    private var currentPressure: CGFloat = 0
    private var lastStage: Int = 0
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        
        let options: NSTrackingArea.Options = [
            .activeAlways,
            .mouseMoved,
            .mouseEnteredAndExited,
            .inVisibleRect
        ]
        
        let newArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(newArea)
        self.trackingArea = newArea
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        updateLocation(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        updateLocation(with: event)
    }
    
    override func mouseMoved(with event: NSEvent) {
        updateLocation(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        updateLocation(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        onPressureUpdate?(nil, 0, false)
    }

    override func mouseUp(with event: NSEvent) {
        currentPressure = 0
        lastStage = 0
        updateLocation(with: event)
    }

    override func pressureChange(with event: NSEvent) {
        let stage = event.stage
        let stagePressure = CGFloat(event.pressure)
        let didJustForceClick = stage == 2 && lastStage < 2
        lastStage = stage
        
        if stage == 1 {
            currentPressure = stagePressure * 0.5
        } else if stage == 2 {
            currentPressure = 0.5 + (stagePressure * 0.5)
        } else {
            currentPressure = 0
        }
        
        updateLocation(with: event, didForceClick: didJustForceClick)
    }

    private func updateLocation(with event: NSEvent, didForceClick: Bool = false) {
        let location = convert(event.locationInWindow, from: nil)
        
        if bounds.contains(location) {
            onPressureUpdate?(location, currentPressure, didForceClick)
        } else {
            onPressureUpdate?(nil, 0, false)
        }
    }
}
