import CoreMIDI
import Foundation
import MusicCore
import Synchronization
import Testing
@testable import MidiIO

/// End-to-end check through the real system MIDI service, using a virtual keyboard in place of
/// hardware: it appears, plays, and disappears while `DeviceManager` is running.
@Suite(.serialized) struct VirtualKeyboardTests {
    @MainActor @Test func hotPlugAndPlaying() async throws {
        let received = Mutex<[PerformanceEvent.Kind]>([])
        let manager = DeviceManager()
        manager.start { event in received.withLock { $0.append(event.kind) } }
        #expect(manager.startError == nil)

        var client = MIDIClientRef()
        MIDIClientCreateWithBlock("MidiotTests" as CFString, &client, nil)
        var source = MIDIEndpointRef()
        MIDISourceCreateWithProtocol(client, "Midiot Test Keyboard" as CFString, ._1_0, &source)

        try await wait { manager.devices.contains { $0.name == "Midiot Test Keyboard" } }

        func send(_ word: UInt32) {
            var list = MIDIEventList()
            let packet = MIDIEventListInit(&list, ._1_0)
            _ = MIDIEventListAdd(&list, 1024, packet, 0, 1, [word])
            MIDIReceivedEventList(source, &list)
        }
        send(0x2090_3C64) // note on, middle C, velocity 100
        send(0x20B0_407F) // sustain pedal down
        send(0x2080_3C00) // note off, middle C

        try await wait { received.withLock { $0.count } == 3 }
        #expect(received.withLock { $0 } == [
            .noteOn(pitch: .middleC, velocity: 100),
            .sustain(isDown: true),
            .noteOff(pitch: .middleC),
        ])

        MIDIEndpointDispose(source)
        try await wait { !manager.devices.contains { $0.name == "Midiot Test Keyboard" } }
        MIDIClientDispose(client)
    }

    /// Polls until `condition` holds, failing after two seconds.
    @MainActor private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<40 where !condition() {
            try await Task.sleep(for: .milliseconds(50))
        }
        try #require(condition())
    }
}
