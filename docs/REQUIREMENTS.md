# Midiot — Requirements

Status: draft v1, 2026-11-10. Derived from the requirements interview; items marked **(assumption)** were not asked and need confirmation.

## 1. Purpose

A personal macOS app (iPad later) that teaches keyboard playing to one user and supports composing and performing music for theater plays.

Two goals, in priority order:

1. Learn to play existing songs on a MIDI keyboard.
2. Sketch, organize, export, and perform original music for theater productions.

## 2. User profile

- Complete beginner at the keyboard: needs hand position, fingering, and key geography from zero.
- Experienced musician (many years of transverse flute): reads treble clef, knows rhythm and basic theory. The curriculum must skip what a flautist already knows and focus on what is new: bass clef, two-staff reading, hand independence, chords and harmony.
- Single user. No accounts, no sharing, no store distribution.

## 3. Hardware

| Device | Role |
| --- | --- |
| Roland A-49 (49 full-size keys) | Main instrument when connected |
| Novation Launchkey Mini MK3 (25 mini keys, 16 pads, 8 knobs) | Standalone instrument, or controller when the A-49 is also connected |

Requirements:

- **HW-1** Either keyboard works alone as a full instrument. The app adapts the on-screen keyboard and range to 25 or 49 keys.
- **HW-2** With both connected, the A-49 is the main keyboard and the Launchkey pads/knobs control the app (transport, loop, tempo, sound switching, cue triggers). The Launchkey keys stay playable.
- **HW-3** With only the Launchkey, the app marks which songs and drills fit 25 keys and offers one-hand or octave-folded versions of the others.
- **HW-4** Hot-plug: devices are detected on connect and disconnect without restarting the app.
- **HW-5** Sustain pedal is supported: displayed, recorded, and scored.
- **HW-6** Control mappings are editable (MIDI learn) with sensible defaults for both devices.

## 4. Learning

### 4.1 Song player (first milestone)

- **SP-1** Two switchable views of the same song: grand-staff sheet music with a moving cursor, and falling notes over an on-screen keyboard. Side-by-side display is also available.
- **SP-2** Wait mode: playback pauses until the correct notes are pressed.
- **SP-3** Hands separate: practice right or left hand alone while the app plays the other.
- **SP-4** Loop any selected range of bars.
- **SP-5** Tempo control, from slow practice to full speed, with metronome and count-in.
- **SP-6** Fingering numbers on notes and keys. Imported fingerings are used when present; otherwise the app suggests them.
- **SP-7** Note names switchable between C-D-E and Dó-Ré-Mi.

### 4.2 Feedback

- **FB-1** Live note coloring on staff and keys: correct, wrong, early, late.
- **FB-2** After-run review: accuracy and timing scores, trouble bars, rushing/dragging tendency, and a suggested loop.
- **FB-3** Adaptive practice: the app slows down, loops weak bars, and raises tempo as accuracy improves.
- **FB-4** Score history per song and drill, so improvement is visible over time.

Feedback on dynamics and touch (velocity evenness) is out of scope for now.

### 4.3 Curriculum and drills

- **CU-1** A guided path for a musically literate beginner, with a suggested daily session (warm-up, drill, song). All tools stay freely accessible outside the path.
- **CU-2** Technique drills: scales, arpeggios, fingering patterns, hand independence, each with tempo progression.
- **CU-3** Chords and harmony: chord shapes, inversions, progressions, left-hand accompaniment patterns.
- **CU-4** Bass clef and two-staff sight-reading drills.
- **CU-5** Rhythm and timing drills against the metronome.
- **CU-6** Daily goal, practice-time tracking, and streaks.

### 4.4 Song sources

- **SS-1** Import MIDI files, with automatic or manual assignment of tracks to hands.
- **SS-2** Import MusicXML (including compressed `.mxl`), preserving notation, hand assignment, and fingering.
- **SS-3** Built-in graded library leaning toward classical, film and musical-theater style, and pop/rock chord playing. Bundled content is public domain or freely licensed; copyrighted songs enter only through the user's own imports.

Recording a performance to turn it into a practice piece is not required.

## 5. Composing

Scope is a **sketchpad**, not a DAW. Finishing work happens in external tools.

- **CO-1** Always-on capture: everything played is retained, so an idea can be saved after the fact.
- **CO-2** Simple multi-layer overdub and basic editing (trim, quantize, transpose, delete notes).
- **CO-3** Chord and key detection of what is played, with suggestions for next chords and progressions.
- **CO-4** Mood palettes by dramatic intent (tension, melancholy, comic, pastoral, and so on): scales, progressions, tempos, and sounds as starting points.
- **CO-5** Projects per play, each containing scenes and cues. A cue holds takes, notes, target duration, and status.
- **CO-6** Export a cue as MIDI and MusicXML.
- **CO-7** Export a cue as a clean draft PDF: grand staff or lead sheet (melody plus chord symbols). Final engraving is done in MuseScore from the MusicXML.

Out of scope for now: audio file rendering (WAV/MP3), auto-accompaniment, piano-roll multi-track sequencing, mixing.

## 6. Live performance

- **LV-1** Cue list per play. Stepping to a cue recalls its sound, split/layer, tempo, and on-screen notes or score.
- **LV-2** Playback of recorded cues triggered from pads or keys, with fade in, fade out, and stop.
- **LV-3** Play along: the user plays live over a recorded layer.
- **LV-4** Stage-safe screen: dark, large type, no distractions, locked against accidental changes.
- **LV-5** Cue stepping and playback are controllable from the Launchkey pads.
- **LV-6 (assumption)** A panic control silences all sound immediately.

## 7. Sound

- **SN-1** Built-in sampled instruments from free sources; no other app needed to hear sound.
- **SN-2** Palette: a good piano, plus strings and orchestral, keys and organs, pads and atmospheres, percussion and one-shot effects.
- **SN-3** The audio layer is designed behind an instrument abstraction so that MIDI output to other apps and hosting Audio Unit instruments can be added later without restructuring. Neither is built in the first version.
- **SN-4** Wired output is the default. A latency calibration tool and a warning cover Bluetooth output.
- **SN-5** Key-to-sound latency on wired output is low enough to be imperceptible (target under 10 ms of app-added latency).

## 8. Design

- **DS-1** Dark studio look: deep charcoal, subtle glass and glow, one warm accent color. Clean, with a premium feel.
- **DS-2** Dark only; no light theme. Stage mode is a stricter variant of the same look.
- **DS-3** Interface in English and Portuguese, switchable in the app.

## 9. Platform and data

- **PL-1** Native Swift and SwiftUI, with CoreMIDI and AVAudioEngine. Development machine has Xcode 27 and macOS 27.2.
- **PL-2** macOS first. Code is structured so an iPad target can be added later (shared core, platform-specific shell).
- **PL-3** Data is local: plain files for songs, cues, and recordings, plus a local database for progress. The layout allows iCloud sync to be added later.
- **PL-4** Works fully offline.
- **PL-5** Third-party code, samples, and scores must carry licenses that permit personal use; each is recorded with its source and license.

## 10. Milestones

1. **Play songs.** MIDI connection, piano sound, MIDI and MusicXML import, sheet and falling-notes views, wait mode, tempo, loops, hands separate, live note coloring.
2. **Feedback and curriculum.** After-run review, adaptive practice, history, guided path, drills, streaks, built-in library.
3. **Sketchpad.** Always-on capture, overdub, chord detection and suggestions, mood palettes, play/scene/cue organizer, MIDI/MusicXML/PDF export, wider sound palette.
4. **Live mode.** Cue list with presets, cue playback, play-along, stage-safe screen, Launchkey control mapping.
5. **Later.** MIDI out, Audio Unit hosting, iPad target, iCloud sync.

## 11. Open decisions

| # | Decision | Recommendation |
| --- | --- | --- |
| 1 | Sheet music rendering engine | Evaluate Verovio (open-source MusicXML engraver, embeddable C++) against a custom renderer using the Bravura font. Decide with a spike at the start of milestone 1. |
| 2 | Sample sets | Salamander Grand Piano for the piano; a General MIDI SoundFont (for example GeneralUser GS) for the wider palette. Confirm licenses and sound quality by ear. |
| 3 | Built-in library sources | Mutopia Project and OpenScore for public-domain and CC0 scores. |
| 4 | Minimum macOS version | Current macOS only, since the app is personal. |
| 5 | App name | "Midiot" (repository name) unless changed. |
