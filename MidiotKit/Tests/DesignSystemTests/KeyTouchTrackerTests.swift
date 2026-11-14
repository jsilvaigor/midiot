import CoreGraphics
import MusicCore
import Testing
@testable import DesignSystem

@Suite struct KeyTouchTrackerTests {
    let c = Pitch(midiNumber: 60)
    let e = Pitch(midiNumber: 64)

    @Test func fingersPlayAChord() {
        var tracker = KeyTouchTracker()
        #expect(tracker.move(touch: 1, to: c) == [.press(c)])
        #expect(tracker.move(touch: 2, to: e) == [.press(e)])
        #expect(tracker.move(touch: 1, to: nil) == [.release(c)])
    }

    @Test func slidingReleasesTheOldKeyThenPressesTheNew() {
        var tracker = KeyTouchTracker()
        _ = tracker.move(touch: 1, to: c)
        #expect(tracker.move(touch: 1, to: c).isEmpty)
        #expect(tracker.move(touch: 1, to: e) == [.release(c), .press(e)])
    }

    @Test func sharedKeyIsReleasedWithTheLastFinger() {
        var tracker = KeyTouchTracker()
        #expect(tracker.move(touch: 1, to: c) == [.press(c)])
        #expect(tracker.move(touch: 2, to: c).isEmpty)
        #expect(tracker.move(touch: 1, to: nil).isEmpty)
        #expect(tracker.move(touch: 2, to: nil) == [.release(c)])
    }

    @Test func cancelReleasesEverything() {
        var tracker = KeyTouchTracker()
        _ = tracker.move(touch: 1, to: c)
        _ = tracker.move(touch: 2, to: e)
        #expect(tracker.releaseAll() == [.release(c), .release(e)])
        #expect(tracker.releaseAll().isEmpty)
    }

    @Test func blackKeysWinOverTheWhiteKeysUnderThem() {
        let layout = KeyboardLayout(range: .twentyFiveKeys, size: CGSize(width: 150, height: 100))
        // On the line between C and D, in the black key's height, then below it.
        #expect(layout.pitch(at: CGPoint(x: 9, y: 50)) == Pitch(midiNumber: 49))
        #expect(layout.pitch(at: CGPoint(x: 9, y: 70)) == Pitch(midiNumber: 48))
    }
}
