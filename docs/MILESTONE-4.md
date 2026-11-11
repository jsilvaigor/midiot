# Midiot — Milestone 4: Live mode

Status: plan v1, 2026-11-11. Requirement IDs from [REQUIREMENTS.md](REQUIREMENTS.md); the screen follows [DESIGN.md](DESIGN.md) and the design canvas (Stage, Devices).

## Goal

A play sketched on the Sketchpad can be performed. The Stage screen steps through its cues in order; each cue recalls its sound, plays its recorded layer with fades while the keyboard stays live on top, and all of it can be run from the Launchkey's pads without touching the Mac.

## Phases

| # | Phase | Requirements | Done when |
| --- | --- | --- | --- |
| 1 | Cue sheet and presets | LV-1 | The cues of the selected play line up in scene order. Stepping to a cue points the keyboard at its sound, a second sound layered or split at a key, and shows its tempo and its note. Presets survive a restart. |
| 2 | Recorded layer | LV-2, LV-3 | The cue's take plays from the top, fades in, fades out and stops. A fade leaves the live keyboard at full loudness. A take longer than the cue's target length fades out by itself to end on it. |
| 3 | Stage screen | LV-4, LV-6 | Near-black, very large type, no sidebar. Locked by default: only the performing controls work, and leaving takes a held press on the lock. Panic is always visible and silences everything. |
| 4 | Pads and knobs | HW-2, HW-6, LV-5 | Pads and knobs reach the app as controls. The Launchkey works out of the box for the stage and for practice, and every action can be moved to another pad or knob by pressing it (MIDI learn). |

## Structure

No new module. Each piece joins the module that owns its subject:

- `Sketch`: `StagePreset` on `Cue`, `CueSheet` (the play flattened into performance order) and `LayerPlan` (how long a layer lasts and when it fades by itself).
- `Sound`: `Fade` (a loudness line over time), `SplitInstrument` (two sounds on one keyboard) and per-channel volume on `PaletteSynth`.
- `MidiIO`: `ControlEvent`, `ControlSource`, `ControlAction` and `ControlMap`.
- App: `StageModel`, `StageView`, the "Pads and knobs" section of Settings, and the dispatch of control events in `AppModel`.

The preset is stored inside the play's JSON file with the cue. The control map is stored in the app's preferences.

## Status (2026-11-11)

All four phases are implemented on the `milestone-4` branch. Automated tests pass. The Stage was checked from rendered images in English and Portuguese after a simulated performance driven through the same path pad presses take: step back and on, play the layer with a chord held on top, fade out, turn the fade round, let a 7.5 s take end on a 6 s target (it stopped after 6.1 s), and panic. Not checked: real pad presses and knob turns, and how the fades and the split sound.

Default pads on the Launchkey Mini MK3 (Drum mode), top row left to right:

| Pad | While practicing | On stage |
| --- | --- | --- |
| 1 | Play or pause | Previous cue |
| 2 | Back to the start | Next cue (Go) |
| 3 | Wait mode | Play layer |
| 4 | Metronome | Fade in |
| 5 | Left hand | Fade out |
| 6 | Both hands | Stop |
| 7 | Right hand | |
| 8 | Count-in | |
| 9, 10 | Slower, faster | |
| 16 | Panic | Panic |

Knob 1 sets the practice tempo and knob 8 the volume of everything. On the Mac's keyboard, Space is Go, Left Arrow is Back and Escape is Panic.

Differences from the plan and the design:

- **Piano layers on stage** play through the General MIDI piano, not the sampled grand. The sampled piano has one volume for everything it plays, so fading a piano layer on it would fade the live piano too (measured). The live keyboard still plays the sampled grand.
- **Pad numbers** assume the pads send notes 40–43, 48–51 (top row) and 36–39, 44–47 (bottom row) on channel 10, and the knobs controllers 21–28. This is from memory of the Launchkey's documentation, not checked against the device. If a pad does the wrong thing, Learn fixes it.
- **Pad lights** follow Novation's Launchkey MK3 programmer's reference and are tested against a stand-in port, not yet on the device. The app puts the Launchkey in DAW mode with the pads in the Drum layout, where they keep sending the same notes, and gives the pads back when it quits. In DAW mode the knobs report on the second port; the app listens there too.
- **Tempo** in a preset changes the speed of the recorded layer. There is no click on stage.
- **Fades** take four seconds, fixed. Stepping to another cue while a layer plays fades it out in one second.
- **"On-screen notes or score"** (LV-1): the cue's note is shown. The score is not.
- **Presets are edited on the Stage** with the lock open: the Sound and Split tiles become menus and Tempo gains steppers. The Sketchpad has no preset editor.
- **Settings** keeps its plain list; the device cards of the design canvas are not built.
- **The Sketchpad** has no pad actions yet beyond panic and volume.

## Out of scope

MIDI out, Audio Unit hosting, an iPad target and iCloud sync (later, as in the requirements).

## After the first try on the device

- **Choose the play first.** Opening the Stage shows the plays; choosing one opens it on its first cue, locked. Unlocked, the play title in the header goes back to the chooser.
- **Lock.** One click locks. Unlocking still takes a 0.8 s hold.
- **Pad colours.** Each action has a colour, the same on the Launchkey pad and on screen: Back blue, Go green, Play layer yellow, Fade in cyan, Fade out orange, Stop purple, Panic red. A pad is dim when its action cannot be used and pulses while what it started is under way. The Practice pads are lit the same way.
- **Layers on the Sketchpad.** The selected take lists its layers; each can change instrument, be muted (also on stage, not in exports) or be deleted. Deleting the only layer deletes the take.
- **Metronome on the Sketchpad.** The toggle beside the tempo now also clicks while nothing is playing, and is remembered between launches.
