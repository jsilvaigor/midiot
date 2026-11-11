import MusicCore
import SwiftMIDIIO
import Testing
@testable import MidiIO

@Suite struct DeviceProfileTests {
    @Test func matchesSupportedKeyboards() {
        #expect(DeviceProfile.matching(deviceName: "A-49").model == .rolandA49)
        #expect(DeviceProfile.matching(deviceName: "Launchkey Mini MK3").model == .launchkeyMiniMK3)
        #expect(DeviceProfile.matching(deviceName: "IAC Driver").model == .generic)
    }

    @Test func largestKeyboardIsTheMainInstrument() {
        let mini = ConnectedDevice(id: 1, name: "Launchkey Mini MK3", profile: .launchkeyMiniMK3)
        let a49 = ConnectedDevice(id: 2, name: "A-49", profile: .rolandA49)
        #expect([mini, a49].mainInstrument == a49)
        #expect([mini].mainInstrument == mini)
        #expect([ConnectedDevice]().mainInstrument == nil)
    }
}

@Suite struct EventTranslationTests {
    @Test func notes() {
        let on = PerformanceEvent.Kind(.noteOn(60, velocity: .midi1(100), channel: 0), padChannel: nil)
        #expect(on == .noteOn(pitch: .middleC, velocity: 100))
        let off = PerformanceEvent.Kind(.noteOff(60, velocity: .midi1(0), channel: 0), padChannel: nil)
        #expect(off == .noteOff(pitch: .middleC))
    }

    @Test func noteOnWithZeroVelocityIsNoteOff() {
        let kind = PerformanceEvent.Kind(.noteOn(60, velocity: .midi1(0), channel: 0), padChannel: nil)
        #expect(kind == .noteOff(pitch: .middleC))
    }

    @Test func sustainPedal() {
        #expect(PerformanceEvent.Kind(.cc(.sustainPedal, value: .midi1(127), channel: 0), padChannel: nil) == .sustain(isDown: true))
        #expect(PerformanceEvent.Kind(.cc(.sustainPedal, value: .midi1(0), channel: 0), padChannel: nil) == .sustain(isDown: false))
    }

    @Test func padsAndKnobsAreNotPlaying() {
        #expect(PerformanceEvent.Kind(.noteOn(36, velocity: .midi1(100), channel: 9), padChannel: 9) == nil)
        #expect(PerformanceEvent.Kind(.cc(21, value: .midi1(64), channel: 0), padChannel: 9) == nil)
    }
}
