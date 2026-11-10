import MusicCore

/// Anything that can turn notes into sound.
///
/// The built-in sampler is the first implementation. MIDI output to other apps and hosted
/// Audio Unit instruments will implement the same protocol (requirement SN-3).
/// Methods may be called from any thread, including the MIDI thread.
public protocol Instrument: AnyObject, Sendable {
    /// - Parameter velocity: 1...127.
    func noteOn(_ pitch: Pitch, velocity: Int)
    func noteOff(_ pitch: Pitch)
    func setSustain(_ isDown: Bool)
    /// Silences everything, including notes held by the sustain pedal.
    func allNotesOff()
}
