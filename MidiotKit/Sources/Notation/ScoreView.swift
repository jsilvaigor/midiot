import MusicCore
import SwiftUI

/// Scrolling sheet music with a moving cursor, colored notes and a shaded loop (requirement SP-1).
public struct ScoreView: View {
    private let pages: [ScoreScene]
    private let layout: ScoreLayout
    private let ink: Color
    private let accent: Color
    private let noteColors: [String: Color]
    private let loopBars: ClosedRange<Int>?
    private let position: () -> Double
    private let onTapMeasure: (Int) -> Void

    @State private var scroll = ScrollPosition(edge: .top)
    @State private var width: CGFloat = 0
    /// Top of the system last scrolled to, to scroll only when the music moves to a new line.
    @State private var shownSystem: ScoreLayout.Position?

    private let pageSpacing: CGFloat = 12

    /// - Parameters:
    ///   - ink: color of the notation.
    ///   - accent: color of the cursor and the loop shading.
    ///   - noteColors: color per note, keyed by `Note.notationID`.
    ///   - position: the current beat; read every frame.
    ///   - onTapMeasure: called with the number of a bar when it is clicked.
    public init(
        pages: [ScoreScene], layout: ScoreLayout, ink: Color, accent: Color,
        noteColors: [String: Color] = [:], loopBars: ClosedRange<Int>? = nil,
        position: @escaping () -> Double, onTapMeasure: @escaping (Int) -> Void = { _ in }
    ) {
        self.pages = pages
        self.layout = layout
        self.ink = ink
        self.accent = accent
        self.noteColors = noteColors
        self.loopBars = loopBars
        self.position = position
        self.onTapMeasure = onTapMeasure
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: pageSpacing) {
                ForEach(pages.indices, id: \.self) { index in
                    page(index)
                }
            }
        }
        .scrollPosition($scroll)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .task(id: width) { await followCursor() }
    }

    private func page(_ index: Int) -> some View {
        let scene = pages[index]
        let scale = scene.size.width > 0 ? width / scene.size.width : 1
        return ScoreCanvas(scene: scene, ink: ink, noteColors: noteColors)
            .background(alignment: .topLeading) { loopShading(page: index, scale: scale) }
            .overlay {
                TimelineView(.animation) { _ in
                    Canvas { context, _ in
                        guard let cursor = layout.position(atBeat: position()), cursor.page == index else { return }
                        let line = CGRect(x: cursor.x * scale - 1, y: cursor.top * scale,
                                          width: 2, height: (cursor.bottom - cursor.top) * scale)
                        var glow = context
                        glow.addFilter(.shadow(color: accent.opacity(0.8), radius: 6))
                        glow.fill(Path(roundedRect: line, cornerRadius: 1), with: .color(accent))
                    }
                }
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let point = CGPoint(x: location.x / scale, y: location.y / scale)
                if let number = layout.measure(at: point, page: index) { onTapMeasure(number) }
            }
    }

    @ViewBuilder private func loopShading(page: Int, scale: CGFloat) -> some View {
        if let loopBars {
          // An explicit stack: without it the bars are centered on each other before being placed.
          ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(Array(loopBars), id: \.self) { number in
                if let bar = layout.frame(ofMeasure: number), bar.page == page {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(accent.opacity(0.12))
                        .frame(width: bar.frame.width * scale, height: bar.frame.height * scale)
                        .offset(x: bar.frame.minX * scale, y: bar.frame.minY * scale)
                }
            }
          }
        }
    }

    /// Scrolls so the line of music being played stays in view.
    private func followCursor() async {
        while !Task.isCancelled {
            if width > 0, let cursor = layout.position(atBeat: position()),
               cursor.page != shownSystem?.page || cursor.top != shownSystem?.top {
                shownSystem = cursor
                let pagesAbove = pages.prefix(cursor.page).reduce(CGFloat(0)) { total, scene in
                    total + scene.size.height * (width / max(scene.size.width, 1)) + pageSpacing
                }
                let scale = width / max(pages[cursor.page].size.width, 1)
                withAnimation(.easeInOut(duration: 0.35)) {
                    scroll.scrollTo(y: max(pagesAbove + cursor.top * scale - 24, 0))
                }
            }
            try? await Task.sleep(for: .milliseconds(120))
        }
    }
}
