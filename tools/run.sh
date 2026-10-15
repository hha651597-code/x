#!/bin/zsh
# usage: tools/run.sh <steps.json> [extra godot args]
# Runs the game in a real 1280x720 window, executes the step file (screenshots, probes) and prints errors.
# Needs a real window. Step vocabulary: scripts/core/dbg.gd; look at relevant docs.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$HOME/Tools/godot-4.7.2/Godot.app/Contents/MacOS/Godot}"
cd "$ROOT" || exit 1
# (Re-)import the project in a real window when needed.
# Needed when: no import cache yet (fresh clone), or a script / asset changed since the last import: new class_name
# scripts (scripts/sprites/*) are unknown to the game until the global class cache is rebuilt, and new sprite frames
# need their .import files. The import opens a real window briefly.
ensure_import() {
	local stamp="$ROOT/.godot/.tools_import_stamp"
	local need=0
	[ -d "$ROOT/.godot/imported" ] || need=1
	[ -f "$stamp" ] || need=1
	if [ $need = 0 ]; then
		[ -n "$(find "$ROOT/scripts" "$ROOT/shaders" \( -name '*.gd' -o -name '*.gdshader' \) -newer "$stamp" -print -quit 2>/dev/null)" ] && need=1
		[ -n "$(find "$ROOT/assets/ba" \( -name '*.png' -o -name '*.webp' -o -name '*.jpg' -o -name '*.glb' -o -name '*.gltf' -o -name '*.dds' \) -newer "$stamp" -print -quit 2>/dev/null)" ] && need=1
		[ -n "$(find "$ROOT/assets/audio" \( -name '*.ogg' -o -name '*.wav' -o -name '*.import' \) -newer "$stamp" -print -quit 2>/dev/null)" ] && need=1
	fi
	if [ $need = 1 ]; then
		echo "import: (re)importing the project (a window opens briefly)…"
		"$GODOT" --path "$ROOT" --import >/dev/null 2>&1
		mkdir -p "$ROOT/.godot" && touch "$stamp"
	fi
}
ensure_import
STEPS="$1"
shift
"$GODOT" --path "$ROOT" --resolution 1280x720 --position 40,40 "$@" -- --script="$STEPS" 2>&1 | grep -v -E "^(Godot Engine|Metal|Vulkan|OpenGL|\s*$)" | head -${MAXLINES:-80}
