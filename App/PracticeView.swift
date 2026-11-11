import DesignSystem
import MusicCore
import SwiftUI

/// Practice screen: the open song as falling notes over the live keyboard, with transport below.
/// Without a song it shows the keyboard alone.
struct PracticeView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(NoteNamingSetting.storageKey) private var naming = NoteNaming.letters

    /// White keys wider than this look toy-like on a 25-key keyboard in a wide window.
    private let maxWhiteKeyWidth: CGFloat = 44

    var body: some View {
        if let session = model.session {
            VStack(spacing: 0) {
                header(session)
                Palette.hairline.frame(height: 1)
                lane(session)
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
                    Text(verbatim: session.loaded.entry.format == .midi ? "MIDI" : "MusicXML")
                    Text(verbatim: "·")
                    Text("\(session.song.measures.count) bars")
                }
                .font(.sans(12))
                .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
    }

    /// Falling notes and keyboard share one frame so each note lands on its key.
    private func lane(_ session: PracticeSession) -> some View {
        let range = displayRange(for: session.song)
        return VStack(spacing: 0) {
            FallingNotesView(
                range: range,
                notes: session.song.notes.map { note in
                    FallingNote(
                        id: note.id, pitch: note.pitch, start: note.start, duration: note.duration,
                        color: note.hand == .right ? Palette.handRight : Palette.handLeft,
                        label: note.finger.map(String.init)
                    )
                },
                barLines: session.song.measures.map { .init(beat: $0.start, label: String($0.number)) },
                position: { session.beat }
            )
            .frame(minHeight: 240)
            keyboard(range: range, sounding: session.sounding)
        }
        .frame(maxWidth: keyboardWidth(range))
        .padding(.horizontal, Spacing.l)
        .frame(maxWidth: .infinity)
    }

    private func keyboard(range: KeyboardRange, sounding: [Pitch: Hand]) -> some View {
        var highlights = sounding.mapValues { $0 == .right ? Palette.handRight : Palette.handLeft }
        for pitch in model.pressed { highlights[pitch] = Palette.textPrimary.mix(with: Palette.accent, by: 0.5) }
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

    var body: some View {
        HStack(spacing: 22) {
            HStack(spacing: 10) {
                IconButton(systemImage: "backward.end.fill", label: "Restart") { session.restart() }
                PlayButton(isPlaying: session.isPlaying, label: session.isPlaying ? "Pause" : "Play") { session.togglePlay() }
                    .keyboardShortcut(.space, modifiers: [])
                readout.padding(.leading, 6)
            }
            Palette.hairlineStrong.frame(width: 1, height: 32)
            tempo
            ToggleChip(Text("Metronome"), systemImage: "metronome", isOn: session.metronomeIsOn) {
                session.metronomeIsOn.toggle()
            }
            ToggleChip(Text("Count-in"), systemImage: "timer", isOn: session.countInIsOn) {
                session.countInIsOn.toggle()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Palette.surface)
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
            Text("Tempo").capsLabel()
            Slider(value: $session.rate, in: 0.25...1.5, step: 0.05)
                .frame(width: 150)
                .accessibilityLabel(Text("Tempo"))
            let bpm = session.song.tempoMap.bpm(atBeat: max(session.beat, 0)) * session.rate
            Text(verbatim: "\(Int((session.rate * 100).rounded()))% · \(Int(bpm.rounded()))")
                .font(.readoutSmall)
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 84, alignment: .leading)
        }
    }
}

enum NoteNamingSetting {
    static let storageKey = "noteNaming"
}
