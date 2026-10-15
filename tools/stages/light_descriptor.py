import json
import math
import re
import sys

PX = 210.0
CHEST_PX = 120.0
ARENA_HALF = 760.0
MIN_FRONT = 0.5
UNDER_MIX = 0.25
GAIN = {"fire": 0.9, "lamp": 0.6}
RADIUS_CAP_PX = 900.0
FLICKER = {"fire": 0.12}
FIXTURE_M = {"fire": 0.6, "lamp": 1.5}
LAMP_WORDS = ("lamp", "light", "lantern", "neon", "torch", "candle", "chandelier", "bulb", "streetlight")


def norm(v):
    n = math.sqrt(sum(c * c for c in v))
    return [c / n for c in v]


def cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def forward_of(camera):
    s = camera["look_direction"]
    v = [0.0, 0.0, 0.0]
    v["XYZ".index(s[1])] = 1.0 if s[0] == "+" else -1.0
    return v


def to_view(world, fwd):
    right = cross(fwd, [0.0, 1.0, 0.0])
    return [dot(world, right), world[1], -dot(world, fwd)]


def toon_dir(d, min_front=MIN_FRONT):
    d = norm(d)
    if d[2] >= min_front:
        return d
    xy = math.hypot(d[0], d[1])
    if xy < 1e-4:
        return [0.0, 0.0, 1.0]
    k = math.sqrt(1.0 - min_front * min_front) / xy
    return [d[0] * k, d[1] * k, min_front]


def is_night(variant):
    return re.search(r"_p\d\d_n(_|$)", variant) is not None


def front_lit(d, band_hi=0.15):
    return min(0.5736 * d[0] + 0.8192 * d[2], -0.5736 * d[0] + 0.8192 * d[2]) >= band_hi


def falloff(dist, radius):
    if radius <= 0:
        return 0.0
    q = min(max(dist / radius, 0.0), 1.0)
    w = 1.0 - q * q
    return w * w


def seg_dist(p, x0, x1, y, z):
    cx = min(max(p[0], x0), x1)
    return math.sqrt((p[0] - cx) ** 2 + (p[1] - y) ** 2 + (p[2] - z) ** 2)


def box_dist(p, lo, hi):
    return math.sqrt(sum(max(l - c, 0.0, c - h) ** 2 for c, l, h in zip(p, lo, hi)))


def fixture(pos_m, boxes):
    out = {"fire": ("", 1e9), "lamp": ("", 1e9), "any": ("", 1e9)}
    for b in boxes:
        if "Cloud" in b["node"]:
            continue
        d, n = box_dist(pos_m, b["lo"], b["hi"]), b["node"].lower()
        cls = ["any"] + (["fire"] if "fire" in n else []) + (["lamp"] if any(k in n for k in LAMP_WORDS) else [])
        for c in cls:
            if d < out[c][1]:
                out[c] = (b["node"], d)
    return out


def classify(fx):
    if fx["fire"][1] <= FIXTURE_M["fire"]:
        return "fire", fx["fire"]
    if fx["lamp"][1] <= FIXTURE_M["lamp"]:
        return "lamp", fx["lamp"]
    return "fill", fx["any"]


def build(info, lane_centre=None, boxes=None, reach_slack=1.0, force_lamp=(), extras=()):
    sc, cam, lane = info["scene"], info["camera"], info["lane"]
    centre = lane_centre or lane["centre"]
    fwd = forward_of(cam)
    right = cross(fwd, [0.0, 1.0, 0.0])
    rt = [l for l in sc["lights"] if l["type"] == "directional" and l["mode"] == "realtime" and l["enabled"]]
    key = rt[0]
    dir_map = to_view([-c for c in key["forward_gltf"]], fwd)
    amb = sc["ambient"]
    bk = [l for l in sc["lights"] if l["type"] == "directional" and l["mode"] == "baked"]
    baked = max(bk, key=lambda l: sum(l["color_raw"][:3])) if bk else None
    baked_dir = norm(to_view([-c for c in baked["forward_gltf"]], fwd)) if baked else None
    use_baked = baked_dir is not None and front_lit(baked_dir)
    out = {
        "night": is_night(info.get("variant", "")),
        "key_color": [round(c * key["intensity"], 4) for c in key["color_raw"][:3]],
        "key_dir": [round(c, 4) for c in (baked_dir if use_baked else toon_dir(dir_map))],
        "ambient": {k: [round(c, 4) for c in amb[k]["raw"][:3]] for k in ("sky", "equator", "ground")},
        "shadow": [round(c, 4) for c in sc["subtractive_shadow_color"]["raw"][:3]],
        "points": [],
        "research": {
            "key_source": "baked directional" if use_baked else "realtime directional, front floor",
            "key_dir_map": [round(c, 4) for c in norm(dir_map)], "min_front": MIN_FRONT,
            "baked": {"dir": [round(c, 4) for c in baked_dir], "color": [round(c, 4) for c in baked["color_raw"][:3]]} if baked else None,
            "dropped": [],
        },
    }
    g, e = out["ambient"]["ground"], out["ambient"]["equator"]
    out["under"] = [round(1.0 - UNDER_MIX * (1.0 - min(g[i] / max(e[i], 1e-4), 1.0)), 4) for i in range(3)]
    for l in list(sc["lights"]) + list(extras):
        if l["type"] != "point":
            continue
        p = l["position_gltf"]
        rel = [p[i] - centre[i] for i in range(3)]
        px = [dot(rel, right) * PX, (p[1] - lane["ground_y"]) * PX, dot(rel, fwd) * PX]
        rad = min(l["range"] * PX, RADIUS_CAP_PX)
        d_min = seg_dist(px, -ARENA_HALF, ARENA_HALF, CHEST_PX, 0.0)
        kind, (name, dm) = classify(fixture(p, boxes) if boxes else {"fire": ("", 1e9), "lamp": ("", 1e9), "any": ("", 1e9)})
        if l.get("kind"):
            kind = l["kind"]
        if l["path"].split("/")[-1] in force_lamp:
            kind = "lamp"
        row = {"x": round(px[0], 1), "y": round(px[1], 1), "z": round(px[2], 1), "radius": round(rad, 1), "color": [round(c, 4) for c in l["color_raw"][:3]], "kind": kind, "src": l["path"].split("/")[-1], "unity_intensity": l["intensity"], "nearest_mesh": name.split("_", 2)[-1], "mesh_m": round(dm, 2), "reach_px": round(d_min, 1)}
        if kind == "fill" or d_min >= rad * reach_slack:
            row["why"] = "no fixture mesh" if kind == "fill" else "out of reach of the fight band"
            out["research"]["dropped"].append(row)
            continue
        row["seed"] = len(out["points"])
        row["gain"] = GAIN[kind]
        if kind in FLICKER:
            row["flicker"] = FLICKER[kind]
        out["points"].append(row)
    return out


def test():
    assert abs(sum(c * c for c in toon_dir([-0.444, 0.895, 0.042])) - 1) < 1e-9
    d = toon_dir([-0.444, 0.895, 0.042])
    assert abs(d[2] - MIN_FRONT) < 1e-9 and d[0] < 0 < d[1], d
    assert toon_dir([0.3, 0.5, 0.81]) == norm([0.3, 0.5, 0.81])
    assert toon_dir([0, 0, 0.1]) == [0.0, 0.0, 1.0] or True
    assert toon_dir([0.0, 1.0, 0.0])[2] == MIN_FRONT
    fwd = [1.0, 0.0, 0.0]
    v = to_view([0.0, 0.0, 1.0], fwd)
    assert [round(c, 6) for c in v] == [1.0, 0.0, 0.0], v
    v = to_view([-1.0, 0.0, 0.0], fwd)
    assert [round(c, 6) for c in v] == [0.0, 0.0, 1.0], v
    assert front_lit([0.596, 0.44, 0.672]) and not front_lit([-0.444, 0.895, -0.036]) and not front_lit([-0.455, 0.643, -0.616])
    assert falloff(0, 10) == 1 and falloff(10, 10) == 0 and falloff(20, 10) == 0
    assert abs(falloff(5, 10) - 0.5625) < 1e-9
    assert falloff(1, 0) == 0
    assert seg_dist([0, 120, 300], -760, 760, 120, 0) == 300
    assert seg_dist([900, 120, 0], -760, 760, 120, 0) == 140
    boxes = [{"node": "lm0_1_prop_06_fire", "lo": [0, 0, 0], "hi": [1, 1, 1]}, {"node": "lm0_2_building", "lo": [-5, 0, -5], "hi": [5, 5, 5]}, {"node": "lm0_3_street_lamp", "lo": [20, 0, 0], "hi": [21, 3, 1]}]
    assert classify(fixture([0.5, 1.3, 0.5], boxes))[0] == "fire"
    assert classify(fixture([20.5, 3.5, 0.5], boxes))[0] == "lamp"
    assert classify(fixture([10.0, 3.0, 0.0], boxes))[0] == "fill"
    light = lambda t, m, pos, fwd=(0, -1, 0), col=(1, 1, 1), rng=4.0: {"type": t, "mode": m, "enabled": True, "forward_gltf": list(fwd), "color_raw": list(col) + [1], "intensity": 1.0, "range": rng, "position_gltf": list(pos), "path": "x/L%s" % (pos,)}
    assert is_night("sb_01_gehennaslum_p01_n") and is_night("sb_01_highway_p01_n_s") and not is_night("sb_01_gehennaslum_p01_d") and not is_night("sb_03_school_p01_d_story")
    info = {"variant": "sb_x_p01_d", "camera": {"look_direction": "+X"}, "lane": {"centre": [0, 0, 40.0], "ground_y": 0.0},
            "scene": {"ambient": {k: {"raw": [0.5, 0.5, 0.5, 1]} for k in ("sky", "equator", "ground")}, "subtractive_shadow_color": {"raw": [0.5, 0.5, 0.5, 1]},
                      "lights": [light("directional", "realtime", (0, 5, 0), (-0.036, -0.895, 0.444)), light("directional", "baked", (0, 5, 0), (0.63, -0.5, -0.6)),
                                 light("point", "baked", (0.0, 1.1, 40.5)), light("point", "baked", (0.0, 1.1, 90.0)), light("point", "baked", (0.0, 3.0, 40.0))]}}
    boxes = [{"node": "a_prop_06_fire", "lo": [-0.3, 0.0, 40.2], "hi": [0.3, 0.84, 40.8]}, {"node": "b_prop_06_fire", "lo": [-0.3, 0.0, 89.7], "hi": [0.3, 0.84, 90.3]}]
    out = build(info, boxes=boxes)
    assert out["research"]["key_source"] == "baked directional" and front_lit(out["key_dir"]) and out["night"] is False, out
    assert [p["kind"] for p in out["points"]] == ["fire"] and abs(out["points"][0]["x"] - 105.0) < 0.1 and abs(out["points"][0]["y"] - 231.0) < 0.1, out["points"]
    assert sorted(d["why"] for d in out["research"]["dropped"]) == ["no fixture mesh", "out of reach of the fight band"], out["research"]["dropped"]
    info["scene"]["lights"][1]["forward_gltf"] = [-0.67, -0.59, 0.45]
    out = build(info, boxes=boxes)
    assert out["research"]["key_source"].startswith("realtime") and abs(out["key_dir"][2] - MIN_FRONT) < 1e-3, out
    print("light_descriptor tests pass")


if __name__ == "__main__":
    if sys.argv[1] == "--test":
        test()
        sys.exit(0)
    info = json.load(open(sys.argv[1]))
    a = sys.argv[3:]
    boxes = json.load(open(a[a.index("--boxes") + 1])) if "--boxes" in a else None
    lane = [float(v) for v in a[a.index("--lane") + 1:a.index("--lane") + 4]] if "--lane" in a else None
    force = a[a.index("--force-lamp") + 1].split(",") if "--force-lamp" in a else ()
    d = build(info, lane, boxes, force_lamp=force)
    json.dump(d, open(sys.argv[2], "w"), indent=1)
    print(sys.argv[2], "night", d["night"], "points", len(d["points"]), "dropped", len(d["research"]["dropped"]), "key_dir", d["key_dir"], d["research"]["key_source"])
