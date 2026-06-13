// FocusFilter.swift
// integration with macOS Focus Modes

import AppIntents

@available(macOS 13.0, *)
struct SlabPadFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "focus_filter_title"
    static var description: LocalizedStringResource = "focus_filter_description"
    
    @Parameter(title: "focus_filter_param_silence", default: false)
    var silenceHaptics: Bool
    
    static var parameterSummary: some ParameterSummary {
        Summary("focus_filter_param_silence: \(\.$silenceHaptics)")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "focus_filter_title",
            subtitle: silenceHaptics ? "focus_filter_subtitle_on" : "focus_filter_subtitle_off"
        )
    }

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            SlabPadManager.shared.isFocusActive = silenceHaptics
        }
        return .result()
    }
}
