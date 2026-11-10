/// How pitch names are written for the user (requirement SP-7).
public enum NoteNaming: String, CaseIterable, Sendable {
    /// C D E F G A B
    case letters
    /// Dó Ré Mi Fá Sol Lá Si
    case solfege

    private var naturals: [String] {
        switch self {
        case .letters: ["C", "D", "E", "F", "G", "A", "B"]
        case .solfege: ["Dó", "Ré", "Mi", "Fá", "Sol", "Lá", "Si"]
        }
    }

    /// Name of a pitch class, spelling black keys as sharps: "F♯" or "Fá♯".
    public func name(of pitch: Pitch) -> String {
        // Index of the natural at or below each pitch class, and whether it is sharpened.
        let steps: [(natural: Int, sharp: Bool)] = [
            (0, false), (0, true), (1, false), (1, true), (2, false), (3, false),
            (3, true), (4, false), (4, true), (5, false), (5, true), (6, false),
        ]
        let step = steps[pitch.pitchClass]
        return naturals[step.natural] + (step.sharp ? "♯" : "")
    }

    /// Name with octave number: "C4" or "Dó4".
    public func nameWithOctave(of pitch: Pitch) -> String {
        name(of: pitch) + String(pitch.octave)
    }
}
