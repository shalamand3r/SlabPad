// ContentView.swift
// main ui for the menubar popover

import SwiftUI

struct ContentView: View {
    @ObservedObject private var manager = SlabPadManager.shared
    @State private var titleScale: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            mainInterface
        }
        .padding(.bottom, 20)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.willShowNotification)) { _ in
            triggerClickAnimation()
        }
        .onAppear {
            triggerClickAnimation()
        }
    }

    private var headerSection: some View {
        HStack {
            Text("SlabPad")
                .font(.system(.title3, design: .rounded))
                .fontWeight(.bold)
                .scaleEffect(titleScale)
            Spacer()
            Text(versionLabel)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .opacity(0.4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 10)
    }

    private var mainInterface: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Options", systemImage: "gearshape.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.secondary)
                
                Divider().opacity(0.2)

                Toggle("Launch at Login", isOn: Binding(
                    get: { manager.launchAtLogin },
                    set: { manager.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.checkbox)
                
                Toggle("Disable Haptics on Launch", isOn: $manager.disableOnLaunch)
                    .toggleStyle(.checkbox)
                
                Toggle("Re-enable Haptics on Quit", isOn: $manager.reEnableOnQuit)
                    .toggleStyle(.checkbox)

                Toggle("Invert Menu Bar Clicks", isOn: $manager.invertClicks)
                    .toggleStyle(.checkbox)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(15)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.1), lineWidth: 1))
            .padding(.horizontal, 20)
            
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    manager.toggleHapticsEnabled()
                }
            }) {
                HStack {
                    Image(systemName: "power")
                    Text(manager.isHapticsEnabled ? "DISABLE HAPTICS" : "ENABLE HAPTICS")
                }
                .font(.headline).frame(maxWidth: .infinity).frame(height: 44)
                .background(manager.isHapticsEnabled ? Color.red.gradient : Color.blue.gradient)
                .foregroundColor(.white).cornerRadius(12)
            }
            .buttonStyle(HapticButtonStyle())
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            HStack {
                HStack(spacing: 4) {
                    // sync icon with menubar state
                    Text(manager.invertClicks ? "Left-click" : "Right-click")
                    Image(systemName: SlabPadIcons.menuBarSymbolName(hapticsEnabled: manager.isHapticsEnabled))
                    Text("to instantly toggle haptics")
                }
                
                Text("•")
                
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .underline()
            }
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
    }

    private var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version.map { "v\($0)" } ?? ""
    }

    private func triggerClickAnimation() {
        // scale bounce animation
        titleScale = 1.0
        withAnimation(.spring(response: 0.1, dampingFraction: 0.5)) {
            titleScale = 0.92
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) {
                titleScale = 1.0
            }
        }
    }
}

struct HapticButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.interactiveSpring(), value: configuration.isPressed)
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
