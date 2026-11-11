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
    Sketch/                 capture, takes, harmony, moods, plays and cues
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
 ├─ ScoreImport ► MusicCore, Verovio
 ├─ Library ───► MusicCore
 ├─ Sound ─────► MusicCore
 ├─ Sketch ────► MusicCore
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
- `DeviceManager` turns raw MIDI into two streams: `PerformanceEvent` (note on/off, sustain, with host timestamp and source device) and `ControlEvent` (a pad struck or a knob moved). Notes on a device's pad channel and every controller but the sustain pedal are controls.
- Role assignment follows HW-1 and HW-2: one device connected means it is the instrument; both connected means the A-49 is the instrument and the Launchkey's pads and knobs become controls while its keys stay playable.
- The Launchkey exposes two USB ports. Keys, pads, and knobs arrive on port 1. Port 2 is a "DAW mode" port: the app uses it to light the pads (`PadLights.swift`), and in DAW mode the knobs report there instead of on port 1.
- **MIDI out** (requirement SN-3, Settings › MIDI out). The piano sampler and the palette synth copy every message they are given to a sink (`Sound/MIDIMirror.swift`); the app points the sink at `DeviceManager.out` (`MidiIO/MIDIOut.swift`), which sends to a chosen destination or to a virtual port named "Midiot" that other apps can open. Channels are the ones the synths use: piano and the Sketchpad's keyboard sound on 1 (a program change is sent whenever the two swap), recorded layers on 2 to 9, the Stage's keyboard sounds on 12 and 13. Layer fades go out as controller 7. The metronome is not sent. The app's own instruments can be muted so only the other end is heard. When the destination hands back what it receives (an IAC bus or a network session), input from that port is ignored so nothing goes round in a loop.
- `ControlMap` says which `ControlSource` (pad or controller) runs which `ControlAction` (HW-6). Actions belong to a context (practice, stage, everywhere), so one pad can do one thing while practicing and another on stage. `ControlMap.launchkeyDefaults` is the map out of the box; MIDI learn is `assign`, which takes the control away from any action it would clash with.

### Sound

- `AVAudioEngine` with a small mixer graph.
- `Instrument` protocol: `noteOn`, `noteOff`, `sustain`, `allNotesOff`. This is the seam required by SN-3.
  - `SamplerInstrument`: `AVAudioUnitSampler` loading a SoundFont. Built in milestone 1.
  - `MIDIOutInstrument` and `AudioUnitInstrument`: later; they implement the same protocol.
- Two instrument slots from the start: one for the user's playing, one for the part the app plays (other hand, backing).
- `PaletteSynth`: Apple's multi-timbral General MIDI synthesizer with a different sound on each of sixteen channels (SN-2). The Sketchpad plays it live and gives each layer of a take its own channel. It reads GeneralUser GS when bundled, otherwise the sounds built into macOS.
- `PaletteSynth.setVolume(_:channel:)` turns one channel down without touching the others; `Fade` is the line the loudness follows. Together they fade a recorded layer under live playing (LV-2). The sampler cannot do this: its volume is one for all channels.
- `SplitInstrument`: two instruments behind one, layered over every key or split at a key (LV-1).
- `Metronome`: scheduled clicks on the audio clock, with count-in.
- `LatencyCalibration`: stores an output offset per audio route; applied to visual timing and to scoring (SN-4).

### ScoreImport

- **MIDI files**: parsed by a small reader in this module (`MIDIFile`). It reads only what practice needs: notes, tempo, time signatures, and track names. Tracks map to hands when there are exactly two piano tracks; otherwise a split-point heuristic assigns hands, and the user can correct it (SS-1).
- **MusicXML**: loaded by Verovio, in `Notation.EngravedScore` (it lives there because the notes and the drawn pages must come from the same engraving pass). Notes, timing, staff (hand), and fingerings are read back from Verovio's timemap and element attributes, so the played `Song` and the drawn score share element IDs (SS-2).
- **MIDI → sheet**: a MIDI file has no notation. `MusicXMLWriter` rounds it to sixteenth notes and writes MusicXML, which `Library` engraves and links back to the played notes. Output is a readable draft, not engraving quality.

### Notation

- Wraps Verovio (C++ engraver, LGPLv3, has a Swift package binding). Input MusicXML, output SVG per system or page.
- `ScoreView` shows the SVG, a cursor, and per-note colors addressed by element ID (SP-1, FB-1).
- The SVG is parsed into native paths (`ScoreScene`) and drawn in a SwiftUI `Canvas` (`ScoreCanvas`); no web view. This was settled by the phase 2 trial, recorded in [MILESTONE-1.md](MILESTONE-1.md).

### Practice

- `Transport`: play, pause, seek, loop range, tempo scale. Position is derived from the host clock, never from UI frame timing.
- `Matcher`: compares expected notes with `PerformanceEvent`s inside timing windows and classifies each as correct, wrong, early, late, or missed. Chords are matched as a set.
- `PracticeSession`: a state machine combining transport and matcher with the options wait mode (SP-2), active hands (SP-3), loop (SP-4), and tempo (SP-5). In wait mode the transport holds at each expected onset until the right keys are down.
- Output is an observable `PracticeState` (position, per-note results, held keys) plus a `RunResult` at the end. `RunResult` is stored from milestone 1 so milestone 2 can build history and review on real data.

### Library

- Songs are plain files under `~/Library/Application Support/Midiot/Songs/<id>/`: the original import, the normalized MusicXML, and a small JSON sidecar (PL-3).
- Progress and settings use SwiftData. It syncs through CloudKit when that is switched on later, which satisfies "iCloud-ready" without work now.

### Sketch

Everything the Sketchpad needs that has no screen (milestone 3). It depends only on `MusicCore`.

- `CaptureHistory` keeps the last ten minutes of note and pedal events with their host times (CO-1). `CaptureBuffer` wraps it in a lock so the MIDI thread can write to it.
- `Take` holds one or more `Layer`s of notes timed in beats at one tempo. Edits (trim, quantize, transpose, delete) return a new take (CO-2). `Take.song(title:)` converts it for the player and the score writers.
- `Chord.detect` names the chord formed by the held keys; `SketchKey.detect` finds the key of recent playing with the Krumhansl–Kessler profiles; `ChordSuggestion.next` proposes three chords to follow (CO-3).
- `MoodPalette` lists scales, chord moves, a tempo range and sounds for each dramatic intent (CO-4).
- `Play`, `PlayScene` and `Cue` are the organizer (CO-5). `PlayStore` writes one JSON file per play under `~/Library/Application Support/Midiot/Plays/`.

For the stage (milestone 4): a `Cue` carries a `StagePreset` (sound, second sound layered or split, tempo). `CueSheet` flattens a play into performance order, and `LayerPlan` works out how long a cue's recorded layer lasts and when it must start fading to end on the cue's target length.

Export is spread over the modules that own each format: `ScoreImport.MIDIFileWriter` and `MusicXMLWriter` (grand staff and lead sheet) for CO-6, and `Notation.ScorePDF` for CO-7. `ScorePDF` draws the same engraved shapes the screen shows into PDF pages, one line of music at a time, so lines are never cut across sheets.

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
| SwiftMIDI `swift-midi-io` (orchetect; formerly MIDIKit) | CoreMIDI wrapper | MIT | |
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
