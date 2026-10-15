#!/bin/zsh
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$HOME/Tools/godot-4.7.2/Godot.app/Contents/MacOS/Godot}"
cd "$ROOT" || exit 1
OUT="$("$GODOT" --path "$ROOT" --resolution 1280x720 --position 40,40 --script res://scripts/stages3d/tests/stage_void.gd 2>&1)"
CODE=$?
print -r -- "$OUT" | grep -v -E "^(Godot Engine|Metal|Vulkan|OpenGL|\s*$)" | tail -n ${MAXLINES:-40}
if print -r -- "$OUT" | grep -q -E "SCRIPT ERROR|SHADER ERROR|Parse Error|^ERROR:"; then
	echo "stage_void: FAIL (SCRIPT ERROR, SHADER ERROR, Parse Error or ERROR: in the output)"
	exit 1
fi
if ! print -r -- "$OUT" | grep -q "^STAGE_VOID PASS"; then
	echo "stage_void: FAIL (no STAGE_VOID PASS line)"
	exit 1
fi
exit $CODE
