// SlabPadManager.swift
// manages user prefs and system state

import SwiftUI
import Combine
import ServiceManagement
import os
import Foundation
import AppIntents

private struct ReleaseVersion {
    let parts: [Int]

    init?(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
        let components = cleaned.split(separator: ".")
        let numbers = components.compactMap { Int($0) }
        guard !components.isEmpty, numbers.count == components.count else { return nil }
        parts = numbers
    }

    func isNewer(than version: ReleaseVersion) -> Bool {
        for index in 0..<max(parts.count, version.parts.count) {
            let latest = index < parts.count ? parts[index] : 0
            let installed = index < version.parts.count ? version.parts[index] : 0
            if latest != installed { return latest > installed }
        }
        return false
    }
}

private struct GitHubReleaseResponse: Decodable, Sendable {
    let tagName: String
    let htmlURL: URL
    let body: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body = "body"
    }
}

private struct GitHubAPIError: Decodable, Sendable {
    let message: String
}

private struct UpdateCheckError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

struct AvailableUpdate {
    let versionText: String
    let releaseURL: URL
    let downloadURL: URL?
    let notes: ReleaseNotes
}

struct ReleaseNotes {
    private static let changelogHeading = try? NSRegularExpression(
        pattern: #"^\s*#{2,6}\s*(changelog|what's new|whats new)\s*:?\s*$"#,
        options: [.caseInsensitive]
    )

    let markdown: String
    let bulletLines: [String]

    init(_ body: String) {
        let normalized = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: .newlines)
        let heading = Self.changelogHeading.flatMap { regex in
            lines.firstIndex { line in
                regex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)) != nil
            }
        }
        let changelog = heading.map { index in
            lines.dropFirst(index + 1).prefix { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed != "---" && !trimmed.hasPrefix("### ")
            }
        }
        let noteLines = changelog ?? lines[...]
        markdown = noteLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        bulletLines = noteLines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") else {
                return nil
            }
            return String(trimmed.dropFirst(2))
        }
    }
}

@MainActor
final class SlabPadManager: ObservableObject {
    static let shared = SlabPadManager()

    private let logger = Logger(subsystem: "SlabPad", category: "manager")
    
    @Published private(set) var isHapticsEnabled: Bool?
    @Published private(set) var isFocusActive = false
    @Published private var hapticsIssue: HapticsManager.Issue?

    private var manualHapticsEnabled: Bool?
    private var focusRefreshTask: Task<Void, Never>?
    private var isDeviceRetryScheduled = false

    var hapticsIssueKey: String? { hapticsIssue?.localizationKey }

    private var shouldRetryDeviceDetection: Bool {
        hapticsIssue == .deviceUnavailable || hapticsIssue == .actuatorUnavailable
    }

    var nextHapticsEnabled: Bool {
        isHapticsEnabled.map { !$0 } ?? manualHapticsEnabled ?? true
    }

    @AppStorage("disableOnLaunch") var disableOnLaunch = true
    @AppStorage("reEnableOnQuit") var reEnableOnQuit = true
    @AppStorage("invertClicks") var invertClicks = false
    @AppStorage("hasLaunchedBefore") var hasLaunchedBefore = false

    // login item state
    @Published private(set) var launchAtLogin: Bool

    @Published private(set) var isCheckingForUpdates = false
    @Published private(set) var showsUpdateConfirmation = false
    private var updateConfirmationTask: Task<Void, Never>?
    @Published private(set) var availableUpdate: AvailableUpdate?

    var hasUpdateAvailable: Bool { availableUpdate != nil }

    var supportsLaunchAtLogin: Bool {
        if #available(macOS 13.0, *) {
            return true
        }
        return false
    }

    private init() {
        self.launchAtLogin = Self.readLaunchAtLogin()
        
        if disableOnLaunch {
            manualHapticsEnabled = false
        }
        applyHapticsStateToSystem()
        scheduleDeviceDetectionRetry()

        if #available(macOS 13.0, *) {
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                Unmanaged.passUnretained(self).toOpaque(),
                { _, _, _, _, _ in
                    Task { @MainActor in
                        SlabPadManager.shared.refreshFocusState()
                    }
                },
                focusFilterDidChange as CFString,
                nil,
                .deliverImmediately
            )
            refreshFocusState()
        }
    }

    @available(macOS 13.0, *)
    private func refreshFocusState() {
        focusRefreshTask?.cancel()
        focusRefreshTask = Task {
            defer {
                if !Task.isCancelled { focusRefreshTask = nil }
            }
            let active: Bool
            do {
                active = try await SlabPadFocusFilter.current.silenceHaptics
            } catch SetFocusFilterIntentError.notFound {
                active = false
            } catch {
                if !Task.isCancelled {
                    logger.debug("Could not read the current Focus filter: \(error.localizedDescription, privacy: .public)")
                }
                return
            }
            guard !Task.isCancelled else { return }
            setFocusActive(active)
        }
    }

    private let currentVersionString = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    
    var currentVersionText: String {
        "v\(currentVersionString)"
    }
    
    private static func readLaunchAtLogin() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }
    
    func setLaunchAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else {
            logger.info("Launch at Login requires macOS 13.0+")
            launchAtLogin = false
            return
        }

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
    
    func checkForUpdate(onFailure: (() -> Void)? = nil) {
        guard !isCheckingForUpdates else { return }
        guard let currentVersion = ReleaseVersion(currentVersionString) else {
            logger.error("Update check failed: invalid installed version")
            onFailure?()
            return
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        guard let url = URL(string: "https://api.github.com/repos/shalamand3r/SlabPad/releases/latest?t=\(timestamp)") else {
            logger.error("Update check failed: invalid update URL")
            onFailure?()
            return
        }

        updateConfirmationTask?.cancel()
        showsUpdateConfirmation = false
        isCheckingForUpdates = true
        Task {
            defer { isCheckingForUpdates = false }

            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("SlabPad", forHTTPHeaderField: "User-Agent")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }

                let decoder = JSONDecoder()
                guard (200...299).contains(http.statusCode) else {
                    let apiMessage = (try? decoder.decode(GitHubAPIError.self, from: data))?.message
                    let body = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let message = body.isEmpty ? "HTTP \(http.statusCode)" : String(body.prefix(300))
                    throw UpdateCheckError(message: apiMessage ?? message)
                }

                let release = try decoder.decode(GitHubReleaseResponse.self, from: data)
                let tag = release.tagName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let latestVersion = ReleaseVersion(tag) else {
                    throw UpdateCheckError(message: "Invalid release version: \(tag)")
                }

                if latestVersion.isNewer(than: currentVersion) {
                    availableUpdate = AvailableUpdate(
                        versionText: tag.hasPrefix("v") ? tag : "v\(tag)",
                        releaseURL: release.htmlURL,
                        downloadURL: URL(string: "https://github.com/shalamand3r/SlabPad/releases/download/\(tag)/SlabPad.Universal.zip"),
                        notes: ReleaseNotes(release.body)
                    )
                } else {
                    availableUpdate = nil
                    showsUpdateConfirmation = true
                    updateConfirmationTask = Task { [weak self] in
                        try? await Task.sleep(nanoseconds: 1_300_000_000)
                        if !Task.isCancelled { self?.showsUpdateConfirmation = false }
                    }
                }
            } catch {
                logger.error("Update check failed: \(error.localizedDescription, privacy: .public)")
                onFailure?()
            }
        }
    }

    func toggleHapticsEnabled() {
        guard !isFocusActive else { return }
        if hapticsIssue == nil {
            manualHapticsEnabled = nextHapticsEnabled
        }
        applyHapticsStateToSystem()
    }

    private func setFocusActive(_ active: Bool) {
        if active != isFocusActive {
            isFocusActive = active
        } else if hapticsIssueKey == nil {
            return
        }
        applyHapticsStateToSystem()
    }

    func retryDeviceDetectionIfNeeded() {
        if shouldRetryDeviceDetection {
            applyHapticsStateToSystem()
        }
    }

    func scheduleDeviceDetectionRetry() {
        guard shouldRetryDeviceDetection, !isDeviceRetryScheduled else { return }
        isDeviceRetryScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            guard let self else { return }
            isDeviceRetryScheduled = false
            retryDeviceDetectionIfNeeded()
        }
    }

    func applyHapticsStateToSystem() {
        // If startup could not read the device, recover its current state before applying overrides.
        if manualHapticsEnabled == nil {
            let result = HapticsManager.shared.readHapticsState()
            if case .success(let enabled) = result {
                manualHapticsEnabled = enabled
            }
            if manualHapticsEnabled != true || !isFocusActive {
                updateHapticsStatus(result)
                return
            }
        }

        let target = manualHapticsEnabled == true && !isFocusActive
        updateHapticsStatus(HapticsManager.shared.setHaptics(to: target), target: target)
    }

    private func updateHapticsStatus(_ result: Result<Bool, HapticsManager.Issue>, target: Bool? = nil) {
        let observed: Bool?
        let issue: HapticsManager.Issue?
        switch result {
        case .success(let enabled):
            observed = enabled
            issue = target.map { $0 != enabled } == true ? .setFailed : nil
        case .failure(let failure):
            observed = nil
            issue = failure
        }

        if isHapticsEnabled != observed {
            isHapticsEnabled = observed
        }
        if hapticsIssue != issue {
            hapticsIssue = issue
        }
    }
}
