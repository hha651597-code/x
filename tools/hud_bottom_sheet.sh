#!/bin/zsh
# usage: zsh tools/hud_bottom_sheet.sh   ->   tmp/hud_bottom_*.png: the bottom row over a real training fight (1280x720 each).
# Needs a real window. Fails on a script error.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$HOME/Tools/godot-4.7.2/Godot.app/Contents/MacOS/Godot}"
cd "$ROOT" || exit 1
"$GODOT" --path "$ROOT" --import >/dev/null 2>&1      # new scripts and textures (a window opens briefly)
OUT="$("$GODOT" --path "$ROOT" --resolution 1280x720 --position 40,40 --script res://scripts/fight/tests/hud_bottom_sheet.gd 2>&1)"
print -r -- "$OUT" | grep -v -E "^(Godot Engine|Metal|Vulkan|OpenGL|\s*$)" | tail -n 40
if print -r -- "$OUT" | grep -q -E "SCRIPT ERROR|SHADER ERROR|SHEET FAIL"; then
	echo "hud_bottom_sheet: FAIL"
	exit 1
fi
