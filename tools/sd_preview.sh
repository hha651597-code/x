#!/bin/zsh
# usage: tools/sd_preview.sh [key] [anim] [game args...]
#        tools/sd_preview.sh --sheet <key|all> <anim|all>
# Opens the SD preview screen (scripts/models/sd_preview_screen.gd) in a real 1280x720 window, preselected on roster
# fighter <key> and <anim> (a state anim from sd.json, a kit move key or a raw clip name). Extra args go to the game after
# "--", e.g. --script=steps.json for scripts/core/dbg.gd. --sheet renders filmstrips (both facings as rows, overlay on)
# to export/sd_preview/<key>/<anim>.png and quits. Fails on a non-zero exit or ANY "SCRIPT ERROR" line
# (sheets: also on any ERROR line or a run that never prints SD_PREVIEW pass).
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
ENGINE=()
ARGS=(--screen=sdpreview)
if [ "$1" = "--sheet" ]; then
	# --quit-after ends a run whose screen never loaded (a parse error leaves the window idle, ~2 min at 20000).
	# lazy implementation: 20000 frames is ~4x a full run with 2 SD fighters (~4800 frames). will fix when the SD roster outgrows it.
	ENGINE=(--disable-vsync --quit-after 20000)
	ARGS+=(--sd-sheet "--sd-key=${2:-all}" "--sd-anim=${3:-all}")
	shift $(( $# < 3 ? $# : 3 ))
else
	if [ -n "$1" ] && [[ "$1" != --* ]]; then ARGS+=("--sd-key=$1"); shift; fi
	if [ -n "$1" ] && [[ "$1" != --* ]]; then ARGS+=("--sd-anim=$1"); shift; fi
fi
LOG="$(mktemp -t sd_preview)"
"$GODOT" --path "$ROOT" --resolution 1280x720 --position 40,40 "${ENGINE[@]}" -- "${ARGS[@]}" "$@" 2>&1 | tee "$LOG" | grep -v -E "^(Godot Engine|Metal|Vulkan|OpenGL|\s*$)"
CODE=${pipestatus[1]}
if [ -n "$ENGINE" ] && ! grep -q "^SD_PREVIEW PASS" "$LOG"; then
	echo "sd_preview: FAIL (no SD_PREVIEW PASS line)"
	CODE=1
fi
# a descriptor naming a missing clip only prints an ERROR and leaves the previous pose in the cell
if [ -n "$ENGINE" ] && grep -q "ERROR:" "$LOG"; then
	echo "sd_preview: FAIL (ERROR in the output)"
	CODE=1
fi
if grep -q "SCRIPT ERROR" "$LOG"; then
	echo "sd_preview: FAIL (SCRIPT ERROR in the output)"
	CODE=1
fi
rm -f "$LOG"
exit $CODE
