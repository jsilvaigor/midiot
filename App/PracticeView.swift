import DesignSystem
import Library
import MusicCore
import Notation
import SwiftUI

/// Practice screen: the open song as falling notes over the live keyboard, with transport below.
/// Without a song it shows the keyboard alone.
struct PracticeView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(NoteNamingSetting.storageKey) private var naming = NoteNaming.letters
    @AppStorage("practiceViewMode") private var viewMode = ViewMode.notes

    /// How the song is shown (requirement SP-1).
    enum ViewMode: String {
        case notes, split, sheet
    }

    /// White keys wider than this look toy-like on a 25-key keyboard in a wide window.
    private let maxWhiteKeyWidth: CGFloat = 44

    var body: some View {
        if let session = model.session, let review = session.review {
            ReviewView(session: session, review: review)
        } else if let session = model.session {
            VStack(spacing: 0) {
                header(session)
                Palette.hairline.frame(height: 1)
                let mode = session.hasSheet ? viewMode : .notes
                if mode != .notes {
                    sheet(session)
                        .frame(maxHeight: mode == .split ? 260 : .infinity)
                    Palette.hairline.frame(height: 1)
                }
                lane(session, showsNotes: mode != .sheet)
                Palette.hairline.frame(height: 1)
                TransportBar(session: session)
            }
            .background(FilamentBackground())
        } else {
            VStack(spacing: 0) {
                EmptyState(
                    systemImage: "pianokeys",
                    title: "Nothing to practice yet",
                    message: "Choose a song from the Library to start practicing."
                )
                keyboard(range: model.range, sounding: [:])
                    .frame(maxWidth: keyboardWidth(model.range))
                    .padding(.horizontal, Spacing.l)
                    .frame(maxWidth: .infinity)
                    .background(Palette.background)
            }
        }
    }

    private func header(_ session: PracticeSession) -> some View {
        HStack(spacing: 14) {
            IconButton(systemImage: "chevron.left", label: "Back to Library", size: 36) { model.closeSong() }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: session.song.title).font(.displayTitle).foregroundStyle(Palette.textPrimary).lineLimit(1)
                HStack(spacing: 6) {
                    formatLabel(session.loaded.entry.format)
                    Text(verbatim: "·")
                    Text("\(session.song.measures.count) bars")
                    if let folded = session.foldedRange {
                        Text(verbatim: "·")
                        Text("Folded to fit \(folded.keyCount) keys").foregroundStyle(Palette.accentHighlight)
                    }
                }
                .font(.sans(12))
                .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            if session.hasSheet {
                SegmentedControl(selection: $viewMode, options: [
                    .init(.notes, "Notes"), .init(.split, "Split"), .init(.sheet, "Sheet"),
                ])
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
    }

    private func formatLabel(_ format: SongEntry.Format) -> Text {
        switch format {
        case .midi: Text(verbatim: "MIDI")
        case .musicXML: Text(verbatim: "MusicXML")
        case .drill: Text("Drill")
        }
    }

    private func sheet(_ session: PracticeSession) -> some View {
        var colors: [String: Color] = [:]
        for note in session.song.notes {
            guard let id = note.notationID else { continue }
            if session.results[note.id] != nil {
                colors[id] = color(for: note, in: session)
            } else if session.awaited.contains(where: { $0.id == note.id }) {
                colors[id] = note.hand == .right ? Palette.handRight : Palette.handLeft
            }
        }
        return ScoreView(
            pages: session.loaded.pages, layout: session.layout,
            ink: Palette.textPrimary, accent: Palette.accent,
            noteColors: colors, loopBars: session.loopBars,
            position: { session.beat },
            onTapMeasure: { session.tappedMeasure($0, extend: NSEvent.modifierFlags.contains(.shift)) }
        )
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
    }

    /// Falling notes and keyboard share one frame so each note lands on its key.
    private func lane(_ session: PracticeSession, showsNotes: Bool) -> some View {
        let range = session.foldedRange ?? displayRange(for: session.song)
        return VStack(spacing: 0) {
            if showsNotes {
              FallingNotesView(
                range: range,
                notes: session.song.notes.map { note in
                    FallingNote(
                        id: note.id, pitch: note.pitch, start: note.start, duration: note.duration,
                        color: color(for: note, in: session),
                        label: note.finger.map(String.init)
                    )
                },
                barLines: session.song.measures.map { .init(beat: $0.start, label: String($0.number)) },
                position: { session.beat }
            )
              .frame(minHeight: 160)
              .overlay(alignment: .top) { StatusChip(session: session, pedalIsDown: model.pedalIsDown).padding(.top, 16) }
            } else {
                StatusChip(session: session, pedalIsDown: model.pedalIsDown).padding(.vertical, 10)
            }
            keyboard(range: range, sounding: session.sounding, session: session)
        }
        .frame(maxWidth: keyboardWidth(range))
        .padding(.horizontal, Spacing.l)
        .frame(maxWidth: .infinity)
    }

    private func color(for note: Note, in session: PracticeSession) -> Color {
        switch session.results[note.id] {
        case .correct: Palette.noteCorrect
        case .early: Palette.noteEarly
        case .late: Palette.noteLate
        case .missed: Palette.noteWrong.opacity(0.55)
        case nil: note.hand == .right ? Palette.handRight : Palette.handLeft
        }
    }

    private func keyboard(range: KeyboardRange, sounding: [Pitch: Hand], session: PracticeSession? = nil) -> some View {
        var highlights = sounding.mapValues { $0 == .right ? Palette.handRight : Palette.handLeft }
        // Keys wait mode is asking for: a soft version of the hand color.
        for note in session?.awaited ?? [] {
            highlights[note.pitch] = (note.hand == .right ? Palette.handRight : Palette.handLeft).opacity(0.5)
        }
        for pitch in model.pressed {
            highlights[pitch] = session?.wrongKeys.contains(pitch) == true
                ? Palette.noteWrong
                : Palette.textPrimary.mix(with: Palette.accent, by: 0.5)
        }
        return KeyboardView(
            range: range, highlights: highlights, naming: naming,
            onPress: model.mouseDown(on:), onRelease: model.mouseUp(on:)
        )
        .frame(height: 150)
        .padding(.top, 6)
        .padding(.bottom, 14)
        // The filament: the amber line where falling notes meet the keys.
        .overlay(alignment: .top) {
            Palette.accent.frame(height: 2).filamentGlow()
        }
    }

    private func keyboardWidth(_ range: KeyboardRange) -> CGFloat {
        CGFloat(range.pitches.count { !$0.isBlackKey }) * maxWhiteKeyWidth
    }

    /// The connected keyboard's range, moved by octaves if needed so the song's lowest note shows.
    private func displayRange(for song: Song) -> KeyboardRange {
        guard let span = song.pitchSpan,
              !(model.range.contains(span.lowerBound) && model.range.contains(span.upperBound))
        else { return model.range }
        return model.range.shifted(toContain: span.lowerBound)
    }
}

/// Play controls, position readout, tempo and metronome.
private struct TransportBar: View {
    @Bindable var session: PracticeSession
    @State private var isEditingLoop = false
    @State private var loopFrom = 1
    @State private var loopTo = 4

    var body: some View {
        // One row when the window is wide enough, two when it is not.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                playback
                Spacer(minLength: 0)
                practice
            }
            VStack(alignment: .leading, spacing: 12) {
                playback
                practice
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface)
    }

    /// Transport, position, tempo and metronome.
    private var playback: some View {
        HStack(spacing: 18) {
            HStack(spacing: 10) {
                IconButton(systemImage: "backward.end.fill", label: "Restart") { session.restart() }
                PlayButton(isPlaying: session.isPlaying, label: session.isPlaying ? "Pause" : "Play") { session.togglePlay() }
                    .keyboardShortcut(.space, modifiers: [])
                readout.padding(.leading, 6)
            }
            Palette.hairlineStrong.frame(width: 1, height: 32)
            tempo
            HStack(spacing: 8) {
                ToggleChip(Text("Metronome"), systemImage: "metronome", isOn: session.metronomeIsOn, showsTitle: false) {
                    session.metronomeIsOn.toggle()
                }
                ToggleChip(Text("Count-in"), systemImage: "timer", isOn: session.countInIsOn, showsTitle: false) {
                    session.countInIsOn.toggle()
                }
            }
        }
        .fixedSize()
    }

    /// Who plays, wait mode and loop.
    private var practice: some View {
        HStack(spacing: 8) {
            SegmentedControl(selection: $session.handMode, options: [
                .init(.listen, "Listen"),
                .init(.both, "Both"),
                .init(.right, "Right", dot: Palette.handRight),
                .init(.left, "Left", dot: Palette.handLeft),
            ])
            .accessibilityLabel(Text("Hands"))
            ToggleChip(Text("Wait mode"), systemImage: "hourglass", isOn: session.waitsForPlayer, showsTitle: false) {
                session.waitsForPlayer.toggle()
            }
            loop
        }
        .fixedSize()
    }

    private var loop: some View {
        let lastBar = max(session.song.measures.count, 1)
        let title = session.loopBars.map { Text("Bars \($0.lowerBound)–\($0.upperBound)") } ?? Text("Loop")
        return ToggleChip(title, systemImage: "repeat", isOn: session.loopBars != nil) {
            isEditingLoop = true
        }
        .popover(isPresented: $isEditingLoop, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Loop these bars", isOn: Binding(
                    get: { session.loopBars != nil },
                    set: { session.loopBars = $0 ? loopFrom...max(loopFrom, loopTo) : nil }
                ))
                Stepper(value: $loopFrom, in: 1...lastBar) {
                    Text("From bar") + Text(verbatim: "  \(loopFrom)").font(.readoutSmall)
                }
                Stepper(value: $loopTo, in: 1...lastBar) {
                    Text("To bar") + Text(verbatim: "  \(loopTo)").font(.readoutSmall)
                }
                Toggle("Raise tempo as I improve", isOn: $session.adaptsTempo)
                Text("Up 5% after three clean passes, down 5% after two poor ones.")
                    .font(.sans(12)).foregroundStyle(Palette.textSecondary)
            }
            .padding(18)
            .frame(width: 280)
            .onChange(of: loopFrom) { updateLoop(lastBar: lastBar) }
            .onChange(of: loopTo) { updateLoop(lastBar: lastBar) }
            .onAppear {
                if let bars = session.loopBars {
                    loopFrom = bars.lowerBound
                    loopTo = bars.upperBound
                } else {
                    // Start from the bar being played, four bars long.
                    loopFrom = session.song.measure(atBeat: max(session.beat, 0))?.number ?? 1
                    loopTo = min(loopFrom + 3, lastBar)
                }
            }
        }
    }

    private func updateLoop(lastBar: Int) {
        if loopTo < loopFrom { loopTo = loopFrom }
        if session.loopBars != nil { session.loopBars = loopFrom...min(loopTo, lastBar) }
    }

    private var readout: some View {
        VStack(alignment: .leading, spacing: 1) {
            TimelineView(.animation(minimumInterval: 1 / 20)) { _ in
                let beat = max(session.beat, 0)
                let measure = session.song.measure(atBeat: beat)
                let bar = measure?.number ?? 1
                let beatInBar = Int(beat - (measure?.start ?? 0)) + 1
                Text(verbatim: String(format: "%02d.%d", bar, beatInBar))
                    .font(.readout)
                    .foregroundStyle(Palette.textPrimary)
                    .monospacedDigit()
            }
            Text("Bar · Beat").font(.sans(10)).tracking(1).textCase(.uppercase).foregroundStyle(Palette.textTertiary)
        }
        .frame(width: 78, alignment: .leading)
    }

    private var tempo: some View {
        HStack(spacing: 12) {
            Slider(value: $session.rate, in: 0.25...1.5, step: 0.05)
                .frame(width: 110)
                .accessibilityLabel(Text("Tempo"))
            let bpm = session.song.tempoMap.bpm(atBeat: max(session.beat, 0)) * session.rate
            Text(verbatim: "\(Int((session.rate * 100).rounded()))% · \(Int(bpm.rounded()))")
                .font(.readoutSmall)
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 84, alignment: .leading)
        }
    }
}

/// Floating chip over the lane saying who is playing, or that the music is waiting.
private struct StatusChip: View {
    let session: PracticeSession
    var pedalIsDown = false

    var body: some View {
        let isWaiting = !session.awaited.isEmpty
        let (title, detail, color): (LocalizedStringKey, LocalizedStringKey, Color) = if isWaiting {
            ("Waiting for you", "Play the highlighted keys", Palette.accent)
        } else {
            switch session.handMode {
            case .listen: ("Listening", "Midiot plays both hands", Palette.textPrimary)
            case .both: ("Both hands", "You play everything", Palette.textPrimary)
            case .right: ("Right hand", "Midiot plays the left hand for you", Palette.handRight)
            case .left: ("Left hand", "Midiot plays the right hand for you", Palette.handLeft)
            }
        }
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8).filamentGlow(color, radius: 5)
            Text(title).font(.sans(13, weight: .medium)).foregroundStyle(Palette.textPrimary)
            Text(detail).font(.sans(13)).foregroundStyle(Palette.textSecondary)
            if pedalIsDown {
                // The sustain pedal, shown while it is held (requirement HW-5).
                Text("Pedal").font(.mono(11, weight: .medium)).foregroundStyle(Palette.accentInk)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Palette.accent, in: Capsule())
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .padding(.vertical, 9)
        .glassPanel(cornerRadius: 999)
    }
}

enum NoteNamingSetting {
    static let storageKey = "noteNaming"
}
