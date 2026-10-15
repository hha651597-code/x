#!/usr/bin/env python3
"""Finds which asset bundle in the Blue Archive client holds each SFX clip in assets/audio/ba/sfx, re-extracts
the clip the way the committed WAV was made (UnityPy AudioClip.samples, decoded by fmod_toolkit) and compares it
with the committed file. Writes assets/audio/ba/sfx_sources.json: clip name -> bundle, cab, path_id,
sha256_match, pcm_identical. tools/ba_audio_import.py copies bundle, cab and path_id into PROVENANCE.json.

usage: ~/Tools/venv-stages/bin/python -I tools/ba_sfx_sources.py CLIENT SCRATCH [--budget SECONDS] [--dst assets/audio/ba]

CLIENT is the client's StreamingAssets folder. It is only read. SCRATCH must not exist or be empty; the re-extracted
WAVs land there. Bundle paths are stored relative to CLIENT. path_id is a string because it is a signed 64-bit int
and JSON readers (Godot's included) turn numbers into doubles. A clip found in several bundles is recorded once,
preferring a byte-identical copy; the other bundles are listed under also_in. Bundles whose names mention audio,
sfx or sound are read first; the scan stops at --budget seconds and prints how many bundles it skipped.
"""
import argparse
import hashlib
import io
import json
import os
import re
import sys
import time
import wave

import UnityPy


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def pcm(data):
    """(format params, sample bytes), or None when the wave module cannot read the file."""
    try:
        with wave.open(io.BytesIO(data)) as w:
            return w.getparams(), w.readframes(w.getnframes())
    except (wave.Error, EOFError):
        return None


def extract(obj, name):
    samples = obj.read().samples
    if name + ".wav" in samples:
        return samples[name + ".wav"]
    if len(samples) == 1:
        return next(iter(samples.values()))
    sys.exit("%s decoded to %s, expected one wav" % (name, sorted(samples)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("client", help="the client's StreamingAssets folder (read only)")
    ap.add_argument("scratch", help="new or empty folder for the re-extracted WAVs")
    ap.add_argument("--budget", type=float, default=1800, help="stop scanning after this many seconds")
    ap.add_argument("--dst", default=None, help="default: assets/audio/ba next to tools/")
    args = ap.parse_args()
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    dst = os.path.abspath(args.dst) if args.dst else os.path.join(root, "assets", "audio", "ba")
    client = os.path.realpath(args.client)
    scratch = os.path.realpath(args.scratch)
    if scratch == client or scratch.startswith(client + os.sep) or client.startswith(scratch + os.sep):
        sys.exit("scratch and client must be separate folders")
    if os.path.exists(scratch) and os.listdir(scratch):
        sys.exit("scratch is not empty: " + scratch)
    os.makedirs(scratch, exist_ok=True)

    committed = {}
    sfx_dir = os.path.join(dst, "sfx")
    for f in sorted(os.listdir(sfx_dir)):
        if f.endswith(".wav"):
            committed[f[:-4]] = open(os.path.join(sfx_dir, f), "rb").read()
    print("%d committed clips in %s" % (len(committed), sfx_dir))

    bundles = []
    for dirpath, _, files in os.walk(client):
        bundles += [os.path.join(dirpath, f) for f in files if f.endswith(".bundle")]
    # clips are usually in audio bundles; reading those first keeps a cut-off scan useful
    bundles.sort(key=lambda p: (not re.search("audio|sfx|sound", os.path.basename(p).lower()), p))
    print("%d bundles under %s" % (len(bundles), client))

    found = {}
    failed = []
    scanned = 0
    start = time.time()
    for path in bundles:
        if time.time() - start > args.budget:
            break
        scanned += 1
        try:
            env = UnityPy.load(path)
            for obj in env.objects:
                if obj.type.name == "AudioClip" and obj.peek_name() in committed:
                    name = obj.peek_name()
                    data = extract(obj, name)
                    found.setdefault(name, []).append({
                        "bundle": os.path.relpath(path, client), "cab": obj.assets_file.name,
                        "path_id": str(obj.path_id), "data": data,
                    })
        except Exception as e:
            failed.append((path, "%s: %s" % (type(e).__name__, e)))
    print("scanned %d of %d bundles in %.0f s; skipped %d (budget); %d failed to load" % (
        scanned, len(bundles), time.time() - start, len(bundles) - scanned, len(failed)))
    for path, why in failed[:10]:
        print("  load failed: %s (%s)" % (os.path.relpath(path, client), why))

    out = {}
    for name, hits in sorted(found.items()):
        want = sha256(committed[name])
        hits.sort(key=lambda h: (sha256(h["data"]) != want, h["bundle"], h["path_id"]))
        best = hits[0]
        got = sha256(best["data"])
        want_pcm = pcm(committed[name])
        entry = {"bundle": best["bundle"], "cab": best["cab"], "path_id": best["path_id"], "sha256_match": got == want}
        entry["pcm_identical"] = got == want or (want_pcm is not None and want_pcm == pcm(best["data"]))
        if len(hits) > 1:
            entry["also_in"] = [{"bundle": h["bundle"], "cab": h["cab"], "path_id": h["path_id"],
                                 "sha256_match": sha256(h["data"]) == want} for h in hits[1:]]
        with open(os.path.join(scratch, name + ".wav"), "wb") as f:
            f.write(best["data"])
        out[name] = entry
    missing = sorted(set(committed) - set(out))
    with open(os.path.join(dst, "sfx_sources.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print("found %d of %d; byte-identical %d; same PCM but different bytes %d; different PCM %d" % (
        len(out), len(committed), sum(e["sha256_match"] for e in out.values()),
        sum(e["pcm_identical"] and not e["sha256_match"] for e in out.values()),
        sum(not e["pcm_identical"] for e in out.values())))
    print("not found: %s" % (", ".join(missing) or "none"))


if __name__ == "__main__":
    main()
