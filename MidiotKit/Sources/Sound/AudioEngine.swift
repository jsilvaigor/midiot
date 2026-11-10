import AVFoundation

/// Owns the audio graph and keeps output latency low (requirement SN-5).
public final class AudioEngine: @unchecked Sendable {
    /// Output delay the app can account for, in seconds.
    public struct Latency: Hashable, Sendable {
        /// Delay added by the audio buffer the app asks for.
        public let buffer: TimeInterval
        /// Delay reported by the output device itself (large for Bluetooth).
        public let device: TimeInterval
        public var total: TimeInterval { buffer + device }
    }

    /// Requested buffer size in frames. 128 frames is about 3 ms at 44.1 kHz.
    public static let preferredBufferFrames: UInt32 = 128

    private let engine = AVAudioEngine()
    private var observer: NSObjectProtocol?

    public init() {}

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    public func attach(_ instrument: SamplerInstrument) {
        engine.attach(instrument.node)
        engine.connect(instrument.node, to: engine.mainMixerNode, format: nil)
    }

    public func start() throws {
        applyBufferSize()
        try engine.start()
        if observer == nil {
            // Fired when the output device changes, for example headphones plugged in.
            observer = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
            ) { [weak self] _ in
                guard let self else { return }
                self.applyBufferSize()
                try? self.engine.start()
            }
        }
    }

    public var latency: Latency {
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let buffer = sampleRate > 0 ? Double(currentBufferFrames()) / sampleRate : 0
        return Latency(buffer: buffer, device: engine.outputNode.presentationLatency)
    }

    private func applyBufferSize() {
        guard let unit = engine.outputNode.audioUnit else { return }
        var frames = Self.preferredBufferFrames
        // The device may refuse or clamp the request; `latency` reports what it actually uses.
        AudioUnitSetProperty(
            unit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0,
            &frames, UInt32(MemoryLayout<UInt32>.size)
        )
    }

    private func currentBufferFrames() -> UInt32 {
        guard let unit = engine.outputNode.audioUnit else { return 0 }
        var frames: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioUnitGetProperty(unit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0, &frames, &size)
        return frames
    }
}
