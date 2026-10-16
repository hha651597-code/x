#!/usr/bin/env python3
"""The game's own sounds, from Blue Archive: every UI and fight sound the Sfx autoload used to synthesise now plays a clip cut from the
client's audio bundles. Writes assets/audio/ba/ui/<sound>_<n>.wav (mono 16 bit, trimmed, faded, peak at -1 dBFS), assets/audio/ba/ui_map.json
(sound name -> clips and playback gain) and assets/audio/ba/ui/PROVENANCE.json.

Copy the audio bundles out of the install first and never run anything from it (SRC is a scratch folder):
  cp .../PUB/Resource/Preload/Windows/*audio-sfx_ui* *audio-sfx_common* *audio-sfx_scenarioeffect* *audio-sfx_backgroundeffect* SRC/
  cp .../PUB/Resource/GameData/Windows/*audio-sfx_ui* *audio-sfx_common* SRC/
usage: ~/Tools/venv-stages/bin/python -I tools/sfx_ui_assets.py SRC        (UnityPy with fmod_toolkit, numpy)

The choice of clip per sound was made from the clip names and their measured length, attack and brightness, not by ear: swap a clip by
editing SOUNDS and re-running. Format of an entry: sound -> (gain in dB after the -1 dBFS normalisation, [(clip, {start, dur, fade})]).
A sound with several clips picks one at random each time and never the same twice in a row."""
import glob
import hashlib
import io
import json
import sys
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/audio/ba"
FADE_IN = 0.003

SOUNDS = {
    # the menus
    "tick": (-13.0, [("UI_EventCollection_Pin_MN_01", {"fade": 0.02}), ("UI_EventCollection_Pin_MN_02", {"fade": 0.02}), ("UI_EventCollection_Pin_MN_04", {"fade": 0.02})]),
    "confirm": (-7.0, [("UI_Button_Wood", {"fade": 0.05})]),
    "back": (-9.0, [("SFX_MiniGame_CCG_Hand_Close", {"fade": 0.08})]),
    "whoosh": (-12.0, [("UI_Fade", {"fade": 0.25})]),
    "pop": (-9.0, [("SFX_Event_Pop_01", {"dur": 0.35, "fade": 0.2}), ("SFX_Event_Pop_02", {"dur": 0.35, "fade": 0.2})]),
    "claim": (-9.0, [("UI_Chime_01", {"dur": 1.1, "fade": 0.4}), ("UI_Chime_02", {"dur": 1.1, "fade": 0.4}), ("UI_Chime_03", {"dur": 1.1, "fade": 0.4}), ("UI_Chime_04", {"dur": 1.1, "fade": 0.4})]),
    "crest": (-10.0, [("UI_Chime_Sparkle", {"dur": 1.5, "fade": 0.6})]),
    "error": (-7.0, [("SFX_MiniGame_TBG_Enemy_HeartDamaged", {"fade": 0.08})]),
    "lock": (-9.0, [("UI_Notice", {"fade": 0.06})]),
    "slam": (-4.0, [("SE_Boom_02", {"dur": 0.8, "fade": 0.35})]),
    "fight": (-4.0, [("SFX_Start_Public_Shing_03", {"fade": 0.15})]),
    # the fight
    "hit_l": (-6.0, [("SFX_Common_Hit_Mech_Short_01", {"dur": 0.22, "fade": 0.09}), ("SFX_Common_Hit_Mech_Short_02", {"dur": 0.22, "fade": 0.09}),
                     ("SFX_Common_Hit_Mech_Short_03", {"dur": 0.22, "fade": 0.09}), ("SFX_Common_Hit_Mech_Short_04", {"dur": 0.22, "fade": 0.09})]),
    "hit_h": (-3.0, [("SFX_Common_Hit_Mech_Long_01", {"dur": 0.45, "fade": 0.18}), ("SFX_Common_Hit_Mech_Long_02", {"dur": 0.45, "fade": 0.18}),
                     ("SFX_Common_Hit_Mech_Long_03", {"dur": 0.45, "fade": 0.18}), ("SFX_Common_Hit_Mech_Long_04", {"dur": 0.45, "fade": 0.18})]),
    "block": (-6.0, [("SFX_Common_Retro_Hit", {"fade": 0.1})]),
    "just_guard": (-5.0, [("SFX_Start_Public_Shing_04", {"fade": 0.15})]),
    "guard_crush": (-4.0, [("UI_Conquest_Boss_Shield_Broken", {"dur": 0.95, "fade": 0.35})]),
    "shot": (-8.0, [("SFX_Common_HG_01", {"dur": 0.35, "fade": 0.15}), ("SFX_Common_HG_02", {"dur": 0.35, "fade": 0.15}), ("SFX_Common_HG_03", {"dur": 0.35, "fade": 0.15})]),
    "shot_big": (-5.0, [("SFX_Common_SR_01", {"dur": 0.68, "fade": 0.3}), ("SFX_Common_SR_02", {"dur": 0.68, "fade": 0.3})]),
    "beam": (-8.0, [("SFX_JSD_Laser_01", {"fade": 0.25}), ("SFX_JSD_Laser_03", {"fade": 0.25})]),
    "launch": (-6.0, [("SFX_Common_RL_01", {"dur": 0.9, "fade": 0.35}), ("SFX_Common_RL_02", {"dur": 0.9, "fade": 0.35})]),
    "boom": (-3.0, [("SFX_Explosion_Grenade_L_A_01", {"fade": 0.4}), ("SFX_Explosion_Grenade_L_A_02", {"fade": 0.4}), ("SFX_Explosion_Grenade_L_A_03", {"fade": 0.4})]),
    "flame": (-9.0, [("SFX_Common_Flame_T_CH0088_01", {"dur": 1.1, "fade": 0.4})]),
    "charge": (-10.0, [("SFX_Common_Buff_Provoke", {"fade": 0.25})]),
    "super": (-4.0, [("SFX_Start_Public_Shing_01", {"fade": 0.15})]),
    "ko": (-3.0, [("SFX_Explosion_Blue_01", {"dur": 1.0, "fade": 0.45})]),
    "jump": (-10.0, [("SFX_JSD_Jump", {"fade": 0.06})]),
    "land": (-12.0, [("SFX_Down_03", {}), ("SFX_Down_05", {}), ("SFX_Down_08", {}), ("SFX_Down_04", {})]),
    "dash": (-10.0, [("SFX_JSD_Slide_06", {"dur": 0.36, "fade": 0.15}), ("SFX_JSD_Slide_05", {"dur": 0.36, "fade": 0.15})]),
    "throw": (-6.0, [("SFX_Swing_03", {"fade": 0.15})]),
    "tech": (-9.0, [("SFX_JSD_Roll_Breakfall", {"dur": 0.5, "fade": 0.2})]),
    "grab": (-10.0, [("SFX_Common_Cloth_01", {"fade": 0.1}), ("SFX_Common_Cloth_02", {"dur": 0.4, "fade": 0.12})]),
    "swing": (-8.0, [("SFX_Swing_01", {"fade": 0.15}), ("SFX_Swing_02", {"fade": 0.15})]),
    # the ultimate's cut-in and the EX READY cue
    "ex_ready": (-8.0, [("UI_Chime_06", {"dur": 0.9, "fade": 0.35})]),
    "ult_rise": (-6.0, [("UI_Gacha_Normal_01", {"start": 1.2, "dur": 0.8, "fade": 0.03})]),
    "ult_stamp": (-3.0, [("SFX_Aris_Hit", {"dur": 0.45, "fade": 0.2})]),
    "ult_release": (-2.0, [("SFX_Explosion_Blue_L_01", {"dur": 1.0, "fade": 0.45})]),
}


def sha(b):
    return hashlib.sha256(b).hexdigest()


def decode(wav_bytes):
    w = wave.open(io.BytesIO(wav_bytes))
    n, sr, ch, sw = w.getnframes(), w.getframerate(), w.getnchannels(), w.getsampwidth()
    raw = w.readframes(n)
    if sw == 2:
        a = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768
    elif sw == 3:
        b = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3)
        a = (((b[:, 0].astype(np.int32) | (b[:, 1].astype(np.int32) << 8) | (b[:, 2].astype(np.int32) << 16)) << 8).astype(np.int32)).astype(np.float64) / 2**31
    elif sw == 4:
        a = np.frombuffer(raw, dtype="<i4").astype(np.float64) / 2**31
    else:
        a = np.frombuffer(raw, dtype=np.uint8).astype(np.float64) / 128 - 1
    return (a.reshape(-1, ch).mean(axis=1) if ch > 1 else a), sr


def cut(a, sr, o):
    s = int(o.get("start", 0.0) * sr)
    e = len(a) if "dur" not in o else min(len(a), s + int(o["dur"] * sr))
    seg = a[s:e].copy()
    fi = min(int(FADE_IN * sr), len(seg) // 4)
    fo = min(int(o.get("fade", 0.06) * sr), len(seg) // 2)
    if fi:
        seg[:fi] *= np.linspace(0, 1, fi)
    if fo:
        seg[-fo:] *= np.linspace(1, 0, fo) ** 1.5
    pk = float(np.max(np.abs(seg))) if len(seg) else 0.0
    return seg * (10 ** (-1 / 20) / pk) if pk > 0 else seg


def encode(a, sr):
    buf = io.BytesIO()
    w = wave.open(buf, "wb")
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(sr)
    w.writeframes((np.clip(a, -1, 1) * 32767).astype("<i2").tobytes())
    w.close()
    return buf.getvalue()


def main(src):
    import UnityPy
    need = {c for _, clips in SOUNDS.values() for c, _ in clips}
    found = {}
    for f in sorted(glob.glob(str(Path(src) / "*.bundle"))):
        for o in UnityPy.load(f).objects:
            if o.type.name == "AudioClip":
                d = o.read()
                if d.m_Name in need and d.m_Name not in found:
                    found[d.m_Name] = (next(iter(d.samples.values())), Path(f).name)
    missing = need - set(found)
    if missing:
        sys.exit("clips not found in %s: %s" % (src, sorted(missing)))
    (OUT / "ui").mkdir(parents=True, exist_ok=True)
    prov, smap = {}, {}
    for name, (db, clips) in SOUNDS.items():
        rels = []
        for i, (clip, o) in enumerate(clips, 1):
            raw, bundle = found[clip]
            a, sr = decode(raw)
            out = OUT / "ui" / ("%s_%d.wav" % (name, i))
            data = encode(cut(a, sr, o), sr)
            out.write_bytes(data)
            rels.append("ui/" + out.name)
            prov[out.name] = {"sound": name, "clip": clip, "bundle": bundle, "edit": o, "source_sha256": sha(raw), "sha256": sha(data),
                              "derived_from": "tools/sfx_ui_assets.py: mono 16 bit, trimmed and faded, peak -1 dBFS"}
        smap[name] = {"clips": rels, "db": db}
    (OUT / "ui_map.json").write_text(json.dumps({"version": 1, "notes": "tools/sfx_ui_assets.py writes this. db is the playback gain after the -1 dBFS normalisation.", "sounds": smap}, indent=1) + "\n")
    (OUT / "ui/PROVENANCE.json").write_text(json.dumps(prov, indent=1, sort_keys=True) + "\n")
    tot = sum((OUT / "ui" / n).stat().st_size for n in prov)
    print("wrote %d clips for %d sounds, %.1f MB" % (len(prov), len(smap), tot / 1048576))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else sys.exit(__doc__))
