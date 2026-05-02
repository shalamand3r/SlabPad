import SwiftUI
import Combine

enum ToastType: Equatable {
    case info(String, systemImage: String? = nil)
    case success(String)
    case error(String)
    case warning(String)
    case invert(isRightClick: Bool)
    case upToDate
    case reset(progress: Double, countdown: Int, isTriggered: Bool)
    
    var icon: String? {
        switch self {
        case .info(_, let systemImage): return systemImage ?? "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .invert(let isRight): return isRight ? "rectangle.rightthird.inset.filled" : "rectangle.leftthird.inset.filled"
        case .upToDate: return "checkmark.circle.fill"
        case .reset: return nil
        }
    }
    
    var iconColor: Color {
        switch self {
        case .info: return .blue
        case .success: return .green
        case .error: return .red
        case .warning: return .orange
        case .invert: return .secondary
        case .upToDate: return .green
        case .reset: return .red
        }
    }
}

struct Toast: Identifiable, Equatable {
    let id: UUID
    let type: ToastType
    var duration: Double?
    
    init(id: UUID = UUID(), type: ToastType, duration: Double? = 2.5) {
        self.id = id
        self.type = type
        self.duration = duration
    }
    
    static func == (lhs: Toast, rhs: Toast) -> Bool {
        lhs.id == rhs.id && lhs.type == rhs.type
    }
}

class ToastManager: ObservableObject {
    @Published var toasts: [Toast] = []
    private var timers: [UUID: AnyCancellable] = [:]
    
    func show(_ type: ToastType, duration: Double? = 2.5) {
        let toast = Toast(type: type, duration: duration)
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            toasts.append(toast)
        }
        
        if let duration = duration {
            let timer = Just(())
                .delay(for: .seconds(duration), scheduler: RunLoop.main)
                .sink { [weak self] _ in
                    self?.dismiss(toast.id)
                }
            timers[toast.id] = timer
        }
    }
    
    func dismiss(_ id: UUID) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            toasts.removeAll { $0.id == id }
        }
        timers.removeValue(forKey: id)
    }
    
    func updateResetToast(progress: Double, countdown: Int, isTriggered: Bool) {
        if let index = toasts.firstIndex(where: { 
            if case .reset = $0.type { return true }
            return false
        }) {
            let existingToast = toasts[index]
            toasts[index] = Toast(id: existingToast.id, type: .reset(progress: progress, countdown: countdown, isTriggered: isTriggered), duration: nil)
        } else {
            show(.reset(progress: progress, countdown: countdown, isTriggered: isTriggered), duration: nil)
        }
    }
    
    func hideResetToast() {
        if let toast = toasts.first(where: { 
            if case .reset = $0.type { return true }
            return false
        }) {
            dismiss(toast.id)
        }
    }
}
