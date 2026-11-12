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
        let controls = Mutex<[ControlEvent]>([])
        manager.start(
            onEvent: { event in received.withLock { $0.append(event.kind) } },
            onControl: { event in controls.withLock { $0.append(event) } }
        )
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
        send(0x20B0_1540) // a knob: controller 21 at 64

        try await wait { received.withLock { $0.count } == 3 }
        #expect(received.withLock { $0 } == [
            .noteOn(pitch: .middleC, velocity: 100),
            .sustain(isDown: true),
            .noteOff(pitch: .middleC),
        ])
        try await wait { controls.withLock { $0.count } == 1 }
        #expect(controls.withLock { $0.map(\.source) } == [.controller(number: 21)])
        #expect(controls.withLock { $0.map(\.value) } == [64])

        MIDIEndpointDispose(source)
        try await wait { !manager.devices.contains { $0.name == "Midiot Test Keyboard" } }
        MIDIClientDispose(client)
    }

    /// A stand-in for the Launchkey's DAW port receives the take-over and the pad colours.
    @MainActor @Test func padLights() async throws {
        let manager = DeviceManager()
        manager.start(onEvent: { _ in })
        let words = Mutex<[UInt32]>([])

        var client = MIDIClientRef()
        MIDIClientCreateWithBlock("MidiotLightTests" as CFString, &client, nil)
        let port = Self.destination(named: "Launchkey Mini MK3 DAW Port", client: client) { new in
            words.withLock { $0 += new }
        }

        // DAW mode on (channel 16, note 12), then the Drum layout (controller 3 = 1).
        try await wait { words.withLock { $0.count } >= 2 }
        #expect(words.withLock { Array($0.prefix(2)) } == [0x209F_0C7F, 0x20BF_0301])

        // Checked by what arrives at all, not by order: a running copy of the app sees this
        // port too and sends it its own colours.
        func received(_ word: UInt32) -> Bool { words.withLock { $0.contains(word) } }

        manager.setPadLights([40: PadLight(.blue), 41: PadLight(.green, .pulsing), 42: PadLight(.yellow, .dim)])
        try await wait { received(0x2099_2A0F) } // pad 3 dim yellow
        try await wait { received(0x2099_282D) } // pad 1 steady blue
        try await wait { received(0x209B_2915) } // pad 2 pulsing green
        try await wait { received(0x2089_2400) } // the others are told to go dark

        manager.setPadLights([40: PadLight(.blue), 41: PadLight(.green), 42: PadLight(.yellow, .dim)])
        try await wait { received(0x2099_2915) }

        words.withLock { $0 = [] }
        manager.releasePadLights()
        try await wait { words.withLock { $0.contains { $0 & 0xFFEF_FF00 == 0x208F_0C00 } } } // note 12 off, channel 16

        MIDIEndpointDispose(port)
        MIDIClientDispose(client)
    }

    /// What the app plays reaches the chosen destination, and stops when MIDI out is turned off.
    @MainActor @Test func midiOut() async throws {
        let manager = DeviceManager()
        manager.start(onEvent: { _ in })
        let words = Mutex<[UInt32]>([])
        var client = MIDIClientRef()
        MIDIClientCreateWithBlock("MidiotOutTests" as CFString, &client, nil)
        let port = Self.destination(named: "Midiot Test Synth", client: client) { new in
            words.withLock { $0 += new }
        }
        func received(_ word: UInt32) -> Bool { words.withLock { $0.contains(word) } }

        try await wait { manager.destinations.contains { $0.name == "Midiot Test Synth" } }
        let synth = try #require(manager.destinations.first { $0.name == "Midiot Test Synth" })

        // Nothing is sent until a destination is chosen.
        manager.out.noteOn(60, velocity: 100, channel: 0)
        manager.setOutput(.destination(id: synth.id, name: synth.name))
        try await Task.sleep(for: .milliseconds(200))
        manager.out.program(48, channel: 2)
        manager.out.noteOn(62, velocity: 90, channel: 2)
        manager.out.controller(7, value: 64, channel: 2)
        manager.out.noteOff(62, channel: 2)
        try await wait { received(0x2082_3E00) }
        #expect(received(0x20C2_3000))
        #expect(received(0x2092_3E5A))
        #expect(received(0x20B2_0740))
        #expect(!received(0x2090_3C64))

        // Turning it off releases everything first.
        manager.setOutput(.off)
        try await wait { received(0x20BF_7B00) }
        words.withLock { $0 = [] }
        manager.out.noteOn(64, velocity: 100, channel: 0)
        try await Task.sleep(for: .milliseconds(200))
        #expect(words.withLock { $0.isEmpty })

        MIDIEndpointDispose(port)
        MIDIClientDispose(client)
    }

    /// The port the app offers to other apps must not be heard by the app itself: what it
    /// played would be played again, sent again, and so on for ever.
    @MainActor @Test func theAppDoesNotHearItsOwnPort() async throws {
        let heard = Mutex(0)
        let manager = DeviceManager()
        manager.start(onEvent: { [out = manager.out] event in
            heard.withLock { $0 += 1 }
            // What the app does with playing while MIDI out is on.
            if case let .noteOn(pitch, velocity) = event.kind { out.noteOn(pitch.midiNumber, velocity: velocity, channel: 0) }
        })
        manager.setOutput(.otherApps)
        try await Task.sleep(for: .milliseconds(300))
        manager.out.noteOn(60, velocity: 100, channel: 0)
        manager.out.noteOff(60, channel: 0)
        try await Task.sleep(for: .milliseconds(300))
        #expect(heard.withLock { $0 } == 0)
        #expect(!manager.devices.contains { $0.name == "Midiot" })
        manager.setOutput(.off)
    }

    /// Another app listening to the port named Midiot receives what the app plays.
    @MainActor @Test func otherAppsHearThePort() async throws {
        let manager = DeviceManager()
        manager.start(onEvent: { _ in })
        manager.setOutput(.otherApps)
        try await Task.sleep(for: .milliseconds(300))

        let words = Mutex<[UInt32]>([])
        var client = MIDIClientRef()
        MIDIClientCreateWithBlock("MidiotListenerTests" as CFString, &client, nil)
        let port = Self.listener(client: client) { new in words.withLock { $0 += new } }
        var found = 0
        for index in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(index)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(source, kMIDIPropertyName, &name)
            guard name?.takeRetainedValue() as String? == "Midiot" else { continue }
            MIDIPortConnectSource(port, source, nil)
            found += 1
        }
        #expect(found >= 1)

        manager.out.noteOn(61, velocity: 99, channel: 4)
        try await wait { words.withLock { $0.contains(0x2094_3D63) } }

        manager.setOutput(.off)
        MIDIPortDispose(port)
        MIDIClientDispose(client)
    }

    private nonisolated static func listener(client: MIDIClientRef, receive: @escaping @Sendable ([UInt32]) -> Void) -> MIDIPortRef {
        var port = MIDIPortRef()
        MIDIInputPortCreateWithProtocol(client, "listener" as CFString, ._1_0, &port) { list, _ in
            for packet in list.unsafeSequence() { receive(Array(packet.sequence())) }
        }
        return port
    }

    /// A virtual MIDI destination. Made outside the main actor because it is called on the
    /// MIDI thread.
    private nonisolated static func destination(
        named name: String, client: MIDIClientRef, receive: @escaping @Sendable ([UInt32]) -> Void
    ) -> MIDIEndpointRef {
        var port = MIDIEndpointRef()
        MIDIDestinationCreateWithProtocol(client, name as CFString, ._1_0, &port) { list, _ in
            for packet in list.unsafeSequence() { receive(Array(packet.sequence())) }
        }
        return port
    }

    /// Polls until `condition` holds, failing after two seconds.
    @MainActor private func wait(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        for _ in 0..<40 where !condition() {
            try await Task.sleep(for: .milliseconds(50))
        }
        try #require(condition(), sourceLocation: sourceLocation)
    }
}
