// HapticsManager.swift
// wrapper for private multitouch apis

import Foundation

typealias MTDeviceCreateDefaultType = @convention(c) () -> UnsafeMutableRawPointer?
typealias MTDeviceGetMTActuatorType = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?
typealias MTActuatorGetSystemActuationsEnabledType = @convention(c) (UnsafeMutableRawPointer) -> Int
typealias MTActuatorSetSystemActuationsEnabledType = @convention(c) (UnsafeMutableRawPointer, Int) -> Int32
typealias MTDeviceReleaseType = @convention(c) (UnsafeMutableRawPointer) -> Void

final class HapticsManager {
    static let shared = HapticsManager()

    enum Issue: Error, Equatable {
        case frameworkUnavailable
        case symbolUnavailable
        case deviceUnavailable
        case actuatorUnavailable
        case setFailed
        case stateReadFailed

        var localizationKey: String {
            switch self {
            case .frameworkUnavailable:
                return "haptics_framework_unavailable"
            case .symbolUnavailable:
                return "haptics_private_api_unavailable"
            case .deviceUnavailable:
                return "haptics_trackpad_unavailable"
            case .actuatorUnavailable:
                return "haptics_actuator_unavailable"
            case .setFailed:
                return "haptics_set_failed"
            case .stateReadFailed:
                return "haptics_state_read_failed"
            }
        }
    }
    
    // private API definitions
    private var createDefault: MTDeviceCreateDefaultType?
    private var getActuator: MTDeviceGetMTActuatorType?
    private var getEnabled: MTActuatorGetSystemActuationsEnabledType?
    private var setEnabled: MTActuatorSetSystemActuationsEnabledType?
    private var releaseDevice: MTDeviceReleaseType?

    private let handle: UnsafeMutableRawPointer?
    private var loadIssue: Issue?

    private init() {
        // dynamic load to bypass static linking
        handle = dlopen(
            "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
            RTLD_NOW
        )

        guard let handle else {
            loadIssue = .frameworkUnavailable
            return
        }

        // load function pointers
        createDefault = loadSymbol("MTDeviceCreateDefault", from: handle, type: MTDeviceCreateDefaultType.self)
        getActuator = loadSymbol("MTDeviceGetMTActuator", from: handle, type: MTDeviceGetMTActuatorType.self)
        getEnabled = loadSymbol(
            "MTActuatorGetSystemActuationsEnabled",
            from: handle,
            type: MTActuatorGetSystemActuationsEnabledType.self
        )
        setEnabled = loadSymbol(
            "MTActuatorSetSystemActuationsEnabled",
            from: handle,
            type: MTActuatorSetSystemActuationsEnabledType.self
        )
        releaseDevice = loadSymbol("MTDeviceRelease", from: handle, type: MTDeviceReleaseType.self)
    }

    private func loadSymbol<T>(_ name: String, from handle: UnsafeMutableRawPointer, type: T.Type) -> T? {
        guard let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: type)
    }

    deinit {
        if let handle {
            dlclose(handle)
        }
    }

    func availabilityIssue() -> Issue? {
        if let loadIssue { return loadIssue }
        guard let createDevice = createDefault,
              let getTrackpadActuator = getActuator,
              releaseDevice != nil,
              getEnabled != nil,
              setEnabled != nil else { return .symbolUnavailable }

        guard let device = createDevice() else { return .deviceUnavailable }
        defer { releaseDevice?(device) }

        guard getTrackpadActuator(device) != nil else { return .actuatorUnavailable }
        return nil
    }

    private func withActuator<T>(_ body: (UnsafeMutableRawPointer) -> T) -> Result<T, Issue> {
        if let loadIssue { return .failure(loadIssue) }
        guard let createDevice = createDefault,
              let getTrackpadActuator = getActuator,
              let release = releaseDevice else { return .failure(.symbolUnavailable) }

        guard let device = createDevice() else { return .failure(.deviceUnavailable) }
        defer { release(device) }

        guard let actuator = getTrackpadActuator(device) else { return .failure(.actuatorUnavailable) }
        return .success(body(actuator))
    }
    
    @discardableResult
    func setHaptics(to enabled: Bool) -> Issue? {
        guard let setSystemEnabled = setEnabled else { return .symbolUnavailable }
        let setResult = withActuator { actuator in
            _ = setSystemEnabled(actuator, enabled ? 1 : 0)
        }

        if case .failure(let issue) = setResult {
            return issue
        }

        switch readEnabledState() {
        case .success(let observed):
            return observed == enabled ? nil : .setFailed
        case .failure:
            return .stateReadFailed
        }
    }
    
    func isEnabled() -> Bool {
        if case .success(let isEnabled) = readEnabledState() {
            return isEnabled
        }

        // default to true on fail to prevent bricking trackpad
        return true
    }

    private func readEnabledState() -> Result<Bool, Issue> {
        guard let getSystemEnabled = getEnabled else { return .failure(.symbolUnavailable) }

        return withActuator { actuator in
            getSystemEnabled(actuator) == 1
        }
    }
}
