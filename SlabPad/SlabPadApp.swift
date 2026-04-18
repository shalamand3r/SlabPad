// SlabPadApp.swift
// app entry point and lifecycle

import SwiftUI
import Combine

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
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // hide dock icon
        NSApp.setActivationPolicy(.accessory)
        
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 340)
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

        // anchor popover to menubar icon
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if manager.reEnableOnQuit {
            // restore haptics on exit
            HapticsManager.shared.setHaptics(to: true)
        }
    }
}
