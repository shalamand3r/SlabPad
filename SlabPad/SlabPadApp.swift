// SlabPadApp.swift
// app entry point and lifecycle

import SwiftUI
import Combine

extension Notification.Name {
    static let slabPadPopoverNeedsResize = Notification.Name("slabpad.popoverNeedsResize")
    static let slabPadRequestQuit = Notification.Name("slabpad.requestQuit")
    static let slabPadRequestResetAndQuit = Notification.Name("slabpad.resetAndQuit")
    static let slabPadRequestOpenUpdate = Notification.Name("slabpad.openUpdate")
}

@main
struct SlabPadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            // menubar only, no settings window
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let manager = SlabPadManager.shared
    private var statusBarItem: NSStatusItem!
    private var popover: NSPopover!
    private var cancellables = Set<AnyCancellable>()

    private let popoverWidth: CGFloat = 288
    private let maxPopoverHeight: CGFloat = 500
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // hide dock icon
        NSApp.setActivationPolicy(.accessory)
        
        popover = NSPopover()
        popover.contentSize = NSSize(width: popoverWidth, height: 10)
        popover.behavior = .transient
        // bridge swiftui to appkit popover
        popover.contentViewController = NSHostingController(rootView: ContentView())
        
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusBarItem.button {
            // left + right click both do things
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.action = #selector(handleMenuBarClick)
            updateIcon()
        }

        manager.$isHapticsEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // keep icon in sync
                self?.updateIcon()
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePopoverNeedsResize),
            name: .slabPadPopoverNeedsResize,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleQuitRequest),
            name: .slabPadRequestQuit,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleResetAndQuitRequest),
            name: .slabPadRequestResetAndQuit,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenUpdateRequest(_:)),
            name: .slabPadRequestOpenUpdate,
            object: nil
        )
        
        // auto-open on first launch
        if !manager.hasLaunchedBefore {
            manager.hasLaunchedBefore = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.togglePopover()
            }
        }
    }
    
    @objc private func handleWake(_ notification: Notification) {
        // macos sleep sometimes resets haptics, force reapply
        manager.applyHapticsStateToSystem()
        updateIcon()
    }
    
    @objc private func handleMenuBarClick() {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
        
        // handle click inversion logic
        switch (manager.invertClicks, isRightClick) {
        case (true, true), (false, false):
            togglePopover()
        case (true, false), (false, true):
            manager.toggleHapticsEnabled()
        }
    }
    
    private func updateIcon() {
        guard let button = statusBarItem.button else { return }
        let iconName = SlabPadIcons.menuBarSymbolName(hapticsEnabled: manager.isHapticsEnabled)
        button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "SlabPad")
    }
    
    private func togglePopover() {
        guard let button = statusBarItem.button else { return }

        if popover.isShown {
            // close if already open
            popover.performClose(nil)
            return
        }

        adjustPopoverSize()

        // anchor popover to menubar icon
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc private func handlePopoverNeedsResize() {
        guard popover.isShown else { return }
        adjustPopoverSize()
    }

    private func adjustPopoverSize() {
        guard let view = popover.contentViewController?.view else { return }
        view.layoutSubtreeIfNeeded()

        var size = view.fittingSize
        size.width = popoverWidth
        size.height = max(10, min(maxPopoverHeight, size.height))
        popover.contentSize = size
    }

    @objc private func handleQuitRequest() {
        let showPressedStateDelay: TimeInterval = 0.20
        DispatchQueue.main.asyncAfter(deadline: .now() + showPressedStateDelay) { [weak self] in
            self?.closePopoverAndQuit(relaunch: false)
        }
    }
    
    @objc private func handleResetAndQuitRequest() {
        resetAppDefaultsForTesting()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.closePopoverAndQuit(relaunch: true)
        }
    }
    
    private func resetAppDefaultsForTesting() {
        let defaults = UserDefaults.standard

        // keep language/locale behavior intact; only reset our own app prefs
        let keysToReset: [String] = [
            "disableOnLaunch",
            "reEnableOnQuit",
            "invertClicks",
            "hasLaunchedBefore",
            "showBottomHint",
        ]

        keysToReset.forEach(defaults.removeObject(forKey:))
    }
    
    private func closePopoverAndQuit(relaunch: Bool) {
        let quitAfterCloseDelay: TimeInterval = 0.08
        popover.performClose(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + quitAfterCloseDelay) { [weak self] in
            if relaunch {
                self?.relaunchApp()
            }
            NSApplication.shared.terminate(nil)
        }
    }
    
    private func relaunchApp() {
        let url = Bundle.main.bundleURL
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", url.path]
        try? process.run()
    }
    
    @objc private func handleOpenUpdateRequest(_ notification: Notification) {
        guard let url = notification.object as? URL else { return }

        let showPressedStateDelay: TimeInterval = 0.20
        DispatchQueue.main.asyncAfter(deadline: .now() + showPressedStateDelay) { [weak self] in
            NSWorkspace.shared.open(url)
            self?.popover.performClose(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if manager.reEnableOnQuit {
            // restore haptics on exit
            HapticsManager.shared.setHaptics(to: true)
        }
    }
}
