// ContentView.swift
// main ui for the menubar popover

import SwiftUI
import Combine
import Foundation

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
    @AppStorage("showBottomHint") private var showBottomHint = true
    @State private var resetHoldTriggered = false
    @State private var isPowerPressActive = false
    @State private var powerHoldStartWorkItem: DispatchWorkItem?
    @State private var powerHoldCompleteWorkItem: DispatchWorkItem?
    @State private var powerHoldProgress: CGFloat = 0
    @State private var powerHoldDidStartProgress = false
    @State private var ignoreNextPowerTap = false
    @State private var resetCountdownValue = 2
    
    @StateObject private var toastManager = ToastManager()
    
    private let spring = Animation.spring(response: 0.5, dampingFraction: 0.82)

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
    
    private var latestVersionText: String {
        guard let latestTag = manager.latestReleaseTag else { return manager.currentVersionText }
        let tag = latestTag.trimmingCharacters(in: .whitespacesAndNewlines)
        return tag.hasPrefix("v") ? tag : "v\(tag)"
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
        .overlay(
            VStack(spacing: 8) {
                ForEach(toastManager.toasts) { toast in
                    renderToast(toast)
                }
            }
            .padding(.bottom, 20),
            alignment: .bottom
        )
        .onChange(of: showSettings) { _ in requestPopoverResize() }
        .onChange(of: showReleaseNotes) { _ in requestPopoverResize() }
        .onChange(of: showPressurePlayground) { _ in requestPopoverResize() }
    }

    private func showError(_ message: String) {
        toastManager.show(.error(message))
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
                    VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
                )
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity.combined(with: .scale(scale: 0.95))
                ))
        }
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
            .help(Text("View Pressure Playground"))
            
            Button(action: {
                if manager.hasUpdateAvailable {
                    withAnimation(spring) {
                        showReleaseNotes.toggle()
                        if showReleaseNotes {
                            showSettings = false
                            showPressurePlayground = false
                        }
                    }
                } else if !manager.isCheckingForUpdates {
                    manager.checkForUpdate { result in
                        switch result {
                        case .success(let isAvailable):
                            if !isAvailable {
                                toastManager.show(.upToDate)
                            }                        case .failure:
                            showError("Update check failed")
                        }
                    }
                }
            }) {
                HStack(spacing: 4) {
                    if manager.isCheckingForUpdates {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                    }
                    
                    VersionPillLabel(
                       current: manager.currentVersionText,
                       latest: latestVersionText,
                       showLatest: shouldShowLatestInVersionPill
                    )                }
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .layoutPriority(1)
                .foregroundColor(showReleaseNotes ? .accentColor : .secondary.opacity(0.6))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(showReleaseNotes ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06))
                        .overlay(Capsule().stroke(showReleaseNotes ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.1), lineWidth: 0.5))
                )
                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                .animation(.easeInOut(duration: 0.18), value: shouldShowLatestInVersionPill)
                .animation(.easeInOut(duration: 0.18), value: manager.isCheckingForUpdates)
            }
            .buttonStyle(PopButtonStyle())
            .help(Text(manager.hasUpdateAvailable ? "View Release Notes" : "Check for Updates"))
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
                    .foregroundColor(showSettings ? .accentColor : .secondary.opacity(0.6))
                    .frame(width: 28, height: 28)
                    .background(showSettings ? Color.accentColor.opacity(0.15) : Color.clear)
                    .cornerRadius(8)
            }
            .buttonStyle(PopButtonStyle())
            .help(Text("Settings"))

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
            resetCountdownValue = 2
            
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                updateResetToast()
            }

            if !quitPressed {
                withAnimation(spring) {
                    quitPressed = true
                }
            }

            powerHoldProgress = 0
            
            // Continuous progress updates for the toast
            Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
                if !isPowerPressActive || resetHoldTriggered {
                    timer.invalidate()
                } else {
                    powerHoldProgress += 0.05 / 2.0 // Total 2 seconds
                    updateResetToast()
                }
            }

            // Countdown timer
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                guard isPowerPressActive, !resetHoldTriggered else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    resetCountdownValue = 1
                }
            }

            let completeWork = DispatchWorkItem {
                guard isPowerPressActive, !resetHoldTriggered else { return }
                resetHoldTriggered = true
                toastManager.hideResetToast()
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

        toastManager.hideResetToast()

        cancelPowerHoldWorkItems()
        if powerHoldDidStartProgress && !resetHoldTriggered {
            ignoreNextPowerTap = true
            DispatchQueue.main.async {
                self.ignoreNextPowerTap = false
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
                    .allowsHitTesting(activePanel == .settings)

                mainButtonSection
                    .opacity(activePanel == .mainButton ? 1 : 0)
                    .allowsHitTesting(activePanel == .mainButton)
                
                releaseNotesSection
                    .opacity(activePanel == .releaseNotes ? 1 : 0)
                    .allowsHitTesting(activePanel == .releaseNotes)

                pressurePlaygroundSection
                    .opacity(activePanel == .pressurePlayground ? 1 : 0)
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
        let leftClick: LocalizedStringKey = "Left-click the menu bar icon to instantly toggle haptics"
        let rightClick: LocalizedStringKey = "Right-click the menu bar icon to instantly toggle haptics"
        
        return ZStack(alignment: .trailing) {
            Text(manager.invertClicks ? leftClick : rightClick)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 10)
                .padding(.leading, 12)
                .padding(.trailing, 36)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showBottomHint = false
                }
                DispatchQueue.main.async { requestPopoverResize() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary.opacity(isHoveringBottomHint ? 0.75 : 0.55))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(PopButtonStyle())
            .help(Text("Dismiss"))
            .padding(10)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.035))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        )
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHoveringBottomHint = hovering
            }
        }
    }

    private func updateResetToast() {
        guard isPowerPressActive || resetHoldTriggered else { return }
        toastManager.updateResetToast(
            progress: Double(powerHoldProgress),
            countdown: resetCountdownValue
        )
    }

    @ViewBuilder
    private func renderToast(_ toast: Toast) -> some View {
        switch toast.type {
        case .upToDate:
            upToDateToast
        case .reset(let progress, let countdown):
            resetToastView(progress: CGFloat(progress), countdown: countdown)
        case .error(let message):
            errorToastView(message: message)
        case .info(let message, let systemImage):
            infoToastView(message: message, systemImage: systemImage)
        case .success(let message):
            successToastView(message: message)
        case .warning(let message):
            warningToastView(message: message)
        }
    }

    private var upToDateToast: some View {
        ToastView {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 12, weight: .bold))
                Text("You're up to date!")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.primary.opacity(0.8))
            }
        }
    }

    private func resetToastView(progress: CGFloat, countdown: Int) -> some View {
        ToastView {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(Color.red.opacity(0.2), lineWidth: 2)
                        .frame(width: 20, height: 20)
                    Circle()
                        .trim(from: 0, to: 1.0 - progress)
                        .stroke(Color.red, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 20, height: 20)
                        .rotationEffect(.degrees(-90))
                    
                    Text("\(countdown)")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(.red)
                }
                
                Text("Keep holding to reset app data...")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.primary.opacity(0.8))
            }
        }
    }

    private func errorToastView(message: String) -> some View {
        ToastView {
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 12, weight: .bold))
                Text(message.isEmpty ? "Error" : LocalizedStringKey(message))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.primary.opacity(0.8))
            }
        }
    }

    private func infoToastView(message: String, systemImage: String?) -> some View {
        ToastView {
            HStack(spacing: 8) {
                Image(systemName: systemImage ?? "info.circle.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 12, weight: .bold))
                Text(LocalizedStringKey(message))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.primary.opacity(0.8))
            }
        }
    }

    private func successToastView(message: String) -> some View {
        ToastView {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 12, weight: .bold))
                Text(LocalizedStringKey(message))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.primary.opacity(0.8))
            }
        }
    }

    private func warningToastView(message: String) -> some View {
        ToastView {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 12, weight: .bold))
                Text(LocalizedStringKey(message))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.primary.opacity(0.8))
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
        let titleLatest: LocalizedStringKey = "What's New"

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
                WhatsNewBulletsView(bulletLines: manager.bulletLines, fallbackMarkdown: manager.processedReleaseNotes)
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
                buttonBackground(isEnabled: manager.isHapticsEnabled, isFocusActive: manager.isFocusActive)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                
                HStack {
                    Image(systemName: manager.isFocusActive ? "moon.stars.fill" : "power")
                    let disableHaptics: LocalizedStringKey = "DISABLE HAPTICS"
                    let enableHaptics: LocalizedStringKey = "ENABLE HAPTICS"
                    let focusActive: LocalizedStringKey = "FOCUS ACTIVE"
                    Text(manager.isFocusActive ? focusActive : (manager.isHapticsEnabled ? disableHaptics : enableHaptics))
                }
                .font(.headline)
                .foregroundColor(manager.isFocusActive ? .secondary : .white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 3D & GLIMMER EFFECT ON BIG HAPTICS BUTTON!!!
            .modifier(FloatingPerspectiveModifier())
            .animation(.easeInOut(duration: 0.18), value: manager.isHapticsEnabled)
        }
        .buttonStyle(HapticButtonStyle())
        .disabled(manager.isFocusActive)
        .help(Text(manager.isFocusActive ? "Haptics managed by Focus" : (manager.isHapticsEnabled ? "Disable Haptics" : "Enable Haptics")))
        .padding(.horizontal, 14)
    }
    
    @ViewBuilder
    private func buttonBackground(isEnabled: Bool, isFocusActive: Bool) -> some View {
        if isFocusActive {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [5, 5]))
                .foregroundColor(.secondary.opacity(0.4))
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.02)))
        } else if #available(macOS 13.0, *) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isEnabled ? Color.red.gradient : Color.accentColor.gradient)
                .animation(.easeInOut(duration: 0.18), value: isEnabled)
        } else {
            let base = isEnabled ? Color.red : Color.accentColor
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

private struct SettingsRow: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool
    var isDisabled: Bool = false

    var body: some View {
        HStack(alignment: .center) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
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
