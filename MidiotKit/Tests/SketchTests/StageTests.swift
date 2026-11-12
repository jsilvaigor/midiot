import Foundation
import Testing
@testable import Sketch

@Suite struct StageTests {
    private func take(seconds: Double, bpm: Double = 60, program: Int? = nil) -> Take {
        Take(number: 1, bpm: bpm, layers: [Layer(notes: [SketchNote(pitch: 60, start: 0, duration: seconds * bpm / 60)], program: program)])
    }

    @Test func playsSavedBeforeStagePresetsStillLoad() throws {
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Dawn","note":"","status":"draft","takes":[]}"#
        let cue = try JSONDecoder().decode(Cue.self, from: Data(old.utf8))
        #expect(cue.stage == nil)
        #expect(cue.stagePreset == StagePreset())
    }

    @Test func aCueWithoutAPresetUsesTheSoundOfItsTake() {
        var cue = Cue(name: "Forest", takes: [take(seconds: 10, program: 88)])
        #expect(cue.stagePreset.program == 88)
        cue.stage = StagePreset(program: 48, second: .init(program: 8, splitAt: 60), bpm: 72)
        #expect(cue.stagePreset.program == 48)
    }

    @Test func presetsSurviveSaving() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PlayStore(root: root)
        let preset = StagePreset(program: nil, second: .init(program: 48), bpm: 96)
        let play = Play(title: "Dream", scenes: [PlayScene(title: "I", cues: [Cue(name: "A", stage: preset)])])
        try store.save(play)
        #expect(store.plays().first?.scenes[0].cues[0].stage == preset)
    }

    @Test func presetsWithoutAnExternalChannelLoadAndStayAsTheyWere() throws {
        let old = #"{"program":48,"bpm":90}"#
        let preset = try JSONDecoder().decode(StagePreset.self, from: Data(old.utf8))
        #expect(preset == StagePreset(program: 48, bpm: 90))
        #expect(preset.externalChannel == nil)
        let json = try String(decoding: JSONEncoder().encode(preset), as: UTF8.self)
        #expect(!json.contains("externalChannel"))
    }

    @Test func anExternalChannelSurvivesSaving() throws {
        let preset = StagePreset(program: 5, externalChannel: 13)
        let data = try JSONEncoder().encode(preset)
        let back = try JSONDecoder().decode(StagePreset.self, from: data)
        #expect(back == preset)
        #expect(back.externalChannel == 13)
        #expect(preset != StagePreset(program: 5))
    }

    @Test func theCueSheetRunsThroughScenesInOrder() {
        let play = Play(title: "Dream", scenes: [
            PlayScene(title: "One", cues: [Cue(name: "a"), Cue(name: "b")]),
            PlayScene(title: "Empty"),
            PlayScene(title: "Three", cues: [Cue(name: "c")]),
        ])
        let sheet = CueSheet(play)
        #expect(sheet.entries.map(\.label) == ["1A", "1B", "3A"])
        #expect(sheet.entries.map(\.sceneTitle) == ["One", "One", "Three"])
        #expect(sheet.index(of: play.scenes[2].cues[0].id) == 2)
        #expect(sheet.index(stepping: 1, from: 0) == 1)
        #expect(sheet.index(stepping: 1, from: 2) == 2)
        #expect(sheet.index(stepping: -1, from: 0) == 0)
        #expect(CueSheet(Play(title: "x")).index(stepping: 1, from: 0) == 0)
    }

    @Test func aLayerLongerThanItsTargetFadesOutToEndOnIt() {
        let plan = LayerPlan(take: take(seconds: 60), preset: StagePreset(), targetSeconds: 45)
        #expect(plan.rate == 1)
        #expect(plan.duration == 60)
        #expect(plan.fadeOutStart == 45 - LayerPlan.fadeSeconds)
    }

    @Test func aLayerShorterThanItsTargetPlaysOut() {
        #expect(LayerPlan(take: take(seconds: 30), preset: StagePreset(), targetSeconds: 45).fadeOutStart == nil)
        #expect(LayerPlan(take: take(seconds: 30), preset: StagePreset(), targetSeconds: nil).fadeOutStart == nil)
    }

    @Test func thePresetTempoChangesHowLongTheLayerLasts() {
        let plan = LayerPlan(take: take(seconds: 60, bpm: 60), preset: StagePreset(bpm: 120), targetSeconds: nil)
        #expect(plan.rate == 2)
        #expect(plan.duration == 30)
        // Beat 30 of a 60 bpm take is 30 s in, or 15 s at double speed.
        #expect(plan.seconds(atBeat: 30, bpm: 60) == 15)
    }
}
