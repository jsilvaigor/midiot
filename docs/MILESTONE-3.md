# Midiot — Milestone 3: Sketchpad

Status: plan v1, 2026-11-11. Requirement IDs from [REQUIREMENTS.md](REQUIREMENTS.md); the screen follows [DESIGN.md](DESIGN.md) and the design canvas (Sketchpad).

## Goal

Anything played on the keyboard can be kept after the fact, shaped into a cue for a play, and handed to other tools as MIDI, MusicXML or a draft PDF. While playing, the app names the chord and key it hears and offers where to go next.

## Phases

| # | Phase | Requirements | Done when |
| --- | --- | --- | --- |
| 1 | Capture and cues | CO-1, CO-5 | Everything played is retained for ten minutes. "Keep last 30 s" turns it into a take inside the selected cue. Plays hold scenes, scenes hold cues, and a cue holds takes, a note, a target length and a status. All of it survives a restart. |
| 2 | Takes | CO-2 | A take plays back, takes a second layer recorded over it, and can be trimmed, quantized, transposed and have notes deleted, with undo. |
| 3 | Harmony and moods | CO-3, CO-4 | The chord being held and the key of the recent playing are named, with three chords to try next that can be heard by clicking. Six mood palettes give scales, moves, a tempo range and sounds. |
| 4 | Export | CO-6, CO-7 | A cue's take exports as a MIDI file, a MusicXML file, and a PDF as grand staff or lead sheet. |
| 5 | Sounds | SN-2 | The Sketchpad plays strings, keys, pads, percussion and effects besides the piano, and each layer of a take keeps its sound. |

## Structure

A new package module, `Sketch`, holds everything that needs no screen: the capture buffer, takes and their edits, chord and key detection, mood palettes, and the play store. It depends only on `MusicCore`. Writers for MIDI files and lead sheets join `ScoreImport`; the PDF writer joins `Notation`, next to the engraving it draws. `Sound` gains a multi-sound synthesizer behind the existing `Instrument` protocol.

Plays are plain JSON files under `~/Library/Application Support/Midiot/Plays/`, one per play (PL-3).

## Status (2026-11-11)

All five phases are implemented on the `milestone-3` branch. Automated tests pass, and the Sketchpad was checked from rendered images in English and Portuguese after a simulated session: two takes kept, a second layer recorded over one, a quantize, and all four exports opened. Not checked: real keyboards, how the sounds and the overdub timing feel, and the exported files in MuseScore.

Differences from the plan:

- **Key and mode:** the app names major and minor keys only. Modes such as Dorian appear in the mood palettes but are not detected.
- **Chord suggestions** follow common moves within the detected key; they do not learn from what was played.
- **Trim** removes the silence before the first note, or keeps only the stretch spanned by the selected notes. There is no drag handle.
- **Sounds:** each layer keeps its sound, but all piano layers of a take share one piano voice. GeneralUser GS is fetched by `Scripts/fetch-soundfonts.sh`; until it is, the sounds built into macOS are used.
- **Lead sheet:** one chord symbol per bar at most, taken from the notes sounding in that bar. Bars whose notes form no recognizable chord get none.
- **Hands in exports:** notes below middle C are written on the bass staff.

Added after the first review:

- **Keyboard on the Sketchpad:** the on-screen keyboard sits above the capture bar. Pointing at a suggested chord lights its keys, bass note in blue and chord in amber, placed to fit the connected keyboard; clicking plays it and keeps it lit.
- **Chords** (under Learn): a cheat sheet of twenty chord types on any root, each with its keys, spelled notes, formula, right-hand fingering and character, in root position or any inversion, plus the chords that belong to the root's major and minor keys.

## Out of scope

Live mode, pad and knob control, and the stage screen (milestone 4). Audio rendering, piano-roll sequencing and mixing stay out, as in the requirements.
