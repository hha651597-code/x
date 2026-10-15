#!/usr/bin/env python
import glob
import hashlib
import json
import math
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import farfield_layers
import farfield_windows
import lmio
from glbio import Glb, S

GLB_IMPORT = S.GLB_IMPORT


def safe(s):
    return re.sub(r"_+", "_", re.sub(r"[^A-Za-z0-9_]", "_", s)).strip("_")


def digest(path):
    return hashlib.sha1(Path(path).read_bytes()).hexdigest()[:8]


class Source:
    def __init__(self, base, blur=2):
        self.base = Path(base)
        self.glb = Glb(str(self.base) + ".glb")
        self.info = json.load(open(str(self.base) + ".json"))
        self.mats = json.load(open(str(self.base) + ".materials.json"))["materials"]
        self.lms = {}
        for f in glob.glob(str(self.base) + "_lm*.dds"):
            i = int(re.search(r"_lm(\d+)\.dds$", f).group(1))
            px = lmio.load_dds_bc6h(f)
            self.lms[i] = lmio.box_down(px, blur) if blur > 1 else px
        self.by_go = {}
        for n in self.info["nodes"]:
            self.by_go.setdefault(n["go_path"].split("/")[-1], []).append(n["node"])
        self.ambient = np.array(self.info["scene"]["ambient"]["equator"]["raw"][:3])

    def go_names(self, base_name):
        return [g for g in self.by_go if g == base_name or re.sub(r" \(\d+\)$", "", g) == base_name]

    def prims(self, go):
        node = self.by_go[go][0]
        lm = int(node[2]) if node.startswith("lm") and node[2].isdigit() else None
        out = []
        for p in self.glb.prims(node):
            m = self.mats[p["material"]]
            d = {"P": p["P"], "N": p.get("N"), "UV0": p.get("UV0"), "idx": p["idx"], "mat": p["material"], "src_mat": m}
            if lm is not None and lm in self.lms and "UV1" in p:
                d["COL"] = lmio.bake_vertices(self.lms[lm], p["UV1"])
            else:
                d["COL"] = np.tile(self.ambient, (len(p["P"]), 1))
            out.append(d)
        return out


def rot_y(P, th):
    c, s = math.cos(th), math.sin(th)
    return np.stack([P[:, 0] * c + P[:, 2] * s, P[:, 1], -P[:, 0] * s + P[:, 2] * c], axis=1)


def facade_angle(prims):
    hist = np.zeros(36)
    for p in prims:
        if p["N"] is None:
            continue
        a, b, c = (p["P"][p["idx"][:, k]] for k in range(3))
        area = np.linalg.norm(np.cross(b - a, c - a), axis=1) * 0.5
        n = p["N"][p["idx"]].mean(axis=1)
        w = area * (1 - np.abs(n[:, 1])) ** 2
        ang = np.degrees(np.arctan2(n[:, 2], n[:, 0])) % 360
        np.add.at(hist, (ang // 10).astype(int) % 36, w)
    k = int(hist.argmax())
    return math.radians(k * 10 + 5)


def components(P, idx):
    key = np.round(P * 200).astype(np.int64)
    _, inv = np.unique(key, axis=0, return_inverse=True)
    inv = inv.reshape(-1)
    parent = np.arange(inv.max() + 1)

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for t in idx:
        ra = find(inv[t[0]])
        parent[find(inv[t[1]])] = ra
        parent[find(inv[t[2]])] = ra
    return np.array([find(inv[t[0]]) for t in idx])


def prune(prims, frac, diag):
    out = []
    for p in prims:
        lab = components(p["P"], p["idx"])
        keep = np.ones(len(lab), dtype=bool)
        for c in np.unique(lab):
            m = lab == c
            v = p["P"][p["idx"][m].reshape(-1)]
            if np.linalg.norm(v.max(0) - v.min(0)) < frac * diag:
                keep[m] = False
        idx = p["idx"][keep]
        if not len(idx):
            continue
        used = np.unique(idx)
        remap = np.zeros(len(p["P"]), dtype=np.int64)
        remap[used] = np.arange(len(used))
        q = {k: (v[used] if isinstance(v, np.ndarray) and v.ndim == 2 and len(v) == len(p["P"]) else v) for k, v in p.items()}
        q["idx"] = remap[idx]
        out.append(q)
    return out


class Asset:
    def __init__(self, spec, srcs, variant, lod=0.0):
        self.spec = spec
        src = srcs[spec["src"]][variant]
        self.src = src
        go = spec["go"]
        if spec.get("pick") == "brightest":
            # lazy implementation. will fix later :) brightest day instance wins so a moved prop carries no building shadow, night reuses the same game object
            dsrc = srcs[spec["src"]]["d"]
            best, bl = None, -1
            for g in dsrc.go_names(go):
                pr = dsrc.prims(g)
                lum = np.mean(np.concatenate([p["COL"] for p in pr]))
                if lum > bl:
                    best, bl = g, lum
            go = best
        if go not in src.by_go:
            c = src.go_names(go)
            assert c, f"{spec['src']}: no game object {go}"
            go = c[0]
        self.prims = src.prims(go)
        allp = np.concatenate([p["P"] for p in self.prims])
        lo, hi = allp.min(0), allp.max(0)
        self.anchor = np.array([(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2 if spec.get("anchor") == "center" else lo[1], (lo[2] + hi[2]) / 2])
        self.size = hi - lo
        self.face = facade_angle(self.prims) if spec.get("face") == "auto" else None
        self.srcid = spec["src"]
        self.gain = spec.get("gain", 1.0)
        if lod:
            self.prims = prune(self.prims, lod, float(np.linalg.norm(self.size)))

    def placed(self, pos, yaw_deg, scale, gain, tint, seed=0.0, lit=0.0, floor=None):
        sc = np.broadcast_to(np.array(scale, dtype=np.float64), (3,))
        assert (sc > 0).all(), "negative scale flips winding"
        th = math.radians(yaw_deg)
        if self.face is not None:
            th += self.face - math.pi
        out = []
        for p in self.prims:
            P = rot_y((p["P"] - self.anchor), th) * sc + np.array(pos)
            N = None if p["N"] is None else rot_y(p["N"], th)
            col = p["COL"] * gain * self.gain * np.array(tint)
            if floor is not None:
                col = np.maximum(col, np.array(floor) * np.array(tint))
            uv1 = np.tile([seed, lit], (len(P), 1))
            out.append({**p, "P": P, "N": N, "COL": col, "UV1": uv1})
        return out


def load_world(maps_path, map_id):
    maps_path = Path(maps_path)
    entry = json.load(open(maps_path))["maps"][map_id]
    world = json.load(open(maps_path.parent / entry["data"] / "world.json"))
    kit = json.load(open(maps_path.parent / "farfield_kits" / entry["far_kit"] / "kit.json"))
    out = {**kit, **world}
    for k in ("sources", "assets", "crops", "windows", "fx"):
        out[k] = {**kit.get(k, {}), **world.get(k, {})}
    out["layers"] = world.get("layers", kit.get("layers", []))
    out["sky"] = json.load(open(maps_path.parent / entry["data"] / "sky.json"))
    return out


def ground_mesh(lay, colour, seed=1):
    x0, x1 = lay["x"]
    z0, z1 = lay["z"]
    xs = [x0]
    d = lay.get("step0", 4.0)
    while xs[-1] < x1:
        xs.append(xs[-1] + d)
        d *= lay.get("grow", 1.25)
    zs_pos = []
    zc = lay["zc"]
    d = lay.get("step0", 4.0)
    z = zc
    while z < z1:
        zs_pos.append(z)
        z += d * 1.0
        d *= lay.get("grow", 1.25)
    zs_neg = []
    z = zc
    d = lay.get("step0", 4.0)
    while z > z0:
        zs_neg.append(z)
        z -= d
        d *= lay.get("grow", 1.25)
    zs = sorted(set(zs_neg[::-1] + zs_pos))
    X, Z = np.meshgrid(xs, zs, indexing="ij")
    P = np.stack([X, np.full_like(X, lay.get("y", -0.02)), Z], axis=-1).reshape(-1, 3)
    nx, nz = len(xs), len(zs)
    idx = []
    for i in range(nx - 1):
        for j in range(nz - 1):
            a, b, c, d2 = i * nz + j, i * nz + j + 1, (i + 1) * nz + j, (i + 1) * nz + j + 1
            idx += [[a, b, c], [b, d2, c]]  # fixes bug(far ground): (a, c, b) faced down and was back-face culled, leaving the void
    r = np.random.default_rng(seed)
    n = r.normal(0, lay.get("noise", 0.02), (len(P), 1))
    col = np.clip(np.array(colour)[None, :] * (1 + n), 0, None)
    N = np.tile([0, 1, 0], (len(P), 1)).astype(float)
    return {"P": P, "N": N, "UV0": None, "idx": np.array(idx), "mat": "flat", "COL": col}


def ground_colour(srcs, variant, lay):
    src = srcs[lay["from"]["src"]][variant]
    go = lay["from"]["go"]
    cols = []
    for g in src.go_names(go):
        node = src.by_go[g][0]
        lm = int(node[2])
        for p in src.glb.prims(node):
            m = src.mats[p["material"]]
            if "_ENV_ALPHA_MODE" in m["keywords"]:
                continue
            sel = (p["P"][:, 0] > lay["from"]["xmin"]) & (p["P"][:, 2] > lay["from"]["z"][0]) & (p["P"][:, 2] < lay["from"]["z"][1]) & (p["N"][:, 1] > 0.9)
            if not sel.any():
                continue
            tex = np.asarray(Image.open(src.base.parent / m["textures"]["_MainTex"]["file"]).convert("RGB"), dtype=np.float64) / 255.0
            H, W, _ = tex.shape
            uv = p["UV0"][sel]
            alb = farfield_layers.srgb_to_lin(tex[np.clip((uv[:, 1] * H).astype(int), 0, H - 1), np.clip((uv[:, 0] * W).astype(int) % W, 0, W - 1)])
            lmv = lmio.bake_vertices(src.lms[lm], p["UV1"][sel])
            cm = np.array(m["colors"]["_Color"]["raw"][:3])
            cols.append(alb * cm * lmv)
    c = np.concatenate(cols)
    return np.median(c, axis=0)


def ground_light(srcs, variant, lay):
    src = srcs[lay["from"]["src"]][variant]
    cols = []
    for g in src.go_names(lay["from"]["go"]):
        node = src.by_go[g][0]
        lm = int(node[2])
        for p in src.glb.prims(node):
            sel = (p["P"][:, 0] > lay["from"]["xmin"]) & (p["P"][:, 2] > lay["from"]["z"][0]) & (p["P"][:, 2] < lay["from"]["z"][1]) & (p["N"][:, 1] > 0.9)
            if sel.any():
                cols.append(lmio.bake_vertices(src.lms[lm], p["UV1"][sel]))
    c = np.concatenate(cols)
    lum = c.mean(axis=1)
    return np.median(c[lum >= np.percentile(lum, 55)], axis=0)


def build(world, conv_root, own_scenes, variant, vid, out_dir, layers_dir):
    conv_root = Path(conv_root)
    srcs = {}
    for k, spec in world["sources"].items():
        names = own_scenes if spec == "self" else spec
        srcs[k] = {v: Source(conv_root / sc / sc) for v, sc in names.items() if v == variant or v == "d"}
    assets = world["assets"]
    cache = {}

    def asset(aid, lod=0.0):
        if (aid, lod) not in cache:
            cache[(aid, lod)] = Asset(assets[aid], srcs, variant, lod)
        return cache[(aid, lod)]

    org = np.array(srcs[next(k for k, v in world["sources"].items() if v == "self")][variant].info["lane"]["centre"])
    items = farfield_layers.expand(world, asset, org, variant)
    rules = world.get("rules", {})
    edges = world["chunks"]["dist_edges"]
    sec = world["chunks"]["sector_deg"]
    buckets = {}
    mats = {}
    tex_out = Path(out_dir) / "tex"
    tex_out.mkdir(parents=True, exist_ok=True)
    violations, stats = [], {"items": 0, "tris": 0}
    by_layer = {}
    asset_tex_dir = {k: v[variant].base.parent for k, v in srcs.items() if variant in v}
    emis = {}
    down = world.get("texture_downscale", 1)
    night = variant == "n"

    def add(prim, chunk, mat_key):
        key = (chunk, mat_key)
        b = buckets.setdefault(key, {"P": [], "N": [], "UV0": [], "UV1": [], "COL": [], "idx": [], "n": 0})
        n = len(prim["P"])
        b["P"].append(prim["P"])
        b["N"].append(prim["N"] if prim["N"] is not None else np.tile([0, 1, 0], (n, 1)))
        b["UV0"].append(prim["UV0"] if prim["UV0"] is not None else np.zeros((n, 2)))
        b["UV1"].append(prim["UV1"] if prim.get("UV1") is not None else np.zeros((n, 2)))
        b["COL"].append(prim["COL"])
        b["idx"].append(prim["idx"] + b["n"])
        b["n"] += n
        stats["tris"] += len(prim["idx"])

    def chunk_of(c):
        d = c - org
        r = math.hypot(d[0], d[2])
        az = math.degrees(math.atan2(d[2], d[0]))
        band = sum(r > e for e in edges)
        return f"b{band}s{int(math.floor((az + 180) / sec))}"

    def save_tex(im, name):
        im.save(tex_out / name)
        return f"tex/{name}"

    def register_mat(srcid, p):
        m = p["src_mat"]
        kw = set(m["keywords"])
        assert m["shader"] != "MX/VertexColor" and "_ENV_ALPHA_MODE" not in kw, f"{p['mat']}: alpha materials are not ported to the far shader"
        kind = "cutout" if "_ENV_CUTOUT_MODE" in kw else "opaque"
        tf = m["textures"].get("_MainTex", {}).get("file")
        cm = m["colors"].get("_Color")
        cull = int(m["blend"]["cull"]) if m["blend"].get("cull") is not None else 2
        key = f"{safe(p['mat'])}_{digest(asset_tex_dir[srcid] / tf)[:6]}" if tf else safe(p["mat"])
        if key in mats:
            return key
        tex = None
        if tf:
            im = Image.open(asset_tex_dir[srcid] / tf)
            k = down.get(srcid, down.get("default", 1)) if isinstance(down, dict) else (1 if world["sources"][srcid] == "self" else int(down))
            if k > 1:
                size = (im.width // k, im.height // k)
                rgb = im.convert("RGB").resize(size, Image.LANCZOS)
                if "A" in im.getbands():
                    rgb.putalpha(im.getchannel("A").resize(size, Image.LANCZOS))
                im = rgb
            tex = save_tex(im, f"{srcid}_{Path(tf).name}")
        mats[key] = {"kind": kind, "shader": m["shader"], "tex": tex, "color_mul": cm["raw"][:3] if cm else [1, 1, 1], "cutoff": m["floats"].get("_Cutoff", 0.5), "cull": cull}
        wcfg = world.get("windows", {}).get(p["mat"])
        if night and wcfg and tf:
            if p["mat"] not in emis:
                img, rect, _ = farfield_windows.build(Image.open(asset_tex_dir[srcid] / tf), wcfg, wcfg.get("seed", 5))
                emis[p["mat"]] = (save_tex(img, f"emis_{safe(p['mat'])}.png"), rect)
            mats[key]["emis"], mats[key]["emis_rect"] = emis[p["mat"]]
            mats[key]["params"] = {"emis_gain": wcfg.get("gain", 1.0)}
        return key

    crops = {}

    def crop_mat(name):
        if name not in crops:
            c = world["crops"][name]
            m = srcs[c["src"]][variant].mats[c["material"]]
            im = Image.open(asset_tex_dir[c["src"]] / m["textures"]["_MainTex"]["file"]).convert("RGB")
            x, y, w, h = c["rect"]
            mats[f"crop_{name}"] = {"kind": "opaque", "shader": "crop", "tex": save_tex(im.crop((x, y, x + w, y + h)), f"crop_{name}.png"), "color_mul": m["colors"]["_Color"]["raw"][:3], "cutoff": 0.5, "cull": 2}
            crops[name] = f"crop_{name}"
        return crops[name]

    def fx_mat(kind):
        cfg = world["fx"][kind]
        if kind not in mats:
            im = Image.open(next(Path(layers_dir).glob(f"fx_*/tex/{cfg['tex']}"))).convert("RGBA")
            mats[kind] = {"kind": kind, "shader": kind, "tex": save_tex(im, f"fx_{kind}.png"), "color_mul": [1, 1, 1], "cutoff": 0.5, "cull": 0, "params": cfg.get("params_" + variant, {})}
        return kind

    card_cfg = world.get("cards")
    card_state = {}

    def card_mat():
        if "mat" not in card_state:
            c = card_cfg
            m = srcs[c["src"]][variant].mats[c["material"]]
            atlas = Image.open(asset_tex_dir[c["src"]] / m["textures"]["_MainTex"]["file"])
            sheet = farfield_windows.card_sheet(atlas, world["windows"][c["material"]], c.get("seed", 3), c["cols"], c["rows"])
            mats["card"] = {"kind": "card", "shader": "card", "tex": save_tex(sheet, "fx_card.png"), "color_mul": [1, 1, 1], "cutoff": 0.5, "cull": 0, "params": {}}
            card_state["mat"] = "card"
        return card_state["mat"]

    ctx = {"crop_mat": crop_mat, "ground_light": lambda lay: ground_light(srcs, variant, lay), "org": org}
    for it in items:
        grp = it.get("group", "far")
        t = it.get("type")
        if t == "ground":
            col = ground_colour(srcs, variant, it)
            g = ground_mesh(it, col * it.get("gain", 1.0), it.get("seed", 1))
            mats.setdefault("flat", {"kind": "flat", "shader": "flat", "tex": None, "color_mul": [1, 1, 1], "cutoff": 0.5, "cull": 2})
            add(g, grp + "|ground", "flat")
            it["_colour"] = col.tolist()
            continue
        if t == "ground_cells":
            g, mk = farfield_layers.ground_cells(it, ctx)
            add(g, grp + "|ground", mk)
            continue
        if t == "skyline":
            blocks, mk = farfield_layers.skyline(it, ctx)
            for prim, c in blocks:
                add(prim, grp + "|" + chunk_of(c), mk)
            continue
        if t in ("smoke", "glow"):
            if t == "glow" and not night:
                continue
            mk = fx_mat(t)
            for q in farfield_layers.billboards(it):
                add(q, grp + "|" + chunk_of(np.array(it["pos"])), mk)
            stats["items"] += 1
            continue
        a = asset(it["asset"], it.get("lod", 0.0))
        placed = a.placed(it["pos"], it.get("yaw", 0.0), it.get("scale", 1.0), it.get("gain", 1.0), it.get("tint", [1, 1, 1]), it.get("seed", 0.0), it.get("lit", 0.0) if night else 0.0, world.get("night_floor") if night and grp == "far" else None)
        if it.get("scattered") and min(p["P"][:, 0].min() for p in placed) < rules.get("min_x", -1e9):
            stats["dropped"] = stats.get("dropped", 0) + 1
            continue
        for p in placed:
            if a.spec.get("alpha") == "drop" and "_ENV_ALPHA_MODE" in p["src_mat"]["keywords"]:
                continue
            lo, hi = p["P"].min(0), p["P"].max(0)
            if lo[0] < rules.get("min_x", -1e9):
                violations.append((it["layer"], it["asset"], "min_x", lo[0]))
            strip = rules.get("lane_strip")
            if strip and hi[0] > strip[0] and lo[0] < strip[1] and hi[2] > rules["z_range"][0] and lo[2] < rules["z_range"][1]:
                violations.append((it["layer"], it["asset"], "lane_strip", (lo[0], hi[0])))
            add(p, grp + "|" + chunk_of((lo + hi) / 2), register_mat(a.srcid, p))
            by_layer[it["layer"]] = by_layer.get(it["layer"], 0) + len(p["idx"])
        if night and it.get("cards") and card_cfg:
            spec = {**it["cards"], **{k: card_cfg[k] for k in ("cols", "rows")}}
            spec["cells"] = card_cfg["cols"] * card_cfg["rows"]
            for q in farfield_layers.wall_cards(placed, spec, float(np.mean(it.get("scale", 1.0))), np.random.default_rng(int(it["seed"] * 2 ** 31))):
                add(q, grp + "|" + chunk_of(q["P"].mean(axis=0)), card_mat())
                by_layer["cards"] = by_layer.get("cards", 0) + 2
        stats["items"] += 1
    assert not violations, violations[:10]
    stats["layers"] = by_layer

    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    for grp in sorted({k[0].split("|")[0] for k in buckets}):
        write_group(world, vid, out, grp, {k: b for k, b in buckets.items() if k[0].startswith(grp + "|")}, mats, stats, items)


def write_group(world, vid, out, grp, buckets, mats, stats, items):
    used = sorted({mk for (_, mk) in buckets})
    # fixes bug(far colour): Godot keeps vertex colours as 8 bit, so a group wide scale (smoke packs rise up to 34) flattened night colours to zero. each material gets its own scale
    top = {mk: max(float(np.concatenate(b["COL"]).max()) for (_, k), b in buckets.items() if k == mk) for mk in used}
    gmats = {k: {**mats[k], "params": {**mats[k].get("params", {}), "color_scale": max(math.ceil(top[k] * 1000) / 1000, 0.001)}} for k in used}
    g = S.Glb()
    gl_mats, gl_images, gl_tex, gl_samp, gl_meshes, gl_nodes = [], [], [], [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}], [], []
    mat_idx = {}
    for mk, m in gmats.items():
        gm = {"name": mk, "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0, "roughnessFactor": 1.0}, "extensions": {"KHR_materials_unlit": {}}, "doubleSided": m["cull"] == 0}
        if m["kind"] == "cutout":
            gm["alphaMode"] = "MASK"
            gm["alphaCutoff"] = m["cutoff"]
        if m["tex"]:
            if m["tex"] not in [i["uri"] for i in gl_images]:
                gl_images.append({"uri": m["tex"]})
                gl_tex.append({"sampler": 0, "source": len(gl_images) - 1})
            gm["pbrMetallicRoughness"]["baseColorTexture"] = {"index": [i["uri"] for i in gl_images].index(m["tex"])}
        mat_idx[mk] = len(gl_mats)
        gl_mats.append(gm)
    chunk_info, tris = {}, 0
    color_scale = max(m["params"]["color_scale"] for m in gmats.values())
    for (chunk, mk), b in sorted(buckets.items()):
        P = np.concatenate(b["P"]).astype("<f4")
        col = np.concatenate(b["COL"])
        attrs = {"POSITION": P, "TEXCOORD_0": np.concatenate(b["UV0"]).astype("<f4"), "COLOR_0": (col / gmats[mk]["params"]["color_scale"]).astype("<f4")}
        if gmats[mk].get("emis") or gmats[mk]["kind"] in ("smoke", "glow"):
            attrs["TEXCOORD_1"] = np.concatenate(b["UV1"]).astype("<f4")
        small = len(P) < 65536
        idx = np.concatenate(b["idx"]).astype("<u2" if small else "<u4").reshape(-1, 1)
        accs = {k: g.add(v, 5126, {1: "SCALAR", 2: "VEC2", 3: "VEC3", 4: "VEC4"}[v.shape[1]], 34962, minmax=(k == "POSITION")) for k, v in attrs.items()}
        ia = g.add(idx, 5123 if small else 5125, "SCALAR", 34963)
        name = f"ff_{chunk.split('|')[1]}_{mk}"
        gl_meshes.append({"name": name, "primitives": [{"attributes": accs, "indices": ia, "mode": 4, "material": mat_idx[mk]}]})
        gl_nodes.append({"name": name, "mesh": len(gl_meshes) - 1})
        info = {"chunk": chunk.split("|")[1], "material": mk, "tris": int(len(idx) // 3), "aabb": [P.min(0).tolist(), P.max(0).tolist()]}
        if gmats[mk]["kind"] == "smoke":
            info["cull_margin"] = float(col[:, 0].max() + col[:, 2].max())
        chunk_info[name] = info
        tris += len(idx) // 3
    nodes = [{"name": f"{grp}_{vid}", "children": list(range(1, len(gl_nodes) + 1))}] + gl_nodes
    doc = {"asset": {"version": "2.0", "generator": "farfield_gen.py"}, "extensionsUsed": ["KHR_materials_unlit"], "scene": 0, "scenes": [{"name": grp, "nodes": [0]}],
           "nodes": nodes, "meshes": gl_meshes, "materials": gl_mats, "accessors": g.accessors, "bufferViews": g.views}
    if gl_images:
        doc["images"], doc["textures"], doc["samplers"] = gl_images, gl_tex, gl_samp
    base = f"{grp}_{vid}"
    S.write_glb(out / f"{base}.glb", doc, g.buf)
    (out / f"{base}.glb.import").write_text(GLB_IMPORT)
    side = {"name": base, "variant": vid, "group": grp, "color_scale": color_scale, "materials": gmats, "chunks": chunk_info, "stats": {"tris": tris, "nodes": len(gl_nodes), "items": stats["items"], "dropped": stats.get("dropped", 0), "layers": stats.get("layers", {})},
            "haze": {**(world.get("haze", {}) if grp == "far" else world.get("props_haze", {})), "color": world["sky"]["palettes"]["night" if vid.endswith("n") else "day"]["haze"]["color"]},
            "ground_colour": next((i.get("_colour") for i in items if i.get("type") == "ground"), None)}
    (out / f"{base}.json").write_text(json.dumps(side, indent=1) + "\n")
    print(base, "tris", tris, "nodes", len(gl_nodes), "materials", len(gmats))


if __name__ == "__main__":
    if len(sys.argv) != 7:
        sys.exit("usage: farfield_gen.py <maps.json> <map id> <conv root> <variant d|n> <variant id> <out dir>")
    maps_json, map_id, conv_root, variant, vid, out_dir = sys.argv[1:]
    entry = json.load(open(maps_json))["maps"][map_id]
    own = {sc.rsplit("_", 1)[1]: sc for sc in entry["variants"].values()}
    build(load_world(maps_json, map_id), conv_root, own, variant, vid, out_dir, Path(out_dir).parent)
