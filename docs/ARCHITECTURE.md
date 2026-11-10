# Midiot — Architecture

Status: draft v1, 2026-11-10. Implements [REQUIREMENTS.md](REQUIREMENTS.md). Requirement IDs (SP-1, HW-2, ...) refer to that document.

## 1. Shape

One Xcode app target (`Midiot`, macOS) on top of one local Swift package (`MidiotKit`) split into modules. The app target holds only SwiftUI screens and wiring. Everything else lives in the package, so an iPad target can reuse it later (PL-2).

```
Midiot.xcodeproj            generated from project.yml (XcodeGen)
App/                        SwiftUI app: screens, navigation, composition root
MidiotKit/                  local Swift package
  Sources/
    MusicCore/              pure Swift music model, no dependencies
    MidiIO/                 devices, input, control mapping
    Sound/                  audio engine, instruments, metronome
    ScoreImport/            MIDI file and MusicXML → Song
    Notation/               sheet-music rendering
    Practice/               transport, matching, wait mode, scoring
    Library/                persistence: songs on disk, progress database
    DesignSystem/           colors, type, shared components
  Tests/
Resources/                  SoundFonts, bundled songs, licenses
docs/
```

Dependency direction, top depends on bottom:

```
App
 ├─ DesignSystem
 ├─ Practice ──► MusicCore
 ├─ Notation ──► MusicCore, Verovio
 ├─ ScoreImport ► MusicCore, SwiftMIDI, Verovio
 ├─ Library ───► MusicCore
 ├─ Sound ─────► MusicCore
 └─ MidiIO ────► MusicCore, SwiftMIDI
```

`Practice` knows nothing about CoreMIDI, audio, or SwiftUI. It consumes timestamped note events and emits state. That keeps the hardest logic testable without a keyboard attached.

## 2. Modules

### MusicCore

Value types shared by everything:

- `Pitch` (MIDI number, spelling), `NoteName` formatting in C-D-E or Dó-Ré-Mi (SP-7).
- `Song`: metadata, `TempoMap`, time signatures, and `Note`s. Each note has pitch, start and duration in beats, `Hand` (left/right), optional finger number, and an optional notation element ID that links it to the rendered score.
- `TempoMap`: converts beats ↔ seconds, with a user tempo scale applied on top (SP-5).
- `KeyboardRange`: 25 or 49 keys plus octave offset; answers "does this song fit?" (HW-3).

### MidiIO

- Built on the open-source SwiftMIDI packages (MIT; the successor to MIDIKit, by the same author), which wrap CoreMIDI and handle hot-plug (HW-4). Only the `swift-midi-io` package is used for devices.
- `DeviceManager` publishes connected devices and matches them to `DeviceProfile`s. Profiles exist for the Roland A-49 and the Launchkey Mini MK3: key count, pads, knobs, port names.
- `InputRouter` turns raw MIDI into two streams: `PerformanceEvent` (note on/off, sustain, with host timestamp and source device) and `ControlEvent` (pad, knob, transport button).
- Role assignment follows HW-1 and HW-2: one device connected means it is the instrument; both connected means the A-49 is the instrument and the Launchkey's pads and knobs become controls while its keys stay playable.
- The Launchkey exposes two USB ports. Keys, pads, and knobs arrive on port 1. Port 2 is a "DAW mode" port that allows pad LED feedback; it is used from milestone 4 onward, not in milestone 1.
- `ControlMap` (MIDI learn, HW-6) is designed in now and built in milestone 4.

### Sound

- `AVAudioEngine` with a small mixer graph.
- `Instrument` protocol: `noteOn`, `noteOff`, `sustain`, `allNotesOff`. This is the seam required by SN-3.
  - `SamplerInstrument`: `AVAudioUnitSampler` loading a SoundFont. Built in milestone 1.
  - `MIDIOutInstrument` and `AudioUnitInstrument`: later; they implement the same protocol.
- Two instrument slots from the start: one for the user's playing, one for the part the app plays (other hand, backing).
- `Metronome`: scheduled clicks on the audio clock, with count-in.
- `LatencyCalibration`: stores an output offset per audio route; applied to visual timing and to scoring (SN-4).

### ScoreImport

- **MIDI files**: parsed with the `swift-midi-file` package from the same family. Tracks map to hands when there are exactly two piano tracks; otherwise a split-point heuristic assigns hands, and the user can correct it (SS-1).
- **MusicXML**: loaded by Verovio. Notes, timing, staff (hand), and fingerings are read back from Verovio's timemap and element attributes, so the played `Song` and the drawn score share element IDs (SS-2).
- **MIDI → sheet**: a MIDI file has no notation. A transcriber quantizes it and writes MusicXML, which then follows the MusicXML path. Output is a readable draft, not engraving quality.

### Notation

- Wraps Verovio (C++ engraver, LGPLv3, has a Swift package binding). Input MusicXML, output SVG per system or page.
- `ScoreView` shows the SVG, a cursor, and per-note colors addressed by element ID (SP-1, FB-1).
- How the SVG reaches the screen is the main open question; see section 6.

### Practice

- `Transport`: play, pause, seek, loop range, tempo scale. Position is derived from the host clock, never from UI frame timing.
- `Matcher`: compares expected notes with `PerformanceEvent`s inside timing windows and classifies each as correct, wrong, early, late, or missed. Chords are matched as a set.
- `PracticeSession`: a state machine combining transport and matcher with the options wait mode (SP-2), active hands (SP-3), loop (SP-4), and tempo (SP-5). In wait mode the transport holds at each expected onset until the right keys are down.
- Output is an observable `PracticeState` (position, per-note results, held keys) plus a `RunResult` at the end. `RunResult` is stored from milestone 1 so milestone 2 can build history and review on real data.

### Library

- Songs are plain files under `~/Library/Application Support/Midiot/Songs/<id>/`: the original import, the normalized MusicXML, and a small JSON sidecar (PL-3).
- Progress and settings use SwiftData. It syncs through CloudKit when that is switched on later, which satisfies "iCloud-ready" without work now.

### DesignSystem

- Color tokens for the dark studio look (DS-1): charcoal surfaces, one warm accent, semantic colors for correct, wrong, early, late.
- Typography, spacing, and shared components (buttons, sliders, transport bar, panels).
- The on-screen `KeyboardView` and `FallingNotesView` live here because several features use them.

## 3. Data flow while practicing

```
Keyboard ─► CoreMIDI thread ─► InputRouter ─┬─► Instrument.noteOn      (sound, immediate)
                                             └─► event queue ─► PracticeSession ─► PracticeState ─► UI

Transport (host clock) ─► scheduled notes for the app-played hand ─► second Instrument
                       └► position ─► FallingNotesView, ScoreView cursor
```

Rules:

- **Sound never waits for the UI.** A key press goes from the CoreMIDI callback straight to the sampler. It does not hop through the main actor.
- **One clock.** Every event carries a host timestamp. Song position, scoring, and drawing all derive from it, so visuals cannot drift from audio.
- **UI reads state at display rate.** `FallingNotesView` is a SwiftUI `Canvas` driven by `TimelineView`; it computes note positions from the transport position each frame.

## 4. Cross-cutting

- **Concurrency**: Swift 6 strict concurrency. `PracticeSession` is an actor; UI models are `@MainActor @Observable`.
- **Localization**: String Catalogs with English and Portuguese, with an in-app language switch (DS-3). Portuguese variant is assumed to be Brazilian; say so if it should be European.
- **Testing**: Swift Testing for `MusicCore`, `Practice`, and `ScoreImport`, using recorded event sequences and fixture files. A virtual MIDI source drives end-to-end checks without hardware.
- **Licenses**: `Resources/LICENSES.md` lists every third-party asset with source and license (PL-5).

## 5. Third-party components

| Component | Use | License | Note |
| --- | --- | --- | --- |
| SwiftMIDI packages (orchetect; formerly MIDIKit) | CoreMIDI wrapper, MIDI file parsing | MIT | `swift-midi-io` now, `swift-midi-file` in phase 3 |
| Verovio | MusicXML engraving, timemap | LGPLv3 | Used unmodified, so no obligations beyond attribution for personal use |
| Salamander Grand Piano | Piano samples | CC-BY 3.0 | Credit Alexander Holm |
| GeneralUser GS | Wider palette (milestone 3) | GeneralUser GS License 2.0 | Permits personal music creation |
| Bravura | Music font, only if the custom renderer is chosen | SIL OFL | |

## 6. Risks and how they are retired

| Risk | Plan |
| --- | --- |
| **Sheet rendering.** Verovio produces SVG, and SwiftUI has no native live SVG view with per-element styling. | Spike in phase 2 of milestone 1. Option A: draw Verovio's SVG natively by parsing it into Core Graphics paths. Option B: host it in a `WKWebView` and color notes by element ID. Option C: custom renderer with Bravura. Pick the first that gives smooth cursor movement and note coloring. |
| **Latency.** The app-added delay between key press and sound must be imperceptible (SN-5). | Measured in phase 1 before anything else is built on the audio path. Buffer size is tuned; the sampler is replaced if it cannot meet the target. |
| **MIDI → sheet quality.** Quantizing arbitrary MIDI gives ugly notation. | Falling notes are the primary view for MIDI imports. The generated sheet is labelled as a draft. MusicXML is the recommended import format. |
| **Hand assignment in MIDI files.** Many files are a single track. | Heuristic split plus a manual split-point control in the import sheet. |
| **Piano sample size.** The full Salamander set is over 1 GB. | Start with a reduced-layer SoundFont build; quality is judged by ear in phase 1. |
