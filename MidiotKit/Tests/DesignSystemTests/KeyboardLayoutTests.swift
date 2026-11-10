import CoreGraphics
import MusicCore
import Testing
@testable import DesignSystem

@Suite struct KeyboardLayoutTests {
    // 25 keys = 15 white keys; 150 pt wide gives 10 pt per white key.
    let layout = KeyboardLayout(range: .twentyFiveKeys, size: CGSize(width: 150, height: 100))

    @Test func whiteKeysTileTheWidth() {
        #expect(layout.whiteKeyWidth == 10)
        #expect(layout.frame(of: Pitch(midiNumber: 48)).minX == 0)
        #expect(layout.frame(of: Pitch(midiNumber: 50)).minX == 10)
        #expect(layout.frame(of: Pitch(midiNumber: 72)).maxX == 150)
    }

    @Test func blackKeyStraddlesItsNeighbours() {
        let cSharp = layout.frame(of: Pitch(midiNumber: 49))
        #expect(cSharp.midX == 10)
        #expect(cSharp.height < 100)
    }

    @Test func hitTesting() {
        #expect(layout.pitch(at: CGPoint(x: 5, y: 90)) == Pitch(midiNumber: 48))
        #expect(layout.pitch(at: CGPoint(x: 10, y: 10)) == Pitch(midiNumber: 49))
        #expect(layout.pitch(at: CGPoint(x: 10.5, y: 90)) == Pitch(midiNumber: 50))
        #expect(layout.pitch(at: CGPoint(x: 200, y: 10)) == nil)
    }
}
