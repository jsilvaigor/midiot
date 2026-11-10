# Midiot — Milestone 1: Play Songs

Status: plan v1, 2026-11-10. Architecture in [ARCHITECTURE.md](ARCHITECTURE.md); requirement IDs from [REQUIREMENTS.md](REQUIREMENTS.md).

## Goal

Plug in either keyboard, import a song, and practice it with sheet music or falling notes, wait mode, tempo control, loops, hands separate, and live note coloring.

## In scope

SP-1 to SP-5, SP-7, FB-1, SS-1, SS-2, HW-1, HW-3, HW-4, SN-1 (piano only), SN-4, SN-5, DS-1 to DS-3, PL-1 to PL-5.

Partially in scope:

- **SP-6 fingering**: fingerings present in an imported MusicXML file are shown. Generated suggestions come in milestone 2.
- **HW-5 pedal**: sustain affects the sound. Display and scoring come in milestone 2.
- **HW-2 dual-keyboard roles**: with both connected, both play. Pad and knob control comes in milestone 4.

Out of scope: after-run review, adaptive practice, history screens, curriculum, drills, built-in library, composing, live mode. Run results are stored silently so milestone 2 has data.

## Phases

Each phase ends in something that runs and can be judged by hand.

### Phase 0 — Skeleton

- `project.yml` (XcodeGen), app target, `MidiotKit` package with empty modules, test target.
- Design tokens and the main window shell: sidebar (Library, Practice, Settings) in the dark studio look.
- String Catalog with English and Portuguese; in-app language switch.

**Done when:** the app builds, launches to the styled shell, switches language, and `swift test` passes.

### Phase 1 — Hear the keyboard

- `MidiIO`: device discovery, hot-plug, profiles for the A-49 and Launchkey Mini, `PerformanceEvent` stream.
- `Sound`: audio engine, `Instrument` protocol, `SamplerInstrument` with the piano SoundFont, sustain pedal.
- `KeyboardView`: on-screen keyboard sized to the connected device, keys light up as played, note names in either naming system.
- Device status in the toolbar.
- Latency measurement and buffer tuning.

**Done when:** plugging in either keyboard makes it playable within a second, unplugging does not crash, and playing feels immediate on wired output.

### Phase 2 — Notation spike

Time-boxed experiment, done early because it is the largest risk.

- Add Verovio through Swift Package Manager; load one MusicXML file; render SVG.
- Try display options A (native drawing of the SVG) and B (`WKWebView`) from the architecture risk table.
- Check: read notes, timing, staff, and element IDs back from Verovio; color one note by ID; move a cursor smoothly.

**Done when:** a short written result in this file names the chosen option, with option C (custom renderer) as fallback if both fail.

### Phase 3 — Songs in, falling notes out

- `MusicCore`: `Song`, `TempoMap`, `KeyboardRange`.
- `ScoreImport`: MIDI file import with hand assignment and a manual split-point control; MusicXML import through Verovio.
- `Library`: song storage on disk, library screen with import by drag-and-drop or file picker, "fits 25 keys" badge.
- `Transport` and listening playback: the app plays the song through the sampler.
- `FallingNotesView`: notes fall onto the keyboard, colored by hand, synced to the transport.
- Metronome with count-in.

**Done when:** an imported MIDI file and an imported MusicXML file both play back with falling notes in sync with the sound, at any tempo from 25% to 150%.

### Phase 4 — Practice engine

- `Matcher` and `PracticeSession`: wait mode, tempo scale, loop range, active-hand selection with the app playing the other hand.
- Live coloring on falling notes and keys: correct, wrong, early, late, missed.
- Practice toolbar: play/pause, restart, tempo, loop in/out by bar, hands, wait-mode toggle, metronome.
- Keyboard shortcuts for all transport actions.
- `RunResult` saved per run.
- Unit tests for the matcher: chords, repeated notes, early and late hits, wrong notes during wait.

**Done when:** a two-hand piece can be practiced right hand only, looped over four bars at 60% tempo in wait mode, with correct coloring throughout.

### Phase 5 — Sheet view

- `ScoreView` built on the phase 2 choice: grand staff, moving cursor, auto-scroll, per-note coloring from `PracticeState`.
- View switch: sheet, falling notes, or both.
- Loop selection by clicking bars in the score.
- Imported fingerings shown on the score.
- MIDI → MusicXML transcriber so MIDI imports get a draft sheet.

**Done when:** the phase 4 scenario works identically in sheet view, and both views stay in sync when shown together.

### Phase 6 — Fit and finish

- Settings: note naming, language, audio output, latency calibration tool with Bluetooth warning, device list.
- 25-key handling: one-hand and octave-folded options for songs that do not fit.
- Empty states, error messages for bad files, window state restoration.
- Visual polish pass against the design tokens; app icon.
- `Resources/LICENSES.md` complete.
- A handful of public-domain test pieces bundled for first launch.

**Done when:** a fresh launch on a clean user account leads to practicing a bundled piece without reading any instructions.

## Order and dependencies

```
0 ─► 1 ─► 3 ─► 4 ─► 5 ─► 6
     └─► 2 ───────────┘
```

Phase 2 depends only on phase 0 and must finish before phase 5. Phases 3 and 4 do not depend on its outcome.

## Verification

- Automated: unit tests for `MusicCore`, `Practice`, and `ScoreImport` run on every change.
- By hand, with hardware: each phase's "done when" check is run on both keyboards. These need you at the keys; latency and feel cannot be judged from tests.
