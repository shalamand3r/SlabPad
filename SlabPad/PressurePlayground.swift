// PressurePlayground.swift
// cool way to interact w/ force touch trackpad

import SwiftUI
import AppKit

private struct Shockwave {
    var progress: CGFloat
    var center: CGPoint
}

private final class RenderState {
    var currentLoc: CGPoint = CGPoint(x: 150, y: 50)
    var currentPres: CGFloat = 0
    var shockwaves: [Shockwave] = []
    var lastTime: TimeInterval = 0
}

@available(macOS 12.0, *)
struct PressurePlayground: View {
    @ObservedObject private var manager = SlabPadManager.shared
    @State private var pressure: CGFloat = 0
    @State private var location: CGPoint = CGPoint(x: 150, y: 50)
    @State private var isHovering: Bool = false
    @State private var renderState = RenderState()
    
    let onExit: () -> Void

    var body: some View {
        ZStack {
            PressureSensitiveArea { loc, pres, didForceClick in
                if let loc = loc {
                    self.location = loc
                    self.isHovering = true
                } else {
                    self.isHovering = false
                }
                
                if didForceClick && manager.isHapticsEnabled {
                    renderState.shockwaves.append(Shockwave(progress: 0.0, center: renderState.currentLoc))
                }
                
                self.pressure = pres
            }

            TimelineView(.animation) { (timeline: TimelineViewDefaultContext) in
                Canvas { context, size in
                    let now = timeline.date.timeIntervalSinceReferenceDate
                    let dt = renderState.lastTime == 0 ? 0 : now - renderState.lastTime
                    renderState.lastTime = now

                    func smoothFactor(_ speed: CGFloat) -> CGFloat {
                        CGFloat(1.0 - exp(-dt * Double(speed)))
                    }
                    
                    var targetLoc = location
                    var targetPres = pressure
                    
                    if !isHovering {
                        // idle sway
                        let swayX = size.width / 2 + CGFloat(cos(now * 0.7)) * 50
                        let swayY = size.height / 2 + CGFloat(sin(now * 1.1)) * 25
                        targetLoc = CGPoint(x: swayX, y: swayY)
                        targetPres = 0.08
                    }
                    
                    // smooth crawl interpolation
                    let lerpSpeed: CGFloat = isHovering ? 12.0 : 4.0
                    let presLerpSpeed: CGFloat = isHovering ? 8.0 : 4.0
                    let lerpFactor = smoothFactor(lerpSpeed)
                    let presLerpFactor = smoothFactor(presLerpSpeed)
                    
                    renderState.currentLoc.x += (targetLoc.x - renderState.currentLoc.x) * lerpFactor
                    renderState.currentLoc.y += (targetLoc.y - renderState.currentLoc.y) * lerpFactor
                    renderState.currentPres += (targetPres - renderState.currentPres) * presLerpFactor
                    
                    let shockwaveProgressSpeed: CGFloat = 0.8
                    for i in 0..<renderState.shockwaves.count {
                        renderState.shockwaves[i].progress += CGFloat(dt) * shockwaveProgressSpeed
                    }
                    renderState.shockwaves.removeAll { $0.progress >= 1.0 }
                    
                    let drawLoc = renderState.currentLoc
                    let drawPres = renderState.currentPres
                    let gridSpacing: CGFloat = 14
                    let t = now

                    let shockwaveRadiusScale: CGFloat = 400.0
                    let ringWidth: CGFloat = 40.0
                    let rippleSpeed = 2.0
                    
                    let baseStrength: CGFloat = 8
                    let maxStrength: CGFloat = baseStrength + (40 * drawPres)
                    let influenceRadius: CGFloat = 60 + (drawPres * 60)
                    
                    var gridPoints: [[CGPoint]] = []
                    
                    for y in stride(from: -gridSpacing, through: size.height + gridSpacing, by: gridSpacing) {
                        var row: [CGPoint] = []
                        for x in stride(from: -gridSpacing, through: size.width + gridSpacing, by: gridSpacing) {
                            let originalPoint = CGPoint(x: x, y: y)
                            let dx = originalPoint.x - drawLoc.x
                            let dy = originalPoint.y - drawLoc.y
                            let dist = sqrt(dx*dx + dy*dy)
                            
                            let rippleBase = CGFloat(sin(Double(dist) * 0.04 - t * Double(rippleSpeed))) * (1.0 + drawPres * 2.0)

                            let rippleStabilityFactor = min(dist / 30.0, 1.0)
                            let ripple = rippleBase * rippleStabilityFactor

                            let warp = CGFloat(exp(-Double(dist * dist) / Double(2.0 * influenceRadius * influenceRadius)))

                            var displacedX = x - (dx * warp * maxStrength / 50.0)
                            var displacedY = y - (dy * warp * maxStrength / 50.0)
                            
                            for shockwave in renderState.shockwaves {
                                let swDx = originalPoint.x - shockwave.center.x
                                let swDy = originalPoint.y - shockwave.center.y
                                let swDist = sqrt(swDx*swDx + swDy*swDy)
                                
                                let shockwaveRadius = shockwave.progress * shockwaveRadiusScale
                                let shockwaveIntensity = 1.0 - shockwave.progress
                                
                                let distFromRing = abs(swDist - shockwaveRadius)
                                if distFromRing < ringWidth {
                                    let swWarp = CGFloat(cos((distFromRing / ringWidth) * .pi / 2)) * shockwaveIntensity * 20.0
                                    let angle = atan2(swDy, swDx)
                                    displacedX += cos(angle) * swWarp
                                    displacedY += sin(angle) * swWarp
                                }
                            }

                            row.append(CGPoint(x: displacedX, y: displacedY + ripple * warp))
                        }
                        gridPoints.append(row)
                    }
                    
                    for yIndex in 0..<gridPoints.count {
                        for xIndex in 0..<gridPoints[yIndex].count {
                            let p = gridPoints[yIndex][xIndex]
                            
                            func drawLine(to nextP: CGPoint) {
                                var path = Path()
                                path.move(to: p)
                                path.addLine(to: nextP)
                                
                                let dist = sqrt(pow(p.x - drawLoc.x, 2) + pow(p.y - drawLoc.y, 2))
                                let intensity = CGFloat(exp(-Double(dist * dist) / Double(2.0 * influenceRadius * influenceRadius)))
                                
                                var swHighlight: CGFloat = 0
                                for shockwave in renderState.shockwaves {
                                    let swDx = p.x - shockwave.center.x
                                    let swDy = p.y - shockwave.center.y
                                    let swDist = sqrt(swDx*swDx + swDy*swDy)
                                    
                                    let shockwaveRadius = shockwave.progress * shockwaveRadiusScale
                                    let shockwaveIntensity = 1.0 - shockwave.progress
                                    
                                    let distFromRing = abs(swDist - shockwaveRadius)
                                    if distFromRing < ringWidth {
                                        swHighlight += CGFloat(cos((distFromRing / ringWidth) * .pi / 2)) * shockwaveIntensity
                                    }
                                }
                                
                                let style = StrokeStyle(lineWidth: 0.3 + intensity * 1.7 + swHighlight * 2.0, lineCap: .round, lineJoin: .round)
                                let alpha = (0.08 + intensity * 0.45) + swHighlight * 0.5
                                let color = Color(nsColor: .controlAccentColor)

                                context.stroke(path, with: .color(color.opacity(alpha)), style: style)
                            }
                            
                            if xIndex < gridPoints[yIndex].count - 1 {
                                drawLine(to: gridPoints[yIndex][xIndex + 1])
                            }
                            
                            if yIndex < gridPoints.count - 1 {
                                drawLine(to: gridPoints[yIndex + 1][xIndex])
                            }
                        }
                    }
                }
            }
            .allowsHitTesting(false)
            .drawingGroup()

            ZStack {
                Button(action: onExit) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.7))
                        .frame(width: 22, height: 22)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(6)
                }
                .buttonStyle(PopButtonStyle())
                .help(Text(LocalizedStringKey("close_playground")))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                
                // pressure meter
                Text("\(Int(pressure * 100))%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.05))
                            .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
                    )
                    .opacity(pressure > 0 ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: pressure > 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PressureSensitiveArea: NSViewRepresentable {
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

class PressureNSView: NSView {
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
        var didJustForceClick = false
        
        if stage == 2 && lastStage < 2 {
            didJustForceClick = true
        }
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
