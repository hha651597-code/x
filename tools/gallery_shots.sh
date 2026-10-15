#!/bin/zsh
# usage: tools/gallery_shots.sh   Captures every Extras state (scripts/ui/tools/shots/s3_*.json) into /tmp/ba-ui-out/extras,
# the wide one in a 1600x900 window. Real windows.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
SHOTS=scripts/ui/tools/shots
zsh tools/run.sh $SHOTS/extras_final.json
zsh tools/run.sh $SHOTS/extras_wide.json --resolution 1600x900
zsh tools/run.sh $SHOTS/select_special.json
