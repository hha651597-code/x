#!/usr/bin/env python3
"""Copies the confirmed Hina and Hoshino sounds out of the raw extract into assets/audio/ba, measures
their loudness with ffmpeg (ebur128) and writes manifest.json (what Sfx plays) and PROVENANCE.json.

usage: python3 -I tools/ba_audio_import.py --src <path to export/ba_audio> [--dst assets/audio/ba]

The extract is git-ignored; pass its path with --src.
Only .wav and .ogg are copied, never the .import files next to them. Both json files are rewritten
from scratch, so a rerun with the same input gives the same bytes.

SFX entries get source = {bundle, cab, path_id} from assets/audio/ba/sfx_sources.json when that file exists
(written by tools/ba_sfx_sources.py against the game client); without it source stays null.

After a first run, open the project once (tools/sd_test.sh does it) so Godot writes the .import files, then set
compress/mode=0 (PCM) in the sfx/*.wav.import files: Godot 4.7 defaults to QOA, which is lossy, and sound_test.gd
requires 16-bit PCM. Commit the .import files like the BGM ones.

Event tuning (vol, pitch, channel, gap, mute_in, priority) lives in SFX_EVENTS and VOICE_EVENTS below.
Volumes with no AudioAnimatorExcel row are marked "guess": true, to tune by ear.
RandomPitchMin/Max has no stated unit. Semitones are assumed: pitch_scale = 2^(n/12). Unverified.
"""
import argparse
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys

CEILING_DB = -1.5      # same true-peak ceiling as the BGM (assets/audio/bgm/TRACKS.md)
PEAK_MARGIN_DB = 0.05  # ffmpeg prints the peak to 0.1 dB
VOICE_TARGET_LUFS = -16.0
GATE_FLOOR_LUFS = -69.0  # clips shorter than 400 ms report -70 LUFS: nothing was measured

SFX_COUNT = 43

# linked to nobody (Hit_Mech_Short_01, Sweephair, Explosion_Grenade_01, Public_Ray_Glow, Ups) and held back
# because Hoshino has no shield (Ex_Shield_Drop)
SFX_SKIP = {
    "SFX_Common_Hit_Mech_Short_01", "SFX_Common_Sweephair", "SFX_Explosion_Grenade_01",
    "SFX_Public_Ray_Glow", "SFX_Ups", "SFX_Skill_Hoshino_Ex_Shield_Drop",
}

STUDENTS = {"hina": "Hina", "hoshino": "Hoshino"}
VOICE_LINES = [
    "Battle_Damage_1", "Battle_Damage_2", "Battle_Damage_3", "Battle_In_1", "Battle_In_2",
    "Battle_Retire", "Battle_Victory_1", "Battle_Victory_2", "CommonSkill",
    "ExSkill_1", "ExSkill_2", "ExSkill_3",
]
EVIDENCE_KEYS = {"hina": "Hina_default", "hoshino": "Hoshino_default"}

WIKI = "bluearchive.wiki/wiki/%s/audio"
SOURCE = "Blue Archive PC client, Steam install, copied out and unpacked 2026-10-14"
SCOPE = "Local fan project. Redistribution permission is not inferred."


def seq(prefix, n):
    return ["%s_%02d" % (prefix, i) for i in range(1, n + 1)]


IMPACTS = seq("SFX_Shot_Impact_Hit", 3)


def impacts():
    return {
        "hit_l": dict(clips=IMPACTS, vol=0.7, scale=1.1, channel="pool", guess=True),
        "hit_h": dict(clips=IMPACTS, vol=1.0, scale=0.9, channel="pool", guess=True),
    }


# delay is a hint in ticks for the hook-up, Sfx ignores it. 0.3 s is 18 ticks; 0.02 s is dropped.
SFX_EVENTS = {
    "hina": dict(
        shot=dict(clips=seq("SFX_Common_HMG", 5), vol=0.7, pitch=[-1, 1], channel="move", gap=36, mute_in=["ex"]),
        spool=dict(clips=seq("SFX_Common_HMG_Start_Hina", 3), vol=0.6, pitch=[0, 0], channel="long", gap=45),
        reload=dict(clips=seq("SFX_Common_HMG_Reload_Hina", 3), vol=0.8, pitch=[-1, 1], channel="long"),
        lock_and_load=dict(clips=["SFX_Public_Hina"], vol=0.8, channel="long", gap=120, guess=True),
        cutin=dict(clips=["SFX_Skill_Hina_Ex_Cut_in"], vol=0.9, channel="cut", guess=True),
        ult=dict(clips=["SFX_Skill_Hina_Ex"], vol=0.8, channel="move", guess=True),
        **impacts()
    ),
    "hoshino": dict(
        shot=dict(clips=seq("SFX_Common_SG", 8), vol=0.65, pitch=[-1, 0], channel="pool", gap=6),
        pump=dict(clips=seq("SFX_Common_SG_Delay", 8), vol=0.5, pitch=[-1, 1], channel="pool", delay=12),
        reload=dict(clips=seq("SFX_Common_SG_Reload", 5), vol=0.4, pitch=[-1, 0], channel="long", delay=18),
        first_aid=dict(clips=["SFX_JSD_Laser_02"], vol=0.7, channel="long", guess=True),
        heal_tick=dict(clips=["SFX_Common_Regen_Ing"], vol=0.7, channel="long", guess=True),
        cutin=dict(clips=["SFX_Skill_Hoshino_Ex_Cut_in"], vol=0.9, channel="cut", guess=True),
        ult=dict(clips=["SFX_Skill_Hoshino_Ex_Activate"], vol=0.8, channel="move", guess=True),
        ult_reload=dict(clips=["SFX_Skill_Hoshino_Ex_Reload"], vol=0.8, channel="long", delay=20, guess=True),
        **impacts()
    ),
}

# lines are file names without the student prefix. ko plays through any voice (cuts_all).
VOICE_EVENTS = dict(
    ult=dict(lines=["ExSkill_1", "ExSkill_2", "ExSkill_3"], priority=5),
    ko=dict(lines=["Battle_Retire"], priority=4, cuts_all=True),
    skill=dict(lines=["CommonSkill"], priority=3),
    skill_auto=dict(lines=["CommonSkill"], priority=3, gap=600),
    intro=dict(lines=["Battle_In_1", "Battle_In_2"], priority=2),
    victory=dict(lines=["Battle_Victory_1", "Battle_Victory_2"], priority=2),
    big_hit=dict(lines=["Battle_Damage_1", "Battle_Damage_2", "Battle_Damage_3"], priority=1, gap=180),
)

NOTES = [
    "RandomPitchMin/Max has no stated unit. Semitones are assumed: pitch_scale = 2^(n/12) * scale. Unverified; listen before trusting it.",
    "vol, gap, delay and channel were set from the table rows and from waveforms, not by ear.",
    "Entries with guess: true have no AudioAnimatorExcel row; their vol is a first guess.",
    "gap and delay are sim ticks (60 per second). delay is a hint for the fighter hook-up; Sfx ignores it.",
    "mute_in lists move keys during which the event is silent.",
    "gain_db is added to volume_db after the 0 dB clamp. SFX only pull true peaks down to -1.5 dB. Voices aim at -16 LUFS and never pass the -1.5 dB true-peak ceiling.",
    "Voice events: priority 5 wins; cuts_all plays through any voice, busy time and gap.",
]


def floor10(x):
    return math.floor(x * 10 + 1e-9) / 10.0


def measure(path):
    """Integrated loudness (None when ffmpeg could not gate it), true peak in dBFS, length in seconds."""
    run = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-af", "ebur128=peak=true", "-f", "null", "-"],
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
    tail = run.stderr.split("Summary:")[-1]
    lufs = re.search(r"I:\s+(-?[\d.]+|-inf)\s+LUFS", tail)
    peak = re.search(r"Peak:\s+(-?[\d.]+|-inf)\s+dBFS", tail)
    if run.returncode != 0 or not lufs or not peak:
        sys.exit("ffmpeg could not measure %s:\n%s" % (path, run.stderr[-400:]))
    probe = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
    i = float(lufs.group(1))
    return (None if i < GATE_FLOOR_LUFS else i), float(peak.group(1)), round(float(probe.stdout.strip()), 3)


def sfx_gain(peak):
    return min(0.0, floor10(CEILING_DB - PEAK_MARGIN_DB - peak))


def voice_gain(lufs, peak):
    cap = CEILING_DB - PEAK_MARGIN_DB - peak
    want = VOICE_TARGET_LUFS - lufs if lufs is not None else 0.0
    return floor10(min(want, cap))


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        h.update(f.read())
    return h.hexdigest()


def table_rows(evidence):
    """clip name -> the AudioAnimatorExcel rows that name it, in the shape confirmed_by wants."""
    out = {}
    for who, key in EVIDENCE_KEYS.items():
        entry = evidence[key]
        controller = entry["CostumeExcel"]["AnimatorName"]
        for row in entry["AudioAnimatorExcel"]:
            for clip in row["AudioClipPath"]:
                out.setdefault(clip, []).append({
                    "table": "AudioAnimatorExcel", "controller": controller, "hash": row["ControllerNameHash"],
                    "state": row["StateName"], "volume": row["Volume"], "delay": row["Delay"],
                    "pitch": [row["RandomPitchMin"], row["RandomPitchMax"]], "priority": row["AudioPriority"],
                })
    return out


def basis_for(name):
    if name.startswith("SFX_Shot_Impact_Hit"):
        return {"basis": "generic, no table link"}
    if name in ("SFX_Common_Regen_Ing", "SFX_JSD_Laser_02"):
        return {"basis": "no table row; picked by name for Hoshino's heal"}
    return {"basis": "named for the student; no table row"}


def pack_paths(inventory):
    """voice line (Hina_Battle_Damage_1) -> pack path as listed by the extractor."""
    out = {}
    for line in open(inventory, encoding="utf-8"):
        m = re.match(r"^(\S+) \[.*?\] [\d.]+s \((.*)\)\s*$", line)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="the export/ba_audio folder")
    ap.add_argument("--dst", default=None, help="default: assets/audio/ba next to tools/")
    args = ap.parse_args()
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    src = os.path.abspath(args.src)
    dst = os.path.abspath(args.dst) if args.dst else os.path.join(root, "assets", "audio", "ba")

    evidence = json.load(open(os.path.join(src, "hina_hoshino_audioanimator_evidence.json"), encoding="utf-8"))
    rows = table_rows(evidence)
    packs = pack_paths(os.path.join(src, "inventory.txt"))
    sources_path = os.path.join(dst, "sfx_sources.json")
    sources = json.load(open(sources_path, encoding="utf-8")) if os.path.isfile(sources_path) else {}

    sfx_names = sorted(f[:-4] for f in os.listdir(os.path.join(src, "sfx")) if f.endswith(".wav"))
    sfx_names = [n for n in sfx_names if n not in SFX_SKIP]
    if len(sfx_names) != SFX_COUNT:
        sys.exit("expected %d sfx, found %d" % (SFX_COUNT, len(sfx_names)))
    voices = []
    for who, student in STUDENTS.items():
        names = ["%s_%s" % (student, line) for line in VOICE_LINES]
        for n in names:
            if not os.path.isfile(os.path.join(src, "voice", student, n + ".ogg")):
                sys.exit("missing voice file %s" % n)
        voices += [(who, student, n) for n in names]

    jobs = [("sfx/%s.wav" % n, os.path.join(src, "sfx", n + ".wav"), n, None, None) for n in sfx_names]
    jobs += [("voice/%s/%s.ogg" % (who, n), os.path.join(src, "voice", student, n + ".ogg"), n, who, student) for who, student, n in voices]

    files = []
    clips = {}
    for rel, source, name, who, student in jobs:
        out = os.path.join(dst, rel)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        shutil.copyfile(source, out)
        lufs, peak, seconds = measure(out)
        if who is None:
            gain = sfx_gain(peak)
            confirmed = rows.get(name) or [basis_for(name)]
            method = "AudioAnimatorExcel row" if rows.get(name) else "picked by file name"
            origin = {k: sources[name][k] for k in ("bundle", "cab", "path_id")} if name in sources else None
        else:
            gain = voice_gain(lufs, peak)
            line = name[len(student) + 1:]
            confirmed = [{"pack": os.path.basename(packs[name]), "line": line, "wiki": WIKI % student}]
            method = "pack file name, role matched by name (not by listening)"
            origin = packs[name]
        digest = sha256(out)
        files.append({
            "runtime_path": "assets/audio/ba/" + rel, "source_name": name, "source": origin, "sha256": digest,
            "bytes": os.path.getsize(out), "seconds": seconds, "lufs": lufs, "true_peak_db": peak, "gain_db": gain,
            "confirmed_by": confirmed, "method": method,
        })
        clips[rel] = {"sha256": digest, "seconds": seconds, "gain_db": gain}
        print("%-62s %6.2fs  %7s LUFS  tp %5.1f  gain %5.1f" % (rel, seconds, "n/a" if lufs is None else "%.1f" % lufs, peak, gain))

    sets = {}
    for who, student in STUDENTS.items():
        sfx = {}
        for event, spec in SFX_EVENTS[who].items():
            entry = dict(spec)
            entry["clips"] = ["sfx/%s.wav" % c for c in spec["clips"]]
            sfx[event] = entry
        voice = {}
        for event, spec in VOICE_EVENTS.items():
            entry = {k: v for k, v in spec.items() if k != "lines"}
            entry["clips"] = ["voice/%s/%s_%s.ogg" % (who, student, line) for line in spec["lines"]]
            entry["vol"] = 1.0
            voice[event] = entry
        sets[who] = {"sfx": sfx, "voice": voice}
    for who in sets:
        for kind in ("sfx", "voice"):
            for event, entry in sets[who][kind].items():
                for c in entry["clips"]:
                    if c not in clips:
                        sys.exit("%s.%s.%s names a clip that was not imported: %s" % (who, kind, event, c))

    if sources:
        sfx_note = ("SFX source is the bundle (path under the client's StreamingAssets), CAB and path_id of the clip, found with "
                    "tools/ba_sfx_sources.py; path_id is a string because it is a signed 64-bit id. %d of %d SFX clips were found and %d "
                    "of those re-extract byte for byte (same sha256) with UnityPy and fmod_toolkit." % (
                        len(sources), len(sfx_names), sum(s["sha256_match"] for s in sources.values())))
    else:
        sfx_note = "SFX source is null: the bundle name, CAB and path id were not recorded when the clips were extracted. Recovering them needs one UnityPy run against the client."
    provenance = {
        "source": SOURCE,
        "tools": {
            "voices": "BA-AX v3.0.0, baax extract media",
            "sfx": "UnityPy 1.25.4 with fmod_toolkit",
            "tables": "arisu-archive/bluearchive-data and the local ExcelDB (AudioAnimatorExcel, CostumeExcel)",
            "loudness": "ffmpeg -af ebur128=peak=true",
        },
        "scope": SCOPE,
        "extraction_scripts": "export/ba_audio and the earlier extraction scripts are not tracked",
        "notes": [
            sfx_note,
            "Voices are Ogg as extracted from the JP packs; SFX are WAV as extracted. Nothing was re-encoded. The sfx .import files set compress/mode=0 (PCM) because Godot 4.7 defaults to lossy QOA.",
            "true_peak_db and lufs are measured on the committed file. lufs is null where the clip is too short for ebur128 to gate (under 400 ms).",
            "confirmed_by lists every AudioAnimatorExcel row that names the clip. The Hoshino SG clips appear in a Normal and a Stand row.",
            "Voice lines were matched to roles by their names in the pack, not by listening. method says how each entry was matched; confirmed_by is the evidence it points at.",
            "Credits: Hina is voiced by Hirohashi Ryo and Hoshino by Hanamori Yumiri (look at relevant docs). Show this line wherever the game credits its sources.",
        ],
        "files": files,
    }
    manifest = {"version": 1, "notes": NOTES, "clips": clips, "sets": sets}
    for name, data in (("PROVENANCE.json", provenance), ("manifest.json", manifest)):
        with open(os.path.join(dst, name), "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")
    print("%d sfx, %d voices, wrote manifest.json and PROVENANCE.json to %s" % (len(sfx_names), len(voices), dst))


if __name__ == "__main__":
    main()
