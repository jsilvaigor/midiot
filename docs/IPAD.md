# Midiot on the iPad

The iPad app is for rehearsals and working away from the desk. It is the same code as the Mac app, built as a second target, `MidiotPad`, for iPadOS 26 in landscape.

## What is in it

| Section | iPad | Notes |
| --- | --- | --- |
| Sketchpad | Yes | Capture, takes, layers, chords, moods. No MIDI, MusicXML or PDF export. |
| Stage | Yes | With a touch keyboard for when the Launchkey is not plugged in. |
| Chords | Yes | |
| Settings | Yes | Without the rows for Mac-only features. |
| Today, Library, Practice | No | Sheet music and the practice path stay on the Mac. |

Sounds come from one General MIDI SoundFont (GeneralUser GS, 31 MB), piano included. The Mac's 1.2 GB grand piano is not bundled, so the piano is plainer on the iPad.

The Launchkey Mini MK3 works as on the Mac, pad lights included, through a USB adapter.

## Installing it

1. Fetch the sounds once: `Scripts/fetch-soundfonts.sh`.
2. In Xcode, open Settings › Accounts and sign in with the Apple ID of the developer team (`99U97P63K6`). Both targets are signed with that team.
3. `xcodegen generate`, open `Midiot.xcodeproj`, choose the `MidiotPad` scheme and the iPad as the destination, and run. The first run asks to trust the developer on the iPad (Settings › General › VPN & Device Management) and to turn on Developer Mode.

## Plays in iCloud

Plays are files, one per play. With iCloud Drive on, both apps keep them in the app's iCloud folder (`iCloud.dev.midiot.Midiot`, `Documents/Plays`) and the system moves them between devices.

- **First launch with iCloud:** plays already on the device move into the iCloud folder. A play that exists there in a different state is kept beside it as a copy named after the device.
- **A play changed on two devices before they sync:** the version iCloud chooses stays; the other becomes a separate play with the other device's name in its title.
- **During a performance:** changes arriving from another device wait until the Stage is left or back at its list of plays, so cues never move under a locked stage.
- **No iCloud:** not signed in, or a build without the iCloud entitlement (an unsigned build): plays stay in `Application Support/Midiot/Plays` on the device, as before. Settings shows which.

Practice history, the song library and settings are not synced.

## Building without an Apple account

For a build that only needs to run on this Mac or in the simulator:

```sh
# Mac, signed to run locally, no iCloud
xcodebuild -project Midiot.xcodeproj -scheme Midiot -derivedDataPath build build \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGN_ENTITLEMENTS=

# iPad simulator
xcodebuild -project Midiot.xcodeproj -scheme MidiotPad -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build-pad build CODE_SIGNING_ALLOWED=NO
```

On the simulator, `-section stage` (or `chords`, `sketchpad`, `settings`) as a launch argument opens that section.
