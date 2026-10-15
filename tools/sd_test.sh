#!/bin/zsh
# usage: [TEST=res://scripts/models/tests/<test>.gd] tools/sd_test.sh
# Runs the SD fighter animation suite (scripts/models/tests/sd_anim_test.gd) in a small real window.
# Fails on a non-zero exit or on ANY "SCRIPT ERROR" line in Godot's output.
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
		[ -n "$(find "$ROOT/assets/audio" \( -name '*.ogg' -o -name '*.wav' -o -name '*.import' \) -newer "$stamp" -print -quit 2>/dev/null)" ] && need=1
	fi
	if [ $need = 1 ]; then
		echo "import: (re)importing the project (a window opens briefly)…"
		"$GODOT" --path "$ROOT" --import >/dev/null 2>&1
		mkdir -p "$ROOT/.godot" && touch "$stamp"
	fi
}
ensure_import
OUT="$("$GODOT" --path "$ROOT" --resolution 640x360 --position 40,40 --script "${TEST:-res://scripts/models/tests/sd_anim_test.gd}" 2>&1)"
CODE=$?
print -r -- "$OUT" | grep -v -E "^(Godot Engine|Metal|Vulkan|OpenGL|\s*$)" | tail -n ${MAXLINES:-80}
if print -r -- "$OUT" | grep -q "SCRIPT ERROR"; then
	echo "sd_test: FAIL (SCRIPT ERROR in the output)"
	exit 1
fi
exit $CODE
