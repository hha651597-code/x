#!/bin/sh
# run the game on linux.
cd "$(dirname "$0")" || exit 1

VER=4.7.2
ZIP=Godot_v$VER-stable_linux.x86_64.zip
SHA512=9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65
DIR=$HOME/Tools/godot-$VER
BIN=$DIR/Godot_v$VER-stable_linux.x86_64

fetch() {
  [ "$(uname -m)" = x86_64 ] || { echo "No Godot found, and the download is x86_64 only: install godot and rerun." >&2; exit 1; }
  command -v curl >/dev/null 2>&1 || { echo "curl is needed to download Godot $VER." >&2; exit 1; }
  mkdir -p "$DIR" || exit 1
  echo "Downloading Godot $VER to $DIR"
  curl -fL --progress-bar -o "$DIR/$ZIP" "https://github.com/godotengine/godot-builds/releases/download/$VER-stable/$ZIP" || exit 1
  if [ "$(sha512sum "$DIR/$ZIP" | cut -d' ' -f1)" != "$SHA512" ]; then
    rm -f "$DIR/$ZIP"
    echo "The Godot download failed its SHA-512 check and was deleted." >&2
    exit 1
  fi
  if command -v unzip >/dev/null 2>&1; then
    unzip -qo "$DIR/$ZIP" -d "$DIR" || exit 1
  else
    python3 -m zipfile -e "$DIR/$ZIP" "$DIR" || exit 1
  fi
  chmod +x "$BIN"
  rm -f "$DIR/$ZIP"
}

# gaming mode sets SteamGamepadUI
if [ -z "$WINDOWED" ] && { [ -n "$SteamDeck" ] || [ -n "$SteamGamepadUI" ]; }; then
  set -- --fullscreen "$@"
fi

if [ -n "$GODOT" ]; then
  exec "$GODOT" --path . "$@"
elif command -v godot >/dev/null 2>&1; then
  exec godot --path . "$@"
elif command -v godot4 >/dev/null 2>&1; then
  exec godot4 --path . "$@"
elif command -v flatpak >/dev/null 2>&1 && flatpak info org.godotengine.Godot >/dev/null 2>&1; then
  exec flatpak run org.godotengine.Godot --path "$PWD" "$@"
fi

[ -x "$BIN" ] || fetch
exec "$BIN" --path . "$@"
