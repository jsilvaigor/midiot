# Midiot — Milestone 2: Feedback and Curriculum

Status: plan v1, 2026-11-11. Requirement IDs from [REQUIREMENTS.md](REQUIREMENTS.md); screens follow [DESIGN.md](DESIGN.md) and the design canvas (Review, Today).

## Goal

After each run the app says what went wrong and what to practice next, adapts the practice to how it is going, and offers a daily session built from a path for a musician who is new to keys.

## Phases

| # | Phase | Requirements | Done when |
| --- | --- | --- | --- |
| 1 | After-run review | FB-2, FB-4 | Finishing a song shows accuracy, timing tendency, a bar-by-bar map, the last runs, and a suggested loop that can be started in one click. The library shows best run and last played. |
| 2 | Adaptive practice | FB-3 | A loop started from the review raises the tempo after three clean passes and lowers it after two poor ones. |
| 3 | Drills | CU-2 to CU-5 | Scales, arpeggios, chords and inversions, bass-clef reading, and rhythm drills are generated on demand and practiced with the same tools as songs. |
| 4 | Path and daily session | CU-1, CU-6 | A Today screen proposes warm-up, drill and song; tracks minutes against a daily goal; shows the week and the streak; and shows the path with treble reading and rhythm marked as known. |
| 5 | Leftovers from milestone 1 | SP-6, HW-5, SS-1 | Suggested fingering where a file has none, sustain pedal shown and included in the review, manual hand split on import. |

## Status (2026-11-11)

All five phases are implemented on the `milestone-2` branch. Automated tests pass and the review, Today and drill screens were checked from rendered images, including two simulated full runs. Not checked: real keyboards and how the drills feel to play.

Differences from the plan:

- **Review after loops:** the review appears when a run reaches the end of the piece. A looped section never ends, so it has no review; its result is saved when it has at least eight judged notes.
- **Sustain pedal:** shown on the practice screen while held. It is not scored and is not part of the review.
- **Manual hand split:** a "Split hands" menu on MIDI songs in the library offers fixed split points; there is no visual split editor.
- **Suggested fingering** appears on falling notes. The sheet shows only fingerings that came with the file, or that a drill defines.

## Out of scope

Composing, live mode, more sounds (milestones 3 and 4). A larger built-in library beyond the starter pieces is deferred until the path needs specific pieces.
