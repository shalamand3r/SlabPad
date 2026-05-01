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
    @State private var isHoveringUpdateBadge = false
    @State private var updateHoverFlipWorkItem: DispatchWorkItem?
    @State private var updatePressed = false
    @State private var quitPressed = false
    @State private var isHoveringBottomHint = false
    @State private var hintFlashIsArrow = false
    @AppStorage("showBottomHint") private var showBottomHint = true
    @State private var resetHoldTriggered = false
    @State private var isPowerPressActive = false
    @State private var powerHoldStartWorkItem: DispatchWorkItem?
    @State private var powerHoldCompleteWorkItem: DispatchWorkItem?
    @State private var powerHoldProgress: CGFloat = 0
    @State private var powerHoldDidStartProgress = false
    @State private var ignoreNextPowerTap = false
    
    private let spring = Animation.spring(response: 0.5, dampingFraction: 0.82)

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

    private var launchAtLoginTitle: LocalizedStringKey {
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
    
    private var shouldShowLatestInVersionPill: Bool {
        manager.hasUpdateAvailable && (isHoveringUpdateBadge || showReleaseNotes)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            mainInterface
        }
        .frame(width: 288)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, 14)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .onChange(of: showSettings) { _ in requestPopoverResize() }
        .onChange(of: showReleaseNotes) { _ in requestPopoverResize() }
        .onChange(of: showPressurePlayground) { _ in requestPopoverResize() }
    }

    private var headerSection: some View {
        HStack(spacing: 6) {
            Button(action: {
                withAnimation(spring) {
                    showPressurePlayground.toggle()
                }
            }) {
                Text("SlabPad")
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(PopButtonStyle())
            
            Button(action: {
                if manager.hasUpdateAvailable {
                    withAnimation(spring) {
                        showReleaseNotes.toggle()
                        if showReleaseNotes {
                            showSettings = false
                            showPressurePlayground = false
                        }
                    }
                } else {
                    manager.checkForUpdate()
                }
            }) {
                VersionPillLabel(
                    current: appVersionText,
                    latest: latestVersionText,
                    showLatest: shouldShowLatestInVersionPill
                )
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .layoutPriority(1)
                .foregroundColor(showReleaseNotes ? .slabPadAccent : .secondary.opacity(0.6))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(showReleaseNotes ? Color.slabPadAccent.opacity(0.15) : Color.primary.opacity(0.06))
                        .overlay(Capsule().stroke(showReleaseNotes ? Color.slabPadAccent.opacity(0.2) : Color.primary.opacity(0.1), lineWidth: 0.5))
                )
                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                .animation(.easeInOut(duration: 0.18), value: shouldShowLatestInVersionPill)
            }
            .buttonStyle(PopButtonStyle())
            Spacer(minLength: 8)
            if manager.hasUpdateAvailable, let downloadURL = manager.latestDownloadZipURL {
                Button {
                    updatePressed = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                        NotificationCenter.default.post(name: .slabPadRequestOpenUpdate, object: downloadURL)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        updatePressed = false
                    }
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.green)
                        .frame(width: 28, height: 28)
                        .background(updatePressed ? Color.green.opacity(0.18) : Color.clear)
                        .cornerRadius(8)
                }
                .help(Text("Click to download the latest version!"))
                .buttonStyle(PopButtonStyle())
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isHoveringUpdateBadge = hovering
                    }

                    updateHoverFlipWorkItem?.cancel()
                    updateHoverFlipWorkItem = nil

                    guard hovering, manager.hasUpdateAvailable else { return }

                    let workItem = DispatchWorkItem {
                        guard isHoveringUpdateBadge, manager.hasUpdateAvailable else { return }

                        withAnimation(spring) {
                            showReleaseNotes = true
                            showSettings = false
                            showPressurePlayground = false
                        }
                    }
                    updateHoverFlipWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
                }
            }
            Button(action: {
                withAnimation(spring) {
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

            Button(action: {
                if resetHoldTriggered { return }
                if ignoreNextPowerTap {
                    ignoreNextPowerTap = false
                    return
                }
                
                withAnimation(spring) {
                    quitPressed = true
                    showSettings = false
                    showReleaseNotes = false
                    showPressurePlayground = false
                }
                
                // let the red "pressed" state render before we start closing/quitting
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    NotificationCenter.default.post(name: .slabPadRequestQuit, object: nil)
                }
            }) {
                Image(systemName: "power")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(quitPressed ? .red : .secondary.opacity(0.6))
                    .frame(width: 28, height: 28)
                    .background(quitPressed ? Color.red.opacity(0.15) : Color.clear)
                    .cornerRadius(8)
                    .overlay(powerHoldRing)
            }
            .help(Text("Quit"))
            .buttonStyle(PopButtonStyle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPowerPressActive {
                            beginPowerHold()
                        }
                    }
                    .onEnded { _ in
                        endPowerHold()
                    }
            )
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .layoutPriority(1)
        .onChange(of: manager.hasUpdateAvailable) { hasUpdateAvailable in
            if !hasUpdateAvailable { updatePressed = false }
        }
    }

    private var powerHoldRing: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 2)

            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .trim(from: 0, to: powerHoldProgress)
                .stroke(
                    Color.red.opacity(0.95),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .padding(-3)
        .opacity(powerHoldDidStartProgress ? 1.0 : 0.0)
        .allowsHitTesting(false)
    }

    private func beginPowerHold() {
        isPowerPressActive = true
        powerHoldDidStartProgress = false

        cancelPowerHoldWorkItems()
        powerHoldProgress = 0

        let startWork = DispatchWorkItem {
            guard isPowerPressActive, !resetHoldTriggered else { return }
            powerHoldDidStartProgress = true

            if !quitPressed {
                withAnimation(spring) {
                    quitPressed = true
                }
            }

            withAnimation(.linear(duration: 2.0)) {
                powerHoldProgress = 1
            }

            let completeWork = DispatchWorkItem {
                guard isPowerPressActive, !resetHoldTriggered else { return }
                resetHoldTriggered = true
                NotificationCenter.default.post(name: .slabPadRequestResetAndQuit, object: nil)
            }

            powerHoldCompleteWorkItem = completeWork
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: completeWork)
        }

        powerHoldStartWorkItem = startWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: startWork)
    }

    private func endPowerHold() {
        isPowerPressActive = false

        cancelPowerHoldWorkItems()
        if powerHoldDidStartProgress && !resetHoldTriggered {
            ignoreNextPowerTap = true
            DispatchQueue.main.async {
                ignoreNextPowerTap = false
            }
        }
        powerHoldDidStartProgress = false

        if !resetHoldTriggered {
            withAnimation(.easeOut(duration: 0.12)) {
                powerHoldProgress = 0
            }
            withAnimation(spring) {
                quitPressed = false
            }
        }
    }
    
    private func cancelPowerHoldWorkItems() {
        powerHoldStartWorkItem?.cancel()
        powerHoldCompleteWorkItem?.cancel()
        powerHoldStartWorkItem = nil
        powerHoldCompleteWorkItem = nil
    }
    
    private func requestPopoverResize() {
        NotificationCenter.default.post(name: .slabPadPopoverNeedsResize, object: nil)
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
            .padding(.top, 2)

            if showBottomHint {
                topHintView
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .clipped()
        .animation(.spring(response: 0.55, dampingFraction: 0.82), value: activePanel)
    }

    private var topHintView: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showBottomHint = false
                }
                DispatchQueue.main.async { requestPopoverResize() }
            } label: {
                Image(systemName: hintIconName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary.opacity(isHoveringBottomHint ? 0.75 : 0.55))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(PopButtonStyle())
            .padding(.leading, 10)

            HStack(spacing: 4) {
                let leftClick: LocalizedStringKey = "Left-click"
                let rightClick: LocalizedStringKey = "Right-click"
                Text(manager.invertClicks ? leftClick : rightClick)
                    .fontWeight(.semibold)
                        Image(systemName: SlabPadIcons.menuBarSymbolName(hapticsEnabled: manager.isHapticsEnabled))
                            .opacity(0.75)
                            .animation(.easeInOut(duration: 0.18), value: SlabPadIcons.menuBarSymbolName(hapticsEnabled: manager.isHapticsEnabled))
                        Text("to instantly toggle haptics")
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            .minimumScaleFactor(0.85)
            .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.035))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        )
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHoveringBottomHint = hovering
            }
        }
        .onReceive(
            Timer.publish(every: 0.85, on: .main, in: .common).autoconnect()
        ) { _ in
            guard showBottomHint, !isHoveringBottomHint else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                hintFlashIsArrow.toggle()
            }
        }
    }

    private var hintIconName: String {
        if isHoveringBottomHint { return "xmark" }
        return hintFlashIsArrow ? "arrow.up" : "lightbulb.fill"
    }
    
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsRow(
                title: launchAtLoginTitle,
                isOn: manager.supportsLaunchAtLogin ? launchAtLoginBinding : .constant(false),
                isDisabled: !manager.supportsLaunchAtLogin
            )

            Divider().opacity(0.2)

            SettingsRow(title: "Disable Haptics on Launch", isOn: $manager.disableOnLaunch)

            Divider().opacity(0.2)

            SettingsRow(title: "Re-enable Haptics on Quit", isOn: $manager.reEnableOnQuit)

            Divider().opacity(0.2)

            SettingsRow(title: "Invert Menu Bar Clicks", isOn: $manager.invertClicks)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.1), lineWidth: 1))
        .padding(.horizontal, 14)
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
        .padding(.horizontal, 14)
        .layoutPriority(1)
    }

    private var releaseNotesSection: some View {
        let latestNotes = normalizeNewlines(manager.latestReleaseNotesMarkdown)
        let latestChangelog = extractChangelogMarkdown(from: latestNotes) ?? latestNotes
        
        let titleLatest: LocalizedStringKey = "Changelog"

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(titleLatest)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.secondary)
                Spacer(minLength: 8)

                if let url = manager.latestReleaseURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "safari")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .buttonStyle(PopButtonStyle())
                    .help(Text("Open on GitHub"))
                }

                Button {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                        showReleaseNotes = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.7))
                        .frame(width: 22, height: 22)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(6)
                }
                .buttonStyle(PopButtonStyle())
                .help(Text("Close"))
            }

            Divider().opacity(0.2)

            ScrollView {
                ChangelogBulletsView(markdown: latestChangelog)
                    .padding(.top, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.1), lineWidth: 1))
        .padding(.horizontal, 14)
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

    private struct VersionPillLabel: View {
        let current: String
        let latest: String
        let showLatest: Bool

        var body: some View {
            Group {
                if showLatest {
                    pillContent(showLatest: true)
                        .transition(.opacity)
                } else {
                    pillContent(showLatest: false)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: showLatest)
        }

        @ViewBuilder
        private func pillContent(showLatest: Bool) -> some View {
            HStack(spacing: 4) {
                Text(current)
                if showLatest {
                    HStack(spacing: 4) {
                        Text("→")
                        Text(latest)
                    }
                }
            }
        }
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
                    let disableHaptics: LocalizedStringKey = "DISABLE HAPTICS"
                    let enableHaptics: LocalizedStringKey = "ENABLE HAPTICS"
                    Text(manager.isHapticsEnabled ? disableHaptics : enableHaptics)
                }
                .font(.headline)
                .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(FloatingPerspectiveModifier())
            .animation(.easeInOut(duration: 0.18), value: manager.isHapticsEnabled)
        }
        .buttonStyle(HapticButtonStyle())
        .padding(.horizontal, 14)
    }
    
    @ViewBuilder
    private func buttonBackground(isEnabled: Bool) -> some View {
        if #available(macOS 13.0, *) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isEnabled ? Color.red.gradient : Color.slabPadAccent.gradient)
                .animation(.easeInOut(duration: 0.18), value: isEnabled)
        } else {
            let base = isEnabled ? Color.red : Color.slabPadAccent
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [base.opacity(0.9), base],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .animation(.easeInOut(duration: 0.18), value: isEnabled)
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
		    let title: LocalizedStringKey
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

private struct ViewSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private struct FloatingPerspectiveModifier: ViewModifier {
    var cornerRadius: CGFloat = 12
    var maxTilt: Double = 10
    var shineMaxOpacity: Double = 0.14
    var shineTravel: CGFloat = 150
    var perspective: CGFloat = 0.2

    @State private var viewSize: CGSize = .zero
    @State private var rotation: (x: Double, y: Double) = (0, 0)
    @State private var shineOffset: CGPoint = .zero
    @State private var shineOpacity: Double = 0
    
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content
                .overlay(
                    GeometryReader { geo in
                        ZStack {
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

                            Color.clear
                                .preference(key: ViewSizePreferenceKey.self, value: geo.size)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                )
                .rotation3DEffect(
                    .degrees(rotation.x),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: .center,
                    perspective: perspective
                )
                .rotation3DEffect(
                    .degrees(rotation.y),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: .center,
                    perspective: perspective
                )
                .onPreferenceChange(ViewSizePreferenceKey.self) { newSize in
                    viewSize = newSize
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let w = max(viewSize.width, 1)
                        let h = max(viewSize.height, 1)
                        let x = (location.x / w) - 0.5
                        let y = (location.y / h) - 0.5
                        
                        withAnimation(.interactiveSpring()) {
                            rotation = (x: Double(y * -maxTilt), y: Double(x * maxTilt))
                            // move shine in response to cursor :D
                            shineOffset = CGPoint(x: x * shineTravel, y: y * shineTravel)
                            shineOpacity = shineMaxOpacity
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
