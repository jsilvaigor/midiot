#!/bin/sh
# Downloads the Salamander Grand Piano SoundFont (296 MB download, CC-BY 3.0, Alexander Holm)
# into Resources/SoundFonts, where the Xcode build picks it up. Safe to re-run: resumes a
# partial download and does nothing once the SoundFont is in place.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
dest="$root/Resources/SoundFonts"
cache="$root/.soundfont-download"
url="https://freepats.zenvoid.org/Piano/SalamanderGrandPiano/SalamanderGrandPiano-SF2-V3+20200602.tar.xz"

if ls "$dest"/*.sf2 >/dev/null 2>&1; then
    echo "SoundFont already present in $dest"
    exit 0
fi

mkdir -p "$cache/extracted"
curl -fL --retry 5 -C - -o "$cache/salamander.tar.xz" "$url"
tar -xJf "$cache/salamander.tar.xz" -C "$cache/extracted"
find "$cache/extracted" -name '*.sf2' -exec mv {} "$dest/" \;
rm -rf "$cache"
ls -lh "$dest"/*.sf2
