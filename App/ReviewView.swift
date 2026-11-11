import DesignSystem
import MusicCore
import Practice
import SwiftUI

/// After-run review: how the run went, where it went wrong, and what to practice next
/// (requirements FB-2, FB-4).
struct ReviewView: View {
    @Environment(AppModel.self) private var model
    let session: PracticeSession
    let review: PracticeSession.Review

    @State private var selectedBar: Int?

    private var analysis: RunReview { review.analysis }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                header
                HStack(alignment: .top, spacing: Spacing.m) {
                    accuracyCard
                    timingCard
                    historyCard
                }
                .frame(height: 290)
                barMap
                if let loop = analysis.suggestedLoop { suggestion(loop) }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, 32)
        }
        .background(FilamentBackground())
        .onAppear { selectedBar = analysis.suggestedLoop?.bars.lowerBound ?? analysis.bars.first?.number }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .bottom, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Run complete").font(.label).tracking(0.9).textCase(.uppercase).foregroundStyle(Palette.accent)
                Text(verbatim: session.song.title).font(.serif(44)).foregroundStyle(Palette.textPrimary).lineLimit(1)
                HStack(spacing: 6) {
                    Text("Whole piece")
                    Text(verbatim: "·")
                    switch review.handMode {
                    case .both, .listen: Text("both hands")
                    case .right: Text("right hand")
                    case .left: Text("left hand")
                    }
                    Text(verbatim: "·")
                    Text("\(Int((review.rate * 100).rounded()))% tempo")
                    if review.usedWaitMode {
                        Text(verbatim: "·")
                        Text("wait mode")
                    }
                }
                .font(.sans(13))
                .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            SecondaryButton("Play again") {
                session.dismissReview()
                session.restart()
                session.togglePlay()
            }
            SecondaryButton("Done") { model.closeSong() }
        }
    }

    // MARK: Cards

    private var accuracyCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Notes right").capsLabel()
                Spacer(minLength: 0)
                HStack(alignment: .top, spacing: 4) {
                    Text(verbatim: "\(percent(analysis.accuracy))").font(.hero).foregroundStyle(Palette.textPrimary)
                    Text(verbatim: "%").font(.serif(44)).foregroundStyle(Palette.textSecondary).padding(.top, 14)
                }
                HStack(spacing: 18) {
                    if review.history.count >= 2 {
                        let change = percent(analysis.accuracy) - percent(review.history[review.history.count - 2])
                        HStack(spacing: 5) {
                            Text(verbatim: (change >= 0 ? "+" : "") + "\(change)")
                                .font(.sans(13, weight: .semibold))
                                .foregroundStyle(change >= 0 ? Palette.noteCorrect : Palette.noteWrong)
                            Text("since last run")
                        }
                    } else {
                        Text("First run")
                    }
                    ForEach(Hand.allCases.reversed(), id: \.self) { hand in
                        if analysis.accuracyByHand.count > 1, let value = analysis.accuracyByHand[hand] {
                            HStack(spacing: 5) {
                                Text(hand == .right ? "Right" : "Left")
                                Text(verbatim: "\(percent(value))").font(.readoutSmall).foregroundStyle(Palette.textPrimary)
                            }
                        }
                    }
                }
                .font(.sans(13))
                .foregroundStyle(Palette.textSecondary)
            }
        }
        .background(alignment: .bottomLeading) {
            RadialGradient(colors: [Palette.accent.opacity(0.14), .clear], center: .bottomLeading, startRadius: 0, endRadius: 260)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }

    private var timingCard: some View {
        card {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Timing").capsLabel()
                    Spacer()
                    if let error = analysis.averageError {
                        Text("avg \(Int((error * 1000).rounded())) ms off").font(.readoutSmall).foregroundStyle(Palette.textSecondary)
                    }
                }
                Text(timingSentence).font(.serif(30)).foregroundStyle(Palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if !analysis.offsets.isEmpty {
                    VStack(spacing: 8) {
                        timingStrip
                        HStack {
                            Text("Early").foregroundStyle(Palette.noteEarly)
                            Spacer()
                            Text("On the beat")
                            Spacer()
                            Text("Late").foregroundStyle(Palette.noteLate)
                        }
                        .font(.sans(12))
                        .foregroundStyle(Palette.textTertiary)
                    }
                }
            }
        }
    }

    private var timingSentence: LocalizedStringKey {
        guard analysis.averageError != nil else { return "Timing is not measured in wait mode." }
        switch (analysis.tendency, analysis.tendencyHand) {
        case (.steady, _): return "Your timing is steady."
        case (.rushing, .left): return "You tend to rush, mostly in the left hand."
        case (.rushing, .right): return "You tend to rush, mostly in the right hand."
        case (.rushing, nil): return "You tend to rush."
        case (.dragging, .left): return "You tend to drag, mostly in the left hand."
        case (.dragging, .right): return "You tend to drag, mostly in the right hand."
        case (.dragging, nil): return "You tend to drag."
        }
    }

    /// Every timed note as a tick from early (left) to late (right), with the average as a dot.
    private var timingStrip: some View {
        Canvas { context, size in
            // The strip spans the widest judged window on each side of the beat.
            let span = PlaybackEngine.matchWindow
            func x(_ offset: Double) -> CGFloat { size.width * (0.5 + min(max(offset / span, -1), 1) / 2) }
            context.fill(Path(CGRect(x: 0, y: 16, width: size.width, height: 2)), with: .color(.white.opacity(0.1)))
            context.fill(Path(CGRect(x: size.width / 2, y: 6, width: 1, height: 22)), with: .color(Palette.textPrimary.opacity(0.45)))
            for offset in analysis.offsets {
                let color = offset < 0 ? Palette.noteEarly : Palette.noteLate
                context.fill(Path(roundedRect: CGRect(x: x(offset) - 1, y: 12, width: 2, height: 10), cornerRadius: 1), with: .color(color.opacity(0.5)))
            }
            if let average = analysis.averageOffset {
                let color = analysis.tendency == .steady ? Palette.noteCorrect : (average < 0 ? Palette.noteEarly : Palette.noteLate)
                var glow = context
                glow.addFilter(.shadow(color: color.opacity(0.7), radius: 7))
                glow.fill(Path(ellipseIn: CGRect(x: x(average) - 9, y: 8, width: 18, height: 18)), with: .color(color))
            }
        }
        .frame(height: 34)
        .accessibilityHidden(true)
    }

    private var historyCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Last \(review.history.count) runs").capsLabel()
                Canvas { context, size in
                    let values = review.history
                    let low = max((values.min() ?? 0) - 0.08, 0), high = min((values.max() ?? 1) + 0.04, 1.02)
                    for fraction in [0.1, 0.5, 0.9] {
                        context.fill(Path(CGRect(x: 0, y: size.height * fraction, width: size.width, height: 1)), with: .color(.white.opacity(0.06)))
                    }
                    func point(_ index: Int) -> CGPoint {
                        let x = values.count > 1 ? size.width * CGFloat(index) / CGFloat(values.count - 1) : size.width / 2
                        return CGPoint(x: x, y: size.height * (1 - (values[index] - low) / max(high - low, 0.01)))
                    }
                    var line = Path()
                    for index in values.indices {
                        if index == 0 { line.move(to: point(index)) } else { line.addLine(to: point(index)) }
                    }
                    context.stroke(line, with: .color(Palette.accent), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    if let last = values.indices.last {
                        context.fill(Path(ellipseIn: CGRect(origin: point(last), size: .zero).insetBy(dx: -5, dy: -5)), with: .color(Palette.accent))
                    }
                }
                .accessibilityLabel(Text(verbatim: review.history.map { "\(percent($0))%" }.joined(separator: ", ")))
                HStack {
                    Text(verbatim: "\(percent(review.history.first ?? 0))%").foregroundStyle(Palette.textTertiary)
                    Spacer()
                    Text(verbatim: "\(percent(review.history.last ?? 0))%").foregroundStyle(Palette.accent)
                }
                .font(.mono(11))
            }
        }
    }

    // MARK: Bar map

    private var barMap: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                Text("Bar by bar").font(.displayTitle).foregroundStyle(Palette.textPrimary)
                Spacer()
                HStack(spacing: 8) {
                    Text("Shaky")
                    ForEach([0.3, 0.7, 0.9, 1.0], id: \.self) { score in
                        RoundedRectangle(cornerRadius: 4).fill(color(for: score)).frame(width: 14, height: 14)
                    }
                    Text("Clean")
                }
                .font(.sans(12))
                .foregroundStyle(Palette.textTertiary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 30), spacing: 4)], spacing: 4) {
                ForEach(analysis.bars, id: \.number) { bar in
                    Button {
                        selectedBar = bar.number
                    } label: {
                        Text(verbatim: "\(bar.number)")
                            .font(.mono(10, weight: .medium))
                            .foregroundStyle(bar.score == nil ? Palette.textTertiary : Palette.accentInk)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(color(for: bar.score), in: RoundedRectangle(cornerRadius: 6))
                            .overlay {
                                if selectedBar == bar.number {
                                    RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.textPrimary, lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Bar \(bar.number)"))
                }
            }
            Palette.hairline.frame(height: 1)
            if let bar = analysis.bars.first(where: { $0.number == selectedBar }) {
                HStack(spacing: Spacing.l) {
                    Text("Bar \(bar.number)").font(.readoutSmall).foregroundStyle(Palette.accent)
                    Group {
                        if bar.score == nil {
                            Text("Nothing for you to play in this bar.")
                        } else if bar.wrongKeys + bar.missed + bar.early + bar.late == 0 {
                            Text("Clean. Every note in time and in place.")
                        } else {
                            Text("\(bar.wrongKeys) wrong · \(bar.missed) missed · \(bar.early) early · \(bar.late) late")
                        }
                    }
                    .font(.bodyText)
                    .foregroundStyle(Palette.textPrimary)
                    Spacer()
                }
            }
        }
        .padding(Spacing.l)
        .background(Palette.surface.opacity(0.8), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Palette.hairline))
    }

    /// Red below 55%, amber below 80%, soft green below 93%, green above; grey with nothing to play.
    private func color(for score: Double?) -> Color {
        guard let score else { return Color.white.opacity(0.06) }
        if score < 0.55 { return Palette.noteWrong }
        if score < 0.8 { return Palette.accent }
        if score < 0.93 { return Palette.noteCorrect.mix(with: Palette.surface, by: 0.45) }
        return Palette.noteCorrect
    }

    // MARK: Suggested loop

    private func suggestion(_ loop: RunReview.SuggestedLoop) -> some View {
        let rate = Int((loop.rate * 100).rounded())
        let title: LocalizedStringKey = switch loop.hand {
        case .left: "Loop bars \(loop.bars.lowerBound)–\(loop.bars.upperBound) at \(rate)%, left hand first"
        case .right: "Loop bars \(loop.bars.lowerBound)–\(loop.bars.upperBound) at \(rate)%, right hand first"
        case nil: "Loop bars \(loop.bars.lowerBound)–\(loop.bars.upperBound) at \(rate)%"
        }
        return HStack(spacing: 20) {
            Image(systemName: "repeat").font(.system(size: 24, weight: .medium)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.displayTitle)
                Text("Midiot raises the tempo as soon as you play it cleanly three times in a row.")
                    .font(.sans(13)).opacity(0.75)
            }
            Spacer()
            Button {
                session.startSuggestedLoop()
            } label: {
                Text("Start this loop")
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(Palette.accentHighlight)
                    .padding(.horizontal, 22)
                    .frame(height: 46)
                    .background(Palette.accentInk, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Palette.accentInk)
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, 22)
        .background(Palette.accent, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    // MARK: Helpers

    private func card(@ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Palette.hairline))
    }

    private func percent(_ value: Double) -> Int { Int((value * 100).rounded()) }
}
