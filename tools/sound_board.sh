#!/bin/zsh
# usage: tools/sound_board.sh [sound ...]
# Plays the mapped Blue Archive clips of assets/audio/ba/ui_map.json one after another through the Mac's speakers (afplay), at the map's
# gain, printing each name first. With names it plays only those; without, all 36 sounds in the map's order.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT" "$@" <<'PY'
import json, subprocess, sys, time
root, want = sys.argv[1], sys.argv[2:]
m = json.load(open(root + "/assets/audio/ba/ui_map.json"))["sounds"]
for name in (want or m):
    if name not in m:
        print("no such sound:", name, "(names: %s)" % " ".join(m)); continue
    e = m[name]
    for i, rel in enumerate(e["clips"], 1):
        vol = min(1.0, 10 ** (e["db"] / 20) * 3.0)   # afplay's -v is linear; the map's dB trim, lifted so quiet ones are audible
        print("%-12s %d/%d  %s  (%+.0f dB)" % (name, i, len(e["clips"]), rel, e["db"]))
        subprocess.run(["afplay", "-v", "%.3f" % vol, root + "/assets/audio/ba/" + rel])
        time.sleep(0.25)
PY
