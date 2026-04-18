// SlabPadManager.swift
// manages user prefs and system state

import SwiftUI
import Combine
import ServiceManagement
import os

@MainActor
final class SlabPadManager: ObservableObject {
    static let shared = SlabPadManager()

    private let logger = Logger(subsystem: "SlabPad", category: "manager")
    
    // main "on/off" state
    @Published var isHapticsEnabled: Bool = true {
        didSet {
            // sync with system state
            HapticsManager.shared.setHaptics(to: isHapticsEnabled)
        }
    }
    
    // user prefs
    @AppStorage("disableOnLaunch") var disableOnLaunch = true
    @AppStorage("reEnableOnQuit") var reEnableOnQuit = true
    @AppStorage("invertClicks") var invertClicks = false
    @AppStorage("hasLaunchedBefore") var hasLaunchedBefore = false
    
    // login item state
    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    private init() {
        // start from system setting
        self.isHapticsEnabled = HapticsManager.shared.isEnabled()
        if disableOnLaunch {
            isHapticsEnabled = false
        }

        // push initial state to system
        applyHapticsStateToSystem()
    }
    
    func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            let currentlyEnabled = service.status == .enabled
            guard enabled != currentlyEnabled else { return }

            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            launchAtLogin = service.status == .enabled
        } catch {
            logger.error("Failed to update Launch at Login: \(String(describing: error))")
        }
    }

    func toggleHapticsEnabled() {
        isHapticsEnabled.toggle()
    }

    func applyHapticsStateToSystem() {
        // force re-apply (fixes sleep/wake bugs)
        HapticsManager.shared.setHaptics(to: isHapticsEnabled)
    }
}
