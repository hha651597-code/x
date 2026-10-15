#!/bin/zsh
# usage: HUD_MENUS_OUT=/dir/ HUD_MENUS_SHOTS=pause,result,training zsh tools/hud_menus_shots.sh
# Pause, result and training overlay captures at 1280x720. Needs a real window. Fails on a script or shader error.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$HOME/Tools/godot-4.7.2/Godot.app/Contents/MacOS/Godot}"
cd "$ROOT" || exit 1
"$GODOT" --path "$ROOT" --import >/dev/null 2>&1
OUT="$("$GODOT" --path "$ROOT" --resolution 1280x720 --position 40,40 --script res://scripts/fight/tests/hud_menus_shots.gd 2>&1)"
print -r -- "$OUT" | grep -v -E "^(Godot Engine|Metal|Vulkan|OpenGL|\s*$)" | head -n ${MAXLINES:-60}
if print -r -- "$OUT" | grep -q -E "SCRIPT ERROR|SHADER ERROR"; then
	echo "hud_menus_shots: FAIL"
	exit 1
fi
