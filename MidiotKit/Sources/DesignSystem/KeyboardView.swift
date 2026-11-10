import MusicCore
import SwiftUI

/// An on-screen piano keyboard.
///
/// Keys listed in `highlights` are drawn in the given color and labelled with their note name.
/// Every C is labelled with its octave so the player can find their place.
public struct KeyboardView: View {
    private let range: KeyboardRange
    private let highlights: [Pitch: Color]
    private let naming: NoteNaming
    private let onPress: ((Pitch) -> Void)?
    private let onRelease: ((Pitch) -> Void)?

    @State private var mousePitch: Pitch?

    /// - Parameters:
    ///   - onPress: called when a key is clicked; omit both callbacks for a display-only keyboard.
    ///   - onRelease: called when the click ends or moves to another key.
    public init(
        range: KeyboardRange,
        highlights: [Pitch: Color] = [:],
        naming: NoteNaming = .letters,
        onPress: ((Pitch) -> Void)? = nil,
        onRelease: ((Pitch) -> Void)? = nil
    ) {
        self.range = range
        self.highlights = highlights
        self.naming = naming
        self.onPress = onPress
        self.onRelease = onRelease
    }

    public var body: some View {
        GeometryReader { proxy in
            let layout = KeyboardLayout(range: range, size: proxy.size)
            Canvas { context, _ in
                draw(in: &context, layout: layout)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in moveMouse(to: layout.pitch(at: value.location)) }
                    .onEnded { _ in moveMouse(to: nil) },
                isEnabled: onPress != nil
            )
        }
        .clipShape(.rect(bottomLeadingRadius: Radius.control, bottomTrailingRadius: Radius.control))
        .accessibilityLabel(Text(verbatim: "Keyboard"))
    }

    private func moveMouse(to pitch: Pitch?) {
        guard pitch != mousePitch else { return }
        if let old = mousePitch { onRelease?(old) }
        if let pitch { onPress?(pitch) }
        mousePitch = pitch
    }

    private func draw(in context: inout GraphicsContext, layout: KeyboardLayout) {
        let pitches = range.pitches
        let labelSize = min(max(layout.whiteKeyWidth * 0.34, 8), 12)

        for pitch in pitches where !pitch.isBlackKey {
            let frame = layout.frame(of: pitch).insetBy(dx: 0.5, dy: 0)
            let path = Path(roundedRect: frame, cornerSize: CGSize(width: 3, height: 3))
            if let color = highlights[pitch] {
                context.fill(path, with: .color(Palette.keyWhite))
                context.fill(path, with: .linearGradient(
                    Gradient(colors: [color.opacity(0.55), color]),
                    startPoint: frame.origin, endPoint: CGPoint(x: frame.minX, y: frame.maxY)
                ))
            } else {
                context.fill(path, with: .linearGradient(
                    Gradient(colors: [Palette.keyWhite, Palette.keyWhiteShade]),
                    startPoint: frame.origin, endPoint: CGPoint(x: frame.minX, y: frame.maxY)
                ))
            }

            let isHighlighted = highlights[pitch] != nil
            if isHighlighted || pitch.pitchClass == 0 {
                let text = isHighlighted ? naming.name(of: pitch) : naming.nameWithOctave(of: pitch)
                context.draw(
                    Text(verbatim: text)
                        .font(.system(size: labelSize, weight: isHighlighted ? .semibold : .regular))
                        .foregroundStyle(isHighlighted ? Palette.background : Palette.keyLabel),
                    at: CGPoint(x: frame.midX, y: frame.maxY - labelSize)
                )
            }
        }

        for pitch in pitches where pitch.isBlackKey {
            let frame = layout.frame(of: pitch)
            let path = Path(roundedRect: frame, cornerSize: CGSize(width: 2, height: 2))
            let colors = highlights[pitch].map { [$0.opacity(0.75), $0] } ?? [Palette.keyBlackShade, Palette.keyBlack]
            context.fill(path, with: .linearGradient(
                Gradient(colors: colors),
                startPoint: frame.origin, endPoint: CGPoint(x: frame.minX, y: frame.maxY)
            ))
            if highlights[pitch] != nil, frame.width >= 14 {
                context.draw(
                    Text(verbatim: naming.name(of: pitch))
                        .font(.system(size: labelSize * 0.8, weight: .semibold))
                        .foregroundStyle(Palette.background),
                    at: CGPoint(x: frame.midX, y: frame.maxY - labelSize)
                )
            }
        }
    }
}
