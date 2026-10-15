import json
import math
import re
import struct
import sys
from pathlib import Path

import imagecodecs
import numpy as np
import UnityPy
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import scene_to_glb as S
import stage_camera

UnityPy.config.FALLBACK_UNITY_VERSION = "2021.3.56f2"
PAD, GAP, AW = 6, 4, 1024
SKIP_SHADERS = ("MX/VertexColor", "FX/General Unlit Texture")


class Kit(S.Scene):
    def __init__(self, bundles):
        self.env = UnityPy.load(*[str(p) for p in bundles])
        self.files = {}
        for bf in self.env.files.values():
            for name, f in getattr(bf, "files", {}).items():
                if hasattr(f, "objects"):
                    self.files[name.lower()] = f
        self.sf = next(iter(self.files.values()))
        self._tt, self._mesh = {}, {}

    def ref(self, sf, p):
        if "cab" in p:
            f = self.files.get(p["cab"].lower())
            o = f.objects.get(p["pid"]) if f else None
            return (o, "ok") if o else (None, "missing:" + p["cab"])
        return super().ref(sf, p)

    def world_trs(self, gpid):
        return np.eye(4), (0.0, 0.0, 0.0, 1.0), np.zeros(3)

    def find(self, type_name, name):
        hits = [(o.assets_file.name, o.path_id) for o in self.env.objects if o.type.name == type_name and o.peek_name() == name]
        assert hits, f"no {type_name} named {name}"
        return sorted(hits)[0]


def group_bundles(src_root, group):
    root = Path(src_root)
    hits = sorted(root.glob(f"assets-_mx-{group}-_mxdependency-*.bundle")) + sorted(root.glob("prologdepengroup-assets-_mx-shaders-_mxprolog-*.bundle"))
    assert hits, f"no bundles for {group} in {root}"
    return hits


def export_kits(design, src_root, out):
    kits = {}
    groups = sorted({p["group"] for d in design["donors"] for p in d["parts"]})
    for g in groups:
        kit = Kit(group_bundles(Path(src_root) / g, g))
        name = re.sub(r"[^a-z0-9]+", "_", g.replace("scenes-battle-", "")).strip("_")
        o = Path(out) / "kits" / name
        o.mkdir(parents=True, exist_ok=True)
        ex = S.Exporter(kit, f"kit_{name}", o)
        for d in design["donors"]:
            for p in d["parts"]:
                if p["group"] != g or p["mesh"] in ex.prims_info:
                    continue
                mk = kit.find("Mesh", p["mesh"])
                mats = [kit.find("Material", m) for m in p["materials"]]
                r = {"pid": mk[1], "gpid": 0, "go": p["mesh"], "path": p["mesh"], "lm": 65535, "st": [1, 1, 0, 0], "batch": [0, 0],
                     "mats": [{"cab": m[0], "pid": m[1]} for m in mats], "mesh_ref": {"cab": mk[0], "pid": mk[1]}, "cast_shadows": 0, "receive_shadows": 0, "layer": 0}
                n0 = len(ex.gl_nodes)
                ex.add_renderer(r)
                assert len(ex.gl_nodes) > n0, f"{p['mesh']} exported nothing"
                old = ex.gl_nodes[-1]["name"]
                safe = S.safe_name(p["mesh"])
                ex.gl_nodes[-1]["name"] = ex.gl_meshes[-1]["name"] = safe
                ex.nodes_info[-1]["node"] = safe
                ex.prims_info[safe] = ex.prims_info.pop(old)
        assert not ex.unresolved, ex.unresolved
        ex.finish_gltf()
        (o / f"kit_{name}.materials.json").write_text(json.dumps(ex.materials_json(), indent=1) + "\n")
        kits[g] = name
    return kits


def acc(doc, buf, k):
    a = doc["accessors"][k]
    v = doc["bufferViews"][a["bufferView"]]
    dt = {5126: "<f4", 5123: "<u2", 5125: "<u4"}[a["componentType"]]
    nc = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
    return np.frombuffer(buf, dtype=dt, count=a["count"] * nc, offset=v["byteOffset"]).reshape(-1, nc)


def up_fix(P, up):
    if up == "y":
        return P
    return np.stack([P[:, 0], P[:, 2], -P[:, 1]], axis=1)


def pack(design, kits, out):
    out = Path(out)
    loaded = {}
    prims = []
    for d in design["donors"]:
        for part in d["parts"]:
            k = kits[part["group"]]
            if k not in loaded:
                doc, buf = S.read_glb(out / "kits" / k / f"kit_{k}.glb")
                side = json.load(open(out / "kits" / k / f"kit_{k}.materials.json"))["materials"]
                loaded[k] = (doc, buf, side)
            doc, buf, side = loaded[k]
            node = next(n for n in doc["nodes"][1:] if n["name"] == S.safe_name(part["mesh"]))
            for p in doc["meshes"][node["mesh"]]["primitives"]:
                m = doc["materials"][p["material"]]["name"]
                prims.append({"donor": d["id"], "double_sided": bool(d.get("double_sided", False)), "kit": k, "node": part["mesh"], "up": part.get("up", "y"), "mat": m, "sc": side[m],
                              "P": acc(doc, buf, p["attributes"]["POSITION"]).astype(np.float32),
                              "N": acc(doc, buf, p["attributes"]["NORMAL"]).astype(np.float32),
                              "UV": acc(doc, buf, p["attributes"]["TEXCOORD_0"]).astype(np.float64),
                              "I": acc(doc, buf, p["indices"]).reshape(-1).astype(np.uint32)})
    crops = []
    for q in prims:
        mt = q["sc"]["textures"]["_MainTex"]
        im = Image.open(out / "kits" / q["kit"] / mt["file"]).convert("RGBA")
        W, H = im.size
        uv = q["UV"] * np.array(mt["scale"]) + np.array(mt["offset"])
        assert uv.min() > -0.001 and uv.max() < 1.001, (q["node"], uv.min(), uv.max())
        x0 = max(int(np.floor(uv[:, 0].min() * W)) - PAD, 0) // 4 * 4
        y0 = max(int(np.floor(uv[:, 1].min() * H)) - PAD, 0) // 4 * 4
        x1 = min(-(-(int(np.ceil(uv[:, 0].max() * W)) + PAD) // 4) * 4, W)
        y1 = min(-(-(int(np.ceil(uv[:, 1].max() * H)) + PAD) // 4) * 4, H)
        q["crop"] = (x0, y0, x1, y1, W, H)
        q["tex"] = mt["file"]
        q["uv_src"] = uv
        q["img"] = im.crop((x0, y0, x1, y1))
        crops.append(q)
    uniq = []
    for q in sorted(crops, key=lambda q: -(q["crop"][2] - q["crop"][0]) * (q["crop"][3] - q["crop"][1])):
        host = next((u for u in uniq if u["kit"] == q["kit"] and u["tex"] == q["tex"] and u["crop"][0] <= q["crop"][0] and u["crop"][1] <= q["crop"][1] and u["crop"][2] >= q["crop"][2] and u["crop"][3] >= q["crop"][3]), None)
        if host is None:
            uniq.append(q)
            q["host"] = q
        else:
            q["host"] = host
    order = sorted(range(len(uniq)), key=lambda i: -uniq[i]["img"].height)
    x = y = rowh = 0
    for i in order:
        w, h = uniq[i]["img"].size
        if x + w + GAP > AW:
            x, y, rowh = 0, y + rowh + GAP, 0
        uniq[i]["at"] = (x, y)
        x += w + GAP
        rowh = max(rowh, h)
    AH = 1
    while AH < y + rowh:
        AH *= 2
    atlas = Image.new("RGBA", (AW, AH), (0, 0, 0, 0))
    for q in uniq:
        atlas.paste(q["img"], q["at"])
    for q in crops:
        h = q["host"]
        q["at"] = (h["at"][0] + q["crop"][0] - h["crop"][0], h["at"][1] + q["crop"][1] - h["crop"][1])
    atlas_file = "dressing_atlas.png"
    atlas.save(out / atlas_file)
    g = S.Glb()
    gl_meshes, gl_nodes, gl_mats, mats_json, donors_json = [], [], [], {}, {}
    by_design = {d["id"]: d for d in design["donors"]}
    by_donor = {}
    for q in crops:
        by_donor.setdefault(q["donor"], []).append(q)
    for did, qs in by_donor.items():
        gp = []
        lo, hi = np.full(3, 1e9), np.full(3, -1e9)
        for j, q in enumerate(qs):
            x0, y0, x1, y1, W, H = q["crop"]
            ax, ay = q["at"]
            P = up_fix(q["P"], q["up"])
            N = up_fix(q["N"], q["up"])
            uv = q["uv_src"]
            U = np.stack([(uv[:, 0] * W - x0 + ax) / AW, (uv[:, 1] * H - y0 + ay) / AH], axis=1).astype("<f4")
            lo, hi = np.minimum(lo, P.min(0)), np.maximum(hi, P.max(0))
            key = f"{did}_{j}"
            attrs = {"POSITION": P.astype("<f4"), "NORMAL": N.astype("<f4"), "TEXCOORD_0": U}
            acc_ids = {an: g.add(a, 5126, {2: "VEC2", 3: "VEC3"}[a.shape[1]], 34962, minmax=(an == "POSITION")) for an, a in attrs.items()}
            ia = g.add(q["I"].astype("<u2" if len(P) < 65536 else "<u4").reshape(-1, 1), 5123 if len(P) < 65536 else 5125, "SCALAR", 34963)
            gp.append({"attributes": acc_ids, "indices": ia, "mode": 4, "material": len(gl_mats)})
            sc = json.loads(json.dumps(q["sc"]))
            sc["textures"]["_MainTex"].update({"file": atlas_file, "scale": [1.0, 1.0], "offset": [0.0, 0.0], "width": AW, "height": AH, "srgb": True})
            sc["source"] = {"kit": q["kit"], "mesh": q["node"], "material": q["mat"]}
            mats_json[key] = sc
            gl_mats.append({"name": key, "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0, "roughnessFactor": 1.0, "baseColorTexture": {"index": 0}},
                            "extensions": {"KHR_materials_unlit": {}}, "doubleSided": sc["blend"]["cull"] == 0})
            if q["double_sided"]:
                sc["blend"]["cull"] = 0.0
                gl_mats[-1]["doubleSided"] = True
        gl_meshes.append({"name": did, "primitives": gp})
        gl_nodes.append({"name": did, "mesh": len(gl_meshes) - 1})
        donors_json[did] = {"size": [round(float(v), 3) for v in hi - lo], "min": [round(float(v), 3) for v in lo], "max": [round(float(v), 3) for v in hi],
                            "tris": int(sum(len(q["I"]) // 3 for q in qs)), "hanging": bool(by_design[did].get("hanging", False)), "wind": float(by_design[did].get("wind", 1.0)),
                            "parts": [f"{q['kit']}:{q['node']}" for q in qs], "materials": [f"{did}_{j}" for j in range(len(qs))]}
    doc = {"asset": {"version": "2.0", "generator": "foliage_gen.py"}, "extensionsUsed": ["KHR_materials_unlit"], "scene": 0,
           "scenes": [{"name": "dressing", "nodes": [0]}], "nodes": [{"name": "dressing", "children": list(range(1, len(gl_nodes) + 1))}] + gl_nodes,
           "meshes": gl_meshes, "materials": gl_mats, "accessors": g.accessors, "bufferViews": g.views,
           "images": [{"uri": atlas_file}], "textures": [{"sampler": 0, "source": 0}],
           "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 33071, "wrapT": 33071}]}
    S.write_glb(out / "dressing.glb", doc, g.buf)
    (out / "dressing.glb.import").write_text(S.GLB_IMPORT)
    (out / "dressing.materials.json").write_text(json.dumps({"variant": "dressing", "materials": mats_json}, indent=1) + "\n")
    return donors_json


class Map:
    def __init__(self, conv_root, scene):
        base = Path(conv_root) / scene / scene
        doc, buf = S.read_glb(f"{base}.glb")
        mats = json.load(open(f"{base}.materials.json"))["materials"]
        P, U, L = [], [], []
        for n in doc["nodes"][1:]:
            for p in doc["meshes"][n["mesh"]]["primitives"]:
                mn = doc["materials"][p["material"]]["name"]
                if mats[mn]["shader"] in SKIP_SHADERS or "_ENV_ALPHA_MODE" in mats[mn]["keywords"]:
                    continue
                v = acc(doc, buf, p["attributes"]["POSITION"]).astype(np.float64)
                if "translation" in n:
                    R = S.quat_to_mat(tuple(n["rotation"]))
                    v = (v * np.array(n["scale"])) @ R.T + np.array(n["translation"])
                idx = acc(doc, buf, p["indices"]).reshape(-1, 3).astype(np.int64)
                P.append(v[idx])
                if "TEXCOORD_1" in p["attributes"] and n["name"].startswith("lm") and not n["name"].startswith("lmn_"):
                    U.append(acc(doc, buf, p["attributes"]["TEXCOORD_1"]).astype(np.float64)[idx])
                    L.append(np.ones(len(idx), bool))
                else:
                    U.append(np.zeros((len(idx), 3, 2)))
                    L.append(np.zeros(len(idx), bool))
        self.P, self.U, self.L = np.concatenate(P), np.concatenate(U), np.concatenate(L)
        nrm = np.cross(self.P[:, 1] - self.P[:, 0], self.P[:, 2] - self.P[:, 0])
        self.ny = nrm[:, 1] / np.maximum(np.linalg.norm(nrm, axis=1), 1e-12)
        raw = Path(f"{base}_lm0.dds").read_bytes()
        self.h, self.w = struct.unpack_from("<II", raw, 12)
        self.lm = imagecodecs.bcn_decode(raw[148 : 148 + self.w * self.h], 6, shape=(self.h, self.w, 3)).astype(np.float64)

    def hit(self, x, z, ymax):
        P = self.P
        a, b, c = P[:, 0][:, [0, 2]], P[:, 1][:, [0, 2]], P[:, 2][:, [0, 2]]
        pt = np.array([x, z])
        d = (b[:, 1] - c[:, 1]) * (a[:, 0] - c[:, 0]) + (c[:, 0] - b[:, 0]) * (a[:, 1] - c[:, 1])
        ok = np.abs(d) > 1e-12
        w0 = np.where(ok, ((b[:, 1] - c[:, 1]) * (pt[0] - c[:, 0]) + (c[:, 0] - b[:, 0]) * (pt[1] - c[:, 1])) / np.where(ok, d, 1), -1)
        w1 = np.where(ok, ((c[:, 1] - a[:, 1]) * (pt[0] - c[:, 0]) + (a[:, 0] - c[:, 0]) * (pt[1] - c[:, 1])) / np.where(ok, d, 1), -1)
        w2 = 1 - w0 - w1
        inside = ok & (w0 >= 0) & (w1 >= 0) & (w2 >= 0) & (self.ny > 0.5)
        idx = np.nonzero(inside)[0]
        if not len(idx):
            return None
        y = w0[idx] * P[idx, 0, 1] + w1[idx] * P[idx, 1, 1] + w2[idx] * P[idx, 2, 1]
        keep = y <= ymax
        if not keep.any():
            return None
        j = idx[keep][np.argmax(y[keep])]
        return float(y[keep].max()), int(j), (w0[j], w1[j], w2[j])

    def hit_h(self, x, y, z, reach=1.5):
        P = self.P
        a, b, c = P[:, 0][:, [1, 2]], P[:, 1][:, [1, 2]], P[:, 2][:, [1, 2]]
        pt = np.array([y, z])
        d = (b[:, 1] - c[:, 1]) * (a[:, 0] - c[:, 0]) + (c[:, 0] - b[:, 0]) * (a[:, 1] - c[:, 1])
        ok = np.abs(d) > 1e-12
        w0 = np.where(ok, ((b[:, 1] - c[:, 1]) * (pt[0] - c[:, 0]) + (c[:, 0] - b[:, 0]) * (pt[1] - c[:, 1])) / np.where(ok, d, 1), -1)
        w1 = np.where(ok, ((c[:, 1] - a[:, 1]) * (pt[0] - c[:, 0]) + (a[:, 0] - c[:, 0]) * (pt[1] - c[:, 1])) / np.where(ok, d, 1), -1)
        w2 = 1 - w0 - w1
        nx = np.cross(P[:, 1] - P[:, 0], P[:, 2] - P[:, 0])
        nx = nx[:, 0] / np.maximum(np.linalg.norm(nx, axis=1), 1e-12)
        idx = np.nonzero(ok & (w0 >= 0) & (w1 >= 0) & (w2 >= 0) & (nx < -0.3) & self.L)[0]
        if not len(idx):
            return None
        xs = w0[idx] * P[idx, 0, 0] + w1[idx] * P[idx, 1, 0] + w2[idx] * P[idx, 2, 0]
        keep = (xs >= x - 0.05) & (xs <= x + reach)
        if not keep.any():
            return None
        jj = int(np.argmin(np.where(keep, xs, np.inf)))
        j = int(idx[jj])
        return float(xs[jj]), j, (w0[j], w1[j], w2[j])

    def sample(self, j, w):
        uv = np.array(w) @ self.U[j]
        col, row = uv[0] * self.w - 0.5, (1.0 - uv[1]) * self.h - 0.5
        c0, r0 = int(np.floor(col)), int(np.floor(row))
        fx, fy = col - c0, row - r0
        s = 0
        for cc, rr, wgt in ((c0, r0, (1 - fx) * (1 - fy)), (c0 + 1, r0, fx * (1 - fy)), (c0, r0 + 1, (1 - fx) * fy), (c0 + 1, r0 + 1, fx * fy)):
            s = s + self.lm[min(max(rr, 0), self.h - 1), min(max(cc, 0), self.w - 1)] * wgt
        return s

    def wall_light(self, x, y, z, radius=0.25):
        vals = []
        for dy, dz in ((0, 0), (radius, 0), (-radius, 0), (0, radius), (0, -radius)):
            h = self.hit_h(x, y + dy, z + dz)
            if h is not None:
                vals.append(self.sample(h[1], h[2]))
        return np.mean(vals, axis=0) if vals else None

    def light(self, x, z, ymax, radius=0.25):
        vals = []
        for dx, dz in ((0, 0), (radius, 0), (-radius, 0), (0, radius), (0, -radius)):
            h = self.hit(x + dx, z + dz, ymax)
            if h is None or not self.L[h[1]]:
                continue
            vals.append(self.sample(h[1], h[2]))
        return np.mean(vals, axis=0) if vals else None

    def pick(self, o, d):
        P = self.P
        e1, e2 = P[:, 1] - P[:, 0], P[:, 2] - P[:, 0]
        h = np.cross(d, e2)
        a = (e1 * h).sum(1)
        ok = np.abs(a) > 1e-12
        f = np.where(ok, 1.0 / np.where(ok, a, 1), 0)
        s = o - P[:, 0]
        u = f * (s * h).sum(1)
        q = np.cross(s, e1)
        v = f * (q * d).sum(1)
        t = f * (q * e2).sum(1)
        hit = ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 0.05)
        if not hit.any():
            return None
        i = np.nonzero(hit)[0][np.argmin(t[hit])]
        return o + d * t[i]


def place(design, donors, conv_root, scenes, lane, cam, out):
    maps = {t: Map(conv_root, sc) for t, sc in scenes.items()}
    items = []
    for it in design["placements"]:
        explicit_y = "y" in it
        if "pick" in it:
            k = it["pick"]
            o, d = stage_camera.ray(lane, cam, k["pan"] * cam["px_per_unit"], k.get("zoom", 1.0), k["px"], k["py"])
            if "at_x" in k:
                p = o + d * ((k["at_x"] - o[0]) / d[0])
            else:
                p = maps["d"].pick(o, d)
                if p is None:
                    raise SystemExit(f"pick missed ground: {it}")
            it = dict(it, x=float(p[0]) + k.get("dx", 0.0), z=float(p[2]) + k.get("dz", 0.0), y=float(p[1]) + k.get("dy", 0.0), ymax=float(p[1]) + 0.05)
        ymax = it.get("ymax", 1.2)
        h = maps["d"].hit(it["x"], it["z"], ymax)
        y = it["y"] if "y" in it else (h[0] if h else None)
        if y is None:
            raise SystemExit(f"no ground under {it}")
        ly = y + 0.05
        light, src = {}, {}
        for t in sorted(maps):
            lv = maps[t].wall_light(it["x"], y, it["z"]) if explicit_y else None
            if lv is not None:
                src[t] = "wall"
            else:
                lv = maps[t].light(it["x"], it["z"], ly + 0.2)
                src[t] = "ground"
            light[t] = [round(float(v), 4) for v in (lv if lv is not None else [0.3, 0.3, 0.3])]
        dn = donors[it["mesh"]]
        if not explicit_y and dn["min"][1] > 0.2:
            y -= dn["min"][1] * it.get("scale", 1.0)
        e = {"mesh": it["mesh"], "pos": [round(it["x"], 3), round(y, 3), round(it["z"], 3)], "yaw": it.get("yaw", 0.0), "scale": it.get("scale", 1.0),
             "light": light, "phase": it.get("phase", round((it["x"] * 1.7 + it["z"] * 0.9) % 6.283, 3)),
             "sway": [dn["max"][1], dn["min"][1]] if dn["hanging"] else [dn["min"][1], dn["max"][1]], "wind": dn["wind"]}
        for k in ("pitch", "roll", "only"):
            if k in it:
                e[k] = it[k]
        items.append(e)
    return {"kit": "dressing", "light_gain": design["light_gain"], "wind": design["wind"], "items": items}


def main(design_path, src_root, conv_root, scenes, info_path, out_dir):
    design = json.load(open(design_path))
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    kits = export_kits(design, src_root, out)
    donors = pack(design, kits, out)
    info = json.load(open(info_path))
    lane = {"origin": [info["lane"]["centre"][0], info["lane"]["ground_y"], info["lane"]["centre"][2]], "axis": [0.0, 0.0, 1.0], "up": [0.0, 1.0, 0.0]}
    cam = {"fov": info["camera"]["fov_vertical"], "pitch": info["camera"]["pitch_down_deg"], "px_per_unit": info["camera"]["px_per_unit_zoom1"], "feet_row": info["camera"]["feet_row_of_720"], "view": [1280, 720]}
    doc = place(design, donors, conv_root, scenes, lane, cam, out)
    (out / "dressing.json").write_text(json.dumps(doc, indent=1) + "\n")
    print(json.dumps({"donors": len(donors), "items": len(doc["items"]), "tris": sum(d["tris"] for d in donors.values())}))


if __name__ == "__main__":
    if len(sys.argv) != 7:
        sys.exit("usage: foliage_gen.py <foliage.json> <donor src root (one dir per group)> <conv root> <d=scene,n=scene> <day variant json> <out dir>")
    main(sys.argv[1], sys.argv[2], sys.argv[3], dict(p.split("=", 1) for p in sys.argv[4].split(",")), sys.argv[5], sys.argv[6])
