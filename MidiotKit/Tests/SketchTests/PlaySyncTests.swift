import Foundation
import Testing
@testable import Sketch

@Suite struct PlaySyncTests {
    private func store() -> PlayStore {
        PlayStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("midiot-sync-\(UUID().uuidString)", isDirectory: true))
    }

    /// The first launch with iCloud on: local plays move in, and nothing already there is lost.
    @Test func localPlaysMoveIntoTheCloudFolder() throws {
        let local = store(), cloud = store()
        let onlyLocal = Play(title: "Only here")
        let same = Play(title: "Same on both")
        var changedHere = Play(title: "Changed")
        let changedThere = changedHere
        changedHere.scenes.append(PlayScene(title: "Act I"))
        try local.save(onlyLocal)
        try local.save(same)
        try local.save(changedHere)
        try cloud.save(same)
        try cloud.save(changedThere)
        let onlyCloud = Play(title: "Only there")
        try cloud.save(onlyCloud)

        let moved = try local.adopt(into: cloud) { "\($0.title) (this device)" }

        #expect(moved == 2)
        #expect(local.plays().isEmpty)
        let titles = cloud.plays().map(\.title).sorted()
        #expect(titles == ["Changed", "Changed (this device)", "Only here", "Only there", "Same on both"])
        // The cloud's own version is untouched; the local one sits beside it, whole.
        #expect(cloud.play(changedThere.id)?.scenes == changedThere.scenes)
        #expect(cloud.plays().first { $0.title == "Changed (this device)" }?.scenes.map(\.title) == ["Act I"])
        // Moving in again does nothing.
        #expect(try local.adopt(into: cloud) { $0.title } == 0)
    }

    @Test func aCopyIsASeparatePlayWithTheSameContent() {
        let play = Play(title: "Dream", scenes: [PlayScene(title: "Act I", cues: [Cue(name: "Overture")])])
        let copy = play.copy(titled: "Dream (iPad)")
        #expect(copy.id != play.id)
        #expect(copy.title == "Dream (iPad)")
        #expect(copy.scenes == play.scenes)
        #expect(copy.createdAt == play.createdAt)
    }

    /// A plain folder has nothing to fetch and nothing in conflict.
    @Test func aLocalFolderNeedsNoSettling() throws {
        let local = store()
        try local.save(Play(title: "Dream"))
        #expect(local.requestDownloads() == 0)
        #expect(local.resolveConflicts { play, _ in play.title } == 0)
        #expect(local.plays().count == 1)
    }
}
