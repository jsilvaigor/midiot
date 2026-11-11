#!/usr/bin/env python3
"""Writes "Stage test play" into the app's Plays folder: one cue per thing the Stage can do,
so every function can be tried by hand. Running it again replaces the play.

    python3 Scripts/make-test-play.py        # then restart Midiot and pick the play on the Sketchpad
"""
import json
import uuid
from pathlib import Path

NAMESPACE = uuid.UUID("6f1d0f0e-4d69-4d1f-9a54-5f6d1a0c7e57")
STAMP = "2026-11-11T12:00:00Z"


def uid(name):
    """The same id every run, so the file is replaced instead of piling up."""
    return str(uuid.uuid5(NAMESPACE, name)).upper()


def note(pitch, start, duration, velocity=80):
    return {"pitch": pitch, "start": start, "duration": duration, "velocity": velocity}


def chords(progression, beats_each, bars, low=False):
    """Held chords, one per `beats_each` beats, cycling through `progression`."""
    notes = []
    for bar in range(bars):
        for pitch in progression[bar % len(progression)]:
            notes.append(note(pitch - (12 if low else 0), bar * beats_each, beats_each - 0.1, 70))
    return notes


def melody(pitches, step, start=0.0, velocity=88):
    return [note(p, start + i * step, step * 0.9, velocity) for i, p in enumerate(pitches)]


def take(name, bpm, layers, number=1):
    return {
        "id": uid(name + "/take"), "number": number, "createdAt": STAMP, "bpm": bpm, "isKeeper": True,
        "layers": [
            {"id": uid(f"{name}/layer{i}"), "notes": notes, **({} if program is None else {"program": program})}
            for i, (program, notes) in enumerate(layers)
        ],
    }


def cue(name, note_text, takes=(), stage=None, target=None, status="ready", mood=None):
    result = {"id": uid(name), "name": name, "note": note_text, "status": status, "takes": list(takes)}
    if stage is not None:
        result["stage"] = stage
    if target is not None:
        result["targetSeconds"] = target
    if mood is not None:
        result["mood"] = mood
    return result


D_MINOR = [[50, 57, 62, 65], [46, 53, 58, 62], [41, 48, 53, 57], [45, 52, 57, 61]]
C_MAJOR = [[48, 55, 60, 64], [45, 52, 57, 60], [41, 48, 53, 57], [43, 50, 55, 59]]
TUNE = [62, 65, 69, 72, 76, 72, 69, 65, 67, 70, 74, 77, 74, 72, 69, 65]

# Sounds by General MIDI program: 48 strings, 89 warm pad, 8 celesta, 43 contrabass, 73 flute,
# 19 church organ, 46 harp, 47 timpani. No program is the grand piano.
scenes = [
    ("1 · Sounds", [
        cue("One sound", "CHECK: keyboard plays strings. Play layer runs 20 s to the end and stops by itself.",
            [take("One sound", 60, [(48, chords(D_MINOR, 4, 5))])], stage={"program": 48}),
        cue("Layered", "CHECK: every key plays grand piano and strings together. No recorded layer: Play, Fade in, Fade out and Stop are dimmed.",
            stage={"second": {"program": 48}}),
        cue("Split", "CHECK: below middle C is contrabass, from middle C up is flute. Tile reads B3 | C4. Layer is a 32 s pad to play over.",
            [take("Split", 60, [(89, chords(D_MINOR, 4, 8))])],
            stage={"program": 73, "second": {"program": 43, "splitAt": 60}}),
        cue("No preset", "CHECK: no preset saved, so the keyboard takes the take's own sound (harp) and the tempo it was recorded at (90).",
            [take("No preset", 90, [(46, melody(TUNE * 2, 1.0))])], status="draft"),
    ]),
    ("2 · Layer timing", [
        cue("Fades by itself", "CHECK: 40 s take, 15 s target. Marker on the bar at 0:15, fade starts at 0:11, silent and stopped at 0:15.",
            [take("Fades by itself", 60, [(48, chords(C_MAJOR, 4, 10))])], stage={"program": None}, target=15),
        cue("Shorter than target", "CHECK: 12 s take, 30 s target. No marker, no automatic fade: it plays to the end.",
            [take("Shorter than target", 60, [(89, chords(C_MAJOR, 4, 3))])], stage={"program": 8}, target=30),
        cue("Tempo doubled", "CHECK: recorded at 60, preset 120. Tile reads 120 bpm, the layer lasts 0:16 instead of 0:32 and sounds twice as fast.",
            [take("Tempo doubled", 60, [(46, melody(TUNE * 2, 1.0))])], stage={"program": 46, "bpm": 120}),
        cue("Long drone for fades", "CHECK: 2 min pad. Try Fade in from silence, Fade out, Fade in again halfway down (no jump), Stop. Then Play layer and press Go: it bows out in 1 s.",
            [take("Long drone for fades", 60, [(89, chords(D_MINOR, 8, 15))])], stage={"program": None}, mood="mystery"),
    ]),
    ("3 · Layers and panic", [
        cue("Piano under strings", "CHECK: take has two layers, piano and strings. Card reads 2 layers. Fade out while holding piano keys: the layer fades, your piano does not.",
            [take("Piano under strings", 72, [(None, melody(TUNE * 3, 0.5)), (48, chords(D_MINOR, 4, 6, low=True))])],
            stage={"program": None}),
        cue("Panic", "CHECK: organ. Hold keys with the sustain pedal down, start the layer, hit Panic (pad 16 or Esc): everything stops at once.",
            [take("Panic", 60, [(19, chords(C_MAJOR, 4, 12))])], stage={"program": 19}),
        cue("A cue with a very long name to see how the stage shrinks it to fit",
            "CHECK: the name shrinks onto one line and this note wraps to at most three lines without pushing the tiles or the pads off the screen, even in a small window. "
            "Timpani below F3, celesta above.",
            stage={"program": 8, "second": {"program": 47, "splitAt": 53}}, status="sketch"),
    ]),
    ("4 · Ends", [
        cue("Lock", "CHECK: locked, clicking a cue in the list or Exit stage does nothing. Hold the lock to open it: tiles become menus, Tempo gets − and +, the list jumps. Change the sound, lock again."),
        cue("Last cue", "CHECK: Go is dimmed and reads Last cue. Back still works. After restarting the app, the preset changed on the Lock cue is still there.",
            [take("Last cue", 96, [(48, chords(C_MAJOR, 4, 4)), (47, melody([36, 43, 36, 43] * 4, 1.0, velocity=100))])],
            stage={"program": 73}),
    ]),
]

play = {
    "id": uid("Stage test play"), "title": "Stage test play", "createdAt": STAMP,
    "scenes": [{"id": uid(title), "title": title, "cues": cues} for title, cues in scenes],
}

folder = Path.home() / "Library/Application Support/Midiot/Plays"
folder.mkdir(parents=True, exist_ok=True)
path = folder / f"{play['id']}.json"
path.write_text(json.dumps(play, ensure_ascii=False, sort_keys=True))
print(f"Wrote {sum(len(c) for _, c in scenes)} cues to {path}")
