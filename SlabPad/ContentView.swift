// ContentView.swift
// main ui for the menubar popover

import SwiftUI
import Combine
import Foundation

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
    @State private var showReleaseNotes = false
    @State private var showPressurePlayground = false
    @State private var releaseNotesOpenedByHover = false
    @State private var hoverRestoreShowSettings = false
    @State private var hoverRestoreShowReleaseNotes = false
    @State private var isHoveringUpdateBadge = false
    @State private var updatePulse = false
    
    init(initialShowSettings: Bool = false, initialShowReleaseNotes: Bool = false) {
        _showSettings = State(initialValue: initialShowSettings)
        _showReleaseNotes = State(initialValue: initialShowReleaseNotes)
    }
    
    private enum Panel: Hashable {
        case mainButton
        case settings
        case releaseNotes
        case pressurePlayground
    }
    
    private var activePanel: Panel {
        if showPressurePlayground { return .pressurePlayground }
        if showReleaseNotes { return .releaseNotes }
        if showSettings { return .settings }
        return .mainButton
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { manager.launchAtLogin },
            set: { manager.setLaunchAtLogin($0) }
        )
    }

    private var launchAtLoginTitle: String {
        if manager.supportsLaunchAtLogin {
            return "Launch at Login"
        }

        return "Launch at Login (macOS 13+)"
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
        .onChange(of: showReleaseNotes) { _ in
            NotificationCenter.default.post(name: .slabPadPopoverNeedsResize, object: nil)
        }
        .onChange(of: showPressurePlayground) { _ in
            NotificationCenter.default.post(name: .slabPadPopoverNeedsResize, object: nil)
        }
    }

    private var headerSection: some View {
        HStack(spacing: 6) {
            Button(action: {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                    showPressurePlayground.toggle()
                }
            }) {
                Text("SlabPad")
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }
            .buttonStyle(PopButtonStyle())
            
            Button(action: {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                    showReleaseNotes.toggle()
                    if showReleaseNotes {
                        showSettings = false
                        showPressurePlayground = false
                    }
                }
                releaseNotesOpenedByHover = false
                manager.checkForUpdate()
                manager.fetchCurrentReleaseNotes()
            }) {
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
            }
            .buttonStyle(PopButtonStyle())
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
                .help("Click to download the latest version!")
                .buttonStyle(PopButtonStyle())
                .onHover { hovering in
                    isHoveringUpdateBadge = hovering
                    if hovering, manager.hasUpdateAvailable {
                        if !showReleaseNotes {
                            hoverRestoreShowSettings = showSettings
                            hoverRestoreShowReleaseNotes = showReleaseNotes
                            releaseNotesOpenedByHover = true
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                                showReleaseNotes = true
                                showSettings = false
                            }
                        }
                    } else if !hovering, releaseNotesOpenedByHover {
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                            showSettings = hoverRestoreShowSettings
                            showReleaseNotes = hoverRestoreShowReleaseNotes
                        }
                        releaseNotesOpenedByHover = false
                    }
                }
            }
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showSettings.toggle()
                    if showSettings {
                        showReleaseNotes = false
                        showPressurePlayground = false
                    }
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
                    .opacity(activePanel == .settings ? 1 : 0)
                    .scaleEffect(activePanel == .settings ? 1.0 : 0.9)
                    .rotation3DEffect(
                        .degrees(activePanel == .settings ? 0 : -90),
                        axis: (x: 1, y: 0, z: 0),
                        anchor: .center,
                        perspective: 0.15
                    )
                    .allowsHitTesting(activePanel == .settings)

                mainButtonSection
                .opacity(activePanel == .mainButton ? 1 : 0)
                .scaleEffect(activePanel == .mainButton ? 1.0 : 0.9)
                .rotation3DEffect(
                    .degrees(activePanel == .mainButton ? 0 : 90),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: .center,
                    perspective: 0.15
                )
                .allowsHitTesting(activePanel == .mainButton)
                
                releaseNotesSection
                    .opacity(activePanel == .releaseNotes ? 1 : 0)
                    .scaleEffect(activePanel == .releaseNotes ? 1.0 : 0.9)
                    .rotation3DEffect(
                        .degrees(activePanel == .releaseNotes ? 0 : 90),
                        axis: (x: 1, y: 0, z: 0),
                        anchor: .center,
                        perspective: 0.15
                    )
                    .allowsHitTesting(activePanel == .releaseNotes)

                pressurePlaygroundSection
                    .opacity(activePanel == .pressurePlayground ? 1 : 0)
                    .scaleEffect(activePanel == .pressurePlayground ? 1.0 : 0.9)
                    .rotation3DEffect(
                        .degrees(activePanel == .pressurePlayground ? 0 : 90),
                        axis: (x: 1, y: 0, z: 0),
                        anchor: .center,
                        perspective: 0.15
                    )
                    .allowsHitTesting(activePanel == .pressurePlayground)
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
        .animation(.spring(response: 0.55, dampingFraction: 0.82), value: activePanel)
    }
    
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsRow(
                title: launchAtLoginTitle,
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

    private var pressurePlaygroundSection: some View {
        VStack(spacing: 0) {
            if #available(macOS 12.0, *) {
                PressurePlayground(onExit: {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                        showPressurePlayground = false
                    }
                })
            } else {
                Spacer()
                Text("Pressure Playground requires macOS 12.0+")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.1), lineWidth: 1))
        .padding(.horizontal, 20)
        .layoutPriority(1)
    }

    private var releaseNotesSection: some View {
        let shouldShowLatest = manager.hasUpdateAvailable && isHoveringUpdateBadge
        
        let currentNotes = normalizeNewlines(manager.currentReleaseNotesMarkdown)
        let latestNotes = normalizeNewlines(manager.latestReleaseNotesMarkdown)
        let currentChangelog = extractChangelogMarkdown(from: currentNotes) ?? currentNotes
        let latestChangelog = extractChangelogMarkdown(from: latestNotes) ?? latestNotes
        
        let titleCurrent = "Release Notes"
        let titleLatest = "Changelog"

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    Text(titleCurrent)
                        .opacity(shouldShowLatest ? 0 : 1)
                    Text(titleLatest)
                        .opacity(shouldShowLatest ? 1 : 0)
                }
                .animation(.easeInOut(duration: 0.18), value: shouldShowLatest)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.secondary)
                Spacer(minLength: 8)

                if let url = manager.latestReleaseURL, !shouldShowLatest {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "safari")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .buttonStyle(PopButtonStyle())
                    .help("Open on GitHub")
                }

                Button {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                        showReleaseNotes = false
                    }
                    releaseNotesOpenedByHover = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.7))
                        .frame(width: 22, height: 22)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(6)
                }
                .buttonStyle(PopButtonStyle())
                .help("Close")
            }

            Divider().opacity(0.2)

            ZStack {
                ScrollView {
                    ChangelogBulletsView(markdown: currentChangelog)
                        .padding(.top, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .opacity(shouldShowLatest ? 0 : 1)
                
                ScrollView {
                    ChangelogBulletsView(markdown: latestChangelog)
                        .padding(.top, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .opacity(shouldShowLatest ? 1 : 0)
            }
            .animation(.easeInOut(duration: 0.18), value: shouldShowLatest)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.1), lineWidth: 1))
        .padding(.horizontal, 20)
    }

    private func versionPillText(for tag: String?) -> String {
        let raw = (tag ?? "?").trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return "v?" }
        return raw.hasPrefix("v") ? raw : "v\(raw)"
    }

    private func extractChangelogMarkdown(from markdown: String?) -> String? {
        guard let markdown else { return nil }
        let lines = markdown.components(separatedBy: .newlines)
        let headerRegex = try? NSRegularExpression(pattern: "^\\s*#{2,6}\\s*changelog\\s*:?(\\s*)$", options: [.caseInsensitive])
        guard let headerRegex else { return nil }

        var startIndex: Int?
        for (index, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if headerRegex.firstMatch(in: line, options: [], range: range) != nil {
                startIndex = index + 1
                break
            }
        }

        guard let startIndex, startIndex < lines.count else { return nil }
        let extracted = lines[startIndex...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return extracted.isEmpty ? nil : extracted
    }

    private func normalizeNewlines(_ value: String?) -> String? {
        guard let value else { return nil }
        return value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
    
    private var mainButtonSection: some View {
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

private struct ReleaseNotesMarkdownView: View {
    let markdown: String?
    
    var body: some View {
        Group {
            if let markdown, !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if #available(macOS 12.0, *) {
                    if let attributed = try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .full)) {
                        Text(attributed)
                            .textSelection(.enabled)
                    } else {
                        Text(markdown)
                            .textSelection(.enabled)
                    }
                } else {
                    Text(markdown)
                }
            } else {
                Text("Loading...")
                    .foregroundColor(.secondary)
            }
        }
        .font(.system(size: 11))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChangelogBulletsView: View {
    let markdown: String?
    
    private var bulletLines: [String] {
        guard let markdown else { return [] }
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        
        let lines = normalized.components(separatedBy: "\n")
        let bullets = lines.compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("- ") { return String(trimmed.dropFirst(2)) }
            if trimmed.hasPrefix("* ") { return String(trimmed.dropFirst(2)) }
            if trimmed.hasPrefix("• ") { return String(trimmed.dropFirst(2)) }
            return nil
        }
        return bullets
    }
    
    var body: some View {
        if bulletLines.isEmpty {
            ReleaseNotesMarkdownView(markdown: markdown)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(bulletLines, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.top, 1)
                        Group {
                            if #available(macOS 12.0, *) {
                                if let attributed = try? AttributedString(markdown: bullet, options: .init(interpretedSyntax: .full)) {
                                    Text(attributed)
                                } else {
                                    Text(bullet)
                                }
                            } else {
                                Text(bullet)
                            }
                        }
                        .font(.system(size: 11))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
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
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
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
