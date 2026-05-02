// SlabPadManager.swift
// manages user prefs and system state

import SwiftUI
import Combine
import ServiceManagement
import os
import Foundation
import AppIntents

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

@MainActor
final class SlabPadManager: ObservableObject {
    static let shared = SlabPadManager()

    private let logger = Logger(subsystem: "SlabPad", category: "manager")
    
    // main "on/off" state
    @Published var isHapticsEnabled: Bool = true {
        didSet {
            // sync with system state
            applyHapticsStateToSystem()
        }
    }
    
    // user prefs
    @AppStorage("disableOnLaunch") var disableOnLaunch = true
    @AppStorage("reEnableOnQuit") var reEnableOnQuit = true
    @AppStorage("invertClicks") var invertClicks = false
    @AppStorage("hasLaunchedBefore") var hasLaunchedBefore = false
    
    // focus state
    @Published var isFocusActive: Bool = false {
        didSet {
            if oldValue && !isFocusActive {
                isHapticsEnabled = true
            }
            applyHapticsStateToSystem()
        }
    }
    
    // login item state
    @Published var launchAtLogin: Bool
    
    @Published var isCheckingForUpdates: Bool = false
    @Published var hasUpdateAvailable: Bool = false
    @Published var latestReleaseURL: URL?
    @Published var latestReleaseTag: String?
    @Published var latestReleaseNotesMarkdown: String?
    @Published var latestDownloadZipURL: URL?

    var processedReleaseNotes: String? {
        guard let markdown = latestReleaseNotesMarkdown else { return nil }
        
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            
        let lines = normalized.components(separatedBy: .newlines)
        let headerRegex = try? NSRegularExpression(pattern: "^\\s*#{2,6}\\s*(changelog|what's new|whats new)\\s*:?(\\s*)$", options: [.caseInsensitive])
        
        var startIndex: Int?
        if let headerRegex = headerRegex {
            for (index, line) in lines.enumerated() {
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                if headerRegex.firstMatch(in: line, options: [], range: range) != nil {
                    startIndex = index + 1
                    break
                }
            }
        }

        if let startIndex = startIndex, startIndex < lines.count {
            let extracted = lines[startIndex...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return extracted.isEmpty ? normalized : extracted
        }
        
        return normalized
    }

    var bulletLines: [String] {
        guard let markdown = processedReleaseNotes else { return [] }
        let lines = markdown.components(separatedBy: .newlines)
        return lines.compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("- ") { return String(trimmed.dropFirst(2)) }
            if trimmed.hasPrefix("* ") { return String(trimmed.dropFirst(2)) }
            if trimmed.hasPrefix("• ") { return String(trimmed.dropFirst(2)) }
            return nil
        }
    }

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
        
        if #available(macOS 13.0, *) {
            Task {
                let shouldSilence = (try? await SlabPadFocusFilter.current.silenceHaptics) ?? false
                await MainActor.run {
                    self.isFocusActive = shouldSilence
                }
            }
        }
    }
    
    var currentVersionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    }
    
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
    
    enum UpdateError: Error {
        case invalidVersion
        case invalidURL
        case networkError(Error)
        case apiError(String)
        case decodingError(Error)
    }
    
    func checkForUpdate(completion: ((Result<Bool, UpdateError>) -> Void)? = nil) {
        guard let currentVersion = SemVer(currentVersionString) else {
            completion?(.failure(.invalidVersion))
            return
        }
        let timestamp = Int(Date().timeIntervalSince1970)
        guard let url = URL(string: "https://api.github.com/repos/shalamand3r/SlabPad/releases/latest?t=\(timestamp)") else {
            completion?(.failure(.invalidURL))
            return
        }

        isCheckingForUpdates = true
        Task {
            defer { isCheckingForUpdates = false }
            
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("SlabPad", forHTTPHeaderField: "User-Agent")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    completion?(.failure(.networkError(NSError(domain: "SlabPad", code: -1))))
                    return
                }
                guard (200...299).contains(http.statusCode) else {
                    let message: String
                    if let apiError = try? JSONDecoder().decode(GitHubAPIError.self, from: data) {
                        message = apiError.message
                    } else if let body = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                              !body.isEmpty {
                        message = String(body.prefix(300))
                    } else {
                        message = "HTTP \(http.statusCode)"
                    }
                    logger.error("Update check failed: \(message, privacy: .public)")
                    completion?(.failure(.apiError(message)))
                    return
                }

                do {
                    let release = try JSONDecoder().decode(GitHubReleaseResponse.self, from: data)
                    guard let latestVersion = SemVer(release.tagName) else {
                        completion?(.failure(.decodingError(NSError(domain: "SlabPad", code: -2))))
                        return
                    }
                    let isUpdateAvailable = latestVersion > currentVersion

                    self.latestReleaseURL = release.htmlURL
                    self.latestReleaseTag = release.tagName
                    self.latestReleaseNotesMarkdown = release.body
                    self.latestDownloadZipURL = Self.makeDownloadZipURL(tagName: release.tagName)
                    self.hasUpdateAvailable = isUpdateAvailable
                    completion?(.success(isUpdateAvailable))
                } catch {
                    logger.error("Update check failed: \(String(describing: error), privacy: .public)")
                    completion?(.failure(.decodingError(error)))
                }
            } catch {
                logger.error("Update check failed: \(String(describing: error), privacy: .public)")
                completion?(.failure(.networkError(error)))
            }
        }
    }

    private static func makeDownloadZipURL(tagName: String) -> URL? {
        let trimmed = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: "https://github.com/shalamand3r/SlabPad/releases/download/\(trimmed)/SlabPad.Universal.zip")
    }
    
    func toggleHapticsEnabled() {
        isHapticsEnabled.toggle()
    }

    func applyHapticsStateToSystem() {
        let targetState = isFocusActive ? false : isHapticsEnabled
        HapticsManager.shared.setHaptics(to: targetState)
    }
}
