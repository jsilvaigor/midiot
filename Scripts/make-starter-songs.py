#!/usr/bin/env python3
"""Writes the starter pieces bundled with the app into Resources/Songs as MusicXML.

All three melodies are traditional or long out of copyright; the simple left-hand parts
and fingerings were written for Midiot. Re-run after editing: python3 Scripts/make-starter-songs.py
"""
import os

TYPES = {1: ("eighth", False), 2: ("quarter", False), 3: ("quarter", True), 4: ("half", False),
         6: ("half", True), 8: ("whole", False)}


def note(name, eighths, staff, chord=False, finger=None):
    """name like 'E4' or 'F#3'; eighths is the length in eighth notes."""
    kind, dotted = TYPES[eighths]
    sharp = "#" in name
    xml = "<note>" + ("<chord/>" if chord else "")
    xml += f"<pitch><step>{name[0]}</step>" + ("<alter>1</alter>" if sharp else "") + f"<octave>{name[-1]}</octave></pitch>"
    xml += f"<duration>{eighths}</duration><voice>{staff}</voice><type>{kind}</type>" + ("<dot/>" if dotted else "")
    xml += ("<accidental>sharp</accidental>" if sharp else "") + f"<staff>{staff}</staff>"
    if finger:
        xml += f"<notations><technical><fingering>{finger}</fingering></technical></notations>"
    return xml + "</note>"


def song(title, composer, tempo, right, left):
    """right: bars of (name, eighths, finger?) tuples; left: bars of chords (tuples of names) held a bar,
    or lists of (chord, eighths) for bars with more than one chord."""
    out = ['<?xml version="1.0" encoding="UTF-8"?>',
           f'<score-partwise version="4.0"><work><work-title>{title}</work-title></work>',
           f'<identification><creator type="composer">{composer}</creator></identification>',
           '<part-list><score-part id="P1"><part-name></part-name></score-part></part-list><part id="P1">']
    for index, (rh, lh) in enumerate(zip(right, left)):
        bar = f'<measure number="{index + 1}">'
        if index == 0:
            bar += ('<attributes><divisions>2</divisions><key><fifths>0</fifths></key>'
                    '<time><beats>4</beats><beat-type>4</beat-type></time><staves>2</staves>'
                    '<clef number="1"><sign>G</sign><line>2</line></clef>'
                    '<clef number="2"><sign>F</sign><line>4</line></clef></attributes>'
                    '<direction placement="above"><direction-type><metronome><beat-unit>quarter</beat-unit>'
                    f'<per-minute>{tempo}</per-minute></metronome></direction-type><staff>1</staff>'
                    f'<sound tempo="{tempo}"/></direction>')
        assert sum(n[1] for n in rh) == 8, (title, index + 1)
        for n in rh:
            bar += note(n[0], n[1], 1, finger=n[2] if len(n) > 2 else None)
        bar += "<backup><duration>8</duration></backup>"
        chords = lh if isinstance(lh, list) else [(lh, 8)]
        assert sum(c[1] for c in chords) == 8, (title, index + 1)
        for chord, eighths in chords:
            for i, name in enumerate(chord):
                bar += note(name, eighths, 2, chord=i > 0)
        out.append(bar + "</measure>")
    out.append("</part></score-partwise>")
    return "\n".join(out) + "\n"


def q(names, fingers=None):
    """A bar of quarter notes."""
    fingers = fingers or [None] * len(names)
    return [(n, 2, f) for n, f in zip(names, fingers)]


C, G, F = ("C3", "G3"), ("B2", "G3"), ("C3", "A3")

ode_a = [q(["E4", "E4", "F4", "G4"], [3, None, 4, 5]), q(["G4", "F4", "E4", "D4"], [5, 4, 3, 2]),
         q(["C4", "C4", "D4", "E4"], [1, None, 2, 3])]
ode = song("Ode to Joy", "Ludwig van Beethoven", 100,
           ode_a + [[("E4", 3, 3), ("D4", 1, 2), ("D4", 4)]]
           + ode_a + [[("D4", 3, 2), ("C4", 1, 1), ("C4", 4)]]
           + [q(["D4", "D4", "E4", "C4"], [2, None, 3, 1]),
              [("D4", 2, 2), ("E4", 1, 3), ("F4", 1, 4), ("E4", 2, 3), ("C4", 2, 1)],
              [("D4", 2, 2), ("E4", 1, 3), ("F4", 1, 4), ("E4", 2, 3), ("D4", 2, 2)],
              [("C4", 2, 1), ("D4", 2, 2), ("G3", 4, 1)]]
           + ode_a + [[("D4", 3, 2), ("C4", 1, 1), ("C4", 4)]],
           [C, G, C, G, C, G, C, [(G, 4), (C, 4)], G, [(G, 4), (C, 4)], [(G, 4), (C, 4)], G,
            C, G, C, [(G, 4), (C, 4)]])

jacques = song("Frère Jacques", "Traditional", 96,
               [q(["C4", "D4", "E4", "C4"], [1, 2, 3, 1])] * 2
               + [[("E4", 2, 3), ("F4", 2, 4), ("G4", 4, 5)]] * 2
               + [[("G4", 1, 4), ("A4", 1, 5), ("G4", 1, 4), ("F4", 1, 3), ("E4", 2, 2), ("C4", 2, 1)]] * 2
               + [[("C4", 2, 2), ("G3", 2, 1), ("C4", 4, 2)]] * 2,
               [C, C, C, C, C, C, [(C, 2), (G, 2), (C, 4)], [(C, 2), (G, 2), (C, 4)]])

lune_a = [q(["C4", "C4", "C4", "D4"], [1, None, None, 2]), [("E4", 4, 3), ("D4", 4, 2)],
          q(["C4", "E4", "D4", "D4"], [1, 3, 2, None]), [("C4", 8, 1)]]
lune = song("Au clair de la lune", "Traditional", 92,
            lune_a + lune_a
            + [q(["D4", "D4", "D4", "D4"], [2, None, None, None]), [("A3", 4, 1), ("A3", 4)],
               q(["D4", "C4", "B3", "A3"], [4, 3, 2, 1]), [("G3", 8, 1)]]
            + lune_a,
            [C, [(C, 4), (G, 4)], [(C, 4), (G, 4)], C] * 2
            + [("D3", "A3"), ("D3", "A3"), [(("D3", "A3"), 4), (("D3", "F#3"), 4)], G]
            + [C, [(C, 4), (G, 4)], [(C, 4), (G, 4)], C])

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Resources", "Songs")
os.makedirs(root, exist_ok=True)
for name, xml in [("Ode to Joy", ode), ("Frère Jacques", jacques), ("Au clair de la lune", lune)]:
    with open(os.path.join(root, name + ".musicxml"), "w", encoding="utf-8") as f:
        f.write(xml)
    print("wrote", name)
