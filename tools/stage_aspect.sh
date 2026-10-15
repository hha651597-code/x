#!/bin/zsh
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
if [ ! -f "$1" ]; then
	print -u2 "usage: tools/stage_aspect.sh <step file> [WxH ...]"
	exit 2
fi
STEPS="$1"
shift
SIZES=(1920x1080 1280x960 2560x1080 1000x800 1280x720)
[ -n "$1" ] && SIZES=("$@")
STAMP="$(mktemp)"
for S in $SIZES; do
	echo "ASPECT $S"
	touch "$STAMP"
	timeout "${TIMEOUT:-300}" tools/run.sh "$STEPS" --resolution "$S"
	DEST=".dev/out/aspect/$S"
	mkdir -p "$DEST"
	find .dev/out -path .dev/out/aspect -prune -o -type f -name '*.png' -newer "$STAMP" -print | while IFS= read -r F; do
		mv "$F" "$DEST/" && echo "KEPT $DEST/${F:t}"
	done
done
rm -f "$STAMP"
