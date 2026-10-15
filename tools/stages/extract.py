import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import farfield_gen
import source_copy

PY = [sys.executable, "-I"]
SHADERS = "prologdepengroup-assets-_mx-shaders-_mxprolog-*"


def run(*args, ok=(0,)):
    print("+", " ".join(str(a) for a in args), flush=True)
    r = subprocess.run([str(a) for a in args], capture_output=True, text=True)
    sys.stdout.write(r.stdout[-1500:])
    if r.returncode not in ok:
        sys.stdout.write(r.stderr[-3000:])
        raise SystemExit(f"step failed ({r.returncode}): {args[1] if len(args) > 1 else args[0]}")
    return r.stdout


def bundle_of(work_src, scene):
    return next(Path(work_src).glob(f"{scene}_mxload*.bundle"))


def main(map_id, install, work, out):
    maps_path = HERE / "maps.json"
    maps = json.load(open(maps_path))
    entry = maps["maps"][map_id]
    data = HERE / entry["data"]
    work, out = Path(work), Path(out)
    work.mkdir(parents=True, exist_ok=True)
    world = farfield_gen.load_world(maps_path, map_id)
    foliage = json.load(open(data / "foliage.json"))
    index = source_copy.Index(install, work / "cab_index.json")

    own = dict(entry["variants"])
    src_map = work / "src" / map_id
    names, missing = source_copy.unit(index, sorted(own.values()), entry["bundles"], src_map)
    assert not missing, missing
    donor_scenes = sorted({n for spec in world["sources"].values() if spec != "self" for n in spec.values()})
    for sc in donor_scenes:
        _, missing = source_copy.unit(index, [sc], [], work / "src" / f"donor_{sc}")
        assert not missing, missing
    for g in sorted({p["group"] for d in foliage["donors"] for p in d["parts"]}):
        source_copy.unit(index, [], [f"assets-_mx-{g}-_mxdependency-*", SHADERS], work / "src" / g)

    conv = work / "conv"
    letters = {}
    for time, scene in sorted(own.items()):
        letters[scene.rsplit("_", 1)[1]] = scene
        lane = [] if entry["lane"] is None else ["--lane", "%s,%s" % (entry["lane"]["lane_x"], entry["lane"]["z_centre"])]
        run(*PY, HERE / "scene_to_glb.py", bundle_of(src_map, scene), conv / scene, src_map, *lane)
        run(*PY, HERE / "verify_topdown.py", bundle_of(src_map, scene), conv / scene, conv / scene / "verify", src_map)
    for sc in donor_scenes:
        res = run(*PY, HERE / "scene_to_glb.py", bundle_of(work / "src" / f"donor_{sc}", sc), conv / sc, work / "src" / f"donor_{sc}", "--no-lane", ok=(0, 1))
        info = json.loads(res.strip().splitlines()[-1])
        assert info["selfcheck"]["triangle_counts_match"] and all(u["status"] == "no_meshfilter" for u in info["unresolved"]), (sc, info["unresolved"][:3])

    layers = work / "layers" / map_id
    own_arg = ",".join(f"{l}={s}" for l, s in sorted(letters.items()))
    run(*PY, HERE / "sky_assets.py", src_map, data / "sky.json", layers / "sky", *[f"{s.split(map_id + '_', 1)[1]}={conv / s}" for s in sorted(own.values())])
    for letter, scene in sorted(letters.items()):
        vid = scene.split(map_id + "_", 1)[1]
        run(*PY, HERE / "fx_export.py", bundle_of(src_map, scene), src_map, data / "fx.json", layers / f"fx_{letter}")
        run(*PY, HERE / "farfield_gen.py", maps_path, map_id, conv, letter, vid, layers / "world")
    day = letters["d"]
    run(*PY, HERE / "foliage_gen.py", data / "foliage.json", work / "src", conv, own_arg, conv / day / f"{day}.json", layers / "foliage")
    run(*PY, HERE / "publish_stage.py", map_id, maps_path, work, out)
    stage = out / map_id
    node = os.environ.get("NODE", "node")
    for glb in sorted(stage.rglob("*.glb")):
        res = run(node, HERE / "validate_gltf.js", glb)
        if " errors 0 " not in res:
            raise SystemExit(f"gltf validator reports errors in {glb}")
    print("extract ok", map_id)


if __name__ == "__main__":
    a = sys.argv[1:]
    if len(a) != 7 or a[1] != "--install" or a[3] != "--work" or a[5] != "--out":
        sys.exit("usage: extract.py <map id> --install <BlueArchive_Data dir> --work <dir> --out <assets/ba/stages dir>")
    main(a[0], a[2], a[4], a[6])
