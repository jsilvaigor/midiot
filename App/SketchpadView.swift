#if os(macOS)
import AppKit
#endif
import DesignSystem
import MusicCore
import Sketch
import SwiftUI
import UniformTypeIdentifiers

/// The Sketchpad: the play's scenes and cues on the left, the selected cue with its takes in
/// the middle, harmony and mood on the right, and the always-on capture along the bottom.
struct SketchpadView: View {
    let model: SketchpadModel
    @Environment(AppModel.self) private var app
    @Environment(\.locale) private var locale
    @AppStorage(NoteNamingSetting.storageKey) private var naming = NoteNaming.letters

    @State private var prompt: TextPrompt?
    @State private var promptText = ""
    @State private var confirmsDeletePlay = false
    @State private var editsOpeningDate = false

    /// A question answered by typing a name.
    struct TextPrompt {
        let title: LocalizedStringKey
        let action: (String) -> Void
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.error { errorBanner(error) }
            if let play = model.play {
                GeometryReader { proxy in
                    // A smaller iPad has less to share between the three columns.
                    let compact = Platform.isPad && proxy.size.width < 1000
                    HStack(spacing: 0) {
                        cueList(play).frame(width: compact ? 196 : 248)
                        Palette.hairline.frame(width: 1)
                        Group {
                            if let cue = model.cue {
                                CueDetail(model: model, play: play, cue: cue)
                            } else {
                                EmptyState(systemImage: "text.badge.plus", title: "No cue selected",
                                           message: "Choose a cue on the left, or add one to a scene.")
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Palette.hairline.frame(width: 1)
                        SketchAside(model: model, range: app.range).frame(width: compact ? 232 : 288)
                    }
                }
            } else {
                noPlay
            }
            Palette.hairline.frame(height: 1)
            keyboard
            Palette.hairline.frame(height: 1)
            CaptureBar(model: model)
        }
        .background(FilamentBackground())
        .alert(prompt?.title ?? "", isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } })) {
            TextField("Name", text: $promptText)
            Button("Save") {
                let text = promptText.trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { prompt?.action(text) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this play and all its takes?", isPresented: $confirmsDeletePlay) {
            Button("Delete play", role: .destructive) { model.deletePlay() }
        }
    }

    /// The keys being played, and the keys of the suggested chord being shown: its bass note
    /// in the left hand's color, the chord in the right hand's.
    private var keyboard: some View {
        var highlights: [Pitch: Color] = [:]
        if let chord = model.shownChord {
            let placed = chord.voicing(in: app.range)
            if let bass = placed.bass { highlights[bass] = Palette.handLeft }
            for tone in placed.tones { highlights[tone] = Palette.handRight }
        }
        for pitch in app.pressed {
            // A suggested key that is being pressed turns green: that one is found.
            highlights[pitch] = highlights[pitch] != nil ? Palette.noteCorrect : Palette.textPrimary.mix(with: Palette.accent, by: 0.5)
        }
        let whiteKeys = app.range.pitches.count { !$0.isBlackKey }
        return KeyboardView(
            range: app.range, highlights: highlights, naming: naming,
            onPress: app.mouseDown(on:), onRelease: app.mouseUp(on:)
        )
        .frame(height: 104)
        .frame(maxWidth: CGFloat(whiteKeys) * 44)
        .padding(.horizontal, Spacing.l)
        .padding(.top, 8).padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(Palette.background)
    }

    private func ask(_ title: LocalizedStringKey, initial: String = "", action: @escaping (String) -> Void) {
        promptText = initial
        prompt = TextPrompt(title: title, action: action)
    }

    private func string(_ resource: LocalizedStringResource) -> String {
        var resource = resource
        resource.locale = locale
        return String(localized: resource)
    }

    private func newPlay() {
        ask("New play") { title in
            model.newPlay(title: title, sceneTitle: string("Scene 1"), cueName: string("New cue"))
        }
    }

    private var noPlay: some View {
        EmptyState(systemImage: "theatermasks", title: "No play yet",
                   message: "A play holds scenes, and each scene holds cues. Everything you keep from the keyboard goes into a cue.")
            .overlay {
                // Below the message, which is centered in the same space.
                PrimaryButton("New play", systemImage: "plus") { newPlay() }.offset(y: 170)
            }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Palette.noteWrong)
            Text(verbatim: message).font(.sans(13)).foregroundStyle(Palette.textPrimary)
            Spacer()
            Button("Dismiss") { model.error = nil }
                .buttonStyle(.plain).font(.sans(13, weight: .medium)).foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(Palette.noteWrong.opacity(0.08))
    }

    // MARK: Scenes and cues

    private func cueList(_ play: Play) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                playHeader(play)
                ForEach(Array(play.scenes.enumerated()), id: \.element.id) { index, scene in
                    sceneSection(scene, number: index + 1, in: play)
                }
                Button {
                    ask("New scene") { model.addScene(title: $0) }
                } label: {
                    Label("Add scene", systemImage: "plus")
                        .font(.sans(13)).foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, 8).frame(height: Platform.touch(40)).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func playHeader(_ play: Play) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Its own key: "Play" alone is the verb on the transport button.
                Text("Play (theater)").capsLabel()
                Spacer()
                Menu {
                    ForEach(model.plays) { other in
                        Toggle(isOn: Binding(get: { other.id == play.id }, set: { _ in model.selectPlay(other.id) })) {
                            Text(verbatim: other.title)
                        }
                    }
                    Divider()
                    Button("New play…") { newPlay() }
                    Button("Rename…") { ask("Rename play", initial: play.title) { title in model.updatePlay { $0.title = title } } }
                    Button("Opening date…") { editsOpeningDate = true }
                    Divider()
                    Button("Delete play…", role: .destructive) { confirmsDeletePlay = true }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.textSecondary).frame(width: Platform.touch(32), height: Platform.touch(28)).contentShape(Rectangle())
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel(Text("Play options"))
                .popover(isPresented: $editsOpeningDate) { openingDateEditor(play) }
            }
            Text(verbatim: play.title).font(.serif(26)).foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: 5) {
                if let opens = play.opensOn {
                    Text("Opens \(opens, format: .dateTime.day().month(.abbreviated).year())")
                    Text(verbatim: "·")
                }
                if play.cueCount == 1 { Text("1 cue") } else { Text("\(play.cueCount) cues") }
            }
            .font(.sans(12)).foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, 8)
    }

    private func openingDateEditor(_ play: Play) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Opening date").capsLabel()
            DatePicker(
                "Opening date",
                selection: Binding(get: { play.opensOn ?? Date() }, set: { date in model.updatePlay { $0.opensOn = date } }),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical).labelsHidden()
            Button("No date") {
                model.updatePlay { $0.opensOn = nil }
                editsOpeningDate = false
            }
        }
        .padding(16)
    }

    private func sceneSection(_ scene: PlayScene, number: Int, in play: Play) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(verbatim: scene.title).font(.sans(12)).foregroundStyle(Palette.textTertiary).lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    model.addCue(to: scene.id, name: string("New cue"))
                } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.textSecondary).frame(width: Platform.touch(28), height: Platform.touch(24)).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Text("Add a cue to this scene"))
                .accessibilityLabel(Text("Add a cue to this scene"))
            }
            .padding(.leading, 8).padding(.bottom, 2)
            .contextMenu {
                Button("Rename…") { ask("Rename scene", initial: scene.title) { model.renameScene(scene.id, to: $0) } }
                Button("Delete scene", role: .destructive) { model.deleteScene(scene.id) }
            }
            ForEach(scene.cues) { cue in
                cueRow(cue, label: play.label(of: cue.id) ?? "")
            }
        }
    }

    private func cueRow(_ cue: Cue, label: String) -> some View {
        let isSelected = cue.id == model.selectedCueID
        return Button {
            model.selectCue(cue.id)
        } label: {
            HStack(spacing: 8) {
                Text(verbatim: label).font(.mono(12)).foregroundStyle(Palette.textSecondary).frame(width: 30, alignment: .leading)
                Text(verbatim: cue.name).font(.sans(13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary).lineLimit(1)
                Spacer(minLength: 4)
                Circle().fill(SketchNames.color(of: cue.status)).frame(width: 7, height: 7)
                    .accessibilityLabel(Text(SketchNames.status(cue.status)))
            }
            .padding(.horizontal, 10)
            .frame(minHeight: Platform.touch(40))
            .background(isSelected ? Palette.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            Button("Delete cue", role: .destructive) { model.deleteCue(cue.id) }
        }
    }
}

// MARK: - The selected cue

/// Name, note, target and status of a cue, its takes, and the tools that work on a take.
private struct CueDetail: View {
    let model: SketchpadModel
    let play: Play
    let cue: Cue
    @Environment(\.locale) private var locale
    @State private var targetText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                chips
                takes
                if let take = model.take { layers(of: take) }
                if model.take != nil, !Platform.isPad { toolbar }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // On the iPad the tools stay in reach: the keyboard leaves little room for scrolling to them.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.take != nil, Platform.isPad {
                toolbar
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.background)
                    .overlay(alignment: .top) { Palette.hairline.frame(height: 1) }
            }
        }
        .onAppear { targetText = Self.clock(cue.targetSeconds) }
        .onChange(of: cue.id) { targetText = Self.clock(cue.targetSeconds) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Cue \(play.label(of: cue.id) ?? "")").font(.mono(13)).foregroundStyle(Palette.accent)
                Spacer()
                // Exports stay on the Mac: the notation engine behind them is heavy for an iPad.
                #if os(macOS)
                HStack(spacing: 8) {
                    SketchButton("MIDI") { export(.midi) }
                    SketchButton("MusicXML") { export(.musicXML) }
                    Menu {
                        Button("Grand staff") { export(.pdfGrandStaff) }
                        Button("Lead sheet") { export(.pdfLeadSheet) }
                    } label: {
                        Text("PDF draft").font(.sans(13)).foregroundStyle(Palette.textPrimary)
                            .padding(.horizontal, 14).frame(height: Platform.touch(38))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.hairlineStrong))
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                }
                .disabled(model.exportTake == nil)
                .opacity(model.exportTake == nil ? 0.45 : 1)
                #endif
            }
            VStack(alignment: .leading, spacing: 6) {
                TextField("Cue name", text: Binding(get: { cue.name }, set: { name in model.updateCue { $0.name = name } }))
                    .textFieldStyle(.plain).font(.serif(44)).foregroundStyle(Palette.textPrimary)
                TextField(
                    "What happens on stage, and when the music ends",
                    text: Binding(get: { cue.note }, set: { note in model.updateCue { $0.note = note } }), axis: .vertical
                )
                .textFieldStyle(.plain).font(.sans(13)).foregroundStyle(Palette.textSecondary).lineLimit(1...3)
            }
        }
    }

    private var chips: some View {
        FlowLayout(spacing: 10) {
            chip {
                Text("Target")
                TextField("0:00", text: $targetText)
                    .textFieldStyle(.plain).font(.mono(13)).foregroundStyle(Palette.textPrimary)
                    .frame(width: 40)
                    .onSubmit { commitTarget() }
            }
            if let best = cue.bestTake {
                chip {
                    Text("Best take")
                    Text(verbatim: Self.clock(best.seconds)).font(.mono(13)).foregroundStyle(Palette.textPrimary)
                }
            }
            Menu {
                ForEach(Cue.Status.allCases, id: \.self) { status in
                    Toggle(isOn: Binding(get: { cue.status == status }, set: { _ in model.updateCue { $0.status = status } })) {
                        Text(SketchNames.status(status))
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Circle().fill(SketchNames.color(of: cue.status)).frame(width: 7, height: 7)
                    Text(SketchNames.status(cue.status))
                }
                .font(.sans(13)).foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, 12).frame(height: Platform.touch(34))
                .background(Palette.surfaceRaised.opacity(0.7), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel(Text("Status"))
            if let mood = cue.mood {
                (Text("Mood") + Text(verbatim: " · ") + Text(SketchNames.mood(mood)))
                    .font(.sans(13)).foregroundStyle(Palette.handLeft.mix(with: .white, by: 0.3))
                    .padding(.horizontal, 12).frame(height: 34)
                    .background(Palette.handLeft.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
    }

    private func chip(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 8) { content() }
            .font(.sans(13)).foregroundStyle(Palette.textSecondary).lineLimit(1).fixedSize()
            .padding(.horizontal, 12).frame(height: 34)
            .background(Palette.surfaceRaised.opacity(0.7), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    /// Reads "0:45", "45" or "1:30" as a length; anything else clears the target.
    private func commitTarget() {
        let parts = targetText.split(separator: ":").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        var seconds: Double?
        if parts.count == 1, let only = parts[0] { seconds = only }
        if parts.count == 2, let minutes = parts[0], let rest = parts[1] { seconds = minutes * 60 + rest }
        let target = seconds.flatMap { $0 > 0 ? $0 : nil }
        model.updateCue { $0.targetSeconds = target }
        targetText = Self.clock(target)
    }

    // MARK: Takes

    @ViewBuilder private var takes: some View {
        if cue.takes.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("No takes yet").font(.sans(15, weight: .medium)).foregroundStyle(Palette.textPrimary)
                Text("Play the idea, then press “Keep last 30 s” below. The app has been listening all along.")
                    .font(.sans(13)).foregroundStyle(Palette.textSecondary)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.textPrimary.opacity(0.16), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
        } else {
            VStack(spacing: 10) {
                // Newest first, as on the design.
                ForEach(cue.takes.reversed()) { take in takeRow(take) }
            }
        }
    }

    private func takeRow(_ take: Take) -> some View {
        let isSelected = take.id == model.selectedTakeID
        let isSounding = take.id == model.playingTakeID
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Take \(take.number)").font(.sans(14, weight: .medium)).foregroundStyle(Palette.textPrimary)
                (Text(verbatim: Self.clock(take.seconds) + " · ") + (take.layers.count == 1 ? Text("1 layer") : Text("\(take.layers.count) layers")))
                    .font(.mono(12)).foregroundStyle(Palette.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(width: 132, alignment: .leading)
            TakeRoll(
                take: take, selected: isSelected ? model.selectedNotes : [],
                playhead: isSounding ? { model.beat } : nil,
                onTap: isSelected ? { ref in
                    guard let ref else { return model.selectedNotes = [] }
                    if !model.selectedNotes.insert(ref).inserted { model.selectedNotes.remove(ref) }
                } : nil
            )
            .frame(height: isSelected ? 124 : 56)
            Group {
                if take.isKeeper {
                    Pill(Text("Keeper"), tone: .green).fixedSize()
                } else {
                    Color.clear
                }
            }
            .frame(minWidth: 64, minHeight: 24, maxHeight: 24)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(isSelected ? Palette.surfaceRaised.opacity(0.7) : Palette.surface.opacity(0.8),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(isSelected ? Palette.accent.opacity(0.35) : Palette.hairline))
        .contentShape(Rectangle())
        .onTapGesture { model.selectTake(take.id) }
        .contextMenu {
            Button(take.isKeeper ? "Not the keeper" : "Mark as keeper") { model.toggleKeeper(take.id) }
            Button("Delete take", role: .destructive) { model.deleteTake(take.id) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Layers

    /// One row per layer of the selected take: its sound, how much it holds, and what can be
    /// done to it alone.
    private func layers(of take: Take) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Layers").capsLabel()
            ForEach(Array(take.layers.enumerated()), id: \.element.id) { index, layer in
                layerRow(layer, number: index + 1)
            }
        }
    }

    private func layerRow(_ layer: Layer, number: Int) -> some View {
        HStack(spacing: 8) {
            Text("Layer \(number)").font(.sans(13, weight: .medium)).foregroundStyle(Palette.textPrimary)
                .frame(width: 66, alignment: .leading)
            Menu {
                ForEach(SketchSound.Group.allCases, id: \.self) { group in
                    Section {
                        ForEach(SketchSound.catalog.filter { $0.group == group }) { sound in
                            Toggle(isOn: Binding(get: { sound.program == layer.program }, set: { _ in model.setProgram(sound.program, ofLayer: layer.id) })) {
                                Text(SketchNames.sound(sound))
                            }
                        }
                    } header: {
                        Text(SketchNames.group(group))
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(SketchNames.sound(SketchSound.sound(program: layer.program)))
                        .font(.sans(13)).foregroundStyle(Palette.textPrimary).lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundStyle(Palette.textSecondary)
                }
                .padding(.horizontal, 12).frame(width: 164, height: Platform.touch(34))
                .background(Palette.surfaceRaised.opacity(0.7), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel(Text("Instrument"))
            Group {
                if layer.notes.count == 1 { Text("1 note") } else { Text("\(layer.notes.count) notes") }
            }
            .font(.mono(12)).foregroundStyle(Palette.textSecondary).lineLimit(1).fixedSize()
            Spacer(minLength: 0)
            layerButton(layer.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        label: layer.isMuted ? "Unmute layer" : "Mute layer",
                        tint: layer.isMuted ? Palette.accentHighlight : Palette.textSecondary) { model.toggleMute(layer: layer.id) }
            layerButton("trash", label: "Delete layer", tint: Palette.textSecondary) { model.deleteLayer(layer.id) }
        }
        .padding(.horizontal, 14).frame(minHeight: 48)
        .background(Palette.surface.opacity(0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.hairline))
        .opacity(layer.isMuted ? 0.6 : 1)
        .accessibilityElement(children: .contain)
    }

    private func layerButton(_ systemImage: String, label: LocalizedStringKey, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: 13, weight: .medium)).foregroundStyle(tint)
                .frame(width: Platform.touch(34), height: Platform.touch(34)).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }

    // MARK: Tools

    private var toolbar: some View {
        let picked = model.selectedNotes.count
        return VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 8) {
                SketchButton(model.isPlaying && !model.isOverdubbing ? "Stop" : "Play",
                             systemImage: model.isPlaying && !model.isOverdubbing ? "stop.fill" : "play.fill") { model.togglePlay() }
                    .disabled(model.isOverdubbing)
                Button {
                    if model.isOverdubbing { model.stop() } else { model.overdub() }
                } label: {
                    HStack(spacing: 8) {
                        Circle().fill(model.isOverdubbing ? Palette.noteWrong : Palette.accentInk).frame(width: 9, height: 9)
                        Text(model.isOverdubbing ? "Finish layer" : "Overdub a layer").font(.sans(13, weight: .semibold))
                    }
                    .foregroundStyle(Palette.accentInk)
                    .padding(.horizontal, 14).frame(height: Platform.touch(40))
                    .background(Palette.accent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                SketchButton("Trim") { model.trim() }
                    .help(Text("With notes selected, keeps only that stretch. Otherwise removes the silence at the start."))
                quantizeMenu
                transposeMenu
                SketchButton("Delete notes") { model.deleteSelectedNotes() }
                    .disabled(picked == 0).opacity(picked == 0 ? 0.45 : 1)
                SketchButton("Undo", systemImage: "arrow.uturn.backward") { model.undo() }
                    .disabled(!model.canUndo).opacity(model.canUndo ? 1 : 0.45)
            }
            Group {
                if model.isOverdubbing {
                    Text("Recording a new layer. Play along after the count-in; it ends with the take.")
                } else if picked > 0 {
                    if picked == 1 { Text("1 note selected") } else { Text("\(picked) notes selected") }
                } else {
                    (Platform.isPad ? Text("Tap notes in the take to select them.") : Text("Click notes in the take to select them."))
                }
            }
            .font(.sans(12)).foregroundStyle(model.isOverdubbing ? Palette.accentHighlight : Palette.textTertiary)
        }
    }

    private var quantizeMenu: some View {
        let grids: [(Double, String)] = [(1, "1/4"), (0.5, "1/8"), (0.25, "1/16")]
        let current = grids.first { $0.0 == model.quantizeGrid }?.1 ?? "1/8"
        return Menu {
            ForEach(grids, id: \.0) { grid in
                Button {
                    model.quantizeGrid = grid.0
                    model.quantize()
                } label: {
                    Text("To \(grid.1) notes")
                }
            }
        } label: {
            SketchButton.label(Text("Quantize") + Text(verbatim: " · " + current), systemImage: nil)
        } primaryAction: {
            model.quantize()
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }

    private var transposeMenu: some View {
        Menu {
            Button("Up a semitone") { model.transpose(by: 1) }
            Button("Down a semitone") { model.transpose(by: -1) }
            Button("Up an octave") { model.transpose(by: 12) }
            Button("Down an octave") { model.transpose(by: -12) }
        } label: {
            SketchButton.label(Text("Transpose"), systemImage: nil)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }

    // MARK: Export

    private func export(_ format: SketchpadModel.ExportFormat) {
        func string(_ resource: LocalizedStringResource) -> String {
            var resource = resource
            resource.locale = locale
            return String(localized: resource)
        }
        let label = play.label(of: cue.id) ?? ""
        let number = model.exportTake?.number ?? 0
        guard let data = model.export(
            format, layerName: { string("Layer \($0)") },
            subtitle: play.title + " · " + string("Cue \(label)") + " · " + string("Take \(number)")
        ) else {
            model.error = string("This take could not be exported.")
            return
        }
        #if os(macOS)
        let panel = NSSavePanel()
        let name = cue.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "\(label) \(name).\(format.fileExtension)"
        if let type = UTType(filenameExtension: format.fileExtension) { panel.allowedContentTypes = [type] }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try data.write(to: url) } catch { model.error = error.localizedDescription }
        #else
        _ = data
        #endif
    }

    static func clock(_ seconds: Double?) -> String {
        guard let seconds else { return "" }
        let total = Int(seconds.rounded())
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }
}

/// Bordered 40-point button used across the Sketchpad's toolbars.
struct SketchButton: View {
    private let title: LocalizedStringKey
    private let systemImage: String?
    private let action: () -> Void

    init(_ title: LocalizedStringKey, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) { Self.label(Text(title), systemImage: systemImage) }
            .buttonStyle(.plain)
    }

    static func label(_ title: Text, systemImage: String?) -> some View {
        HStack(spacing: 8) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 11, weight: .semibold)) }
            title.font(.sans(13))
        }
        .foregroundStyle(Palette.textPrimary)
        .padding(.horizontal, 14).frame(height: Platform.touch(40))
        .background(Palette.surfaceRaised.opacity(0.7), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Palette.hairlineStrong))
        .contentShape(Rectangle())
    }
}

// MARK: - Piano roll

/// A take drawn as a small piano roll: time left to right, pitch bottom to top, the left
/// hand's range in blue. Selected notes are drawn bright with an outline.
struct TakeRoll: View {
    let take: Take
    var selected: Set<NoteRef> = []
    /// Position in beats while the take plays; read every frame.
    var playhead: (() -> Double)?
    /// Called with the note under a click, or nil for empty space. Nil makes the roll display-only.
    var onTap: ((NoteRef?) -> Void)?

    var body: some View {
        GeometryReader { proxy in
            let layout = Layout(take: take, size: proxy.size)
            ZStack {
                Canvas { context, _ in
                    for (ref, note) in layout.notes {
                        let frame = layout.frame(of: note)
                        let isSelected = selected.contains(ref)
                        let color = note.pitch < Take.handSplit ? Palette.handLeft : Palette.handRight
                        let path = Path(roundedRect: frame, cornerRadius: min(frame.height / 2, 2))
                        let muted = take.layers.indices.contains(ref.layer) && take.layers[ref.layer].isMuted
                        context.fill(path, with: .color(color.opacity(muted ? 0.25 : selected.isEmpty || isSelected ? 0.9 : 0.4)))
                        if isSelected {
                            context.stroke(Path(roundedRect: frame.insetBy(dx: -1.5, dy: -1.5), cornerRadius: 3),
                                           with: .color(Palette.textPrimary), lineWidth: 1.5)
                        }
                    }
                }
                if let playhead {
                    TimelineView(.animation) { timeline in
                        // Read per tick, so the playhead is redrawn every frame.
                        let beat = playhead()
                        Canvas { context, size in
                            _ = timeline.date
                            let x = layout.x(atBeat: max(beat, 0))
                            var glow = context
                            glow.addFilter(.shadow(color: Palette.accent.opacity(0.8), radius: 5))
                            glow.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)), with: .color(Palette.accent))
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in onTap?(layout.note(at: location)) }
            .allowsHitTesting(onTap != nil)
        }
        .background(Color(hex: 0x0E0F12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }

    struct Layout {
        let notes: [(ref: NoteRef, note: SketchNote)]
        private let size: CGSize
        private let length: Double
        private let low: Int
        private let rows: Int
        private let inset: CGFloat = 6

        init(take: Take, size: CGSize) {
            self.size = size
            notes = take.layers.enumerated().flatMap { layerIndex, layer in
                layer.notes.enumerated().map { (NoteRef(layer: layerIndex, index: $0.offset), $0.element) }
            }
            length = max(take.length, 1)
            // At least two octaves, so a take of a few close notes is not stretched tall.
            let span = take.pitchSpan ?? 60...60
            let extra = max(24 - (span.upperBound - span.lowerBound + 1), 0)
            low = span.lowerBound - extra / 2
            rows = span.upperBound - span.lowerBound + 1 + extra
        }

        private var rowHeight: CGFloat { (size.height - inset * 2) / CGFloat(rows) }

        func x(atBeat beat: Double) -> CGFloat {
            inset + CGFloat(beat / length) * (size.width - inset * 2)
        }

        func frame(of note: SketchNote) -> CGRect {
            let height = min(max(rowHeight, 2.5), 6)
            let center = size.height - inset - (CGFloat(note.pitch - low) + 0.5) * rowHeight
            let x = x(atBeat: note.start)
            return CGRect(x: x, y: center - height / 2, width: max(self.x(atBeat: note.end) - x - 1, 3), height: height)
        }

        /// The note under a point, with a little slack; the topmost layer wins.
        func note(at point: CGPoint) -> NoteRef? {
            notes.last { frame(of: $0.note).insetBy(dx: -3, dy: -3).contains(point) }?.ref
        }
    }
}

/// Lays children out left to right, wrapping to a new line when the width runs out.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y), proposal: .unspecified)
            }
        }
    }

    private struct Row {
        var items: [(index: Int, x: CGFloat)] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            var row = rows[rows.count - 1]
            if !row.items.isEmpty, row.width + spacing + size.width > width {
                rows.append(Row(y: row.y + row.height + spacing))
                row = rows[rows.count - 1]
            }
            let x = row.items.isEmpty ? 0 : row.width + spacing
            row.items.append((index, x))
            row.width = x + size.width
            row.height = max(row.height, size.height)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
