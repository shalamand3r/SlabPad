// HapticsManager.swift
// wrapper for private multitouch apis

import Foundation
import CoreFoundation

private typealias MTDeviceCreateListType = @convention(c) () -> Unmanaged<CFArray>?
private typealias MTDeviceIsBuiltInType = @convention(c) (UnsafeMutableRawPointer) -> Bool
private typealias MTDeviceCreateDefaultType = @convention(c) () -> UnsafeMutableRawPointer?
private typealias MTDeviceGetMTActuatorType = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?
private typealias MTActuatorGetSystemActuationsEnabledType = @convention(c) (UnsafeMutableRawPointer) -> Int
private typealias MTActuatorSetSystemActuationsEnabledType = @convention(c) (UnsafeMutableRawPointer, Int) -> Int32
private typealias MTDeviceReleaseType = @convention(c) (UnsafeMutableRawPointer) -> Void

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
    private var createDeviceList: MTDeviceCreateListType?
    private var isBuiltIn: MTDeviceIsBuiltInType?
    private var getActuator: MTDeviceGetMTActuatorType?
    private var getEnabled: MTActuatorGetSystemActuationsEnabledType?
    private var setEnabled: MTActuatorSetSystemActuationsEnabledType?
    private var releaseDevice: MTDeviceReleaseType?

    private let handle: UnsafeMutableRawPointer?

    private init() {
        // dynamic load to bypass static linking
        handle = dlopen(
            "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
            RTLD_NOW
        )

        guard let handle else { return }

        // load function pointers
        createDefault = loadSymbol("MTDeviceCreateDefault", from: handle, type: MTDeviceCreateDefaultType.self)
        createDeviceList = loadSymbol("MTDeviceCreateList", from: handle, type: MTDeviceCreateListType.self)
        isBuiltIn = loadSymbol("MTDeviceIsBuiltIn", from: handle, type: MTDeviceIsBuiltInType.self)
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

    private func withActuator<T>(
        _ body: (UnsafeMutableRawPointer) -> Result<T, Issue>
    ) -> Result<T, Issue> {
        guard let getActuator else { return .failure(.symbolUnavailable) }

        var issue: Issue = .symbolUnavailable
        if let createDefault, let releaseDevice {
            issue = .deviceUnavailable
            if let device = createDefault() {
                defer { releaseDevice(device) }
                if isBuiltIn?(device) != false {
                    if let actuator = getActuator(device) {
                        return body(actuator)
                    }
                    issue = .actuatorUnavailable
                }
            }
        }

        guard let createDeviceList, let isBuiltIn else { return .failure(issue) }
        if issue == .symbolUnavailable { issue = .deviceUnavailable }
        guard let devices = createDeviceList()?.takeRetainedValue() else { return .failure(issue) }
        // Devices borrowed from this list stay alive only as long as the list does.
        return withExtendedLifetime(devices) {
            for index in 0..<CFArrayGetCount(devices) {
                guard let entry = CFArrayGetValueAtIndex(devices, index) else { continue }
                let device = UnsafeMutableRawPointer(mutating: entry)
                guard isBuiltIn(device) else { continue }
                if let actuator = getActuator(device) {
                    return body(actuator)
                }
                issue = .actuatorUnavailable
            }
            return .failure(issue)
        }
    }

    @discardableResult
    func setHaptics(to enabled: Bool) -> Result<Bool, Issue> {
        guard handle != nil else { return .failure(.frameworkUnavailable) }
        guard let getEnabled, let setEnabled else { return .failure(.symbolUnavailable) }

        return withActuator { actuator in
            let target = enabled ? 1 : 0
            if getEnabled(actuator) == target {
                return .success(enabled)
            }

            _ = setEnabled(actuator, target)
            return readHapticsState(from: actuator, using: getEnabled)
        }
    }

    func readHapticsState() -> Result<Bool, Issue> {
        guard handle != nil else { return .failure(.frameworkUnavailable) }
        guard let getEnabled else { return .failure(.symbolUnavailable) }

        return withActuator { actuator in
            readHapticsState(from: actuator, using: getEnabled)
        }
    }

    private func readHapticsState(
        from actuator: UnsafeMutableRawPointer,
        using getEnabled: MTActuatorGetSystemActuationsEnabledType
    ) -> Result<Bool, Issue> {
        switch getEnabled(actuator) {
        case 0: return .success(false)
        case 1: return .success(true)
        default: return .failure(.stateReadFailed)
        }
    }
}
