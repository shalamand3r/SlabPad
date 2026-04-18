// SlabPadIcons.swift
// centralized icon names

import Foundation

enum SlabPadIcons {
    // centralize icon names to avoid magic strings
    static let hapticsOnSymbolName = "rectangle.and.hand.point.up.left.fill"
    static let hapticsOffSymbolName = "rectangle.and.hand.point.up.left"

    static func menuBarSymbolName(hapticsEnabled: Bool) -> String {
        hapticsEnabled ? hapticsOnSymbolName : hapticsOffSymbolName
    }
}
