#if os(iOS)
import MusicCore
import SwiftUI
import UIKit

/// Multi-touch input for `KeyboardView`: every finger plays the key under it, so chords work.
/// Sliding to another key releases the old one and presses the new one, as the mouse does.
struct KeyboardTouchLayer: UIViewRepresentable {
    let layout: KeyboardLayout
    let onPress: (Pitch) -> Void
    let onRelease: (Pitch) -> Void

    func makeUIView(context: Context) -> TouchView {
        let view = TouchView()
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: TouchView, context: Context) {
        view.layout = layout
        view.onPress = onPress
        view.onRelease = onRelease
    }

    static func dismantleUIView(_ view: TouchView, coordinator: ()) {
        view.apply(view.tracker.releaseAll())
    }

    final class TouchView: UIView {
        var layout: KeyboardLayout?
        var onPress: ((Pitch) -> Void)?
        var onRelease: ((Pitch) -> Void)?
        var tracker = KeyTouchTracker()

        func apply(_ changes: [KeyTouchTracker.Change]) {
            for change in changes {
                switch change {
                case .press(let pitch): onPress?(pitch)
                case .release(let pitch): onRelease?(pitch)
                }
            }
        }

        private func update(_ touches: Set<UITouch>, ended: Bool) {
            for touch in touches {
                let pitch = ended ? nil : layout?.pitch(at: touch.location(in: self))
                apply(tracker.move(touch: touch.hash, to: pitch))
            }
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches, ended: false) }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches, ended: false) }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches, ended: true) }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches, ended: true) }

        override func willMove(toWindow newWindow: UIWindow?) {
            if newWindow == nil { apply(tracker.releaseAll()) }
        }
    }
}
#endif
