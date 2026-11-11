import DesignSystem
import MidiIO
import MusicCore
import Sketch
import SwiftUI

/// Stage mode: the current cue in very large type, the cue list, and six performing
/// controls. Dark, locked against accidental changes, with panic always in reach
/// (requirements LV-1 to LV-6).
struct StageView: View {
    @Environment(AppModel.self) private var app
    @Bindable var model: StageModel
    @AppStorage(NoteNamingSetting.storageKey) private var naming = NoteNaming.letters

    var body: some View {
        Group {
            if model.isChoosing { chooser } else { stage }
        }
        .background(Palette.stage.ignoresSafeArea())
        .foregroundStyle(Palette.textPrimary)
    }

    private var stage: some View {
        VStack(spacing: 0) {
            header
            if let entry = model.current {
                HStack(alignment: .top, spacing: 24) {
                    currentCue(entry)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    cueList
                        .frame(width: 320)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 20)
                pads
            } else {
                nothingToPerform
            }
        }
    }

    // MARK: Chooser

    private var chooser: some View {
        VStack(spacing: 0) {
            HStack {
                Button { app.section = .sketchpad } label: {
                    Text("Exit stage").font(.sans(13)).foregroundStyle(Palette.textTertiary)
                        .frame(height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 18)
            if model.plays.isEmpty {
                noPlays
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Choose the play").font(.serif(44))
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(model.plays) { play in playRow(play) }
                        }
                    }
                    .scrollIndicators(.never)
                }
                .frame(maxWidth: 640, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
    }

    private func playRow(_ play: Play) -> some View {
        let isCurrent = play.id == model.play?.id
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let cues = play.scenes.flatMap(\.cues)
        let recorded = cues.filter { ($0.bestTake?.noteCount ?? 0) > 0 }.count
        return Button { model.choose(play.id) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: play.title).font(.sans(22, weight: .medium)).lineLimit(1)
                Text("\(cues.count) cues · \(recorded) with a recorded layer")
                    .font(.sans(14)).foregroundStyle(Palette.textSecondary)
            }
            .padding(.horizontal, 22).padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(isCurrent ? Palette.accentSoft : Palette.stagePanel, in: shape)
            .overlay(shape.strokeBorder(isCurrent ? Palette.accent.opacity(0.5) : Palette.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private var noPlays: some View {
        VStack(spacing: 16) {
            Text("No plays yet").font(.serif(52))
            Text("Make a play in the Sketchpad, add its cues, and you can choose it here.")
                .font(.sans(18)).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            SecondaryButton("Open the Sketchpad") { app.section = .sketchpad }
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: Header

    private var canLeave: Bool { !model.isLocked || model.current == nil }

    private var header: some View {
        HStack(spacing: 18) {
            Button { app.section = .sketchpad } label: {
                Text("Exit stage").font(.sans(13)).foregroundStyle(Palette.textTertiary)
                    .frame(height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canLeave)
            .opacity(canLeave ? 1 : 0.45)
            .help(canLeave ? Text(verbatim: "") : Text("Unlock to leave the stage"))

            if let play = model.play {
                Button { model.changePlay() } label: {
                    Text(verbatim: play.title).font(.sans(13)).tracking(1.5).textCase(.uppercase)
                        .foregroundStyle(Palette.textSecondary).lineLimit(1)
                        .frame(height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.isLocked)
                .help(model.isLocked ? Text(verbatim: "") : Text("Change play"))
                .accessibilityLabel(model.isLocked ? Text(verbatim: play.title) : Text("Change play"))
            }
            Spacer(minLength: 12)
            if model.current != nil { LockButton(isLocked: $model.isLocked) }
            panicButton
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 18)
    }

    private var panicButton: some View {
        Button { app.panic() } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 3).fill(Palette.noteWrong).frame(width: 12, height: 12)
                Text("Panic").font(.sans(16, weight: .bold)).tracking(2).textCase(.uppercase)
                    .foregroundStyle(Color(hex: 0xFF8A85))
                controlName(.panic, color: Color(hex: 0xFF8A85).opacity(0.75))
            }
            .padding(.horizontal, 24)
            .frame(height: 52)
            .background(Palette.noteWrong.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.noteWrong, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.escape, modifiers: [])
        .accessibilityLabel(Text("Panic: silence all sound"))
    }

    // MARK: Current cue

    private func currentCue(_ entry: CueSheet.Entry) -> some View {
        let cue = entry.cue
        return VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: entry.label).font(.mono(40, weight: .medium)).foregroundStyle(Palette.accent)
                    .filamentGlow(radius: 16)
                Text(verbatim: cue.name).font(.hero).lineLimit(1).minimumScaleFactor(0.4)
                    .padding(.vertical, -8)
                if !cue.note.isEmpty {
                    Text(verbatim: cue.note).font(.sans(22)).foregroundStyle(Palette.textSecondary)
                        .lineLimit(3).frame(maxWidth: 760, alignment: .leading)
                }
            }
            presetTiles(cue)
            LayerCard(model: model, cue: cue)
                .frame(maxWidth: 820)
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func presetTiles(_ cue: Cue) -> some View {
        let preset = cue.stagePreset
        return HStack(spacing: 12) {
            editable {
                tile("Sound") {
                    if let second = preset.second {
                        Text("\(Text(SketchNames.sound(.sound(program: preset.program)))) + \(Text(SketchNames.sound(.sound(program: second.program))))")
                    } else {
                        Text(SketchNames.sound(.sound(program: preset.program)))
                    }
                }
            } menu: {
                soundMenu(preset)
            }
            editable {
                tile("Split (keyboard)") {
                    if let second = preset.second {
                        if let split = second.splitAt {
                            Text(verbatim: naming.nameWithOctave(of: Pitch(midiNumber: split - 1)) + " | "
                                + naming.nameWithOctave(of: Pitch(midiNumber: split))).font(.mono(22))
                        } else {
                            Text("Layered")
                        }
                    } else {
                        Text(verbatim: "—").font(.mono(22))
                    }
                }
            } menu: {
                splitMenu(preset)
            }
            tile("Tempo") {
                HStack(spacing: 10) {
                    if let bpm = preset.bpm ?? cue.bestTake?.bpm {
                        Text("\(Int(bpm.rounded())) bpm").font(.mono(22))
                    } else {
                        Text(verbatim: "—").font(.mono(22))
                    }
                    if !model.isLocked, let recorded = cue.bestTake?.bpm {
                        tempoStep("minus", label: "Slower") { $0.bpm = max(($0.bpm ?? recorded).rounded() - 2, 30) }
                        tempoStep("plus", label: "Faster") { $0.bpm = min(($0.bpm ?? recorded).rounded() + 2, 240) }
                        if preset.bpm != nil {
                            tempoStep("arrow.uturn.backward", label: "As recorded") { $0.bpm = nil }
                        }
                    }
                }
            }
        }
    }

    private func tile(_ title: LocalizedStringKey, @ViewBuilder value: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.sans(13)).foregroundStyle(Palette.textTertiary)
            value().font(.sans(22, weight: .medium)).foregroundStyle(Palette.textPrimary).lineLimit(1)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .frame(height: 80, alignment: .leading)
        .background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(model.isLocked ? Palette.hairline : Palette.accent.opacity(0.35)))
    }

    /// A tile that opens a menu while the stage is unlocked, and is plain text while locked.
    @ViewBuilder
    private func editable(@ViewBuilder _ label: () -> some View, @ViewBuilder menu: () -> some View) -> some View {
        if model.isLocked {
            label()
        } else {
            Menu(content: menu, label: label)
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        }
    }

    private func tempoStep(_ systemImage: String, label: LocalizedStringKey, change: @escaping (inout StagePreset) -> Void) -> some View {
        Button { model.updatePreset(change) } label: {
            Image(systemName: systemImage).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.textSecondary).frame(width: 32, height: 32)
                .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }

    @ViewBuilder
    private func soundMenu(_ preset: StagePreset) -> some View {
        soundChoices(selected: preset.program) { program in model.updatePreset { $0.program = program } }
        Divider()
        Menu("Second sound") {
            Toggle("None", isOn: Binding(get: { preset.second == nil }, set: { _ in model.updatePreset { $0.second = nil } }))
            Divider()
            soundChoices(selected: preset.second.map(\.program) ?? .some(-1)) { program in
                model.updatePreset { $0.second = StagePreset.Second(program: program, splitAt: $0.second?.splitAt) }
            }
        }
    }

    /// The sound catalog as one submenu per group.
    private func soundChoices(selected: Int?, pick: @escaping (Int?) -> Void) -> some View {
        ForEach(SketchSound.Group.allCases, id: \.self) { group in
            Menu(SketchNames.group(group)) {
                ForEach(SketchSound.catalog.filter { $0.group == group }) { sound in
                    Toggle(SketchNames.sound(sound), isOn: Binding(get: { sound.program == selected }, set: { _ in pick(sound.program) }))
                }
            }
        }
    }

    /// Keys a split can sit at: the lowest key of the upper sound.
    private static let splitPoints = [41, 48, 53, 60, 65, 72]

    @ViewBuilder
    private func splitMenu(_ preset: StagePreset) -> some View {
        if preset.second == nil {
            Text("Choose a second sound first")
        } else {
            Toggle("Layered", isOn: Binding(get: { preset.second?.splitAt == nil }, set: { _ in model.updatePreset { $0.second?.splitAt = nil } }))
            Divider()
            ForEach(Self.splitPoints, id: \.self) { point in
                Toggle(isOn: Binding(get: { preset.second?.splitAt == point }, set: { _ in model.updatePreset { $0.second?.splitAt = point } })) {
                    Text("Split below \(naming.nameWithOctave(of: Pitch(midiNumber: point)))")
                }
            }
        }
    }

    // MARK: Cue list

    private var cueList: some View {
        let entries = model.sheet.entries
        return VStack(alignment: .leading, spacing: 8) {
            Text("Cues").font(.sans(13)).tracking(1.5).textCase(.uppercase).foregroundStyle(Palette.textTertiary)
                .padding(.horizontal, 4).padding(.bottom, 4)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { offset, entry in
                            cueRow(entry, offset: offset).id(entry.id)
                        }
                    }
                }
                .scrollIndicators(.never)
                .onChange(of: model.index, initial: true) {
                    // Keep the cue before the current one in view, for context.
                    guard let id = entries.indices.contains(model.index - 1) ? entries[model.index - 1].id : entries.first?.id else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .top) }
                }
            }
        }
    }

    private func cueRow(_ entry: CueSheet.Entry, offset: Int) -> some View {
        let isCurrent = offset == model.index, isNext = offset == model.index + 1
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button { model.select(offset) } label: {
            HStack(spacing: 14) {
                Text(verbatim: entry.label).font(.mono(18)).foregroundStyle(isCurrent ? Palette.accent : Palette.textSecondary)
                    .frame(width: 44, alignment: .leading)
                Text(verbatim: entry.cue.name).font(.sans(20)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                if isCurrent || isNext {
                    Text(isCurrent ? "Now" : "Next (cue)").font(.sans(13, weight: .semibold)).tracking(1).textCase(.uppercase)
                        .foregroundStyle(isCurrent ? Palette.accent : Palette.textSecondary)
                }
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 60)
            .background(isCurrent ? Palette.accentSoft : isNext ? Palette.sidebar : .clear, in: shape)
            .overlay(shape.strokeBorder(isCurrent ? Palette.accent.opacity(0.5) : isNext ? Palette.hairlineStrong : .clear))
            .opacity(offset < model.index ? 0.4 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Jumping about the list is an edit; stepping with Go and Back is always allowed.
        .allowsHitTesting(!model.isLocked)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    // MARK: Pads

    private var pads: some View {
        HStack(spacing: 10) {
            pad(.cueBack, "Back", isEnabled: model.index > 0) { model.back() }
                .keyboardShortcut(.leftArrow, modifiers: [])
            goPad
            pad(.playLayer, "Play layer", isEnabled: model.layerTake != nil) { model.playLayer() }
            pad(.fadeIn, "Fade in", isEnabled: model.layerTake != nil) { model.fadeIn() }
            pad(.fadeOut, "Fade out", isEnabled: model.playingCueID != nil) { model.fadeOut() }
            pad(.stopLayer, "Stop", isEnabled: model.playingCueID != nil) { model.stopLayer() }
        }
        .padding(.horizontal, 32)
        .padding(.top, 16)
        .padding(.bottom, 24)
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }

    private var goPad: some View {
        pad(.cueGo, isEnabled: model.next != nil) {
            model.next.map { Text("Go · \($0.label)") } ?? Text("Last cue")
        } action: { model.go() }
            .keyboardShortcut(.space, modifiers: [])
    }

    private func pad(
        _ action: ControlAction, _ title: LocalizedStringKey, isEnabled: Bool = true,
        action perform: @escaping () -> Void
    ) -> some View {
        pad(action, isEnabled: isEnabled, title: { Text(title) }, action: perform)
    }

    /// A pad in the colour its Launchkey pad is lit in: full when its action is under way or
    /// is the next thing to do, tinted otherwise.
    private func pad(
        _ action: ControlAction, isEnabled: Bool,
        title: () -> Text, action perform: @escaping () -> Void
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let color = (action.padColor ?? .white).color
        let style = app.padLightStyle(action)
        // Go is the one pad that is always the next thing to do.
        let isFull = style == .pulsing || (action == .cueGo && isEnabled)
        return Button(action: perform) {
            VStack(alignment: .leading) {
                HStack {
                    controlName(action, color: isFull ? Palette.accentInk.opacity(0.7) : Palette.textTertiary)
                    Spacer(minLength: 0)
                    Circle().fill(isFull ? Palette.accentInk.opacity(0.5) : color).frame(width: 9, height: 9)
                }
                Spacer(minLength: 0)
                title().font(.sans(isFull ? 22 : 20, weight: isFull ? .bold : .semibold))
                    .foregroundStyle(isFull ? Palette.accentInk : Palette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 92, maxHeight: 92, alignment: .leading)
            .background(color.opacity(isFull ? 0.92 : 0.14), in: shape)
            .background(Palette.sidebar, in: shape)
            .overlay(shape.strokeBorder(color.opacity(isFull ? 0 : 0.55)))
            .shadow(color: isFull ? color.opacity(0.35) : .clear, radius: 17)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }

    /// The pad or knob an action is on, in small capitals: "PAD 2".
    @ViewBuilder
    private func controlName(_ action: ControlAction, color: Color) -> some View {
        if let source = app.controlMap.source(of: action) {
            ControlNames.source(source).font(.mono(11)).textCase(.uppercase).foregroundStyle(color)
        } else {
            Text(verbatim: " ").font(.mono(11))
        }
    }

    // MARK: Empty

    private var nothingToPerform: some View {
        VStack(spacing: 16) {
            Text("Nothing to perform yet").font(.serif(52))
            Text("Cues come from the Sketchpad. Make a play there, add its cues, and they line up here in order.")
                .font(.sans(18)).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            SecondaryButton("Open the Sketchpad") { app.section = .sketchpad }
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

/// Shows whether the stage is locked. Unlocking takes a held press, so a stray click during
/// a performance cannot open the screen to changes; locking again is one click.
private struct LockButton: View {
    @Binding var isLocked: Bool
    @State private var isHeld = false
    @State private var hold: Task<Void, Never>?

    var body: some View {
        let color = isLocked ? Palette.noteCorrect : Palette.accent
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        HStack(spacing: 10) {
            Image(systemName: isLocked ? "lock.fill" : "lock.open.fill").font(.system(size: 14, weight: .medium))
            Text(isLocked ? "Locked · hold to unlock" : "Unlocked · click to lock").font(.sans(14))
        }
        .foregroundStyle(color.mix(with: .white, by: 0.2))
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(color.opacity(isHeld ? 0.22 : 0.08), in: shape)
        .overlay(shape.strokeBorder(color.opacity(isLocked ? 0.35 : 0.5)))
        .contentShape(Rectangle())
        .gesture(
            // One gesture for both: a press unlocks once held, a press while unlocked locks.
            // Separate long-press and tap gestures left the tap unreachable.
            DragGesture(minimumDistance: 0)
                .onChanged { _ in press() }
                .onEnded { _ in release() }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { isLocked.toggle() }
    }

    private func press() {
        guard !isHeld else { return }
        isHeld = true
        guard isLocked else {
            isLocked = true
            return
        }
        hold = Task {
            try? await Task.sleep(for: .milliseconds(800))
            if !Task.isCancelled { isLocked = false }
        }
    }

    private func release() {
        isHeld = false
        hold?.cancel()
        hold = nil
    }
}

/// The recorded layer of the current cue: what it is, where it has got to, and when it
/// fades by itself.
private struct LayerCard: View {
    let model: StageModel
    let cue: Cue

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let take = model.layerTake, let plan = model.plan {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !model.isPlaying)) { _ in
                    let elapsed = model.isPlaying ? model.elapsed : 0
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            title(take).font(.sans(18, weight: .medium)).lineLimit(1)
                            Spacer(minLength: 8)
                            HStack(spacing: 0) {
                                Text(verbatim: Self.clock(elapsed)).foregroundStyle(model.isPlaying ? Palette.accent : Palette.textSecondary)
                                Text(verbatim: " / " + Self.clock(plan.duration)).foregroundStyle(Palette.textTertiary)
                            }
                            .font(.mono(22))
                        }
                        bar(fraction: plan.duration > 0 ? elapsed / plan.duration : 0, plan: plan)
                    }
                }
                hint(plan).font(.sans(14)).foregroundStyle(Palette.textTertiary)
            } else {
                Text("No recorded layer").font(.sans(18, weight: .medium))
                Text("You play this cue live.").font(.sans(14)).foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.stagePanel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.hairline))
    }

    /// Minutes and seconds: "0:47".
    private static func clock(_ seconds: Double) -> String {
        let total = Int(max(seconds, 0).rounded(.down))
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    private func title(_ take: Take) -> Text {
        let sound = Text(SketchNames.sound(.sound(program: take.layers.first?.program)))
        let detail = take.layers.count == 1 ? sound : Text("\(take.layers.count) layers")
        return Text("\(Text("Take \(take.number)")) · \(detail)")
    }

    private func bar(fraction: Double, plan: LayerPlan) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08)).frame(height: 8)
                Capsule().fill(Palette.accent)
                    .frame(width: max(width * min(max(fraction, 0), 1), fraction > 0 ? 8 : 0), height: 8)
                    // The bar dims with the layer, so a fade can be seen as well as heard.
                    .opacity(model.isPlaying ? 0.35 + 0.65 * model.level : 1)
                    .filamentGlow(radius: 7)
                if let target = cue.targetSeconds, plan.fadeOutStart != nil {
                    // Where the cue is meant to end.
                    Rectangle().fill(Palette.textPrimary.opacity(0.5)).frame(width: 2, height: 20)
                        .offset(x: width * target / plan.duration - 1)
                }
            }
            .frame(height: proxy.size.height)
        }
        .frame(height: 20)
        .accessibilityHidden(true)
    }

    private func hint(_ plan: LayerPlan) -> Text {
        let playAlong = Text("you play live on top")
        if model.isPlaying, model.fadeDirection != 0 {
            return model.fadeDirection > 0 ? Text("Fading in") : Text("Fading out")
        }
        if let start = plan.fadeOutStart {
            return Text("\(Text("Fades out by itself from \(Self.clock(start))")) · \(playAlong)")
        }
        return Text("\(Text("Plays to the end")) · \(playAlong)")
    }
}

/// Names of pads, knobs and what they do, in the interface language.
enum ControlNames {
    static func source(_ source: ControlSource) -> Text {
        switch source.name {
        case let .pad(number): Text("Pad \(number)")
        case let .knob(number): Text("Knob \(number)")
        case let .note(number): Text("Note \(number)")
        case let .controller(number): Text("Controller \(number)")
        }
    }

    static func action(_ action: ControlAction) -> LocalizedStringKey {
        switch action {
        case .playPause: "Play or pause"
        case .restart: "Back to the start"
        case .toggleWait: "Wait mode, on or off"
        case .toggleMetronome: "Metronome, on or off"
        case .toggleCountIn: "Count-in, on or off"
        case .handLeft: "Left hand"
        case .handBoth: "Both hands"
        case .handRight: "Right hand"
        case .tempoDown: "Slower"
        case .tempoUp: "Faster"
        case .tempo: "Practice tempo"
        case .cueBack: "Previous cue"
        case .cueGo: "Next cue"
        case .playLayer: "Play layer"
        case .fadeIn: "Fade in"
        case .fadeOut: "Fade out"
        case .stopLayer: "Stop"
        case .panic: "Panic"
        case .volume: "Volume"
        }
    }

    static func context(_ context: ControlAction.Context) -> LocalizedStringKey {
        switch context {
        case .practice: "While practicing"
        case .stage: "On stage"
        case .everywhere: "Everywhere"
        }
    }
}

extension PadColor {
    /// The colour on screen, matching the lit pad.
    var color: Color {
        Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
