#!/bin/sh
# Downloads the app's SoundFonts into Resources/SoundFonts, where the Xcode build picks them up:
#   - Salamander Grand Piano (296 MB download, CC-BY 3.0, Alexander Holm): the piano.
#   - GeneralUser GS (31 MB, GeneralUser GS License 2.0, S. Christian Collins): the Sketchpad's
#     strings, keys, pads and percussion. Without it the app uses the sounds built into macOS.
# Safe to re-run: resumes partial downloads and skips what is already in place.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
dest="$root/Resources/SoundFonts"
cache="$root/.soundfont-download"
piano_url="https://freepats.zenvoid.org/Piano/SalamanderGrandPiano/SalamanderGrandPiano-SF2-V3+20200602.tar.xz"
palette_url="https://raw.githubusercontent.com/mrbumpy409/GeneralUser-GS/main/GeneralUser-GS.sf2"

mkdir -p "$cache/extracted"

if ls "$dest"/Salamander*.sf2 >/dev/null 2>&1; then
    echo "Piano already present in $dest"
else
    curl -fL --retry 5 -C - -o "$cache/salamander.tar.xz" "$piano_url"
    tar -xJf "$cache/salamander.tar.xz" -C "$cache/extracted"
    find "$cache/extracted" -name '*.sf2' -exec mv {} "$dest/" \;
fi

if [ -f "$dest/GeneralUser-GS.sf2" ]; then
    echo "GeneralUser GS already present in $dest"
else
    curl -fL --retry 5 -C - -o "$cache/GeneralUser-GS.sf2" "$palette_url"
    mv "$cache/GeneralUser-GS.sf2" "$dest/"
fi

rm -rf "$cache"
ls -lh "$dest"/*.sf2
