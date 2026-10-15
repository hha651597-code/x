#!/usr/bin/env python3
"""The student on the main menu speaks a real Blue Archive voice line, shown with its English subtitle.
Writes assets/audio/ba/menu_voice/<id>_<mood>_<n>.ogg (the pack's own Ogg Vorbis, byte for byte), assets/ba/menu_lines.json
(mood -> clip and subtitle, per fighter) and assets/audio/ba/menu_voice/PROVENANCE.json.

1. Copy the 30 fighters' Japanese voice packs out of the install and unpack them (BA-AX v3.0.0, github.com/Deathemonic/BA-AX):
     cp .../PUB/Resource/GameData/MediaResources/Audio/VOC_JP/JP_<pack>.molru SRC/
     baax extract media --input SRC/JP_<pack>.molru --output OUT/<pack>          (gives OUT/<pack>/JP_<pack>/<Name>_Lobby_1.ogg ...)
   The pack is JP_<fighter name>.molru, or JP_<DevName>.molru (CH0187 for Toki) where SchaleDB's DevName is a CH number.
2. Download the subtitles: https://schaledb.com/data/en/voice.json (each line: Group, AudioClip, Transcription).
usage: python3 -I tools/menu_voice_assets.py OUT voice.json

Moods follow the portrait: calm shows a lobby greeting (the first line of each lobby group, seasonal ones left out), win a victory line,
lose (the worried face) the line said on entering a fight or guarding. A line with no subtitle, or over MAX_CHARS, is not used."""
import hashlib
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/audio/ba/menu_voice"
MAX_CHARS = 110
SEASONAL = ("UILobbyUserBDay", "UILobbyStudentBDay", "UILobbyNewYear", "UILobbyXmas", "UILobbyHalloween")
WIN = ("BattleVictory1", "BattleVictory2", "TacticVictory1", "TacticVictory2")
LOSE = ("BattleDefense1", "FormationIn1", "TacticIn1")


def clean(t):
    return " ".join((t or "").split())


def pick(voice_entry, files):
    """mood -> [(group, clip basename, subtitle)] for one student; files = lower-case clip name -> real file name."""
    def usable(e):
        t = clean(e.get("Transcription"))
        return t and len(t) <= MAX_CHARS and Path(e["AudioClip"]).stem.lower() in files
    out = {"calm": [], "win": [], "lose": []}
    seen = set()
    for e in voice_entry.get("Lobby", []):
        if e["Group"] in SEASONAL or e["Group"] in seen or not usable(e):
            continue
        seen.add(e["Group"])
        out["calm"].append(e)
    by_group = {e["Group"]: e for e in voice_entry.get("Battle", []) if usable(e)}
    out["win"] = [by_group[g] for g in WIN if g in by_group]
    out["lose"] = [by_group[g] for g in LOSE if g in by_group]
    return out


def main(src, voice_json):
    roster = json.loads((ROOT / "assets/ba/roster.json").read_text())["fighters"]
    voice = json.loads(Path(voice_json).read_text())
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    lines, prov = {}, {}
    for f in roster:
        fid = str(f["id"])
        packs = [p for p in Path(src).iterdir() if (p / ("JP_" + p.name)).is_dir()]
        pack = next((p for p in packs if p.name == f["name"]), None) or next((p for p in packs if str(voice[fid].get("Normal", [{}])[0].get("AudioClip", "")).lower().startswith("jp_" + p.name.lower() + "/")), None)
        if pack is None:
            sys.exit("no unpacked voice pack for %s (%s)" % (f["name"], fid))
        folder = pack / ("JP_" + pack.name)
        files = {p.stem.lower(): p for p in folder.glob("*.ogg")}
        chosen = pick(voice[fid], files)
        lines[fid] = {}
        for mood, entries in chosen.items():
            if not entries:
                sys.exit("%s has no %s line" % (f["name"], mood))
            lines[fid][mood] = []
            for n, e in enumerate(entries, 1):
                srcfile = files[Path(e["AudioClip"]).stem.lower()]
                name = "%s_%s_%d.ogg" % (fid, mood, n)
                data = srcfile.read_bytes()
                (OUT / name).write_bytes(data)
                lines[fid][mood].append({"clip": name, "text": clean(e["Transcription"])})
                prov[name] = {"pack": "JP_%s.molru" % pack.name, "clip": srcfile.name, "group": e["Group"], "sha256": hashlib.sha256(data).hexdigest(),
                              "subtitle": "SchaleDB voice.json (English)"}
    (ROOT / "assets/ba/menu_lines.json").write_text(json.dumps(
        {"note": "What the student on the main menu says: a real Blue Archive voice line and its English subtitle. tools/menu_voice_assets.py writes this.",
         "lines": lines}, indent=1, ensure_ascii=False) + "\n")
    (OUT / "PROVENANCE.json").write_text(json.dumps(prov, indent=1, sort_keys=True) + "\n")
    print("wrote %d clips, %.1f MB" % (len(prov), sum(p.stat().st_size for p in OUT.glob("*.ogg")) / 1048576))


if __name__ == "__main__":
    main(*sys.argv[1:3]) if len(sys.argv) == 3 else sys.exit(__doc__)
