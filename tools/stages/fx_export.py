import json
import sys
from pathlib import Path

import numpy as np
import UnityPy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import scene_to_glb as S

UnityPy.config.FALLBACK_UNITY_VERSION = "2021.3.56f2"

LUT_W = 64
SHADER = "DSFX/FX_SHADER_Explosion_Smoke_Flowmap_0"
ASSUMED = {"_BCustom_Data_Use": 1.0, "_GCustom_Data_Use": 1.0, "_Color_Custom_Data_Use": 1.0, "_Flowspeed_Data_Use": 0.0, "_Shadow_Value_Data_Use": 0.0}
UNITY_GRAVITY_Y = -9.81


def mm(c):
    if c["minMaxState"] == 0:
        return (c["scalar"], c["scalar"])
    assert c["minMaxState"] == 3, c["minMaxState"]
    return (min(c["minScalar"], c["scalar"]), max(c["minScalar"], c["scalar"]))


def hermite(keys, t):
    if t <= keys[0]["time"]:
        return keys[0]["value"]
    if t >= keys[-1]["time"]:
        return keys[-1]["value"]
    for a, b in zip(keys, keys[1:]):
        if a["time"] <= t <= b["time"]:
            h = b["time"] - a["time"]
            s = (t - a["time"]) / h
            s2, s3 = s * s, s * s * s
            return (2 * s3 - 3 * s2 + 1) * a["value"] + (s3 - 2 * s2 + s) * h * a["outSlope"] + (-2 * s3 + 3 * s2) * b["value"] + (s3 - s2) * h * b["inSlope"]


def curve(c, t):
    assert c["minMaxState"] == 1
    keys = c["maxCurve"]["m_Curve"]
    assert all(k["weightedMode"] == 0 for k in keys)
    return c["scalar"] * hermite(keys, t)


def gradient(g, t):
    assert g["m_Mode"] == 0
    cols = [(g[f"ctime{i}"] / 65535.0, [g[f"key{i}"][c] for c in "rgb"]) for i in range(g["m_NumColorKeys"])]
    als = [(g[f"atime{i}"] / 65535.0, g[f"key{i}"]["a"]) for i in range(g["m_NumAlphaKeys"])]

    def ev(ks, t):
        if t <= ks[0][0]:
            return np.array(ks[0][1], dtype=float)
        if t >= ks[-1][0]:
            return np.array(ks[-1][1], dtype=float)
        for (t0, v0), (t1, v1) in zip(ks, ks[1:]):
            if t0 <= t <= t1:
                s = 0.0 if t1 == t0 else (t - t0) / (t1 - t0)
                return (1 - s) * np.array(v0, dtype=float) + s * np.array(v1, dtype=float)

    return list(ev(cols, t)) + [float(ev(als, t))]


def dump_particles(sc):
    out = []
    for pid in sorted(sc.objs):
        o = sc.objs[pid]
        if o.type.name not in ("ParticleSystem", "ParticleSystemRenderer"):
            continue
        d = sc.tt(o)
        g = d["m_GameObject"]["m_PathID"]
        W, q, pos = sc.world_trs(g)
        out.append({"type": o.type.name, "go_path": sc.go_path(g), "pos_gltf": S.to_gltf_vec(pos), "quat_unity": [float(x) for x in q], "scale": [float(x) for x in np.linalg.norm(W[:3, :3], axis=0)], "tt": d, "obj": o})
    return out


def system_of(sc, ps, rn, gravity_y):
    t0 = ps["tt"]
    ini, em, sz, rot, col, frc, cd = (t0[k] for k in ("InitialModule", "EmissionModule", "SizeModule", "RotationModule", "ColorModule", "ForceModule", "CustomDataModule"))
    assert not t0["ShapeModule"]["enabled"] and ini["gravityModifier"]["minMaxState"] == 3
    assert t0["moveWithTransform"] == 1 and t0["scalingMode"] == 0 and t0["looping"] and not t0["prewarm"]
    assert not sz["separateAxes"] and not ini["size3D"] and not ini["rotation3D"]
    assert cd["mode0"] == 1 and cd["mode1"] == 2
    sc_col = ini["startColor"]
    assert sc_col["minMaxState"] == 0
    start_col = [sc_col["maxColor"][c] for c in "rgba"]
    rows = np.zeros((3, LUT_W, 4))
    for i in range(LUT_W):
        t = i / (LUT_W - 1)
        rows[0, i] = [curve(cd["vector0_2"], t), curve(cd["vector0_3"], t), curve(sz["curve"], t), 0.0]
        g2 = gradient(cd["color1"]["maxGradient"], t)
        rows[1, i] = [g2[0], g2[1], g2[2], 1.0]
        gc = gradient(col["gradient"]["maxGradient"], t)
        rows[2, i] = [start_col[k] * gc[k] for k in range(4)]
    x, y, z, w = ps["quat_unity"]
    fwd = (2 * (x * z + w * y), 2 * (y * z - w * x), 1 - 2 * (x * x + y * y))
    r = rn["tt"]
    mo, st = sc.ref(sc.sf, r["m_Materials"][0])
    assert mo is not None, st
    mat = S.read_material(sc, mo)
    assert mat["shader"] == SHADER, f"particle shader {mat['shader']} is not ported"
    for k, v in ASSUMED.items():
        assert mat["floats"][k] == v, (k, mat["floats"][k])
    tx = mat["tex_envs"]
    return {
        "rate": em["rateOverTime"]["scalar"],
        "life": mm(ini["startLifetime"]),
        "size": mm(ini["startSize"]),
        "start_speed": ini["startSpeed"]["scalar"],
        "gravity_mod": ini["gravityModifier"]["scalar"],
        "gravity": [0.0, gravity_y, 0.0],
        "force_z": mm(frc["z"]),
        "start_roll": mm(ini["startRotation"]),
        "roll_speed": mm(rot["curve"]),
        "pivot": [r["m_Pivot"][k] for k in "xyz"],
        "dir": [-fwd[0], fwd[1], fwd[2]],
        "scale": ps["scale"][0],
        "lut_w": LUT_W,
        "lut_rows": ["gOff,bOff,sizeMul,0", "custom2.rgb,1", "vertexColor.rgba"],
        "lut": [round(float(f), 6) for f in rows.reshape(-1)],
        "material": {
            "name": mat["name"],
            "shader": SHADER,
            "textures": {"flow": sc.tt(tx["_FlowTexRGB"]["obj"])["m_Name"], "main": sc.tt(tx["_MainTexRGBA"]["obj"])["m_Name"]},
            "flow_st": [tx["_FlowTexRGB"]["scale"][0], tx["_FlowTexRGB"]["scale"][1], tx["_FlowTexRGB"]["offset"][0], tx["_FlowTexRGB"]["offset"][1]],
            "r_color": mat["colors"]["_RColor"]["raw"],
            "floats": {
                "flow_speed": mat["floats"]["_FlowSpeed"],
                "g_sharpness": mat["floats"]["_GColor_Sharpness"],
                "shadow_value": mat["floats"]["_Shadow_Value"],
                "shadow_mul": mat["floats"]["_Shadow_Color_Multiply"],
                "mutiply": mat["floats"]["_Mutiply"],
            },
        },
        "_tex_objs": {"flow": tx["_FlowTexRGB"]["obj"], "main": tx["_MainTexRGBA"]["obj"]},
    }


def find_texture(deps_dir, name):
    for b in sorted(Path(deps_dir).glob("*effectsfreezed-texture*.bundle")):
        env = UnityPy.load(str(b))
        for o in env.objects:
            if o.type.name == "Texture2D" and o.peek_name() == name:
                return o.read()
    raise SystemExit(f"texture {name} not found in the effects bundles")


def build(scene_bundle, deps_dir, extras, glow_presets, glow_texture, tex_out, tex_dir_res):
    sc = S.Scene(scene_bundle, deps_dir)
    d = dump_particles(sc)
    ps_list = [e for e in d if e["type"] == "ParticleSystem"]
    rn = {e["tt"]["m_GameObject"]["m_PathID"]: e for e in d if e["type"] == "ParticleSystemRenderer"}
    gravity = UNITY_GRAVITY_Y
    systems, order, emitters, tex_objs = {}, [], [], {}
    skipped = []
    ps_sorted = sorted(ps_list, key=lambda e: (e["pos_gltf"][2], e["go_path"]))
    for i, e in enumerate(ps_sorted):
        key = json.dumps({k: v for k, v in e["tt"].items() if k != "m_GameObject"}, sort_keys=True, default=str)
        r = rn.get(e["tt"]["m_GameObject"]["m_PathID"])
        if r is None:
            skipped.append(e["go_path"])
            continue
        if key not in systems:
            try:
                s = system_of(sc, e, r, gravity)
            except AssertionError as err:
                skipped.append(f"{e['go_path']}: {err}")
                systems[key] = None
                continue
            tex_objs.update(s.pop("_tex_objs"))
            systems[key] = (f"ps_{len(order)}", s)
            order.append(key)
        if systems[key] is None:
            continue
        emitters.append({"system": systems[key][0], "pos": [round(float(c), 4) for c in e["pos_gltf"]], "name": e["go_path"].split("/")[-1], "source": "ba", "time_offset": round(0.137 * i, 3)})
    assert order, "no ported particle system in the scene"
    first = systems[order[0]][0]
    for i, ex in enumerate(extras):
        glows = []
        for j, g in enumerate(glow_presets.get(ex.get("glow"), [])):
            glows.append({**g, "seed": float(i) + 0.5 * j})
        emitters.append({"system": first, "pos": ex["pos"], "name": "extra_drum_%d" % i, "source": "extra", "time_offset": round(0.29 * (i + 1), 3), "glows": glows})
    tex_out = Path(tex_out)
    tex_out.mkdir(parents=True, exist_ok=True)
    names = []
    for k in sorted(tex_objs):
        t = tex_objs[k].read()
        t.image.save(tex_out / f"{t.m_Name}.png")
        names.append(t.m_Name)
    find_texture(deps_dir, glow_texture).image.save(tex_out / f"{glow_texture}.png")
    names.append(glow_texture)
    doc = {
        "version": 1,
        "source": "BA ParticleSystem barrel fire, shader " + SHADER,
        "tex_dir": tex_dir_res,
        "glow_tex": tex_dir_res + glow_texture + ".png",
        "systems": {systems[k][0]: systems[k][1] for k in order},
        "emitters": emitters,
        "skipped": skipped,
    }
    return doc, names


if __name__ == "__main__":
    if len(sys.argv) != 5:
        sys.exit("usage: fx_export.py <scene bundle> <deps dir> <fx.json data> <out dir>")
    cfg = json.load(open(sys.argv[3]))
    out = Path(sys.argv[4])
    out.mkdir(parents=True, exist_ok=True)
    doc, names = build(sys.argv[1], sys.argv[2], cfg["extras"], cfg["glow_presets"], cfg["glow_texture"], out / "tex", "res://assets/ba/stages/_shared/fx/")
    (out / "fx.json").write_text(json.dumps(doc, indent=1) + "\n")
    print(json.dumps({"textures": names, "emitters": len(doc["emitters"]), "skipped": doc["skipped"]}))
