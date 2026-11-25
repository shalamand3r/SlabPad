// ToastManager.swift
// manages in-app toasts

import SwiftUI
import Combine

@MainActor
final class ToastManager: ObservableObject {
    @Published private(set) var updateErrorIDs: [UUID] = []
    private var timers: [UUID: AnyCancellable] = [:]
    
    func showUpdateError() {
        let id = UUID()
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            updateErrorIDs.append(id)
        }
        
        timers[id] = Just(())
            .delay(for: .seconds(2.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.dismiss(id)
            }
    }

    private func dismiss(_ id: UUID) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            updateErrorIDs.removeAll { $0 == id }
        }
        timers.removeValue(forKey: id)
    }
}
