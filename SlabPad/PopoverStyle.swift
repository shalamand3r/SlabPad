import SwiftUI
import AppKit

struct PopoverPalette {
    let scheme: ColorScheme

    private var isDark: Bool { scheme == .dark }

    var secondary: Color {
        Color.primary.opacity(isDark ? 0.87 : 0.73)
    }

    var accent: Color {
        let accent = NSColor.controlAccentColor
        let adjustment: NSColor = isDark ? .white : .black
        return Color(accent.blended(withFraction: isDark ? 0.46 : 0.34, of: adjustment) ?? accent)
    }

    var success: Color {
        isDark ? Color(red: 0.54, green: 0.85, blue: 0.68) : Color(red: 0.12, green: 0.42, blue: 0.29)
    }

    var destructive: Color {
        isDark ? Color(red: 1, green: 0.57, blue: 0.60) : Color(red: 0.64, green: 0.16, blue: 0.24)
    }

    func actionFill(hapticsEnabled: Bool) -> Color {
        if hapticsEnabled {
            return Color(red: 0.77, green: 0.17, blue: 0.26)
        }

        let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB)
            ?? NSColor(srgbRed: 0.16, green: 0.40, blue: 0.78, alpha: 1)
        // Darken brighter system accents enough to keep the white action label legible.
        let luminance = 0.2126 * pow(accent.redComponent, 2.2)
            + 0.7152 * pow(accent.greenComponent, 2.2)
            + 0.0722 * pow(accent.blueComponent, 2.2)
        let scale = pow(0.15 / max(0.15, luminance), 1.0 / 2.2)
        return Color(
            red: accent.redComponent * scale,
            green: accent.greenComponent * scale,
            blue: accent.blueComponent * scale
        )
    }
}

struct PopoverSurface<Outline: InsettableShape>: View {
    @Environment(\.colorScheme) private var appearance
    @Environment(\.colorSchemeContrast) private var contrast

    let shape: Outline
    var tint: Color? = nil

    var body: some View {
        let isDark = appearance == .dark
        let fill = tint?.opacity(isDark ? 0.16 : 0.09) ?? Color.primary.opacity(isDark ? 0.07 : 0.043)
        let edgeOpacity = contrast == .increased ? 0.28 : (isDark ? 0.14 : 0.09)
        let edge = tint?.opacity(edgeOpacity + 0.07) ?? Color.primary.opacity(edgeOpacity)
        shape
            .fill(fill)
            .overlay(shape.strokeBorder(edge, lineWidth: 1))
    }
}

struct PopoverIcon: View {
    @Environment(\.colorScheme) private var appearance
    @State private var isHovering = false

    let symbol: String
    var size: CGFloat = 28
    var tint: Color? = nil

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundColor(tint ?? PopoverPalette(scheme: appearance).secondary)
            .frame(width: size, height: size)
            .background(
                PopoverSurface(shape: RoundedRectangle(cornerRadius: 8, style: .continuous), tint: tint)
                    .opacity(isHovering || tint != nil ? 1 : 0)
            )
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.14), value: isHovering)
    }
}
