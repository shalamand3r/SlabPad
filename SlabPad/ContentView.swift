// ContentView.swift
// main ui for the menubar popover

import SwiftUI
import Combine

private extension Color {
    static var slabPadAccent: Color {
        if #available(macOS 12.0, *) {
            return Color(nsColor: NSColor.controlAccentColor)
        }
        return Color.accentColor
    }
}

struct ContentView: View {
    @ObservedObject private var manager = SlabPadManager.shared
    @State private var showSettings = false
    @State private var isHoveringUpdateBadge = false
    @State private var updatePulse = false
    
    init(initialShowSettings: Bool = false) {
        _showSettings = State(initialValue: initialShowSettings)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { manager.launchAtLogin },
            set: { manager.setLaunchAtLogin($0) }
        )
    }
    
    private var appVersionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "v" + (short ?? "?")
    }
    
    private var latestVersionText: String {
        guard let latestTag = manager.latestReleaseTag else { return appVersionText }
        return "v\(latestTag)"
    }
    
    private var titleVersionText: String {
        guard manager.hasUpdateAvailable, isHoveringUpdateBadge else { return appVersionText }
        return "\(appVersionText) → \(latestVersionText)"
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            mainInterface
        }
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, 20)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .onChange(of: showSettings) { _ in
            NotificationCenter.default.post(name: .slabPadPopoverNeedsResize, object: nil)
        }
    }

    private var headerSection: some View {
        HStack(spacing: 6) {
            Text("SlabPad")
                .font(.system(.title3, design: .rounded))
                .fontWeight(.bold)
            Text(titleVersionText)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                        .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
                )
                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
            Spacer(minLength: 8)
            if manager.hasUpdateAvailable, let updateURL = manager.latestReleaseURL {
                Button {
                    NSWorkspace.shared.open(updateURL)
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.green)
                        .opacity(updatePulse ? 0.55 : 1.0)
                }
                .help("New version available!")
                .buttonStyle(PopButtonStyle())
                .onHover { hovering in
                    isHoveringUpdateBadge = hovering
                }
            }
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showSettings.toggle()
                }
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(showSettings ? .slabPadAccent : .secondary.opacity(0.6))
                    .frame(width: 28, height: 28)
                    .background(showSettings ? Color.slabPadAccent.opacity(0.15) : Color.clear)
                    .cornerRadius(8)
            }
            .buttonStyle(PopButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 10)
        .layoutPriority(1)
        .onChange(of: manager.hasUpdateAvailable) { hasUpdateAvailable in
            if hasUpdateAvailable {
                updatePulse = true
            } else {
                updatePulse = false
            }
        }
        .onAppear {
            updatePulse = manager.hasUpdateAvailable
        }
        .modifier(UpdatePulseDriver(hasUpdateAvailable: manager.hasUpdateAvailable, updatePulse: $updatePulse))
    }

    private var mainInterface: some View {
        VStack(spacing: 0) {
            ZStack {
                settingsSection
                    .opacity(showSettings ? 1 : 0)
                    .scaleEffect(showSettings ? 1.0 : 0.9)
                    .rotation3DEffect(
                        .degrees(showSettings ? 0 : -90),
                        axis: (x: 1, y: 0, z: 0),
                        anchor: .center,
                        perspective: 0.15
                    )
                    .allowsHitTesting(showSettings)

                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        manager.toggleHapticsEnabled()
                    }
                }) {
                    ZStack {
                        buttonBackground(isEnabled: manager.isHapticsEnabled)
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                        
                        HStack {
                            Image(systemName: "power")
                            Text(manager.isHapticsEnabled ? "DISABLE HAPTICS" : "ENABLE HAPTICS")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .modifier(FloatingPerspectiveModifier())
                }
                .buttonStyle(HapticButtonStyle())
                .padding(.horizontal, 20)
                .opacity(showSettings ? 0 : 1)
                .scaleEffect(showSettings ? 0.9 : 1.0)
                .rotation3DEffect(
                    .degrees(showSettings ? 90 : 0),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: .center,
                    perspective: 0.15
                )
                .allowsHitTesting(!showSettings)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)

            HStack {
                HStack(spacing: 4) {
                    // sync icon with menubar state
                    Text(manager.invertClicks ? "Left-click" : "Right-click")
                    Image(systemName: SlabPadIcons.menuBarSymbolName(hapticsEnabled: manager.isHapticsEnabled))
                    Text("to instantly toggle haptics")
                }
                
                Text("•")
                
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Text("Quit")
                        .underline()
                }
                .buttonStyle(PopButtonStyle())
            }
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 14)
        }
        .clipped()
        .animation(.spring(response: 0.55, dampingFraction: 0.82), value: showSettings)
    }
    
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsRow(
                title: "Launch at Login",
                isOn: manager.supportsLaunchAtLogin ? launchAtLoginBinding : .constant(false),
                isDisabled: !manager.supportsLaunchAtLogin
            )

            Divider().opacity(0.2)

            SettingsRow(
                title: "Disable Haptics on Launch",
                isOn: $manager.disableOnLaunch
            )

            Divider().opacity(0.2)

            SettingsRow(
                title: "Re-enable Haptics on Quit",
                isOn: $manager.reEnableOnQuit
            )

            Divider().opacity(0.2)

            SettingsRow(
                title: "Invert Menu Bar Clicks",
                isOn: $manager.invertClicks
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.1), lineWidth: 1))
        .padding(.horizontal, 20)
        .layoutPriority(1)
    }
    
    @ViewBuilder
    private func buttonBackground(isEnabled: Bool) -> some View {
        if #available(macOS 13.0, *) {
            RoundedRectangle(cornerRadius: 12)
                .fill(isEnabled ? Color.red.gradient : Color.slabPadAccent.gradient)
        } else {
            let base = isEnabled ? Color.red : Color.slabPadAccent
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [base.opacity(0.9), base],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
}

private struct HapticToggleButtonBackground: ViewModifier {
    let isEnabled: Bool
    
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content.background(isEnabled ? Color.red.gradient : Color.slabPadAccent.gradient)
        } else {
            let base = isEnabled ? Color.red : Color.slabPadAccent
            content.background(
                LinearGradient(
                    colors: [base.opacity(0.9), base],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}

struct HapticButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

struct PopButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

	private struct SettingsRow: View {
	    let title: String
	    @Binding var isOn: Bool
	    var isDisabled: Bool = false

	    var body: some View {
	        HStack(alignment: .center) {
	            Text(title).font(.system(size: 13, weight: .semibold))
	            Spacer(minLength: 12)
	            Toggle("", isOn: $isOn).toggleStyle(.switch).labelsHidden()
	        }
	        .disabled(isDisabled)
        .opacity(isDisabled ? 0.6 : 1.0)
    }
}

private struct UpdatePulseDriver: ViewModifier {
    let hasUpdateAvailable: Bool
    @Binding var updatePulse: Bool
    
    func body(content: Content) -> some View {
        if #available(macOS 12.0, *) {
            content.task(id: hasUpdateAvailable) {
                guard hasUpdateAvailable else {
                    updatePulse = false
                    return
                }

                while !Task.isCancelled && hasUpdateAvailable {
                    try? await Task.sleep(nanoseconds: 1_450_000_000)
                    guard hasUpdateAvailable, !Task.isCancelled else { break }
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 1.1)) {
                            updatePulse.toggle()
                        }
                    }
                }
            }
        } else {
            content.onReceive(
                Timer.publish(every: 1.45, on: .main, in: .common).autoconnect()
            ) { _ in
                guard hasUpdateAvailable else {
                    if updatePulse { updatePulse = false }
                    return
                }
                
                withAnimation(.easeInOut(duration: 1.1)) {
                    updatePulse.toggle()
                }
            }
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

#if DEBUG
private struct SlabPadPreviewHost: View {
    let showSettings: Bool
    let showUpdate: Bool
    
    var body: some View {
        ContentView(initialShowSettings: showSettings)
            .onAppear {
                if showUpdate {
                    let manager = SlabPadManager.shared
                    manager.latestReleaseTag = "999.0"
                    manager.latestReleaseURL = URL(string: "https://github.com/shalamand3r/SlabPad/releases")
                    manager.hasUpdateAvailable = true
                }
            }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SlabPadPreviewHost(showSettings: true, showUpdate: false)
                .previewDisplayName("Settings")
            
            SlabPadPreviewHost(showSettings: false, showUpdate: true)
                .previewDisplayName("Big Button + Update")
        }
    }
}
#endif

private struct FloatingPerspectiveModifier: ViewModifier {
    @State private var rotation: (x: Double, y: Double) = (0, 0)
    @State private var shineOffset: CGPoint = .zero
    @State private var shineOpacity: Double = 0
    
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content
                .overlay(
                    GeometryReader { geo in
                        // shiny
                        LinearGradient(
                            colors: [
                                .white.opacity(0),
                                .white.opacity(shineOpacity),
                                .white.opacity(0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .scaleEffect(2.5)
                        .offset(x: shineOffset.x, y: shineOffset.y)
                        .blendMode(.screen)
                        .allowsHitTesting(false)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                )
                .rotation3DEffect(
                    .degrees(rotation.x),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: .center,
                    perspective: 0.2
                )
                .rotation3DEffect(
                    .degrees(rotation.y),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: .center,
                    perspective: 0.2
                )
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let x = (location.x / 260) - 0.5
                        let y = (location.y / 160) - 0.5
                        
                        withAnimation(.interactiveSpring()) {
                            rotation = (x: Double(y * -10), y: Double(x * 10))
                            // move shine in response to cursor :D
                            shineOffset = CGPoint(x: x * 150, y: y * 150)
                            shineOpacity = 0.14
                        }
                    case .ended:
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                            rotation = (0, 0)
                            shineOffset = .zero
                            shineOpacity = 0
                        }
                    }
                }
        } else {
            content
        }
    }
}

private struct ParallaxEffect: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}
