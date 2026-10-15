#!/bin/zsh
# usage: zsh tools/fx_gallery.sh   ->   tmp/fx_gallery_<bright|dark>_<0..2>.png: the Fx kinds on a bright and a dark ground.
# Needs a real window. Fails on a script or shader error, or when an effect runs out of its cell (GALLERY_CLIP).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$HOME/Tools/godot-4.7.2/Godot.app/Contents/MacOS/Godot}"
cd "$ROOT" || exit 1
"$GODOT" --path "$ROOT" --import >/dev/null 2>&1      # new scripts and textures (a window opens briefly)
OUT="$("$GODOT" --path "$ROOT" --resolution 1280x720 --position 40,40 --script res://scripts/fight/tests/fx_gallery.gd 2>&1)"
print -r -- "$OUT" | grep -v -E "^(Godot Engine|Metal|Vulkan|OpenGL|\s*$)" | tail -n 40
if print -r -- "$OUT" | grep -q -E "SCRIPT ERROR|SHADER ERROR|GALLERY_CLIP"; then
	echo "fx_gallery: FAIL"
	exit 1
fi
