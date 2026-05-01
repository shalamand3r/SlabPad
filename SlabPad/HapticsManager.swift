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
    
    // private API definitions
    private var createDefault: MTDeviceCreateDefaultType?
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

    private func withActuator<T>(fallback: T, _ body: (UnsafeMutableRawPointer) -> T) -> T {
        guard let createDevice = createDefault,
              let getTrackpadActuator = getActuator,
              let release = releaseDevice else { return fallback }

        guard let device = createDevice() else { return fallback }
        defer { release(device) }

        guard let actuator = getTrackpadActuator(device) else { return fallback }
        return body(actuator)
    }
    
    func setHaptics(to enabled: Bool) {
        guard let setSystemEnabled = setEnabled else { return }
        withActuator(fallback: ()) { actuator in
            _ = setSystemEnabled(actuator, enabled ? 1 : 0)
        }
    }
    
    func isEnabled() -> Bool {
        guard let getSystemEnabled = getEnabled else { return true }

        // default to true on fail to prevent bricking trackpad
        return withActuator(fallback: true) { actuator in
            getSystemEnabled(actuator) == 1
        }
    }
}
