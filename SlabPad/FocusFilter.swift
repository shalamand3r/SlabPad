// FocusFilter.swift
// integration with macOS Focus Modes

import AppIntents

@available(macOS 13.0, *)
struct SlabPadFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "SlabPad Silence"
    static var description: LocalizedStringResource = "Silences trackpad haptics when this Focus Mode is active."
    
    @Parameter(title: "Silence Haptics", default: false)
    var silenceHaptics: Bool
    
    static var parameterSummary: some ParameterSummary {
        Summary("Silence trackpad haptics: \(\.$silenceHaptics)")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "SlabPad Silence",
            subtitle: silenceHaptics ? "Haptics disabled" : "Haptics enabled"
        )
    }

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            SlabPadManager.shared.isFocusActive = silenceHaptics
        }
        return .result()
    }
}
