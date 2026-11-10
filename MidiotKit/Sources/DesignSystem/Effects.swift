import SwiftUI

public extension View {
    /// The warm glow around anything lit by the accent.
    func filamentGlow(_ color: Color = Palette.accent, radius: CGFloat = 14) -> some View {
        shadow(color: color.opacity(0.55), radius: radius)
    }

    /// Frosted panel for controls that float over moving content, such as the
    /// wait-mode chip over falling notes. Static panels use `Palette.surface` instead.
    func glassPanel(cornerRadius: CGFloat = Radius.panel) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(Palette.glass, in: shape)
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(Palette.hairline))
    }
}

/// Screen background: deep charcoal with a faint warm light rising from the bottom edge,
/// where the hit line sits on the practice screen.
public struct FilamentBackground: View {
    public init() {}

    public var body: some View {
        Palette.background
            .overlay(alignment: .bottom) {
                GeometryReader { proxy in
                    RadialGradient(
                        colors: [Palette.accent.opacity(0.07), .clear],
                        center: .bottom,
                        startRadius: 0,
                        endRadius: max(proxy.size.width, proxy.size.height) * 0.6
                    )
                }
            }
            .ignoresSafeArea()
    }
}
