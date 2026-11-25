// ToastManager.swift
// manages in-app toasts

import SwiftUI
import Combine

enum ToastType {
    case success(LocalizedStringKey)
    case error(LocalizedStringKey)
}

struct Toast: Identifiable {
    let id = UUID()
    let type: ToastType
}

@MainActor
final class ToastManager: ObservableObject {
    @Published private(set) var toasts: [Toast] = []
    private var timers: [UUID: AnyCancellable] = [:]
    
    func show(_ type: ToastType) {
        let toast = Toast(type: type)
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            toasts.append(toast)
        }
        
        timers[toast.id] = Just(())
            .delay(for: .seconds(2.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.dismiss(toast.id)
            }
    }

    private func dismiss(_ id: UUID) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            toasts.removeAll { $0.id == id }
        }
        timers.removeValue(forKey: id)
    }
}
