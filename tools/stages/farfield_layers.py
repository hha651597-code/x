import math

import numpy as np

CORNERS = np.array([[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]])
QUAD_IDX = np.array([[0, 1, 2], [0, 2, 3]])


def srgb_to_lin(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def pick(r, lo_hi):
    return float(lo_hi[0] + (lo_hi[1] - lo_hi[0]) * r.random())


def on_street(x, z, grid, margin=0.0):
    for ax, v in (("x", x), ("z", z)):
        g = grid.get(ax)
        if g:
            k = round((v - g["o"]) / g["p"])
            if abs(v - (g["o"] + k * g["p"])) < g["w"] / 2 + margin:
                return True
    return False


def avoided(lay, x, z):
    if any(b["x"][0] <= x <= b["x"][1] and b["z"][0] <= z <= b["z"][1] for b in lay.get("avoid", [])):
        return True
    return "avoid_grid" in lay and on_street(x, z, lay["avoid_grid"], lay.get("avoid_margin", 0.0))


def item(lay, aid, pos, yaw, scale, r, world, **extra):
    tint = np.array(lay.get("tint", [1, 1, 1]), dtype=float) * (1 + lay.get("tint_var", 0.0) * (2 * r.random(3) - 1))
    return {"asset": aid, "pos": [float(v) for v in pos], "yaw": float(yaw), "scale": scale, "gain": lay.get("gain", 1.0), "tint": [float(v) for v in tint],
            "layer": lay.get("id", lay["type"]), "group": lay.get("group", "far"), "lod": lay.get("lod", 0.0), "seed": float(r.random()), "lit": pick_lit(lay.get("lit", world.get("lit", [0.15, 0.5])), r), **extra}


def pick_lit(lv, r):
    return pick(r, lv) if isinstance(lv, list) else float(lv)


def yaw_of(lay, r):
    if "yaw_choice" in lay:
        return float(r.choice(lay["yaw_choice"])) + float(r.normal(0, lay.get("yaw_jitter", 0.0)))
    ya = lay.get("yaw", [0, 0])
    return ya[0] + (ya[1] - ya[0]) * r.random()


def roof_items(lay, world, asset, r, aid, pos, s):
    roof = lay["roof"]
    a = asset(aid)
    sy = s[1] if isinstance(s, list) else s
    sx = s[0] if isinstance(s, list) else s
    out = []
    top = pos[1] + a.size[1] * sy
    for _ in range(int(r.integers(roof["n"][0], roof["n"][1] + 1))):
        rid = roof["pool"][int(r.integers(len(roof["pool"])))]
        x = pos[0] + (r.random() - 0.5) * a.size[0] * sx * 0.5
        z = pos[2] + (r.random() - 0.5) * a.size[2] * sx * 0.5
        out.append(item(lay, rid, [x, top - 0.2, z], float(r.random() * 360.0), pick(r, roof["scale"]) * sx, r, world, scattered=True, lit=0.0))
        if r.random() < roof.get("smoke", 0.0):
            out.append({"type": "smoke", "pos": [x, top + roof.get("smoke_lift", 6.0) * sx, z], "layer": lay.get("id", "roof"), **roof["smoke_cfg"], "seed": int(r.integers(1 << 30))})
    return out


def expand_scatter(lay, world, r, asset):
    out = []
    xs, zs = lay["region"]["x"], lay["region"]["z"]
    sx, sz = lay["spacing"]
    ids = lay["assets"]
    wts = np.array(lay.get("weights", [1] * len(ids)), dtype=float)
    wts /= wts.sum()
    for x0 in np.arange(xs[0], xs[1], sx):
        for z0 in np.arange(zs[0], zs[1], sz):
            if r.random() > lay.get("fill", 1.0):
                continue
            x = x0 + r.random() * sx * lay.get("jitter", 0.8)
            z = z0 + r.random() * sz * lay.get("jitter", 0.8)
            if avoided(lay, x, z):
                continue
            a = ids[r.choice(len(ids), p=wts)]
            s = pick(r, lay.get("scale", [1.0, 1.0]))
            if "scale_y" in lay:
                sy = lay["scale_y"]
                s = [s, s * (sy[0] + (sy[1] - sy[0]) * r.random()), s]
            yy = lay.get("y", 0.0)
            yy = pick(r, yy) if isinstance(yy, list) else yy
            out.append(item(lay, a, [x, yy, z], yaw_of(lay, r), s, r, world, scattered=True))
            if "roof" in lay:
                out += roof_items(lay, world, asset, r, a, [x, yy, z], s)
    return out


def expand_stacks(lay, world, asset, r):
    out = []
    xs, zs = lay["region"]["x"], lay["region"]["z"]
    sx, sz = lay["spacing"]
    for x0 in np.arange(xs[0], xs[1], sx):
        for z0 in np.arange(zs[0], zs[1], sz):
            if r.random() > lay.get("fill", 1.0):
                continue
            x = x0 + r.random() * sx * lay.get("jitter", 0.8)
            z = z0 + r.random() * sz * lay.get("jitter", 0.8)
            if avoided(lay, x, z):
                continue
            n = int(r.integers(lay["tiers"][0], lay["tiers"][1] + 1))
            s = pick(r, lay["scale"])
            yaw = yaw_of(lay, r)
            y = lay.get("y", 0.0)
            for i in range(n):
                pool = lay["base"] if i == 0 else (lay["top"] if i == n - 1 and r.random() < lay.get("top_p", 0.6) else lay["mid"])
                aid = pool[int(r.integers(len(pool)))]
                a = asset(aid)
                ts = s * (0.92 + 0.16 * r.random())
                off = lay.get("offset", 0.12)
                px = x + (r.random() - 0.5) * a.size[0] * ts * off * 2
                pz = z + (r.random() - 0.5) * a.size[2] * ts * off * 2
                cards = lay["cards"] if aid in lay.get("cards", {}).get("assets", []) else None
                out.append(item(lay, aid, [px, y, pz], yaw + float(r.choice([0, 0, 180])) + float(r.normal(0, lay.get("tier_jitter", 3.0))), ts, r, world, scattered=True, cards=cards))
                y += a.size[1] * ts * lay.get("overlap", 0.97)
            if r.random() < lay.get("smoke", 0.0):
                out.append({"type": "smoke", "pos": [x, y, z], "layer": lay.get("id", "stacks"), **lay["smoke_cfg"], "seed": int(r.integers(1 << 30))})
            if r.random() < lay.get("glow", 0.0):
                out.append({"type": "glow", "pos": [x, y + lay["glow_cfg"].get("lift", 1.0), z], "layer": lay.get("id", "stacks"), **lay["glow_cfg"]})
    return out


def expand_line(lay, world, asset, r):
    a = np.array(lay["from"], dtype=float)
    b = np.array(lay["to"], dtype=float)
    length = float(np.linalg.norm(b - a))
    n = max(int(length // lay["spacing"]), 1) + 1
    pole, wire = asset(lay["pole"]), asset(lay["wire"])
    s = lay.get("scale", 1.0)
    top = pole.size[1] * s * lay.get("wire_h", 0.88)
    sy = s * lay.get("wire_sag", 0.6)
    out = []
    prev = None
    for i in range(n):
        p = a + (b - a) * i / (n - 1)
        out.append(item(lay, lay["pole"], p, lay.get("yaw", 0.0), s, r, world))
        if "glow" in lay and i % lay["glow"].get("every", 1) == 0:
            g = lay["glow"]
            out.append({"type": "glow", "pos": [p[0], p[1] + pole.size[1] * s + g.get("lift", 0.0), p[2]], "layer": lay.get("id", "line"), "color": g["color"], "intensity": g.get("intensity", 1.0),
                        "size": g["size0"] + g["size_per_m"] * p[0]})
        if prev is not None:
            d = p - prev
            dist = math.hypot(d[0], d[2])
            mid = (p + prev) / 2
            along_z = wire.size[2] > wire.size[0]
            yaw = math.degrees(math.atan2(d[0], d[2]) if along_z else math.atan2(-d[2], d[0]))
            scale = [s, sy, dist / wire.size[2]] if along_z else [dist / wire.size[0], sy, s]
            for off in lay.get("wires", [0.0]):
                nx, nz = -d[2] / dist, d[0] / dist
                pos = [mid[0] + nx * off * s, mid[1] + top - wire.size[1] * sy, mid[2] + nz * off * s]
                out.append(item(lay, lay["wire"], pos, yaw, scale, r, world))
        prev = p
    return out


def wall_cards(placed, spec, scale, r):
    w, h = spec["size"][0] * scale, spec["size"][1] * scale
    up = np.array([0.0, 1.0, 0.0])
    A, B, C = [], [], []
    for p in placed:
        T = p["idx"]
        A.append(p["P"][T[:, 0]])
        B.append(p["P"][T[:, 1]])
        C.append(p["P"][T[:, 2]])
    A, B, C = np.concatenate(A), np.concatenate(B), np.concatenate(C)
    cr = np.cross(B - A, C - A)
    area = np.linalg.norm(cr, axis=1) * 0.5
    n = cr / np.maximum(np.linalg.norm(cr, axis=1, keepdims=True), 1e-12)
    cen = (A + B + C) / 3
    face = (n[:, 0] < -0.8) & (np.abs(n[:, 1]) < 0.25) & (area > 1e-4)
    ids = np.nonzero(face)[0]
    out = []
    if not len(ids):
        return out
    want = int(r.integers(spec["n"][0], spec["n"][1] + 1))
    for _ in range(want * 30):
        if len(out) >= want:
            break
        t = int(ids[int(r.integers(len(ids)))])
        nc = n[t]
        side = np.cross(up, nc)
        side /= max(np.linalg.norm(side), 1e-9)
        rel = cen[ids] - cen[t]
        flat = (n[ids] @ nc > 0.97) & (np.abs(rel @ nc) < 0.05 * scale)
        su = np.stack([rel @ side, rel[:, 1]], axis=1)
        inside = flat & (np.abs(su[:, 0]) < w / 2) & (np.abs(su[:, 1]) < h / 2)
        if area[ids][inside].sum() < 0.3 * w * h:
            continue
        ctr = cen[t] + nc * 0.06 * scale
        cell = int(r.integers(spec["cells"]))
        u0, v0 = (cell % spec["cols"]) / spec["cols"], (cell // spec["cols"]) / spec["rows"]
        du, dv = 1.0 / spec["cols"], 1.0 / spec["rows"]
        P = np.array([ctr - side * w / 2 - up * h / 2, ctr + side * w / 2 - up * h / 2, ctr + side * w / 2 + up * h / 2, ctr - side * w / 2 + up * h / 2])
        UV = np.array([[u0, v0 + dv], [u0 + du, v0 + dv], [u0 + du, v0], [u0, v0]])
        idx = QUAD_IDX.copy() if np.dot(np.cross(P[1] - P[0], P[2] - P[0]), nc) > 0 else QUAD_IDX[:, ::-1].copy()
        out.append({"P": P, "N": np.tile(nc, (4, 1)), "UV0": UV, "idx": idx, "COL": np.tile(spec["gain"] * (0.7 + 0.6 * r.random()), (4, 3)).astype(float)})
    return out


def expand_ring(lay, world, asset, r):
    out = []
    cx, cz = lay["centre"]
    for radius in lay["radii"]:
        a = math.radians(lay["arc"][0])
        end = math.radians(lay["arc"][1])
        while a < end:
            aid = lay["assets"][int(r.integers(len(lay["assets"])))]
            s = pick(r, lay["scale"])
            sy = s * pick(r, lay.get("scale_y", [1.0, 1.0]))
            w = min(asset(aid).size[0], asset(aid).size[2]) * s
            out.append(item(lay, aid, [cx + radius * math.cos(a), 0.0, cz + radius * math.sin(a)], pick(r, lay.get("yaw", [0, 0])), [s, sy, s], r, world))
            a += w * lay.get("overlap", 0.8) / radius
    return out


def skyline(lay, ctx):
    r = np.random.default_rng(lay.get("seed", 1))
    light = ctx["ground_light"](lay) * lay.get("gain", 1.0)
    cx, cz = lay["centre"]
    tile = lay.get("tile_m", 30.0)
    out = []
    a = math.radians(lay["arc"][0])
    end = math.radians(lay["arc"][1])
    while a < end:
        w = pick(r, lay["width"])
        h = pick(r, lay["height"])
        d = lay.get("depth", 60.0)
        n = np.array([math.cos(a), 0.0, math.sin(a)])
        t = np.array([-math.sin(a), 0.0, math.cos(a)])
        c = np.array([cx + lay["radius"] * n[0], 0.0, cz + lay["radius"] * n[2]])
        up = np.array([0.0, h, 0.0])
        lo = {(i, j): c + t * w / 2 * i + n * d / 2 * j for i in (-1, 1) for j in (-1, 1)}
        quads = [([lo[-1, -1], lo[1, -1], lo[1, -1] + up, lo[-1, -1] + up], -n, 1.0, w), ([lo[1, -1], lo[1, 1], lo[1, 1] + up, lo[1, -1] + up], t, 0.8, d),
                 ([lo[-1, 1], lo[-1, -1], lo[-1, -1] + up, lo[-1, 1] + up], -t, 0.8, d), ([lo[-1, -1] + up, lo[1, -1] + up, lo[1, 1] + up, lo[-1, 1] + up], np.array([0.0, 1.0, 0.0]), 1.15, w)]
        tint = 0.85 + 0.3 * r.random()
        P, N, UV, COL, idx = [], [], [], [], []
        for q, face, shade, span in quads:
            q = [np.array(v) for v in q]
            if np.dot(np.cross(q[1] - q[0], q[2] - q[0]), face) < 0:
                q = q[::-1]
            base = len(P)
            for k, v in enumerate(q):
                P.append(v)
                N.append(face)
                UV.append([(v[0] * abs(t[0]) + v[2] * abs(t[2])) / tile if abs(face[1]) < 0.5 else v[0] / tile, (v[1] if abs(face[1]) < 0.5 else v[2]) / tile])
                COL.append(light * shade * tint)
            idx += [[base, base + 1, base + 2], [base, base + 2, base + 3]]
        prim = {"P": np.array(P), "N": np.array(N), "UV0": np.array(UV), "idx": np.array(idx), "COL": np.array(COL)}
        out.append((prim, c))
        a += w * lay.get("overlap", 0.9) / lay["radius"]
    return out, ctx["crop_mat"](lay["crop"])


def expand(world, asset, org, variant):
    items = []
    for i, lay in enumerate(world["layers"]):
        t = lay["type"]
        r = np.random.default_rng(lay.get("seed", 1000 + i))
        if t == "place":
            items.append(item(lay, lay["asset"], lay["pos"], lay.get("yaw", 0.0), lay.get("scale", 1.0), r, world))
        elif t == "scatter":
            items += expand_scatter(lay, world, r, asset)
        elif t == "stacks":
            items += expand_stacks(lay, world, asset, r)
        elif t == "line":
            items += expand_line(lay, world, asset, r)
        elif t == "ring":
            items += expand_ring(lay, world, asset, r)
        elif t in ("ground", "ground_cells", "smoke", "glow", "skyline"):
            lay = {**lay, "layer": lay.get("id", t)}
            if lay.get("from", {}).get("go") == "@ground":
                lay["from"] = {**lay["from"], "go": world["ground_object"]}
            if t in ("ground", "ground_cells"):
                lay.setdefault("zc", float(org[2]))
            items.append(lay)
        else:
            raise SystemExit(f"unknown layer type {t}")
    return items


def axis_edges(c0, c1, step0, grow, centre, bands):
    edges = {round(centre, 4)}
    for sign in (1, -1):
        v, d = centre, step0
        while (v < c1 if sign > 0 else v > c0):
            v += sign * d
            d *= grow
            edges.add(round(v, 4))
    if bands:
        lo, hi = bands.get("range", [c0, c1])
        k0 = math.floor((max(c0, lo) - bands["o"]) / bands["p"])
        k1 = math.ceil((min(c1, hi) - bands["o"]) / bands["p"])
        for k in range(k0, k1 + 1):
            for e in (bands["o"] + k * bands["p"] - bands["w"] / 2, bands["o"] + k * bands["p"] + bands["w"] / 2):
                edges.add(round(e, 4))
    out = []
    for e in sorted(edges):
        if c0 <= e <= c1 and (not out or e - out[-1] > 0.3):
            out.append(e)
    return np.array(out)


def ground_cells(lay, ctx):
    r = np.random.default_rng(lay.get("seed", 1))
    grid = lay.get("grid", {})
    xe = axis_edges(lay["x"][0], lay["x"][1], lay.get("step0", 4.0), lay.get("grow", 1.2), lay["x"][0], grid.get("x"))
    ze = axis_edges(lay["z"][0], lay["z"][1], lay.get("step0", 4.0), lay.get("grow", 1.2), lay["zc"], grid.get("z"))
    light = ctx["ground_light"](lay) * lay.get("gain", 1.0) * np.array(lay.get("tint", [1.0, 1.0, 1.0]))
    cx, cz = (xe[:-1] + xe[1:]) / 2, (ze[:-1] + ze[1:]) / 2
    CX, CZ = np.meshgrid(cx, cz, indexing="ij")
    street = np.zeros(CX.shape, dtype=bool)
    for ax, V in (("x", CX), ("z", CZ)):
        g = grid.get(ax)
        if g:
            k = np.round((V - g["o"]) / g["p"])
            lo, hi = g.get("range", [-1e9, 1e9])
            street |= (np.abs(V - (g["o"] + k * g["p"])) < g["w"] / 2 + 0.01) & (V >= lo) & (V <= hi)
    bx = np.floor((CX - grid.get("x", {}).get("o", 0.0)) / grid.get("x", {}).get("p", 1e9)) if "x" in grid else np.zeros_like(CX)
    bz = np.floor((CZ - grid.get("z", {}).get("o", 0.0)) / grid.get("z", {}).get("p", 1e9)) if "z" in grid else np.zeros_like(CZ)
    h = np.sin(bx * 12.9898 + bz * 78.233) * 43758.5453
    bk = lay.get("block", [0.9, 1.1])
    block = bk[0] + (bk[1] - bk[0]) * (h - np.floor(h))
    noise = 1.0 + r.normal(0, lay.get("noise", 0.03), CX.shape)
    mult = np.where(street, lay.get("street", 0.75), block * lay.get("lot", 1.0)) * noise
    nx, nz = len(cx), len(cz)
    x0, x1 = xe[:-1][:, None] * np.ones((1, nz)), xe[1:][:, None] * np.ones((1, nz))
    z0, z1 = np.ones((nx, 1)) * ze[:-1][None, :], np.ones((nx, 1)) * ze[1:][None, :]
    y = lay.get("y", -0.02)
    corners = [(x0, z0), (x0, z1), (x1, z0), (x1, z1)]
    P = np.stack([np.stack([cxn, np.full_like(cxn, y), czn], axis=-1) for cxn, czn in corners], axis=2).reshape(-1, 3)
    n = nx * nz
    base = np.arange(n) * 4
    idx = np.concatenate([np.stack([base, base + 1, base + 2], axis=1), np.stack([base + 1, base + 3, base + 2], axis=1)])
    tile = lay.get("tile_m", 8.0)
    col = np.repeat((light[None, :] * mult.reshape(-1, 1)), 4, axis=0)
    return {"P": P, "N": np.tile([0.0, 1.0, 0.0], (len(P), 1)), "UV0": np.stack([P[:, 0] / tile, P[:, 2] / tile], axis=1), "idx": idx, "COL": col}, ctx["crop_mat"](lay["crop"])


def billboards(it):
    r = np.random.default_rng(int(it.get("seed", 1)))
    centre = np.array(it["pos"], dtype=float)
    out = []
    if it["type"] == "smoke":
        n = int(it.get("puffs", 6))
        for k in range(n):
            c = centre + np.array([r.normal(0, it.get("spread", 0.5)), 0.0, r.normal(0, it.get("spread", 0.5))])
            size = pick(r, it["size"])
            col = np.tile([size, (k + r.random() * 0.6) / n, it["rise"]], (4, 1))
            out.append({"P": np.tile(c, (4, 1)), "N": np.tile([0.0, 1.0, 0.0], (4, 1)), "UV0": (CORNERS + 1) / 2, "UV1": CORNERS.copy(), "idx": QUAD_IDX, "COL": col})
    else:
        col = np.tile(np.array(it["color"], dtype=float) * it.get("intensity", 1.0), (4, 1))
        out.append({"P": np.tile(centre, (4, 1)), "N": np.tile([0.0, 1.0, 0.0], (4, 1)), "UV0": (CORNERS + 1) / 2, "UV1": CORNERS * it["size"], "idx": QUAD_IDX, "COL": col})
    return out
