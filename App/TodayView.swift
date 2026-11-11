import DesignSystem
import Library
import MusicCore
import Practice
import SwiftUI

/// The daily session: warm-up, the next drill on the path and a song, with the daily goal,
/// the week and the path itself (requirements CU-1, CU-6).
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @AppStorage(NoteNamingSetting.storageKey) private var naming = NoteNaming.letters
    @State private var selectedUnit: String?

    private var plan: Curriculum.DailyPlan {
        Curriculum.plan(best: model.drillBest, day: Int(Date().timeIntervalSince1970 / 86_400))
    }

    /// The song for today: the one practiced most recently, else the first in the library.
    private var song: SongEntry? {
        model.songs.max { (model.progress[$0.id]?.last ?? .distantPast) < (model.progress[$1.id]?.last ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                HStack(alignment: .top, spacing: 20) {
                    steps.frame(maxWidth: .infinity)
                    VStack(spacing: 14) {
                        goalCard
                        weekCard
                    }
                    .frame(width: 300)
                }
                path
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, 32)
        }
        .background(FilamentBackground())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.sans(13)).foregroundStyle(Palette.textSecondary)
            (Text("Today’s session") + Text(verbatim: " · ").foregroundStyle(Palette.accent)
                + Text("\(Int(model.dailyGoal)) min").font(.serif(52, italic: true)).foregroundStyle(Palette.accent))
                .font(.display)
                .foregroundStyle(Palette.textPrimary)
        }
    }

    // MARK: Session steps

    private var steps: some View {
        let plan = plan
        let warmUpDone = model.log.isCompleted(plan.warmUp.id, on: Date())
        let drillDone = plan.drill.map { model.log.isCompleted($0.id, on: Date()) } ?? true
        let songDone = song.map { model.log.isCompleted($0.id.uuidString, on: Date()) } ?? true
        // The first step not yet done today is the one to start.
        let next = !warmUpDone ? 1 : (!drillDone ? 2 : (!songDone ? 3 : 0))
        return VStack(spacing: 10) {
            step(1, label: "Warm-up", title: Text(verbatim: title(for: plan.warmUp)), detail: bestText(for: plan.warmUp),
                 isDone: warmUpDone, isNext: next == 1) { model.open(plan.warmUp, title: title(for: plan.warmUp)) }
            if let drill = plan.drill {
                step(2, label: "Drill", title: Text(verbatim: title(for: drill)), detail: bestText(for: drill),
                     isDone: drillDone, isNext: next == 2) { model.open(drill, title: title(for: drill)) }
            } else {
                step(2, label: "Drill", title: Text("The path is complete."), detail: nil, isDone: true, isNext: false) {}
            }
            if let song {
                let best = model.progress[song.id]?.best ?? nil
                step(3, label: "Song", title: Text(verbatim: song.title),
                     detail: best.map { Text("Best \(Int(($0 * 100).rounded()))%") } ?? Text("Not played yet"),
                     isDone: songDone, isNext: next == 3) { model.open(song) }
            } else {
                step(3, label: "Song", title: Text("Import a song in the Library to add it to your session."),
                     detail: nil, isDone: false, isNext: false) { model.section = .library }
            }
        }
    }

    private func step(
        _ number: Int, label: LocalizedStringKey, title: Text, detail: Text?,
        isDone: Bool, isNext: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 20) {
                Group {
                    if isDone {
                        Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.noteCorrect)
                            .frame(width: 40, height: 40).background(Palette.noteCorrect.opacity(0.14), in: Circle())
                    } else if isNext {
                        Text(verbatim: "\(number)").font(.mono(14, weight: .semibold)).foregroundStyle(Palette.accentInk)
                            .frame(width: 40, height: 40).background(Palette.accent, in: Circle()).filamentGlow(radius: 10)
                    } else {
                        Text(verbatim: "\(number)").font(.mono(14)).foregroundStyle(Palette.textSecondary)
                            .frame(width: 40, height: 40).overlay(Circle().strokeBorder(Palette.textPrimary.opacity(0.2), lineWidth: 1.5))
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(label)
                        if isNext {
                            Text(verbatim: "·")
                            Text("Up next")
                        } else if isDone {
                            Text(verbatim: "·")
                            Text("Done today")
                        }
                    }
                    .font(.label).tracking(0.9).textCase(.uppercase)
                    .foregroundStyle(isNext ? Palette.accent : Palette.textTertiary)
                    title
                        .font(isNext ? .displayTitle : .sans(17, weight: .medium))
                        .foregroundStyle(isDone ? Palette.textSecondary : Palette.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let detail { detail.font(.sans(13)).foregroundStyle(Palette.textSecondary) }
                }
                Spacer(minLength: 0)
                if isNext {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill").font(.system(size: 11))
                        Text("Start").font(.sans(14, weight: .semibold))
                    }
                    .foregroundStyle(Palette.accentInk)
                    .padding(.horizontal, 20).frame(height: 44)
                    .background(Palette.accent, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, isNext ? 24 : 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isNext ? Palette.surfaceRaised.opacity(0.6) : Palette.surface.opacity(0.8),
                        in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                .strokeBorder(isNext ? Palette.accent.opacity(0.3) : Palette.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Goal and week

    private var goalCard: some View {
        let minutes = model.log.minutes(on: Date())
        let goal = max(model.dailyGoal, 1)
        return HStack(spacing: 20) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.07), lineWidth: 8)
                Circle().trim(from: 0, to: min(minutes / goal, 1))
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .filamentGlow(radius: 5)
                Text(verbatim: "\(Int(minutes))").font(.serif(30)).foregroundStyle(Palette.textPrimary)
            }
            .frame(width: 84, height: 84)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Daily goal").capsLabel()
                Text("\(Int(minutes)) of \(Int(goal)) minutes").font(.sans(16, weight: .medium)).foregroundStyle(Palette.textPrimary)
                Group {
                    if minutes >= goal { Text("Goal reached") } else { Text("\(Int((goal - minutes).rounded(.up))) to go") }
                }
                .font(.sans(13)).foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .background(Palette.surface.opacity(0.8), in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous).strokeBorder(Palette.hairline))
    }

    private var weekCard: some View {
        let week = model.log.week(endingOn: Date())
        let tallest = max(week.map(\.minutes).max() ?? 0, model.dailyGoal, 1)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week").capsLabel()
                Spacer()
                Text("\(model.log.streak(asOf: Date())) day streak").font(.sans(13)).foregroundStyle(Palette.textSecondary)
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(week.enumerated()), id: \.offset) { index, day in
                    let isToday = index == week.count - 1
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isToday ? Palette.accent : (day.minutes >= model.dailyGoal ? Palette.accent.opacity(0.45) : Color.white.opacity(0.12)))
                            .frame(maxWidth: 22)
                            .frame(height: max(6, 70 * day.minutes / tallest))
                        Text(day.date, format: .dateTime.weekday(.narrow))
                            .font(.mono(11)).foregroundStyle(isToday ? Palette.accent : Palette.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 96, alignment: .bottom)
            .accessibilityHidden(true)
        }
        .padding(22)
        .background(Palette.surface.opacity(0.8), in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous).strokeBorder(Palette.hairline))
    }

    // MARK: Path

    private var path: some View {
        let current = Curriculum.currentUnit(best: model.drillBest)
        let selected = Curriculum.units.first { $0.id == (selectedUnit ?? current?.id) } ?? Curriculum.units[0]
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your path").font(.serif(30)).foregroundStyle(Palette.textPrimary)
                Spacer()
                Text("Treble reading and rhythm are marked as known from the flute.")
                    .font(.sans(13)).foregroundStyle(Palette.textSecondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], spacing: 8) {
                ForEach(Array(Curriculum.units.enumerated()), id: \.element.id) { index, unit in
                    unitChip(unit, number: index + 1, isSelected: unit.id == selected.id)
                }
            }
            Palette.hairline.frame(height: 1)
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(unitTitle(selected.topic)).font(.serif(22)).foregroundStyle(Palette.textPrimary)
                    Text(unitBody(selected.topic)).font(.sans(13)).foregroundStyle(Palette.textSecondary)
                }
                if !selected.drills.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                        ForEach(selected.drills, id: \.id) { drill in drillButton(drill) }
                    }
                }
            }
        }
        .padding(Spacing.l)
        .background(Palette.surface.opacity(0.8), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Palette.hairline))
    }

    private func unitChip(_ unit: Curriculum.Unit, number: Int, isSelected: Bool) -> some View {
        let status = Curriculum.status(of: unit, best: model.drillBest)
        return Button {
            selectedUnit = unit.id
        } label: {
            HStack(spacing: 10) {
                Group {
                    switch status {
                    case .known:
                        Text(verbatim: "–").foregroundStyle(Palette.textTertiary)
                            .frame(width: 26, height: 26).overlay(Circle().strokeBorder(Palette.hairline, lineWidth: 1.5))
                    case .done:
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.noteCorrect)
                            .frame(width: 26, height: 26).background(Palette.noteCorrect.opacity(0.12), in: Circle())
                    case .current:
                        Text(verbatim: "\(number)").foregroundStyle(Palette.accentInk)
                            .frame(width: 26, height: 26).background(Palette.accent, in: Circle()).filamentGlow(radius: 7)
                    case .upcoming:
                        Text(verbatim: "\(number)").foregroundStyle(Palette.textSecondary)
                            .frame(width: 26, height: 26).overlay(Circle().strokeBorder(Palette.hairlineStrong, lineWidth: 1.5))
                    }
                }
                .font(.mono(11, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(unitTitle(unit.topic)).font(.sans(13, weight: .medium)).foregroundStyle(Palette.textPrimary).lineLimit(1)
                    Group {
                        switch status {
                        case .known: Text("Known")
                        case .done: Text("Done")
                        case let .current(passed): Text("\(passed) of \(unit.drills.count)").foregroundStyle(Palette.accent)
                        case .upcoming: Text("Next")
                        }
                    }
                    .font(.sans(11)).foregroundStyle(Palette.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 10).padding(.trailing, 14)
            .frame(minHeight: 52)
            .background(isSelected ? Palette.surfaceRaised : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Palette.accent.opacity(0.4) : Palette.hairline))
            .opacity(status == .known ? 0.75 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func drillButton(_ drill: Drill) -> some View {
        let best = model.drillBest[drill.id]
        let passed = (best ?? 0) >= Curriculum.passAccuracy
        return Button {
            model.open(drill, title: title(for: drill))
        } label: {
            HStack(spacing: 10) {
                Image(systemName: passed ? "checkmark.circle.fill" : "play.circle")
                    .foregroundStyle(passed ? Palette.noteCorrect : Palette.textSecondary)
                Text(verbatim: title(for: drill)).font(.sans(13)).foregroundStyle(Palette.textPrimary).lineLimit(1)
                Spacer(minLength: 0)
                if let best {
                    Text(verbatim: "\(Int((best * 100).rounded()))%").font(.mono(11)).foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Palette.surfaceRaised.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Names

    private func bestText(for drill: Drill) -> Text {
        model.drillBest[drill.id].map { Text("Best \(Int(($0 * 100).rounded()))%") } ?? Text("Not played yet")
    }

    /// Localized drill name, with the key written in the chosen note naming.
    private func title(for drill: Drill) -> String {
        func keyName(_ key: MusicKey) -> String {
            // "B♭" becomes "Si♭" in solfège naming.
            let base = naming.name(of: Pitch(midiNumber: 60 + key.tonic)).replacingOccurrences(of: "♯", with: "")
            let flat = key.tonicName.hasSuffix("♭")
            let letter = flat ? naming.name(of: Pitch(midiNumber: 61 + key.tonic)).replacingOccurrences(of: "♯", with: "") : base
            return letter + (key.tonicName.hasSuffix("♯") ? "♯" : (flat ? "♭" : ""))
        }
        let resource: LocalizedStringResource = switch drill {
        case let .scale(key): key.isMinor ? "\(keyName(key)) minor scale" : "\(keyName(key)) major scale"
        case let .arpeggio(key): key.isMinor ? "\(keyName(key)) minor arpeggio" : "\(keyName(key)) major arpeggio"
        case let .inversions(key): "\(keyName(key)) major inversions"
        case let .cadence(key): "\(keyName(key)) major cadence"
        case let .bassReading(level): "Bass clef reading \(level)"
        case let .rhythm(level): "Rhythm \(level)"
        case let .fiveFinger(_, pattern):
            pattern == 2 ? "Five fingers, contrary" : (pattern == 3 ? "Five fingers, held bass" : "Five fingers, parallel")
        }
        var localized = resource
        localized.locale = locale
        return String(localized: localized)
    }

    private func unitTitle(_ topic: Curriculum.Unit.Topic) -> LocalizedStringKey {
        switch topic {
        case .treble: "Treble clef"
        case .rhythm: "Rhythm & meter"
        case .fiveFinger: "Five-finger positions"
        case .bassClef: "Bass clef"
        case .handsTogether: "Hands together"
        case .scales: "Scales"
        case .arpeggios: "Arpeggios"
        case .chords: "Chords & inversions"
        }
    }

    private func unitBody(_ topic: Curriculum.Unit.Topic) -> LocalizedStringKey {
        switch topic {
        case .treble: "You read treble fluently. Nothing to practice here."
        case .rhythm: "You keep time already. The rhythm drills stay available any time."
        case .fiveFinger: "One finger per key in C position, both hands, with fingering numbers."
        case .bassClef: "Reading the bass staff with the left hand, then ledger lines below and above."
        case .handsTogether: "The hands move in opposite directions, then one moves while the other holds."
        case .scales: "One octave up and down in each key, with standard fingering."
        case .arpeggios: "Each key’s chord broken across an octave."
        case .chords: "Triads in all three positions, then the I–IV–V–I cadence with smooth voice leading."
        }
    }
}
