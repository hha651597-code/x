#!/bin/zsh
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$HOME/Tools/godot-4.7.2/Godot.app/Contents/MacOS/Godot}"
cd "$ROOT" || exit 1
ensure_import() {
	local stamp="$ROOT/.godot/.tools_import_stamp"
	local need=0
	[ -d "$ROOT/.godot/imported" ] || need=1
	[ -f "$stamp" ] || need=1
	if [ $need = 0 ]; then
		[ -n "$(find "$ROOT/scripts" "$ROOT/shaders" \( -name '*.gd' -o -name '*.gdshader' -o -name '*.gdshaderinc' \) -newer "$stamp" -print -quit 2>/dev/null)" ] && need=1
		[ -n "$(find "$ROOT/assets/ba" \( -name '*.png' -o -name '*.glb' -o -name '*.webp' -o -name '*.jpg' \) -newer "$stamp" -print -quit 2>/dev/null)" ] && need=1
	fi
	if [ $need = 1 ]; then
		echo "import: (re)importing the project (a window opens briefly)…"
		"$GODOT" --path "$ROOT" --import >/dev/null 2>&1
		mkdir -p "$ROOT/.godot" && touch "$stamp"
	fi
}
ensure_import
OUT="$("$GODOT" --path "$ROOT" --resolution 1280x720 --position 40,40 --disable-vsync --script res://scripts/stages3d/tests/stage_perf.gd -- "$@" 2>&1)"
CODE=$?
print -r -- "$OUT" | grep -E "^(PERF|SCRIPT ERROR|SHADER ERROR|ERROR:|WATCHDOG)"
if print -r -- "$OUT" | grep -q -E "SCRIPT ERROR|SHADER ERROR|Parse Error|^ERROR:|^WATCHDOG"; then
	echo "stage_perf: FAIL (SCRIPT ERROR, SHADER ERROR, Parse Error, ERROR: or WATCHDOG in the output)"
	exit 1
fi
if ! print -r -- "$OUT" | grep -q "^PERF "; then
	echo "stage_perf: FAIL (no PERF line)"
	exit 1
fi
exit $CODE
