#!/bin/zsh
# usage: [E2_OUT=dir] [E2_SETS=cutin,reduce,kinds] zsh tools/effects_cutin_shots.sh [WxH]
# Captures for the effects at exact sim ticks (scripts/fight/tests/effects_cutin_shots.gd). Needs a real window.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$HOME/Tools/godot-4.7.2/Godot.app/Contents/MacOS/Godot}"
cd "$ROOT" || exit 1
"$GODOT" --path "$ROOT" --import >/dev/null 2>&1
OUT="$("$GODOT" --path "$ROOT" --resolution "${1:-1280x720}" --position 40,40 --script res://scripts/fight/tests/effects_cutin_shots.gd 2>&1)"
print -r -- "$OUT" | grep -v -E "^(Godot Engine|Metal|Vulkan|OpenGL|\s*$)" | tail -n 30
if print -r -- "$OUT" | grep -q -E "SCRIPT ERROR|SHADER ERROR"; then
	echo "effects_cutin_shots: FAIL"
	exit 1
fi
