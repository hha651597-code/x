#!/bin/zsh
# usage: zsh tools/glyph_shots.sh [OUTDIR] [WIDTHxHEIGHT]   ->   OUTDIR/assign_*, options_*, gallery_*, hud_*.png (a real window)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$HOME/Tools/godot-4.7.2/Godot.app/Contents/MacOS/Godot}"
cd "$ROOT" || exit 1
"$GODOT" --path "$ROOT" --import >/dev/null 2>&1
OUT="$("$GODOT" --path "$ROOT" --resolution "${2:-1280x720}" --position 40,40 --script res://scripts/ui/tools/glyph_shots.gd -- "${1:-$ROOT/tmp}" "${2:-1280x720}" 2>&1)"
print -r -- "$OUT" | grep -v -E "^(Godot Engine|Metal|Vulkan|OpenGL|\s*$)" | tail -n 80
if print -r -- "$OUT" | grep -q -E "SCRIPT ERROR|SHADER ERROR|GLYPH_SHOTS FAIL"; then
	echo "glyph_shots: FAIL"
	exit 1
fi
