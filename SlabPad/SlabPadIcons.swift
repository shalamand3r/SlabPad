// SlabPadIcons.swift
// centralized icon names

import Foundation

enum SlabPadIcons {
    // centralize icon names to avoid magic strings
    private static let hapticsOnSymbolName = "rectangle.and.hand.point.up.left.fill"
    private static let hapticsOffSymbolName = "rectangle.and.hand.point.up.left"

    static func menuBarSymbolName(hapticsEnabled: Bool) -> String {
        hapticsEnabled ? hapticsOnSymbolName : hapticsOffSymbolName
    }
}
