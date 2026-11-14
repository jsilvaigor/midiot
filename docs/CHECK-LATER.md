# Check later

Things that are built but have not been confirmed by hand. Remove a line once it is checked.

## MIDI out

- **No crash over time.** With MIDI out on, play a full Practice song and a long Stage layer; the app used to crash after a few thousand notes.
- **Per-cue routing.** Run `python3 Scripts/make-test-play.py`, open the cue "Plays on MIDI out": the keys sound only at the other end on channel 14, and fall back to Midiot's sound when MIDI out is off.
- **"Plays on" tile.** Unlocked, the menu lists Midiot and channels 1 to 16; the tile reads "MIDI out · ch N" when routed and "MIDI out is off" when routed with MIDI out off.
- **To a hardware device.** Choose a synth or interface in Settings › MIDI out and play.
- **Mute toggle.** With "Silence Midiot's own instruments" on, only the other end is heard and the metronome still clicks.
- **No stuck notes.** Switch the destination, or turn MIDI out off, while holding a note.
- **IAC bus.** If one is ever used as the destination, notes do not double or run away.

## Earlier milestones

- How the piano sounds, and how latency feels on the keys.
- The Roland A-49 in Practice.

## iPad and iCloud

Nothing here has run on a real iPad or against real iCloud; it was built and looked at in the simulator only.

- **Mac still builds in Xcode.** The Mac target is now signed with the team instead of ad hoc. If Xcode says "No Accounts", sign in under Settings › Accounts.
- **Install on the iPad** following `docs/IPAD.md`.
- **Launchkey on the iPad.** Keys, pads, knobs and pad lights behave as on the Mac.
- **Sound on the iPad.** Piano and cue sounds play; latency is acceptable; the metronome clicks.
- **Touch keyboard.** Chords with several fingers, slides between keys, no stuck notes.
- **iCloud, first launch.** Plays made on the Mac before this change appear on the iPad; Settings shows "Plays in iCloud: On" on both.
- **iCloud, both ways.** A cue recorded on the iPad shows up on the Mac, and the other way round, without restarting either app.
- **iCloud, conflict.** With the iPad offline, change the same play on both devices, then reconnect: both versions exist, one named after the other device.
- **Stage during sync.** With the stage locked on one device, a change made on the other appears only after unlocking and going back to the list of plays.
- **Mac sounds changed.** `Scripts/fetch-soundfonts.sh` now also installs GeneralUser GS, which the Mac uses for every sound but the piano in place of the macOS built-in set. Check cue sounds still suit.
