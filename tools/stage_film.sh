#!/bin/zsh
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$HOME/Tools/godot-4.7.2/Godot.app/Contents/MacOS/Godot}"
cd "$ROOT" || exit 1
rm -f "$ROOT"/tmp/intro2/{day,night}/tick_*.png(N)
OUT="$("$GODOT" --path "$ROOT" --resolution 1280x720 --position 40,40 --script res://scripts/stages3d/tests/stage_path_test.gd -- --film 2>&1)"
CODE=$?
print -r -- "$OUT" | grep -v -E "^(Godot Engine|Metal|Vulkan|OpenGL|FILM [a-z]+ tick |\s*$)" | tail -n ${MAXLINES:-40}
SHORT=0
for v in day night; do
	n=$(ls "$ROOT/tmp/intro2/$v" 2>/dev/null | grep -c '^tick_.*\.png$')
	echo "stage_film: $v $n frames in tmp/intro2/$v"
	[ "$n" -ge 20 ] || SHORT=1
done
if print -r -- "$OUT" | grep -q -E "SCRIPT ERROR|SHADER ERROR|Parse Error|^ERROR:"; then
	echo "stage_film: FAIL (SCRIPT ERROR, SHADER ERROR, Parse Error or ERROR: in the output)"
	exit 1
fi
if [ $SHORT = 1 ]; then
	echo "stage_film: FAIL (fewer than 20 frames for a variant)"
	exit 1
fi
exit $CODE
