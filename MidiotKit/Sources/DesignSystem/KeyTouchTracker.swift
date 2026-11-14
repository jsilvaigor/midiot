import MusicCore

/// Which finger holds which key. Pure bookkeeping, so the touch layer stays thin and testable.
///
/// Several fingers may rest on the same key; it sounds once and is released with the last finger.
struct KeyTouchTracker {
    private var held: [Int: Pitch] = [:]

    /// A key to sound or to stop, in the order the caller should do them.
    enum Change: Equatable {
        case press(Pitch)
        case release(Pitch)
    }

    /// A finger landed, moved, or lifted (`pitch == nil`: it is over no key, or it ended).
    mutating func move(touch: Int, to pitch: Pitch?) -> [Change] {
        let old = held[touch]
        guard old != pitch else { return [] }
        var changes: [Change] = []
        held[touch] = pitch
        if let old, !held.values.contains(old) { changes.append(.release(old)) }
        if let pitch, held.values.count(where: { $0 == pitch }) == 1 { changes.append(.press(pitch)) }
        return changes
    }

    /// Every finger lifted at once: a cancelled touch sequence, or the view going away.
    mutating func releaseAll() -> [Change] {
        let pitches = Set(held.values)
        held.removeAll()
        return pitches.sorted().map { .release($0) }
    }
}
