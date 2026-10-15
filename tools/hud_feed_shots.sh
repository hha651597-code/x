#!/bin/zsh
# usage: [W3_SHOTS=banner,feed,warn] [W3_OUT=dir] zsh tools/hud_feed_shots.sh
# 1280x720 captures of the fight feed, the hit and guard words and every banner kind over a real stage. Needs a real window.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$HOME/Tools/godot-4.7.2/Godot.app/Contents/MacOS/Godot}"
cd "$ROOT" || exit 1
"$GODOT" --path "$ROOT" --import >/dev/null 2>&1
OUT="$("$GODOT" --path "$ROOT" --resolution 1280x720 --position 40,40 --script res://scripts/fight/tests/hud_feed_shots.gd 2>&1)"
print -r -- "$OUT" | grep -v -E "^(Godot Engine|Metal|Vulkan|OpenGL|\s*$)" | tail -n ${MAXLINES:-60}
if print -r -- "$OUT" | grep -q -E "SCRIPT ERROR|SHADER ERROR"; then
	echo "hud_feed_shots: FAIL"
	exit 1
fi
