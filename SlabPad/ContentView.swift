// ContentView.swift
// main ui for the menubar popover

import SwiftUI
import Foundation

struct ContentView: View {
    @Environment(\.colorScheme) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ObservedObject var popoverVisibility: PopoverVisibility
    @ObservedObject private var manager = SlabPadManager.shared
    @State private var activePanel: Panel = .mainButton
    @State private var isHoveringUpdateBadge = false
    @State private var updateHoverFlipWorkItem: DispatchWorkItem?
    @State private var updatePressed = false
    @State private var quitPressed = false
    @AppStorage("showBottomHint") private var showBottomHint = true
    @State private var resetHoldTriggered = false
    @State private var powerHoldTask: Task<Void, Never>?
    @State private var powerHoldProgress: CGFloat = 0
    @State private var powerHoldDidStartProgress = false
    @State private var ignoreNextPowerTap = false
    @State private var resetCountdownValue = 2
    
    @StateObject private var toastManager = ToastManager()
    
    private let spring = Animation.spring(response: 0.5, dampingFraction: 0.82)
    private var palette: PopoverPalette { PopoverPalette(scheme: appearance) }

    private enum Panel: Hashable {
        case mainButton
        case settings
        case releaseNotes
        case pressurePlayground
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { manager.launchAtLogin },
            set: { manager.setLaunchAtLogin($0) }
        )
    }

    private var launchAtLoginTitle: LocalizedStringKey {
        if manager.supportsLaunchAtLogin {
            return "launch_at_login"
        }

        return "launch_at_login_macos13"
    }
    
    private var shouldShowLatestInVersionPill: Bool {
        manager.hasUpdateAvailable && (isHoveringUpdateBadge || activePanel == .releaseNotes)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            mainInterface
        }
        .frame(width: 288)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, 14)
        .overlay(
            VStack(spacing: 8) {
                ForEach(toastManager.toasts) { toast in
                    renderToast(toast)
                }
                if powerHoldDidStartProgress {
                    resetToastView(progress: powerHoldProgress, countdown: resetCountdownValue)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .allowsHitTesting(false),
            alignment: .bottom
        )
        .onChange(of: popoverVisibility.isVisible) { isVisible in
            if !isVisible {
                endPowerHold()
                updateHoverFlipWorkItem?.cancel()
                updateHoverFlipWorkItem = nil
                isHoveringUpdateBadge = false
            }
        }
        .onChange(of: activePanel) { _ in requestPopoverResize() }
        .onChange(of: manager.hapticsIssueKey) { _ in requestPopoverResize() }
    }

    private struct ToastView<Content: View>: View {
        let content: Content
        
        init(@ViewBuilder content: () -> Content) {
            self.content = content()
        }
        
        var body: some View {
            content
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(
                    ToastBackdrop()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(PopoverSurface(shape: RoundedRectangle(cornerRadius: 12, style: .continuous)))
                )
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity.combined(with: .scale(scale: 0.95))
                ))
        }
    }
    
    private var headerSection: some View {
        HStack(spacing: 5) {
            Button(action: {
                withAnimation(spring) {
                    activePanel = activePanel == .pressurePlayground ? .mainButton : .pressurePlayground
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
            .help(Text(LocalizedStringKey("view_pressure_playground")))
            
            Button(action: {
                if manager.hasUpdateAvailable {
                    withAnimation(spring) {
                        activePanel = activePanel == .releaseNotes ? .mainButton : .releaseNotes
                    }
                } else if !manager.isCheckingForUpdates {
                    manager.checkForUpdate { result in
                        switch result {
                        case .success:
                            break
                        case .failure:
                            toastManager.show(.error(LocalizedStringKey("update_check_failed")))
                        }
                    }
                }
            }) {
                versionPill
            }
            .buttonStyle(PopButtonStyle())
            .help(Text(versionPillHelp))
            .accessibilityLabel(Text(versionPillHelp))
            .accessibilityValue(Text(verbatim: versionPillText))
            .layoutPriority(1)
            Spacer(minLength: 4)
            if let downloadURL = manager.availableUpdate?.downloadURL {
                Button {
                    updatePressed = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                        NotificationCenter.default.post(name: .slabPadRequestOpenUpdate, object: downloadURL)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        updatePressed = false
                    }
                } label: {
                    PopoverIcon(symbol: "arrow.down.to.line", tint: palette.success)
                        .scaleEffect(updatePressed ? 0.94 : 1)
                        .animation(.easeOut(duration: 0.14), value: updatePressed)
                }
                .help(Text(LocalizedStringKey("click_to_download_latest_version")))
                .buttonStyle(PopButtonStyle())
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isHoveringUpdateBadge = hovering
                    }

                    updateHoverFlipWorkItem?.cancel()
                    updateHoverFlipWorkItem = nil

                    guard hovering, manager.hasUpdateAvailable else { return }

                    let workItem = DispatchWorkItem {
                        guard popoverVisibility.isVisible, isHoveringUpdateBadge, manager.hasUpdateAvailable else { return }

                        withAnimation(spring) {
                            activePanel = .releaseNotes
                        }
                    }
                    updateHoverFlipWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
                }
            }
            Button(action: {
                withAnimation(spring) {
                    activePanel = activePanel == .settings ? .mainButton : .settings
                }
            }) {
                PopoverIcon(symbol: "gearshape", tint: activePanel == .settings ? palette.accent : nil)
            }
            .buttonStyle(PopButtonStyle())
            .help(Text(LocalizedStringKey("settings")))

            Button(action: {
                if resetHoldTriggered { return }
                if ignoreNextPowerTap {
                    ignoreNextPowerTap = false
                    return
                }
                
                withAnimation(spring) {
                    quitPressed = true
                    activePanel = .mainButton
                }
                
                // let the red "pressed" state render before we start closing/quitting
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    NotificationCenter.default.post(name: .slabPadRequestQuit, object: nil)
                }
            }) {
                PopoverIcon(symbol: "power", tint: quitPressed ? palette.destructive : nil)
                    .overlay(powerHoldRing)
            }
            .help(Text(LocalizedStringKey("quit")))
            .buttonStyle(PopButtonStyle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        beginPowerHold()
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
                    palette.destructive,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .padding(-3)
        .opacity(powerHoldDidStartProgress ? 1.0 : 0.0)
        .allowsHitTesting(false)
    }

    private func beginPowerHold() {
        guard powerHoldTask == nil, !resetHoldTriggered else { return }

        powerHoldTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                try Task.checkCancellation()
                resetCountdownValue = 2
                withAnimation(spring) {
                    powerHoldDidStartProgress = true
                    quitPressed = true
                }

                try await Task.sleep(nanoseconds: 1_000_000_000)
                try Task.checkCancellation()
                withAnimation(spring) {
                    resetCountdownValue = 1
                }

                try await Task.sleep(nanoseconds: 1_000_000_000)
                try Task.checkCancellation()
                resetHoldTriggered = true
                withAnimation(spring) {
                    powerHoldDidStartProgress = false
                }
                NotificationCenter.default.post(name: .slabPadRequestResetAndQuit, object: nil)
            } catch is CancellationError {
                // Releasing or closing the popover cancels the reset.
            } catch {
                assertionFailure("Unexpected error during reset countdown: \(error)")
            }
        }
    }

    private func endPowerHold() {
        guard let powerHoldTask else { return }
        powerHoldTask.cancel()
        self.powerHoldTask = nil

        if powerHoldDidStartProgress && !resetHoldTriggered {
            ignoreNextPowerTap = true
            DispatchQueue.main.async {
                ignoreNextPowerTap = false
            }
        }

        if !resetHoldTriggered {
            withAnimation(spring) {
                powerHoldDidStartProgress = false
                quitPressed = false
            }
            powerHoldProgress = 0
        }
    }

    private func requestPopoverResize() {
        NotificationCenter.default.post(name: .slabPadPopoverNeedsResize, object: nil)
    }

    private var mainInterface: some View {
        VStack(spacing: 0) {
            ZStack {
                settingsSection
                    .opacity(activePanel == .settings ? 1 : 0)
                    .allowsHitTesting(activePanel == .settings)

                mainButtonSection
                    .opacity(activePanel == .mainButton ? 1 : 0)
                    .allowsHitTesting(activePanel == .mainButton)

                releaseNotesSection
                    .opacity(activePanel == .releaseNotes ? 1 : 0)
                    .allowsHitTesting(activePanel == .releaseNotes)

                if popoverVisibility.isVisible && activePanel == .pressurePlayground {
                    pressurePlaygroundSection
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)

            if showBottomHint && manager.hapticsIssueKey == nil {
                topHintView
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .clipped()
        .animation(.easeInOut(duration: 0.20), value: activePanel)
    }

    private var topHintView: some View {
        let leftClick: LocalizedStringKey = "hint_left_click_menu_bar"
        let rightClick: LocalizedStringKey = "hint_right_click_menu_bar"
        
        return HStack(spacing: 8) {
            Text(manager.invertClicks ? leftClick : rightClick)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showBottomHint = false
                }
                DispatchQueue.main.async { requestPopoverResize() }
            } label: {
                PopoverIcon(symbol: "xmark", size: 22)
            }
            .buttonStyle(PopButtonStyle())
            .help(Text(LocalizedStringKey("dismiss")))
        }
        .padding(.leading, 12)
        .padding(.trailing, 7)
        .padding(.vertical, 7)
        .background(PopoverSurface(shape: RoundedRectangle(cornerRadius: 12, style: .continuous)))
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func renderToast(_ toast: Toast) -> some View {
        switch toast.type {
        case .error(let message):
            messageToast(message, symbol: "xmark.circle.fill", color: palette.destructive)
        case .success(let message):
            messageToast(message, symbol: "checkmark.circle.fill", color: palette.success)
        }
    }

    private func resetToastView(progress: CGFloat, countdown: Int) -> some View {
        ToastView {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(palette.destructive.opacity(0.25), lineWidth: 2)
                        .frame(width: 20, height: 20)
                    Circle()
                        .trim(from: 0, to: 1.0 - progress)
                        .stroke(palette.destructive, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 20, height: 20)
                        .rotationEffect(.degrees(-90))
                    
                    Text("\(countdown)")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(palette.destructive)
                }
                
                Text(LocalizedStringKey("keep_holding_to_reset_app_data"))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
        }
        .onAppear {
            DispatchQueue.main.async {
                guard powerHoldDidStartProgress else { return }
                withAnimation(.linear(duration: 2)) {
                    powerHoldProgress = 1
                }
            }
        }
    }

    private func messageToast(_ message: LocalizedStringKey, symbol: String, color: Color) -> some View {
        ToastView {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundColor(color)
                    .font(.system(size: 12, weight: .bold))
                Text(message)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsRow(
                title: launchAtLoginTitle,
                isOn: manager.supportsLaunchAtLogin ? launchAtLoginBinding : .constant(false),
                isDisabled: !manager.supportsLaunchAtLogin
            )

            panelDivider

            SettingsRow(title: LocalizedStringKey("disable_haptics_on_launch"), isOn: $manager.disableOnLaunch)

            panelDivider

            SettingsRow(title: LocalizedStringKey("re_enable_haptics_on_quit"), isOn: $manager.reEnableOnQuit)

            panelDivider

            SettingsRow(title: LocalizedStringKey("invert_menu_bar_clicks"), isOn: $manager.invertClicks)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(PopoverSurface(shape: RoundedRectangle(cornerRadius: 16, style: .continuous)))
        .padding(.horizontal, 14)
        .layoutPriority(1)
    }

    private var pressurePlaygroundSection: some View {
        VStack(spacing: 0) {
            if #available(macOS 12.0, *) {
                PressurePlayground(onExit: {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                        activePanel = .mainButton
                    }
                })
            } else {
                Spacer()
                Text(LocalizedStringKey("pressure_playground_requires_macos_12"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PopoverSurface(shape: RoundedRectangle(cornerRadius: 16, style: .continuous)))
        .padding(.horizontal, 14)
        .layoutPriority(1)
    }

    private var releaseNotesSection: some View {
        let titleLatest: LocalizedStringKey = "whats_new"

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(titleLatest)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer(minLength: 8)

                if let url = manager.availableUpdate?.releaseURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        PopoverIcon(symbol: "arrow.up.right", size: 24)
                    }
                    .buttonStyle(PopButtonStyle())
                    .help(Text(LocalizedStringKey("open_on_github")))
                }

                Button {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                        activePanel = .mainButton
                    }
                } label: {
                    PopoverIcon(symbol: "xmark", size: 24)
                }
                .buttonStyle(PopButtonStyle())
                .help(Text(LocalizedStringKey("close")))
            }

            panelDivider

            ScrollView {
                WhatsNewBulletsView(
                    bulletLines: manager.availableUpdate?.notes.bulletLines ?? [],
                    fallbackMarkdown: manager.availableUpdate?.notes.markdown
                )
                    .padding(.top, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(PopoverSurface(shape: RoundedRectangle(cornerRadius: 16, style: .continuous)))
        .padding(.horizontal, 14)
    }
    private var panelDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.11))
            .frame(height: 1)
    }

    private var versionPillHelp: LocalizedStringKey {
        if manager.isCheckingForUpdates { return "loading" }
        return manager.hasUpdateAvailable ? "view_release_notes" : "check_for_updates"
    }

    private var versionPillText: String {
        let current = manager.currentVersionText
        guard shouldShowLatestInVersionPill, let update = manager.availableUpdate else { return current }
        return "\(current) →\u{00A0}\(update.versionText)"
    }

    private var versionPill: some View {
        let tint = activePanel == .releaseNotes ? palette.accent : nil
        let ink = tint ?? palette.secondary

        let isChecking = manager.isCheckingForUpdates && popoverVisibility.isVisible
        let isConfirmed = manager.showsUpdateConfirmation && popoverVisibility.isVisible
        let hasStatus = isChecking || isConfirmed
        let motion: Animation? = reduceMotion ? nil : .easeInOut(duration: 0.18)

        return HStack(spacing: 0) {
            ZStack {
                if isChecking {
                    UpdateSpinner(color: ink)
                        .transition(.opacity)
                }

                Image(systemName: "checkmark")
                    .foregroundColor(palette.success)
                    .opacity(isConfirmed && !isChecking ? 1 : 0)
            }
            .frame(width: 10, height: 10)
            .offset(x: hasStatus ? 0 : -5)
            .frame(width: hasStatus ? 15 : 0, alignment: .leading)
            .clipped()
            .accessibilityHidden(true)

            Text(verbatim: versionPillText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .foregroundColor(ink)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .frame(minHeight: 20)
        .background(PopoverSurface(shape: Capsule(), tint: tint))
        .animation(motion, value: shouldShowLatestInVersionPill)
        .animation(motion, value: isChecking)
        .animation(motion, value: isConfirmed)
    }

    private var mainButtonSection: some View {
        Group {
            if let issueKey = manager.hapticsIssueKey {
                hapticsUnavailableTile(issueKey)
            } else {
                hapticsToggleButton
            }
        }
        .padding(.horizontal, 14)
    }

    private var hapticsToggleButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                manager.toggleHapticsEnabled()
            }
        }) {
            let willEnableHaptics = manager.nextHapticsEnabled
            ZStack {
                buttonBackground(isEnabled: !willEnableHaptics, isFocusActive: manager.isFocusActive)
                    .shadow(color: .black.opacity(manager.isFocusActive ? 0 : 0.13), radius: 7, y: 3)

                HStack {
                    Image(systemName: manager.isFocusActive ? "moon.stars.fill" : "power")
                    let disableHaptics: LocalizedStringKey = "disable_haptics_button"
                    let enableHaptics: LocalizedStringKey = "enable_haptics_button"
                    let focusActive: LocalizedStringKey = "focus_active"
                    Text(manager.isFocusActive ? focusActive : (willEnableHaptics ? enableHaptics : disableHaptics))
                }
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .foregroundColor(manager.isFocusActive ? palette.accent : .white)
            }
            .frame(maxWidth: .infinity, minHeight: 105, maxHeight: .infinity)
            .modifier(FloatingPerspectiveModifier(isEnabled: !manager.isFocusActive))
            .animation(.easeInOut(duration: 0.18), value: manager.isHapticsEnabled)
        }
        .buttonStyle(PopButtonStyle(pressedScale: 0.95, dampingFraction: 0.55))
        .disabled(manager.isFocusActive)
    }

    private func hapticsUnavailableTile(_ issueKey: String) -> some View {
        let title = Text("haptics_unavailable_title")
        let reason = Text(LocalizedStringKey(issueKey))

        return HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            title
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.headline)
        .foregroundColor(palette.secondary)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 105, maxHeight: .infinity)
        .background(PopoverSurface(shape: RoundedRectangle(cornerRadius: 16, style: .continuous)))
        .help(reason)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(reason)
    }

    @ViewBuilder
    private func buttonBackground(isEnabled: Bool, isFocusActive: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if isFocusActive {
            PopoverSurface(shape: shape, tint: palette.accent)
        } else {
            shape
                .fill(palette.actionFill(hapticsEnabled: isEnabled))
                .overlay(
                    shape.fill(
                        LinearGradient(
                            colors: [.white.opacity(0.10), .clear, .black.opacity(0.22)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .overlay(shape.strokeBorder(.white.opacity(0.20), lineWidth: 1))
                .animation(.easeInOut(duration: 0.18), value: isEnabled)
        }
    }
}

private struct UpdateSpinner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSpinning = false

    let color: Color

    var body: some View {
        Circle()
            .strokeBorder(color.opacity(0.22), lineWidth: 1.25)
            .overlay(
                Circle()
                    .trim(from: 0, to: 0.68)
                    .stroke(color, style: StrokeStyle(lineWidth: 1.25, lineCap: .round))
                    .padding(0.65)
                    .rotationEffect(.degrees(isSpinning && !reduceMotion ? 270 : -90))
                    .animation(
                        reduceMotion ? nil : .linear(duration: 0.85).repeatForever(autoreverses: false),
                        value: isSpinning
                    )
            )
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
            .onAppear { isSpinning = !reduceMotion }
            .onChange(of: reduceMotion) { isSpinning = !$0 }
    }
}

struct PopButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.9
    var dampingFraction: Double = 0.5

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(.spring(response: 0.25, dampingFraction: dampingFraction), value: configuration.isPressed)
    }
}

private struct ViewSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private struct FloatingPerspectiveModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isEnabled: Bool
    var cornerRadius: CGFloat = 16
    var maxTilt: Double = 7
    var shineMaxOpacity: Double = 0.10
    var shineTravel: CGFloat = 150
    var perspective: CGFloat = 0.2

    @State private var viewSize: CGSize = .zero
    @State private var rotation: (x: Double, y: Double) = (0, 0)
    @State private var shineOffset: CGPoint = .zero
    @State private var shineOpacity: Double = 0

    func body(content: Content) -> some View {
        if #available(macOS 13.0, *), isEnabled && !reduceMotion {
            content
                .overlay(
                    GeometryReader { geo in
                        ZStack {
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

                        rotation = (x: Double(y * -maxTilt), y: Double(x * maxTilt))
                        shineOffset = CGPoint(x: x * shineTravel, y: y * shineTravel)
                        shineOpacity = shineMaxOpacity
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

private struct SettingsRow: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool
    var isDisabled: Bool = false

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel(Text(title))
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
                Text(LocalizedStringKey("loading"))
                    .foregroundColor(.secondary)
            }
        }
        .font(.system(size: 11))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WhatsNewBulletsView: View {
    let bulletLines: [String]
    let fallbackMarkdown: String?
    
    var body: some View {
        if bulletLines.isEmpty {
            ReleaseNotesMarkdownView(markdown: fallbackMarkdown)
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

private struct ToastBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let visibility = PopoverVisibility()
        visibility.isVisible = true
        return ContentView(popoverVisibility: visibility)
    }
}
#endif
