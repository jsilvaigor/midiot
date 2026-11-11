import Foundation
import SwiftMIDIIO
import Testing
@testable import MidiIO

@Suite struct ControlEventTests {
    @Test func padsAndKnobsAreControls() {
        #expect(ControlEvent(.noteOn(40, velocity: .midi1(90), channel: 9), padChannel: 9) == ControlEvent(source: .pad(note: 40), value: 90))
        #expect(ControlEvent(.noteOff(40, velocity: .midi1(0), channel: 9), padChannel: 9) == ControlEvent(source: .pad(note: 40), value: 0))
        #expect(ControlEvent(.cc(21, value: .midi1(64), channel: 0), padChannel: 9) == ControlEvent(source: .controller(number: 21), value: 64))
    }

    @Test func keysAndThePedalAreNot() {
        #expect(ControlEvent(.noteOn(40, velocity: .midi1(90), channel: 0), padChannel: 9) == nil)
        #expect(ControlEvent(.noteOn(40, velocity: .midi1(90), channel: 9), padChannel: nil) == nil)
        #expect(ControlEvent(.cc(.sustainPedal, value: .midi1(127), channel: 0), padChannel: 9) == nil)
    }

    @Test func controlsAreNamedAsOnTheLaunchkey() {
        #expect(ControlSource.pad(note: 40).name == .pad(1))
        #expect(ControlSource.pad(note: 51).name == .pad(8))
        #expect(ControlSource.pad(note: 36).name == .pad(9))
        #expect(ControlSource.pad(note: 47).name == .pad(16))
        #expect(ControlSource.pad(note: 60).name == .note(60))
        #expect(ControlSource.controller(number: 21).name == .knob(1))
        #expect(ControlSource.controller(number: 28).name == .knob(8))
        #expect(ControlSource.controller(number: 1).name == .controller(1))
    }
}

@Suite struct ControlMapTests {
    @Test func theSamePadDoesOneThingWhilePracticingAndAnotherOnStage() {
        let map = ControlMap.launchkeyDefaults
        let second = ControlSource.pad(note: 41)
        #expect(map.action(for: second, in: .practice) == .restart)
        #expect(map.action(for: second, in: .stage) == .cueGo)
        #expect(map.action(for: second, in: .everywhere) == nil)
    }

    @Test func panicAndVolumeWorkEverywhere() {
        let map = ControlMap.launchkeyDefaults
        for context in ControlAction.Context.allCases {
            #expect(map.action(for: .pad(note: 47), in: context) == .panic)
            #expect(map.action(for: .controller(number: 28), in: context) == .volume)
        }
    }

    @Test func everyActionHasADefaultAndNoTwoClash() {
        let map = ControlMap.launchkeyDefaults
        for action in ControlAction.allCases {
            guard let source = map.source(of: action) else {
                Issue.record("no default for \(action)")
                continue
            }
            for context in ControlAction.Context.allCases where context == action.context || action.context == .everywhere {
                #expect(map.action(for: source, in: context) == action)
            }
        }
    }

    @Test func learningAControlTakesItFromTheActionItClashesWith() {
        var map = ControlMap.launchkeyDefaults
        // Pad 2 is Go on stage and Restart in practice. Give it to Stop on stage.
        let tookStop = map.assign(.pad(note: 41), to: .stopLayer)
        #expect(tookStop)
        #expect(map.source(of: .cueGo) == nil)
        #expect(map.source(of: .restart) == .pad(note: 41))
        #expect(map.action(for: .pad(note: 41), in: .stage) == .stopLayer)
        // Giving a pad to panic clears it everywhere.
        let tookPanic = map.assign(.pad(note: 40), to: .panic)
        #expect(tookPanic)
        #expect(map.source(of: .playPause) == nil)
        #expect(map.source(of: .cueBack) == nil)
    }

    @Test func aPadCannotDriveAKnobAction() {
        var map = ControlMap.launchkeyDefaults
        let padOnKnob = map.assign(.pad(note: 40), to: .volume)
        #expect(!padOnKnob)
        #expect(map == .launchkeyDefaults)
        // A controller can press a button action: it fires when its value goes up.
        let buttonOnPad = map.assign(.controller(number: 115), to: .playPause)
        #expect(buttonOnPad)
    }

    @Test func theMapSurvivesSavingAndSkipsActionsItDoesNotKnow() throws {
        var map = ControlMap.launchkeyDefaults
        map.assign(.controller(number: 22), to: .volume)
        map.clear(.tempoUp)
        let data = try JSONEncoder().encode(map)
        #expect(try JSONDecoder().decode(ControlMap.self, from: data) == map)

        let newer = #"[{"action":"somethingNew","source":{"pad":{"note":40}}},{"action":"panic","source":{"pad":{"note":47}}}]"#
        let decoded = try JSONDecoder().decode(ControlMap.self, from: Data(newer.utf8))
        #expect(decoded.sources == [.panic: .pad(note: 47)])
    }

    @Test func padLightsFollowTheMap() {
        let map = ControlMap.launchkeyDefaults
        let pads = DeviceProfile.launchkeyPadNotes
        let stage = map.padLights(in: .stage) { $0 == .fadeOut ? .dim : $0 == .stopLayer ? nil : .bright }
        #expect(stage[pads[0]] == PadLight(.blue)) // back
        #expect(stage[pads[1]] == PadLight(.green)) // go
        #expect(stage[pads[4]] == PadLight(.orange, .dim))
        #expect(stage[pads[5]] == nil)
        #expect(stage[pads[15]] == PadLight(.red)) // panic works everywhere
        #expect(stage.count == 6)
        // The same pads mean something else while practicing.
        #expect(map.padLights(in: .practice)[pads[0]] == PadLight(.green))
    }

    /// In DAW mode the Launchkey Mini reports its drum pads on the DAW port.
    @Test func padsOnTheDAWPortAreControls() {
        let press = LaunchkeyLights.padPress(.noteOn(40, velocity: .midi1(90), channel: 9), deviceID: 7)
        #expect(press == ControlEvent(source: .pad(note: 40), value: 90, deviceID: 7))
        let release = LaunchkeyLights.padPress(.noteOff(40, velocity: .midi1(0), channel: 9), deviceID: 7)
        #expect(release?.value == 0)
        // Session-layout pads and anything on another channel are not drum pads.
        #expect(LaunchkeyLights.padPress(.noteOn(96, velocity: .midi1(90), channel: 0), deviceID: nil) == nil)
        #expect(LaunchkeyLights.padPress(.noteOn(40, velocity: .midi1(90), channel: 0), deviceID: nil) == nil)
    }
}
