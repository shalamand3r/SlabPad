// SlabPadManager.swift
// manages user prefs and system state

import SwiftUI
import Combine
import ServiceManagement
import os
import Foundation

private struct SemVer: Comparable {
    let parts: [Int]

    init?(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
        let components = cleaned.split(separator: ".")
        guard !components.isEmpty, components.allSatisfy({ Int($0) != nil }) else { return nil }
        self.parts = components.map { Int($0)! }
    }

    static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        let maxCount = max(lhs.parts.count, rhs.parts.count)
        for index in 0..<maxCount {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

private struct GitHubReleaseResponse: Decodable, Sendable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

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
    @Published var launchAtLogin: Bool
    
    @Published var hasUpdateAvailable: Bool = false
    @Published var latestReleaseURL: URL?
    @Published var latestReleaseTag: String?

    var supportsLaunchAtLogin: Bool {
        if #available(macOS 13.0, *) {
            return true
        }
        return false
    }

    private init() {
        self.launchAtLogin = Self.readLaunchAtLogin()
        
        // start from system setting
        self.isHapticsEnabled = HapticsManager.shared.isEnabled()
        if disableOnLaunch {
            isHapticsEnabled = false
        }

        // push initial state to system
        applyHapticsStateToSystem()
        checkForUpdate()
    }
    
    var currentVersionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    }
    
    private static func readLaunchAtLogin() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }
    
    func setLaunchAtLogin(_ enabled: Bool) {
        guard supportsLaunchAtLogin else {
            logger.info("Launch at Login requires macOS 13.0+")
            launchAtLogin = false
            return
        }
        
        if #available(macOS 13.0, *) {
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
    }
    
    func checkForUpdate() {
        guard let currentVersion = SemVer(currentVersionString) else { return }
        guard let url = URL(string: "https://api.github.com/repos/shalamand3r/SlabPad/releases/latest") else { return }

        Task { @MainActor in
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("SlabPad", forHTTPHeaderField: "User-Agent")

            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                let release = try JSONDecoder().decode(GitHubReleaseResponse.self, from: data)
                guard let latestVersion = SemVer(release.tagName) else { return }
                let isUpdateAvailable = latestVersion > currentVersion

                await MainActor.run {
                    self.latestReleaseURL = release.htmlURL
                    self.latestReleaseTag = release.tagName
                    self.hasUpdateAvailable = isUpdateAvailable
                }
            } catch {
            }
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
