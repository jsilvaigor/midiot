import DesignSystem
import Library
import MusicCore
import SwiftUI
import UniformTypeIdentifiers

/// The song library: import by button or drag-and-drop, then pick a song to practice.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var isImporting = false
    @State private var isDropTargeted = false

    private static let importTypes: [UTType] = [.midi, .xml]
        + ["musicxml", "mxl"].compactMap { UTType(filenameExtension: $0) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if let error = model.libraryError { errorBanner(error) }
                dropZone
                if !model.songs.isEmpty { table }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(FilamentBackground())
        .dropDestination(for: URL.self) { urls, _ in
            model.importSongs(from: urls)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: Self.importTypes, allowsMultipleSelection: true) { result in
            if case let .success(urls) = result { model.importSongs(from: urls) }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Library").font(.display).foregroundStyle(Palette.textPrimary)
                Text("Your imports stay on this Mac.").font(.bodyText).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            PrimaryButton("Import", systemImage: "plus") { isImporting = true }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Palette.noteWrong)
            Text(verbatim: message).font(.sans(13)).foregroundStyle(Palette.textPrimary)
            Spacer()
            Button("Dismiss") { model.libraryError = nil }
                .buttonStyle(.plain)
                .font(.sans(13, weight: .medium))
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(16)
        .background(Palette.noteWrong.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.noteWrong.opacity(0.25)))
    }

    private var dropZone: some View {
        HStack(spacing: 18) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 56, height: 56)
                .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Drop a score here").font(.sans(15, weight: .medium)).foregroundStyle(Palette.textPrimary)
                Text("MIDI (.mid) or MusicXML (.musicxml, .mxl).").font(.sans(13)).foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .background(isDropTargeted ? Palette.accentSoft : Color.white.opacity(0.015),
                    in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(isDropTargeted ? Palette.accent.opacity(0.6) : Palette.textPrimary.opacity(0.16),
                              style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
    }

    private var table: some View {
        VStack(spacing: 0) {
            row {
                Text("Piece").capsLabel()
            } format: {
                Text("Format").capsLabel()
            } keys: {
                Text("Keys").capsLabel()
            } length: {
                Text("Length").capsLabel()
            } added: {
                Text("Added").capsLabel()
            }
            .padding(.vertical, 12)

            ForEach(model.songs) { entry in
                Palette.hairline.frame(height: 1)
                Button {
                    model.open(entry)
                } label: {
                    row {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: entry.title).font(.serif(21)).foregroundStyle(Palette.textPrimary).lineLimit(1)
                            Text("\(entry.noteCount) notes").font(.sans(12)).foregroundStyle(Palette.textSecondary)
                        }
                    } format: {
                        Pill(Text(verbatim: entry.format == .midi ? "MIDI" : "MusicXML"), tone: .blue)
                    } keys: {
                        keysPill(for: entry)
                    } length: {
                        Text(verbatim: Self.clock(entry.durationSeconds)).font(.readoutSmall).foregroundStyle(Palette.textPrimary)
                    } added: {
                        Text(entry.addedAt, format: .dateTime.day().month(.abbreviated))
                            .font(.sans(13)).foregroundStyle(Palette.textSecondary)
                    }
                    .frame(minHeight: 64)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Delete", role: .destructive) { model.delete(entry) }
                }
            }
        }
        .background(Palette.surface.opacity(0.8), in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous).strokeBorder(Palette.hairline))
    }

    @ViewBuilder private func keysPill(for entry: SongEntry) -> some View {
        if entry.fits(.twentyFiveKeys) {
            Pill(Text("Fits 25"), tone: .green)
        } else if entry.fits(.fortyNineKeys) {
            Pill(Text("49 keys"))
        } else {
            Pill(Text("Wider than 49"), tone: .amber)
        }
    }

    /// One table row; the header uses the same columns so everything lines up.
    private func row(
        @ViewBuilder piece: () -> some View, @ViewBuilder format: () -> some View,
        @ViewBuilder keys: () -> some View, @ViewBuilder length: () -> some View,
        @ViewBuilder added: () -> some View
    ) -> some View {
        HStack(spacing: Spacing.m) {
            piece().frame(maxWidth: .infinity, alignment: .leading)
            format().frame(width: 110, alignment: .leading)
            keys().frame(width: 130, alignment: .leading)
            length().frame(width: 80, alignment: .leading)
            added().frame(width: 90, alignment: .leading)
        }
        .padding(.horizontal, 24)
    }

    private static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }
}
