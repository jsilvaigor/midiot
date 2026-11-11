import Foundation
import Testing
@testable import Sketch

@Suite struct LayerTests {
    private func layer(_ pitch: Int, program: Int? = nil, muted: Bool = false) -> Layer {
        Layer(notes: [SketchNote(pitch: pitch, start: 0, duration: 1)], program: program, isMuted: muted)
    }

    @Test func layersSavedBeforeMutingStillLoad() throws {
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","notes":[{"pitch":60,"start":0,"duration":1,"velocity":80}],"program":48}"#
        let layer = try JSONDecoder().decode(Layer.self, from: Data(old.utf8))
        #expect(layer.isMuted == false)
        #expect(layer.program == 48)
    }

    @Test func mutingSurvivesEncoding() throws {
        let data = try JSONEncoder().encode(layer(60, muted: true))
        #expect(try JSONDecoder().decode(Layer.self, from: data).isMuted)
    }

    @Test func updatingALayerChangesOnlyThatLayer() {
        let take = Take(number: 1, bpm: 90, layers: [layer(60), layer(64)])
        let target = take.layers[1].id
        let changed = take.updatingLayer(target) { $0.program = 48; $0.isMuted = true }
        #expect(changed.layers[0] == take.layers[0])
        #expect(changed.layers[1].program == 48)
        #expect(changed.layers[1].isMuted)
        #expect(take.updatingLayer(UUID()) { $0.program = 1 } == take)
    }

    @Test func deletingALayerKeepsTheOthers() {
        let take = Take(number: 1, bpm: 90, layers: [layer(60), layer(64), layer(67)])
        let result = take.deletingLayer(take.layers[1].id)
        #expect(result?.layers.map { $0.notes[0].pitch } == [60, 67])
    }

    @Test func theOnlyLayerCannotBeDeletedFromATake() {
        let take = Take(number: 1, bpm: 90, layers: [layer(60)])
        #expect(take.deletingLayer(take.layers[0].id) == nil)
    }

    @Test func mutedLayersAreLeftOutOfTheSongButKeepTheirIndexes() {
        let take = Take(number: 1, bpm: 90, layers: [layer(60, muted: true), layer(64), layer(67)])
        let (song, layerOfNote) = take.song(title: "")
        #expect(song.notes.map(\.pitch.midiNumber) == [64, 67])
        #expect(layerOfNote == [1, 2])
        #expect(take.song(title: "", includingMuted: true).song.notes.count == 3)
        // Counting and editing still see every layer.
        #expect(take.noteCount == 3)
    }

    @Test func cueUpdatesATakeByID() {
        let take = Take(number: 1, bpm: 90, layers: [layer(60)])
        var cue = Cue(name: "A", takes: [take])
        cue.updateTake(take.id) { $0.isKeeper = true }
        #expect(cue.takes[0].isKeeper)
        cue.updateTake(UUID()) { $0.isKeeper = false }
        #expect(cue.takes[0].isKeeper)
    }
}
