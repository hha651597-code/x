#!/bin/zsh
# usage: tools/sd_measure.sh
# Writes assets/ba/sd/<key>/sockets.json for every SD fighter (scripts/models/tools/sd_measure.gd: muzzle per kit spawn and
# shot frame, hurtbox from torso bones) in a small real window. Re-run it after changing a kit's frames,
# an sd.json or a model; tools/sd_test.sh fails while a sockets.json is stale.
# Fails on a non-zero exit, on any "SCRIPT ERROR" line in Godot's output, or on a run that never prints SD_MEASURE pass.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$HOME/Tools/godot-4.7.2/Godot.app/Contents/MacOS/Godot}"
cd "$ROOT" || exit 1
# (Re-)import the project in a real window when needed (same rule as tools/run.sh).
ensure_import() {
	local stamp="$ROOT/.godot/.tools_import_stamp"
	local need=0
	[ -d "$ROOT/.godot/imported" ] || need=1
	[ -f "$stamp" ] || need=1
	if [ $need = 0 ]; then
		[ -n "$(find "$ROOT/scripts" "$ROOT/shaders" \( -name '*.gd' -o -name '*.gdshader' \) -newer "$stamp" -print -quit 2>/dev/null)" ] && need=1
		[ -n "$(find "$ROOT/assets/ba" \( -name '*.png' -o -name '*.webp' -o -name '*.jpg' \) -newer "$stamp" -print -quit 2>/dev/null)" ] && need=1
	fi
	if [ $need = 1 ]; then
		echo "import: (re)importing the project (a window opens briefly)…"
		"$GODOT" --path "$ROOT" --import >/dev/null 2>&1
		mkdir -p "$ROOT/.godot" && touch "$stamp"
	fi
}
ensure_import
OUT="$("$GODOT" --path "$ROOT" --resolution 640x360 --position 40,40 --script res://scripts/models/tools/sd_measure.gd 2>&1)"
CODE=$?
print -r -- "$OUT" | grep -v -E "^(Godot Engine|Metal|Vulkan|OpenGL|\s*$)" | tail -n ${MAXLINES:-80}
if print -r -- "$OUT" | grep -q "SCRIPT ERROR"; then
	echo "sd_measure: FAIL (SCRIPT ERROR in the output)"
	exit 1
fi
if ! print -r -- "$OUT" | grep -q "^SD_MEASURE PASS"; then
	echo "sd_measure: FAIL (no SD_MEASURE PASS line)"
	exit 1
fi
exit $CODE
