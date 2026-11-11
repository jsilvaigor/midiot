/// Suggests fingerings for notes that have none (requirement SP-6).
///
/// Each hand's line is fingered by finding the cheapest sequence of fingers under a simple
/// model of the hand: neighbouring fingers reach a limited distance, the thumb may pass under
/// fingers 2 to 4 (and they over it), and thumb and little finger avoid black keys. Chords get
/// a fixed shape. The result is a sensible default, not an editor's fingering.
public extension Song {
    func suggestingFingering() -> Song {
        var notes = notes
        for hand in Hand.allCases {
            Fingering.assign(to: &notes, hand: hand)
        }
        return Song(title: title, notes: notes, tempoMap: tempoMap, measures: measures)
    }
}

enum Fingering {
    /// Largest comfortable distance in semitones between two fingers, lower finger first.
    private static let reach: [[Int]] = [
        // to:  1  2  3  4  5
        [0, 5, 7, 9, 12], // from 1
        [0, 0, 3, 5, 7], // from 2
        [0, 0, 0, 2, 4], // from 3
        [0, 0, 0, 0, 3], // from 4
        [0, 0, 0, 0, 0],
    ]

    /// A silence longer than this many beats lets the hand move freely.
    private static let phraseGap = 1.0

    static func assign(to notes: inout [Note], hand: Hand) {
        // Group the hand's notes into moments: single notes or chords.
        let indices = notes.indices.filter { notes[$0].hand == hand }
        var moments: [[Int]] = []
        for index in indices {
            if let last = moments.last, abs(notes[last[0]].start - notes[index].start) < 1e-6 {
                moments[moments.count - 1].append(index)
            } else {
                moments.append([index])
            }
        }
        guard !moments.isEmpty else { return }

        // The left hand is the right hand mirrored: flip pitch so one model serves both.
        func height(_ index: Int) -> Int { hand == .right ? notes[index].pitch.midiNumber : -notes[index].pitch.midiNumber }

        /// The note that leads into the next moment, and the finger it must take if already decided.
        struct Step {
            let lead: Int
            let fixed: Int?
        }
        var steps: [Step] = []
        for moment in moments {
            let sorted = moment.sorted { height($0) < height($1) }
            if sorted.count > 1 {
                // A chord: fixed shape from the spacing of its notes.
                let shape = chordShape(sorted.map(height))
                for (index, finger) in zip(sorted, shape) where notes[index].finger == nil {
                    notes[index].finger = finger
                }
            }
            let lead = sorted[sorted.count - 1]
            steps.append(Step(lead: lead, fixed: notes[lead].finger))
        }

        // Cheapest finger sequence through the leading notes.
        var cost = [[Double]](repeating: [Double](repeating: .infinity, count: 6), count: steps.count)
        var from = [[Int]](repeating: [Int](repeating: 0, count: 6), count: steps.count)
        for finger in 1...5 where steps[0].fixed == nil || steps[0].fixed == finger {
            cost[0][finger] = keyPenalty(finger, notes[steps[0].lead].pitch)
        }
        for step in 1..<steps.count {
            let previous = steps[step - 1].lead, current = steps[step].lead
            let isNewPhrase = notes[current].start - notes[previous].end > phraseGap
            for finger in 1...5 where steps[step].fixed == nil || steps[step].fixed == finger {
                for earlier in 1...5 where cost[step - 1][earlier] < .infinity {
                    let move = isNewPhrase ? 0 : transition(from: earlier, at: height(previous), to: finger, at: height(current))
                    let total = cost[step - 1][earlier] + move + keyPenalty(finger, notes[current].pitch)
                    if total < cost[step][finger] {
                        cost[step][finger] = total
                        from[step][finger] = earlier
                    }
                }
            }
        }
        guard var finger = (1...5).min(by: { cost[steps.count - 1][$0] < cost[steps.count - 1][$1] }),
              cost[steps.count - 1][finger] < .infinity else { return }
        for step in stride(from: steps.count - 1, through: 0, by: -1) {
            if notes[steps[step].lead].finger == nil { notes[steps[step].lead].finger = finger }
            finger = from[step][finger]
        }
    }

    /// Cost of moving from one finger on one key to another finger on another key.
    /// Heights rise toward the little finger for both hands.
    private static func transition(from earlier: Int, at low: Int, to finger: Int, at high: Int) -> Double {
        let distance = high - low
        if distance == 0 { return finger == earlier ? 0 : 2 }
        // Moving down is moving up seen from the other side: swap the roles.
        let (a, b, span) = distance > 0 ? (earlier, finger, distance) : (finger, earlier, -distance)
        if a < b {
            // Fingers in their natural order: pay for stretching or for bunching up.
            let stretch = max(0, span - reach[a - 1][b - 1])
            let cramped = max(0, (b - a) - span)
            return Double(stretch) * 3 + Double(cramped)
        }
        if a == b { return 6 + Double(span) }
        // Fingers crossed: only the thumb passes under 2 to 4 (or they over it), a short way.
        guard b == 1, (2...4).contains(a) else { return 12 }
        return 2 + Double(max(0, span - 2)) * 2 + (a == 4 ? 0.5 : 0) + (a == 2 ? 0.3 : 0)
    }

    private static func keyPenalty(_ finger: Int, _ pitch: Pitch) -> Double {
        guard pitch.isBlackKey else { return 0 }
        return finger == 1 ? 2 : (finger == 5 ? 1 : 0)
    }

    /// Fingers for a chord given its notes' heights, lowest first.
    private static func chordShape(_ heights: [Int]) -> [Int] {
        switch heights.count {
        case 2:
            let span = heights[1] - heights[0]
            return [1, span <= 2 ? 2 : (span <= 4 ? 3 : (span <= 6 ? 4 : 5))]
        case 3:
            // A wide gap at the top puts 2 in the middle: E G C is 1 2 5, C E G is 1 3 5.
            return [1, heights[2] - heights[1] >= 5 ? 2 : 3, 5]
        case 4:
            return [1, 2, heights[3] - heights[2] >= 4 ? 3 : 4, 5]
        default:
            return Array((1...5).prefix(heights.count)) + Array(repeating: 5, count: max(0, heights.count - 5))
        }
    }
}
