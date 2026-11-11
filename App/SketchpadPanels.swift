import DesignSystem
import MusicCore
import Sketch
import SwiftUI

/// Right column of the Sketchpad: the sound and tempo, the chord and key being heard, chords
/// to try next, and the mood palettes (requirements CO-3, CO-4, SN-2).
struct SketchAside: View {
    let model: SketchpadModel
    /// Mood shown when no cue is selected to hold one.
    @State private var browsedMood: MoodPalette.Mood?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                playing
                hearing
                if !model.suggestions.isEmpty { tryNext }
                moods
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(hex: 0x0F1013))
    }

    // MARK: Sound and tempo

    private var playing: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 10) {
            Text("Sound").capsLabel()
            Menu {
                ForEach(SketchSound.Group.allCases, id: \.self) { group in
                    Section {
                        ForEach(SketchSound.catalog.filter { $0.group == group }) { sound in
                            Toggle(isOn: Binding(get: { model.sound == sound }, set: { _ in model.sound = sound })) {
                                Text(SketchNames.sound(sound))
                            }
                        }
                    } header: {
                        Text(SketchNames.group(group))
                    }
                }
            } label: {
                HStack {
                    Text(SketchNames.sound(model.sound)).font(.sans(14, weight: .medium)).foregroundStyle(Palette.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                }
                .padding(.horizontal, 14).frame(height: 44)
                .background(Palette.surfaceRaised.opacity(0.7), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Palette.hairline))
                .contentShape(Rectangle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .accessibilityLabel(Text("Sound"))

            HStack(spacing: 8) {
                HStack(spacing: 0) {
                    stepButton("minus", label: "Slower") { model.bpm = max(model.bpm - 2, 40) }
                    Text("\(Int(model.bpm)) bpm").font(.mono(13)).foregroundStyle(Palette.textPrimary)
                        .frame(maxWidth: .infinity)
                    stepButton("plus", label: "Faster") { model.bpm = min(model.bpm + 2, 208) }
                }
                .frame(height: 40)
                .background(Palette.surfaceRaised.opacity(0.7), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Palette.hairline))
                ToggleChip(Text("Metronome"), systemImage: "metronome", isOn: model.metronomeIsOn, showsTitle: false) {
                    model.metronomeIsOn.toggle()
                }
            }
        }
    }

    private func stepButton(_ systemImage: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.textSecondary)
                .frame(width: 44, height: 40).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(Text(label))
    }

    // MARK: Hearing

    private var hearing: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hearing").capsLabel()
            if let chord = model.chord {
                let fifths = model.key?.fifths
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(verbatim: chord.name(fifths: fifths))
                        .font(.serif(chord.name(fifths: fifths).count > 5 ? 44 : 64))
                        .foregroundStyle(Palette.accent)
                        .shadow(color: Palette.accent.opacity(0.35), radius: 15)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    if let key = model.key {
                        Group {
                            if key.isMinor { Text("in \(key.tonicName) minor") } else { Text("in \(key.tonicName) major") }
                        }
                        .font(.sans(13)).foregroundStyle(Palette.textSecondary)
                    }
                }
                if model.chordHistory.count > 1 {
                    FlowLayout(spacing: 6) {
                        ForEach(Array(model.chordHistory.enumerated()), id: \.offset) { index, past in
                            let isLast = index == model.chordHistory.count - 1
                            if index > 0 { Text(verbatim: "→").foregroundStyle(Palette.textTertiary) }
                            Text(verbatim: past.name(fifths: fifths)).foregroundStyle(isLast ? Palette.textPrimary : Palette.textSecondary)
                        }
                    }
                    .font(.mono(12))
                }
            } else {
                Text("Hold three or more keys and the chord is named here.")
                    .font(.sans(13)).foregroundStyle(Palette.textSecondary)
            }
        }
    }

    private var tryNext: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try next").capsLabel()
            ForEach(model.suggestions, id: \.self) { suggestion in
                Button {
                    model.audition(suggestion.chord)
                } label: {
                    HStack(spacing: 10) {
                        Text(verbatim: suggestion.chord.name(fifths: model.key?.fifths)).font(.serif(22)).foregroundStyle(Palette.textPrimary)
                        Spacer()
                        Text(SketchNames.effect(suggestion.effect)).font(.sans(12)).foregroundStyle(Palette.textSecondary)
                    }
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(Palette.surfaceRaised.opacity(0.7), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Palette.hairline))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Text("Click to hear it"))
            }
        }
    }

    // MARK: Mood

    private var moods: some View {
        let current = model.cue?.mood ?? browsedMood
        return VStack(alignment: .leading, spacing: 10) {
            Text("Mood palette").capsLabel()
            FlowLayout(spacing: 6) {
                ForEach(MoodPalette.Mood.allCases, id: \.self) { mood in
                    let isOn = mood == current
                    Button {
                        let next = isOn ? nil : mood
                        browsedMood = next
                        if model.cue != nil { model.updateCue { $0.mood = next } }
                    } label: {
                        Text(SketchNames.mood(mood))
                            .font(.sans(13, weight: isOn ? .medium : .regular))
                            .foregroundStyle(isOn ? Palette.handLeft.mix(with: .white, by: 0.45) : Palette.textSecondary)
                            .padding(.horizontal, 12).frame(height: 34)
                            .background(isOn ? Palette.handLeft.opacity(0.16) : .clear, in: Capsule())
                            .overlay(Capsule().strokeBorder(isOn ? Palette.handLeft.opacity(0.6) : Palette.hairlineStrong))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            if let current {
                moodDetail(MoodPalette.palette(for: current))
            } else {
                Text("Pick a mood for scales, chord moves, a tempo and sounds to start from.")
                    .font(.sans(13)).foregroundStyle(Palette.textSecondary)
            }
        }
    }

    private func moodDetail(_ palette: MoodPalette) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 10) {
            GridRow {
                Text("Scales").foregroundStyle(Palette.textTertiary)
                FlowLayout(spacing: 6) {
                    ForEach(palette.scales, id: \.self) { scale in
                        linkButton(Text(SketchNames.scale(scale)), help: "Click to hear it") { model.audition(scale) }
                    }
                }
            }
            GridRow {
                Text("Moves").foregroundStyle(Palette.textTertiary)
                Text(verbatim: palette.moves).font(.mono(12)).foregroundStyle(Palette.textPrimary).padding(.top, 1)
            }
            GridRow {
                Text("Tempo").foregroundStyle(Palette.textTertiary)
                linkButton(Text("\(palette.tempo.lowerBound)–\(palette.tempo.upperBound) bpm"), help: "Click to set the tempo") {
                    model.bpm = Double((palette.tempo.lowerBound + palette.tempo.upperBound) / 2)
                }
            }
            GridRow {
                Text("Sounds").foregroundStyle(Palette.textTertiary)
                FlowLayout(spacing: 6) {
                    ForEach(palette.sounds) { sound in
                        linkButton(Text(SketchNames.sound(sound)), isOn: model.sound == sound, help: "Click to play with this sound") {
                            model.sound = sound
                        }
                    }
                }
            }
        }
        .font(.sans(13))
        .padding(.top, 4)
    }

    /// A small tappable value inside the mood details.
    private func linkButton(_ title: Text, isOn: Bool = false, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            title.font(.sans(12, weight: isOn ? .medium : .regular))
                .foregroundStyle(isOn ? Palette.accentHighlight : Palette.textPrimary)
                .padding(.horizontal, 9).frame(minHeight: 26)
                .background(isOn ? Palette.accentSoft : Palette.surfaceRaised.opacity(0.8), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(help))
    }
}

/// Bottom bar: the app is always listening, and the last stretch of playing can be kept (requirement CO-1).
struct CaptureBar: View {
    let model: SketchpadModel
    @State private var pulses = false

    private let buckets = 120

    var body: some View {
        HStack(spacing: 20) {
            HStack(spacing: 10) {
                Circle().fill(Palette.noteWrong).frame(width: 9, height: 9)
                    .shadow(color: Palette.noteWrong.opacity(0.8), radius: 5)
                    .opacity(pulses ? 0.3 : 1)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulses)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Always listening").font(.sans(13, weight: .medium)).foregroundStyle(Palette.textPrimary)
                    Group {
                        if model.captureCameUpEmpty {
                            Text("Nothing was played in that time.").foregroundStyle(Palette.accentHighlight)
                        } else if model.cue == nil {
                            Text("Select a cue to keep what you play.")
                        } else {
                            Text("Last 10 minutes kept")
                        }
                    }
                    .font(.sans(11)).foregroundStyle(Palette.textTertiary)
                }
            }
            .fixedSize()

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let activity = model.activity(buckets: buckets)
                HStack(alignment: .center, spacing: 2) {
                    ForEach(Array(activity.enumerated()), id: \.offset) { index, level in
                        // The newest six slices are the last 30 seconds.
                        RoundedRectangle(cornerRadius: 1)
                            .fill(index >= buckets - 6 ? Palette.accent : Palette.textPrimary.opacity(0.22))
                            .frame(height: 3 + 26 * level)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: 36)
            .accessibilityLabel(Text("Activity over the last 10 minutes"))

            HStack(spacing: 8) {
                Button {
                    model.keepLast(seconds: 30)
                } label: {
                    Text("Keep last 30 s").font(.sans(13, weight: .medium)).foregroundStyle(Palette.accentHighlight)
                        .padding(.horizontal, 14).frame(height: 40)
                        .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Palette.accent.opacity(0.45)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                SketchButton("Keep last 2 min") { model.keepLast(seconds: 120) }
            }
            .disabled(model.cue == nil)
            .opacity(model.cue == nil ? 0.45 : 1)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color(hex: 0x111215))
        .onAppear { pulses = true }
    }
}

/// Names of the Sketchpad's sounds, scales, moods and statuses in the interface language.
enum SketchNames {
    static func status(_ status: Cue.Status) -> LocalizedStringKey {
        switch status {
        case .sketch: "Sketch"
        case .draft: "Draft"
        case .ready: "Ready"
        }
    }

    static func color(of status: Cue.Status) -> Color {
        switch status {
        case .sketch: Palette.textTertiary
        case .draft: Palette.accent
        case .ready: Palette.noteCorrect
        }
    }

    static func mood(_ mood: MoodPalette.Mood) -> LocalizedStringKey {
        switch mood {
        case .tension: "Tension"
        case .melancholy: "Melancholy"
        case .comic: "Comic"
        case .pastoral: "Pastoral"
        case .mystery: "Mystery"
        case .ritual: "Ritual"
        }
    }

    static func effect(_ effect: ChordSuggestion.Effect) -> LocalizedStringKey {
        switch effect {
        case .home: "Home"
        case .leadsOn: "Leads on"
        case .gentle: "Gentle, in between"
        case .opens: "Opens out"
        case .tension: "Builds tension"
        case .darker: "Darker"
        case .brighter: "Brighter, lifts"
        case .unsettled: "Unsettled"
        case .surprise: "A surprise turn"
        }
    }

    static func scale(_ scale: SketchScale) -> LocalizedStringKey {
        switch scale {
        case .major: "Major"
        case .aeolian: "Natural minor"
        case .harmonicMinor: "Harmonic minor"
        case .dorian: "Dorian"
        case .phrygian: "Phrygian"
        case .lydian: "Lydian"
        case .mixolydian: "Mixolydian"
        case .majorPentatonic: "Major pentatonic"
        case .wholeTone: "Whole-tone"
        case .octatonic: "Octatonic"
        case .chromatic: "Chromatic"
        }
    }

    static func group(_ group: SketchSound.Group) -> LocalizedStringKey {
        switch group {
        case .piano: "Piano"
        case .orchestra: "Strings and orchestra"
        case .keys: "Keys and organs"
        case .pads: "Pads and atmospheres"
        case .percussion: "Percussion and effects"
        }
    }

    static func sound(_ sound: SketchSound) -> LocalizedStringKey {
        switch sound.program {
        case nil: "Grand piano"
        case 4: "Electric piano"
        case 6: "Harpsichord"
        case 8: "Celesta"
        case 11: "Vibraphone"
        case 13: "Xylophone"
        case 14: "Tubular bells"
        case 16: "Drawbar organ"
        case 19: "Church organ"
        case 21: "Accordion"
        case 42: "Cello"
        case 43: "Contrabass"
        case 44: "Tremolo strings"
        case 45: "Pizzicato strings"
        case 46: "Harp"
        case 47: "Timpani"
        case 48: "String ensemble"
        case 52: "Choir"
        case 60: "French horn"
        case 70: "Bassoon"
        case 73: "Flute"
        case 88: "New-age pad"
        case 89: "Warm pad"
        case 91: "Choir pad"
        case 94: "Halo pad"
        case 95: "Sweep pad"
        case 116: "Taiko drum"
        case 119: "Reverse cymbal"
        case 122: "Seashore"
        case let program?: "Sound \(program + 1)"
        }
    }
}
