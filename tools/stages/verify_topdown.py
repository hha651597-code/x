#!/usr/bin/env python
import json
import struct
import sys
from pathlib import Path

import imagecodecs
import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import scene_to_glb as s2g

KEEP = set()
RES = 0.05


def raster(tris, uv0, uv1, x0, z0, w, h, chunk=20000):
    best_y = np.full((h, w), -1e9, dtype=np.float32)
    win = np.full((h, w), -1, dtype=np.int64)
    bary = np.zeros((h, w, 3), dtype=np.float32)
    for c0 in range(0, len(tris), chunk):
        T = tris[c0 : c0 + chunk].astype(np.float64)
        px = (T[..., 0] - x0) / RES
        pz = (T[..., 2] - z0) / RES
        minx = np.floor(px.min(1)).astype(int)
        maxx = np.ceil(px.max(1)).astype(int)
        minz = np.floor(pz.min(1)).astype(int)
        maxz = np.ceil(pz.max(1)).astype(int)
        nx = np.maximum(maxx - minx + 1, 1)
        nz = np.maximum(maxz - minz + 1, 1)
        cnt = nx * nz
        ti = np.repeat(np.arange(len(T)), cnt)
        off = np.arange(cnt.sum()) - np.repeat(np.cumsum(cnt) - cnt, cnt)
        ix = minx[ti] + off % nx[ti]
        iz = minz[ti] + off // nx[ti]
        sx, sz = ix + 0.5, iz + 0.5
        ax, az = px[ti, 0], pz[ti, 0]
        bx, bz = px[ti, 1], pz[ti, 1]
        cx, cz = px[ti, 2], pz[ti, 2]
        den = (bz - cz) * (ax - cx) + (cx - bx) * (az - cz)
        ok = np.abs(den) > 1e-12
        den = np.where(ok, den, 1.0)
        l0 = ((bz - cz) * (sx - cx) + (cx - bx) * (sz - cz)) / den
        l1 = ((cz - az) * (sx - cx) + (ax - cx) * (sz - cz)) / den
        l2 = 1 - l0 - l1
        ok &= (l0 >= -1e-9) & (l1 >= -1e-9) & (l2 >= -1e-9) & (ix >= 0) & (ix < w) & (iz >= 0) & (iz < h)
        ti, ix, iz, l0, l1, l2 = ti[ok], ix[ok], iz[ok], l0[ok], l1[ok], l2[ok]
        y = l0 * T[ti, 0, 1] + l1 * T[ti, 1, 1] + l2 * T[ti, 2, 1]
        order = np.lexsort((y, iz * w + ix))
        key = (iz * w + ix)[order]
        last = np.r_[key[1:] != key[:-1], True]
        sel = order[last]
        px_i, pz_i, yy = ix[sel], iz[sel], y[sel]
        better = yy > best_y[pz_i, px_i]
        px_i, pz_i, sel, yy = px_i[better], pz_i[better], sel[better], yy[better]
        best_y[pz_i, px_i] = yy
        win[pz_i, px_i] = ti[sel] + c0
        bary[pz_i, px_i] = np.stack([l0[sel], l1[sel], l2[sel]], 1)
    return win, bary, best_y


def shade(win, bary, uv0, uv1, albedo, lm):
    h, w = win.shape
    out = np.zeros((h, w, 3), dtype=np.float32)
    m = win >= 0
    t = win[m]
    b = bary[m]
    u0 = (uv0[t] * b[..., None]).sum(1)
    u1 = (uv1[t] * b[..., None]).sum(1)
    ah, aw = albedo.shape[:2]
    lh, lw = lm.shape[:2]
    a = albedo[np.clip(((1 - u0[:, 1]) * ah).astype(int), 0, ah - 1), np.clip((u0[:, 0] * aw).astype(int), 0, aw - 1)]
    l = lm[np.clip((u1[:, 1] * lh).astype(int), 0, lh - 1), np.clip((u1[:, 0] * lw).astype(int), 0, lw - 1)]
    out[m] = a * l
    return out


def pick_keep(out_dir, variant):
    side = json.load(open(Path(out_dir) / f"{variant}.materials.json"))
    tris = {}
    for node, prims in side["primitives"].items():
        if not node.startswith("lm0_"):
            continue
        for p in prims:
            m = side["materials"][p["material"]]
            kw = set(m["keywords"])
            f = m["textures"].get("_MainTex", {}).get("file")
            if m["shader"] == "MX/E-Standard" and f and not kw & {"_ENV_ALPHA_MODE", "_ENV_CUTOUT_MODE"}:
                tris.setdefault(f, []).append((p["material"], p["triangles"]))
    best = max(sorted(tris), key=lambda f: sum(t for _, t in tris[f]))
    return {side["materials"][k]["name"] for k, _ in tris[best]} | {k for k, _ in tris[best]}


def raw_path(scene_bundle, deps_dir):
    sc = s2g.Scene(scene_bundle, deps_dir)
    rend, _ = s2g.collect_renderers(sc)
    T, U0, U1 = [], [], []
    lm_tex = alb_tex = None
    for r in rend:
        if r["lm"] != 0 or r["batch"][1] == 0:
            continue
        mo, _ = sc.ref(sc.sf, r["mesh_ref"])
        m = mo.read()
        hnd = s2g.MeshHandler(m)
        hnd.process()
        P = np.array(hnd.m_Vertices, dtype=np.float64)
        A = np.array(hnd.m_UV0, dtype=np.float64)
        B = np.array(hnd.m_UV1, dtype=np.float64)
        ind = np.array(hnd.m_IndexBuffer)
        for j in range(r["batch"][1]):
            sm = m.m_SubMeshes[r["batch"][0] + j]
            mat, _ = sc.ref(sc.sf, r["mats"][j])
            if sc.tt(mat)["m_Name"] not in KEEP:
                continue
            if alb_tex is None:
                tex = sc.tt(mat)["m_SavedProperties"]["m_TexEnvs"]
                mt = next(v for k, v in tex if k == "_MainTex")
                to, _ = sc.ref(mat.assets_file, mt["m_Texture"])
                alb_tex = np.array(to.read().image.convert("RGB")).astype(np.float32) / 255.0
            i0 = sm.firstByte // (2 if hnd.m_Use16BitIndices else 4)
            tri = ind[i0 : i0 + sm.indexCount].reshape(-1, 3)
            T.append(P[tri]), U0.append(A[tri]), U1.append(B[tri])
    lm_o = next(o for o in sc.objs.values() if o.type.name == "LightmapSettings")
    lmt, _ = sc.ref(lm_o.assets_file, sc.tt(lm_o)["m_Lightmaps"][0]["m_Lightmap"])
    t = lmt.read()
    raw = t.get_image_data()
    lm = imagecodecs.bcn_decode(raw[: t.m_Width * t.m_Height], 6, shape=(t.m_Height, t.m_Width, 3)).astype(np.float32)
    T = np.concatenate(T)
    T[..., 0] *= -1
    return T, np.concatenate(U0), np.concatenate(U1), alb_tex, lm


def glb_path(out_dir, variant):
    out = Path(out_dir)
    doc, buf = s2g.read_glb(out / f"{variant}.glb")

    def acc(k):
        a = doc["accessors"][k]
        v = doc["bufferViews"][a["bufferView"]]
        dt = {5126: "<f4", 5123: "<u2", 5125: "<u4"}[a["componentType"]]
        nc = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
        return np.frombuffer(buf, dtype=dt, count=a["count"] * nc, offset=v["byteOffset"]).reshape(-1, nc)

    T, U0, U1 = [], [], []
    alb_fn = None
    for n in doc["nodes"][1:]:
        if not n["name"].startswith("lm0_"):
            continue
        for p in doc["meshes"][n["mesh"]]["primitives"]:
            mat = doc["materials"][p["material"]]
            if mat["name"] not in KEEP:
                continue
            if alb_fn is None:
                alb_fn = doc["images"][doc["textures"][mat["pbrMetallicRoughness"]["baseColorTexture"]["index"]]["source"]]["uri"]
            P = acc(p["attributes"]["POSITION"]).astype(np.float64)
            A = acc(p["attributes"]["TEXCOORD_0"]).astype(np.float64)
            B = acc(p["attributes"]["TEXCOORD_1"]).astype(np.float64)
            tri = acc(p["indices"]).reshape(-1, 3)
            T.append(P[tri]), U0.append(A[tri]), U1.append(B[tri])
    alb = np.array(Image.open(out / alb_fn).convert("RGB")).astype(np.float32) / 255.0
    dds = (out / f"{variant}_lm0.dds").read_bytes()
    h, w = struct.unpack_from("<II", dds, 12)
    lm = imagecodecs.bcn_decode(dds[148 : 148 + w * h], 6, shape=(h, w, 3)).astype(np.float32)

    U0 = np.concatenate(U0)
    U1 = np.concatenate(U1)
    U0[..., 1] = 1 - U0[..., 1]
    U1[..., 1] = 1 - U1[..., 1]
    return np.concatenate(T), U0, U1, alb, lm


def main():
    if len(sys.argv) != 5:
        sys.exit("usage: verify_topdown.py <variant scene bundle> <out dir of that variant> <report dir> <deps dir>")
    bundle, out_dir, rep = sys.argv[1], sys.argv[2], Path(sys.argv[3])
    rep.mkdir(parents=True, exist_ok=True)
    variant = Path(bundle).name.split("_mxload")[0]
    KEEP.update(pick_keep(out_dir, variant))
    Tr, A0, B0, alb, lm = raw_path(bundle, sys.argv[4])
    Tg, A1, B1, alb2, lm2 = glb_path(out_dir, variant)
    print("triangles raw", len(Tr), "glb", len(Tg))
    allv = np.concatenate([Tr.reshape(-1, 3), Tg.reshape(-1, 3)])
    x0, z0 = allv[:, 0].min() - 0.5, allv[:, 2].min() - 0.5
    w = int((allv[:, 0].max() - x0) / RES) + 2
    h = int((allv[:, 2].max() - z0) / RES) + 2
    print("raster", w, "x", h)
    ra = raster(Tr, A0, B0, x0, z0, w, h)
    rb = raster(Tg, A1, B1, x0, z0, w, h)
    ia = shade(ra[0], ra[1], A0, B0, alb, lm)
    ib = shade(rb[0], rb[1], A1, B1, alb2, lm2)
    ma, mb = ra[0] >= 0, rb[0] >= 0
    both = ma & mb
    d = np.abs(ia - ib).max(axis=2)
    print("covered raw", int(ma.sum()), "glb", int(mb.sum()), "coverage mismatch px", int((ma ^ mb).sum()))
    print("height diff (both covered) max", float(np.abs(ra[2][both] - rb[2][both]).max()), "mean", float(np.abs(ra[2][both] - rb[2][both]).mean()))
    print("colour diff over both-covered: mean", float(d[both].mean()), "p99", float(np.percentile(d[both], 99)), "max", float(d[both].max()), "px above 0.02:", int((d[both] > 0.02).sum()), "of", int(both.sum()))

    mismatch = int((ma ^ mb).sum())
    bad = int((d[both] > 0.02).sum())
    ok = mismatch <= 0.001 * max(int(ma.sum()), 1) and bad <= 0.001 * max(int(both.sum()), 1)

    def save(img, name):
        v = np.clip(img, 0, 1) ** (1 / 2.2)

        Image.fromarray((v[::-1] * 255).astype(np.uint8)).save(rep / name)

    save(ia, f"{variant}_topdown_raw.png")
    save(ib, f"{variant}_topdown_glb.png")
    save(np.repeat(np.clip(d * 8, 0, 1)[..., None], 3, axis=2), f"{variant}_topdown_diffx8.png")
    json.dump({"x0": x0, "z0": z0, "res": RES, "w": w, "h": h, "coverage_mismatch_px": mismatch, "colour_px_above_0.02": bad}, open(rep / f"{variant}_topdown.json", "w"))
    if not ok:
        sys.exit("top-down check failed")


if __name__ == "__main__":
    main()
