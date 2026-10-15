#!/bin/zsh
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PYTHON="${PYTHON:-$HOME/Tools/venv-stages/bin/python}"
INSTALL="${BA_INSTALL:-$HOME/Downloads/BlueArchive/BlueArchive_Data}"
ID="$1"
[ -n "$ID" ] || { echo "usage: tools/stages/stage_extract.sh <stage id> [work dir] [out dir]; the out dir defaults to tmp/stage_out"; exit 2; }
WORK="${2:-$ROOT/tmp/stage_work}"
OUT="${3:-$ROOT/tmp/stage_out}"
exec "$PYTHON" -I "$ROOT/tools/stages/extract.py" "$ID" --install "$INSTALL" --work "$WORK" --out "$OUT"
