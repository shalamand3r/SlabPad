// FocusFilter.swift
// integration with macOS Focus Modes

import AppIntents

@available(macOS 13.0, *)
struct SlabPadFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "SlabPad Silence"
    static var description: LocalizedStringResource = "Silences trackpad haptics when this Focus Mode is active."
    
    @Parameter(title: "Disable Haptics", default: false)
    var silenceHaptics: Bool
    
    static var parameterSummary: some ParameterSummary {
        Summary("Disable trackpad haptics: \(\.$silenceHaptics)")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource("SlabPad Silence"),
            subtitle: silenceHaptics ? LocalizedStringResource("Haptics disabled") : LocalizedStringResource("Haptics enabled")
        )
    }

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            SlabPadManager.shared.isFocusActive = silenceHaptics
        }
        return .result()
    }
}
