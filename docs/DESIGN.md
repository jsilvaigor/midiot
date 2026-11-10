# Midiot — Design

Status: v1, 2026-11-10. Implements DS-1 to DS-3 from [REQUIREMENTS.md](REQUIREMENTS.md). Tokens live in `MidiotKit/Sources/DesignSystem/`.

Design canvas with every screen (private to the owner): https://claude.ai/code/artifact/594641cf-0f7a-4061-acad-cf121bb3509c

## Filament

A dark studio with one warm light. The light means "now": the hit line where falling notes meet the keys, the playhead, the current cue on stage, the next thing to press.

Three rules:

1. **One light.** Amber (`Palette.accent`) is the only accent. If two things glow, one of them is wrong.
2. **Hands have colors.** Right hand is amber, left hand is nocturne blue. Feedback colors (correct, wrong, early, late) replace the hand color the moment a key is played.
3. **Numbers in mono.** Bar, beat, tempo and latency use Geist Mono so they never jitter while changing.

## Color

| Token | Value | Use |
| --- | --- | --- |
| `background` | `#0C0D10` | Window |
| `sidebar` | `#101114` | Sidebar column |
| `surface` | `#131418` | Cards and panels |
| `surfaceRaised` | `#1C1E23` | Controls, nested panels |
| `control` | `#26282E` | Selected segment |
| `hairline` | white 7% | Borders and dividers |
| `glass` | `#18191E` at 78% + material | Only over moving content |
| `textPrimary` | `#F3EFE7` | Text |
| `textSecondary` | `#A9A59D` | Supporting text |
| `textTertiary` | `#85827B` | Labels (still 4.5:1 on `surface`) |
| `accent` | `#F2A649` | The light |
| `accentSoft` | accent 12% | Active toggles, selected rows |
| `accentInk` | `#1A1206` | Text on accent |
| `handRight` / `handLeft` | `#F2A649` / `#86A0DD` | Falling notes, keys, staff |
| `noteCorrect` / `noteWrong` / `noteEarly` / `noteLate` | `#5FD39A` / `#F0625D` / `#5BB8F5` / `#B58CF5` | Live feedback; always paired with a label or position, never color alone |

## Type

| Style | Face | Size |
| --- | --- | --- |
| `hero` | Instrument Serif | 112 |
| `display` | Instrument Serif | 52 |
| `displayTitle` | Instrument Serif | 28 |
| `sectionTitle` | Geist semibold | 17 |
| `bodyText` | Geist | 14 |
| `control` | Geist medium | 13 |
| `caption` | Geist | 12 |
| `label` + `.capsLabel()` | Geist medium, uppercase, tracked | 11 |
| `readout` / `readoutSmall` | Geist Mono | 20 / 13 |

Fonts are registered at launch by `Typography.registerFonts()`. Licenses: [Resources/LICENSES.md](../Resources/LICENSES.md).

## Shape and space

Spacing: 4, 8, 16, 24, 40, 64. Radii: 8 control, 12 button, 18 panel, 20 card, capsules for chips. Touch targets are at least 40 pt tall in the sidebar and 44 pt in practice controls.

## Signature elements

- **The filament.** A 2 pt amber line with a soft glow where falling notes meet the keyboard. `FilamentBackground` echoes it with a faint warm light from the bottom of each screen.
- **Notation on dark.** The staff is drawn light on charcoal, not on a white page, so sheet and falling-notes views read as one surface.
- **Stage mode** is the strictest variant: near-black, very large type, a lock, and a panic control that is always visible.
