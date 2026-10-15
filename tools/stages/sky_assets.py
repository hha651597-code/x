import glob
import json
import re
import sys
from pathlib import Path

import numpy as np
import UnityPy
from UnityPy.helpers.MeshHelper import MeshHandler

sys.path.insert(0, str(Path(__file__).resolve().parent))
import scene_to_glb as S

UnityPy.config.FALLBACK_UNITY_VERSION = "2021.3.56f2"
CLOUD_RE = re.compile(r"^(Binah_Cloud_\d+|Muk_Cloud_\d+)$")
BANK_TOL = 0.01


def read_meshes(deps_dir, pattern):
    want = re.compile(pattern)
    seen = {}
    for p in sorted(glob.glob(str(Path(deps_dir) / "*.bundle"))):
        name = Path(p).name
        if "_mxcommon-.fbx" not in name and "_mxcommon-fbx" not in name:
            continue
        for o in UnityPy.load(p).objects:
            if o.type.name != "Mesh" or not want.match(o.peek_name()) or o.peek_name() in seen:
                continue
            m = o.read()
            h = MeshHandler(m)
            h.process()
            pos = np.array(h.m_Vertices, dtype=np.float32)[:, :3].copy()
            idx = np.array(h.m_IndexBuffer, dtype=np.uint32)
            nrm = np.array(h.m_Normals, dtype=np.float32)[:, :3].copy() if h.m_Normals else None
            uv = np.array(h.m_UV0, dtype=np.float32)[:, :2].copy() if h.m_UV0 else None
            col = None
            if h.m_Colors:
                c = np.array(h.m_Colors, dtype=np.float32)
                col = (c / 255.0 if c.max() > 1.0001 else c)[:, :4].copy()
            pos[:, 0] *= -1
            if nrm is not None:
                nrm[:, 0] *= -1
            if uv is not None:
                uv[:, 1] = 1.0 - uv[:, 1]
            seen[m.m_Name] = {"pos": pos, "nrm": nrm, "uv": uv, "col": col, "tri": idx.reshape(-1, 3)[:, ::-1].reshape(-1)}
    return seen


def write_meshes(meshes, names, path):
    g = S.Glb()
    gl_meshes, nodes = [], []
    for n in sorted(names):
        m = meshes[n]
        attrs = {"POSITION": g.add(m["pos"], 5126, "VEC3", 34962, True)}
        if m["nrm"] is not None:
            attrs["NORMAL"] = g.add(m["nrm"], 5126, "VEC3", 34962)
        if m["uv"] is not None:
            attrs["TEXCOORD_0"] = g.add(m["uv"], 5126, "VEC2", 34962)
        if m["col"] is not None:
            attrs["COLOR_0"] = g.add(m["col"], 5126, "VEC4", 34962)
        ii = g.add(m["tri"].astype(np.uint32).reshape(-1, 1), 5125, "SCALAR", 34963)
        gl_meshes.append({"name": n, "primitives": [{"attributes": attrs, "indices": ii, "mode": 4}]})
        nodes.append({"name": n, "mesh": len(gl_meshes) - 1})
    doc = {"asset": {"version": "2.0", "generator": "sky_assets.py"}, "scene": 0, "scenes": [{"nodes": list(range(len(nodes)))}], "nodes": nodes, "meshes": gl_meshes, "accessors": g.accessors, "bufferViews": g.views}
    S.write_glb(path, doc, g.buf)
    Path(str(path) + ".import").write_text(S.GLB_IMPORT)


def needed_names(sky_cfg, bank):
    names = {sky_cfg["celestial"]["sun_mesh"], sky_cfg["celestial"]["moon_mesh"]}
    for l in sky_cfg["layers"]:
        for it in l.get("items", []):
            names.add(it[0])
    for b in bank:
        names.add(b["mesh"])
    return names


def bank_from_scene(info, glb_path, meshes):
    doc, buf = S.read_glb(glb_path)

    def acc(i):
        a = doc["accessors"][i]
        v = doc["bufferViews"][a["bufferView"]]
        return np.frombuffer(buf, dtype="<f4", count=a["count"] * 3, offset=v["byteOffset"]).reshape(-1, 3).astype(np.float64)

    nodes = {n["name"]: n for n in doc["nodes"] if "mesh" in n}
    src = {n: m["pos"].astype(np.float64) for n, m in meshes.items() if CLOUD_RE.match(n)}
    by_count = {}
    for n in sorted(src):
        by_count.setdefault(len(src[n]), []).append(n)
    out = []
    for ni in info["nodes"]:
        if not re.search(r"Cloud( \(\d+\))?$", ni["go_path"]) or ni["node"] not in nodes:
            continue
        P = acc(doc["meshes"][nodes[ni["node"]]["mesh"]]["primitives"][0]["attributes"]["POSITION"])
        lo, hi = P.min(0), P.max(0)
        t = ni["trs_unity"]
        q = [t["quat"][0], -t["quat"][1], -t["quat"][2], t["quat"][3]]
        R = S.quat_to_mat(q)
        pos = np.array([-t["pos"][0], t["pos"][1], t["pos"][2]])
        sc = np.array(t["scale"])
        best = None
        for mn in by_count.get(len(P), []):
            w = (src[mn] * sc) @ R.T + pos
            err = max(np.abs(w.min(0) - lo).max(), np.abs(w.max(0) - hi).max())
            if best is None or err < best[0]:
                best = (err, mn)
        assert best is not None, f"no source mesh for {ni['node']} ({len(P)} vertices)"
        out.append({"node": ni["node"], "mesh": best[1], "pos": [round(float(v), 4) for v in pos], "quat": [round(float(v), 5) for v in q], "scale": [round(float(v), 4) for v in sc], "aabb_err": round(float(best[0]), 4)})
    return out, doc, buf, nodes, acc


def verify_bank(bank, meshes, nodes, doc, acc):
    worst = 0.0
    for b in bank:
        w = (meshes[b["mesh"]]["pos"].astype(np.float64) * np.array(b["scale"])) @ S.quat_to_mat(b["quat"]).T + np.array(b["pos"])
        ref = acc(doc["meshes"][nodes[b["node"]]["mesh"]]["primitives"][0]["attributes"]["POSITION"])
        d = np.sqrt(((w[:, None, :] - ref[None, :, :]) ** 2).sum(2))
        worst = max(worst, d.min(1).max(), d.min(0).max())
    return worst


def build(deps_dir, sky_cfg, variants, out_dir):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    meshes = read_meshes(deps_dir, r"^(Binah_Cloud_\d+|Muk_Cloud_\d+|Sky_Cloud_Prop_\d+|Sky_Sun_Prop_01|Sky_Moon_Prop_01)$")
    banks, worst = {}, 0.0
    for vid, conv in variants.items():
        info = json.load(next(p for p in sorted(Path(conv).glob("sb_*.json")) if not p.name.endswith(".materials.json")).open())
        glb = next(Path(conv).glob("sb_*.glb"))
        bank, doc, buf, nodes, acc = bank_from_scene(info, glb, meshes)
        w = verify_bank(bank, meshes, nodes, doc, acc)
        assert w < BANK_TOL, f"cloud bank does not match the scene geometry for {vid}: {w}"
        worst = max(worst, w)
        banks[vid] = bank
        (out / f"bank_{vid}.json").write_text(json.dumps(bank, indent=1) + "\n")
    names = set()
    for b in banks.values():
        names |= needed_names(sky_cfg, b)
    write_meshes(meshes, names, out / "sky_meshes.glb")
    return {"meshes": sorted(names), "bank_clouds": {v: len(b) for v, b in banks.items()}, "bank_worst_vertex_error": worst}


if __name__ == "__main__":
    if len(sys.argv) < 5:
        sys.exit("usage: sky_assets.py <deps dir> <sky.json> <out dir> <variant id>=<converter out dir> ...")
    cfg = json.load(open(sys.argv[2]))
    variants = dict(a.split("=", 1) for a in sys.argv[4:])
    print(json.dumps(build(sys.argv[1], cfg, variants, sys.argv[3])))
