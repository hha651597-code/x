import hashlib
import io
import json
import math
import re
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import farfield_gen
import light_descriptor
import node_boxes
import provenance
import scene_to_glb as S
import stage_camera

RES = "res://assets/ba/stages"
FLOATS = ["_Cutoff", "_LightmapStrength", "_ReflectBaseAmount", "_ReflectAnglePower", "_ShadowAttenRefl", "_ReflectStrength", "_EmissionStrength", "_SpecPower", "_ShadowAttenSpec"]
COLORS = ["_Color", "_TintColor", "_SpecLightColor", "_SpecLightDir"]
TEXTURES = ["_MainTex", "_ReflectTex", "_EmissionTex", "_SpecTex"]
GLB_IMPORT = S.GLB_IMPORT
TEX_IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=%d
mipmaps/generate=%s
process/fix_alpha_border=%s
detect_3d/compress_to=0
"""
TEX_VRAM = TEX_IMPORT % (2, "true", "true")
TEX_LOSSLESS_MIPS = TEX_IMPORT % (0, "true", "false")
TEX_LOSSLESS = TEX_IMPORT % (0, "false", "false")


def rounded(o):
    if isinstance(o, float):
        return round(o, 5)
    if isinstance(o, list):
        return [rounded(v) for v in o]
    if isinstance(o, dict):
        return {k: rounded(v) for k, v in o.items()}
    return o


def jdump(obj, path):
    Path(path).write_text(json.dumps(rounded(obj), indent=1) + "\n")


def jload(path):
    return json.load(open(path))


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()[:8]


def slug(fn):
    stem = Path(fn).stem
    m = re.search(r"_p\d\d_[a-z]+_", stem)
    return stem[m.end():] if m else stem


def reencode(src):
    raw = Path(src).read_bytes()
    im = Image.open(src)
    buf = io.BytesIO()
    im.save(buf, format="PNG", optimize=True)
    same = np.array_equal(np.asarray(Image.open(io.BytesIO(buf.getvalue())).convert("RGBA")), np.asarray(im.convert("RGBA")))
    return buf.getvalue() if same and buf.tell() < len(raw) else raw


class Out:
    def __init__(self, root):
        self.root = Path(root)
        self.root.mkdir(parents=True, exist_ok=True)
        self.files = {}

    def put(self, rel, data=None, src=None):
        p = self.root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        if src is not None:
            shutil.copyfile(src, p)
        else:
            p.write_bytes(data if isinstance(data, bytes) else data.encode())
        self.files[rel] = p.stat().st_size

    def texture(self, src, prefix="", kind="vram"):
        name = f"{prefix}{slug(src)}_{digest(src)}.png"
        rel = f"tex/{name}"
        if rel not in self.files:
            self.put(rel, data=reencode(src))
            self.put(rel + ".import", {"vram": TEX_VRAM, "lossless": TEX_LOSSLESS, "lossless_mips": TEX_LOSSLESS_MIPS}[kind])
        return rel


def trim_materials(side, texmap, dir_of):
    out = {}
    for key, m in side["materials"].items():
        e = {"shader": m["shader"], "keywords": m["keywords"], "blend": {k: m["blend"][k] for k in ("src", "dst", "cull", "zoffset_factor")},
             "floats": {k: m["floats"][k] for k in FLOATS if k in m["floats"]}, "colors": {k: m["colors"][k]["raw"] for k in COLORS if k in m["colors"]}, "textures": {}}
        for tn in TEXTURES:
            t = m["textures"].get(tn)
            if t is not None:
                f = t.get("file")
                e["textures"][tn] = {"file": texmap[(dir_of, f)] if f else None, "scale": t["scale"], "offset": t["offset"]}
        out[key] = e
    return {"materials": out}


def patch_glb(src, dst, uri_map, drop=None):
    doc, buf = S.read_glb(src)
    for im in doc.get("images", []):
        im["uri"] = uri_map[im["uri"]]
    if drop is not None:
        doc, buf = S.repack_glb(doc, buf, drop)
    S.write_glb(dst, doc, buf)


def normal_dropper(doc, side):
    mats = [side["materials"][m["name"]] for m in doc["materials"]]

    def drop(node, prim, attr):
        if attr != "NORMAL":
            return False
        m = mats[prim["material"]]
        return not (m["shader"] == "MX/E-Standard" and (node["name"].startswith("lmn_") or bool(set(m["keywords"]) & {"_ENV_REFLECT_MODE", "_ENV_SPECULAR_MODE"})))

    return drop


def variant_ids(map_id, variants):
    return {t: sc.split(map_id + "_", 1)[1] for t, sc in variants.items()}


def far_distance(rest, side_files, sky_cfg):
    far = 0.0
    for sf in side_files:
        for c in jload(sf)["chunks"].values():
            lo, hi = np.array(c["aabb"][0]), np.array(c["aabb"][1])
            corners = np.array([[x, y, z] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])])
            far = max(far, float(np.linalg.norm(corners - rest, axis=1).max()))
    for l in sky_cfg["layers"]:
        far = max(far, float(l.get("dist", 0.0)) * 1.4)
    far = max(far, float(sky_cfg["celestial"]["dist"]) * 1.4)
    return float(math.ceil(far * 1.05 / 100.0) * 100.0)


def main(map_id, maps_path, work, out_root):
    maps = jload(maps_path)
    entry = maps["maps"][map_id]
    data = Path(maps_path).parent / entry["data"]
    work = Path(work)
    out = Out(Path(out_root) / map_id)
    ids = variant_ids(map_id, entry["variants"])
    sky_data = jload(data / "sky.json")
    fx_data = jload(data / "fx.json")
    world_data = farfield_gen.load_world(maps_path, map_id)
    layers = work / "layers" / map_id
    texmap = {}
    variants_json = {}
    cam_defaults = maps["defaults"]["camera"]
    for time, scene in entry["variants"].items():
        vid = ids[time]
        letter = vid[-1]
        conv = work / "conv" / scene
        info = jload(conv / f"{scene}.json")
        side = jload(conv / f"{scene}.materials.json")
        uri_map = {}
        for k, t in sorted(side["textures"].items()):
            rel = out.texture(conv / k, kind="vram")
            uri_map[k] = rel
            texmap[(scene, k)] = rel
        patch_glb(conv / f"{scene}.glb", out.root / f"{vid}.glb", uri_map, normal_dropper(S.read_glb(conv / f"{scene}.glb")[0], side))
        out.files[f"{vid}.glb"] = (out.root / f"{vid}.glb").stat().st_size
        out.put(f"{vid}.glb.import", GLB_IMPORT)
        lms = {}
        for lm in info["lightmaps"]:
            if lm.get("file"):
                rel = f"{vid}_lm{lm['index']}.dds"
                out.put(rel, src=conv / lm["file"])
                lms[str(lm["index"])] = rel
        jdump(trim_materials(side, texmap, scene), out.root / f"{vid}.materials.json")
        out.files[f"{vid}.materials.json"] = (out.root / f"{vid}.materials.json").stat().st_size
        files = {"glb": f"{vid}.glb", "materials": f"{vid}.materials.json", "lightmaps": lms}

        wd = layers / "world"
        for grp in ("far", "props"):
            base = f"{grp}_{vid}"
            fside = jload(wd / f"{base}.json")
            for mk, m in sorted(fside["materials"].items()):
                for field in ("tex", "emis"):
                    if m.get(field):
                        m[field] = out.texture(wd / m[field], kind="vram")
            jdump(fside, out.root / f"{base}.json")
            out.files[f"{base}.json"] = (out.root / f"{base}.json").stat().st_size
            patch_images = {i["uri"]: i["uri"] for i in S.read_glb(wd / f"{base}.glb")[0].get("images", [])}
            for u in patch_images:
                patch_images[u] = out.texture(wd / u, kind="vram")
            patch_glb(wd / f"{base}.glb", out.root / f"{base}.glb", patch_images)
            out.files[f"{base}.glb"] = (out.root / f"{base}.glb").stat().st_size
            out.put(f"{base}.glb.import", GLB_IMPORT)
            files[grp] = base

        fx = jload(layers / f"fx_{letter}" / "fx.json")
        fx["tex_dir"] = f"{RES}/{map_id}/fx/"
        fx["glow_tex"] = f"{RES}/{map_id}/fx/{fx['glow_tex'].rsplit('/', 1)[1]}"
        for pngp in sorted((layers / f"fx_{letter}" / "tex").glob("*.png")):
            if f"fx/{pngp.name}" not in out.files:
                out.put(f"fx/{pngp.name}", src=pngp)
                out.put(f"fx/{pngp.name}.import", TEX_LOSSLESS if pngp.stem != fx["glow_tex"].rsplit("/", 1)[1][:-4] else TEX_LOSSLESS_MIPS)
        jdump(fx, out.root / f"fx_{vid}.json")
        out.files[f"fx_{vid}.json"] = (out.root / f"fx_{vid}.json").stat().st_size
        files["fx"] = f"fx_{vid}.json"
        files["dressing"] = "dressing"

        sky = layers / "sky"
        if "sky/sky_meshes.glb" not in out.files:
            out.put("sky/sky_meshes.glb", src=sky / "sky_meshes.glb")
            out.put("sky/sky_meshes.glb.import", GLB_IMPORT)
        out.put(f"sky/bank_{vid}.json", src=sky / f"bank_{vid}.json")

        lane_a, cam_a, clip_a = info["lane"], info["camera"], info["clip"]
        lane = {
            "origin": [lane_a["centre"][0], lane_a["ground_y"], lane_a["centre"][2]],
            "axis": [0.0, 0.0, 1.0],
            "up": [0.0, 1.0, 0.0],
            "ground_y": lane_a["ground_y"],
            "flat_length": lane_a["flat_length"],
            "flat_range": lane_a["flat_z_range_at_lane_x"],
            "corridor": lane_a["flat_corridor_x_range_over_z_band"],
            "z_band": lane_a["z_band"],
            "fight_half_px": maps["defaults"]["fight_half_px"],
        }
        camera = dict(cam_defaults)
        camera["zooms"] = maps["defaults"]["zooms"]
        clip = {"plane": None if clip_a["clip_x"] is None else [-1.0, 0.0, 0.0, clip_a["clip_x"]], "needed": clip_a["needed"]}
        boxes = node_boxes.boxes(conv / f"{scene}.glb")
        extra_lights = []
        for i, ex in enumerate(fx_data["extras"]):
            lt = ex["light"]
            extra_lights.append({"type": "point", "kind": "fire", "position_gltf": ex["pos"], "range": lt["range"], "color_raw": lt["color"] + [1.0], "intensity": lt["intensity"], "path": f"extra/extra_drum_{i}"})
        desc = light_descriptor.build(info, boxes=boxes, extras=extra_lights)
        desc.pop("research")
        sc = info["scene"]
        amb = sc["ambient"]
        ld = info["light_descriptor"]
        desc["published"] = {
            "night": desc["night"],
            "key_color": [round(c * ld["key_intensity"], 4) for c in ld["key_color_raw"]],
            "key_dir": [round(c, 4) for c in ld["key_dir_view"]],
            "ambient": [round(c * amb["intensity"], 4) for c in amb["equator"]["raw"][:3]],
        }
        render = {
            "ambient": {k: amb[k]["raw"][:3] for k in ("sky", "equator", "ground")},
            "subtractive_shadow_color": sc["subtractive_shadow_color"]["raw"][:3],
            "main_light_shadow_strength": info["light_descriptor"]["key_shadow_strength"],
            "fog": {"enabled": bool(sc["fog"]["enabled"])},
        }
        skym = sc["skybox_material"]
        gradient = {"sky_color": skym["colors"]["_SkyColor"]["raw"][:3], "equator_color": skym["colors"]["_EquatorColor"]["raw"][:3],
                    "sky_gradient": skym["floats"]["_SkyGradient"], "equator_offset": skym["floats"]["_EquatorOffset"]}
        palette = sky_data["palettes"]["night" if letter == "n" else "day"]
        for k in ("sky_color", "equator_color"):
            assert all(abs(a - b) < 1e-4 for a, b in zip(palette["gradient"][k], gradient[k])), (vid, k)
        sky_json = {"gradient": gradient, "palette": {k: v for k, v in palette.items() if k != "gradient"}, "celestial": sky_data["celestial"], "layers": sky_data["layers"],
                    "planes": sky_data["planes"], "meshes": f"{RES}/{map_id}/sky/sky_meshes.glb", "bank": f"sky/bank_{vid}.json"}
        rest = stage_camera.solve(lane, camera)[0]
        camera["near"] = cam_defaults["near"]
        far_files = [out.root / f"far_{vid}.json", out.root / f"props_{vid}.json"]
        camera["far"] = far_distance(rest, far_files, sky_json)
        files["sky"] = sky_json["bank"]
        variants_json[time] = {"schema": 1, "id": vid, "source_scene": scene, "night": letter == "n", "files": files, "lane": lane, "camera": camera, "clip": clip, "light": desc, "render": render, "sky": sky_json}
        jdump(variants_json[time], out.root / f"{vid}.json")
        out.files[f"{vid}.json"] = (out.root / f"{vid}.json").stat().st_size

    dress = layers / "foliage"
    dj = jload(dress / "dressing.json")
    dj["kit"] = "dressing"
    jdump(dj, out.root / "dressing.json")
    out.files["dressing.json"] = (out.root / "dressing.json").stat().st_size
    dside = jload(dress / "dressing.materials.json")
    dtex = out.texture(dress / "dressing_atlas.png", kind="vram")
    for m in dside["materials"].values():
        m["textures"]["_MainTex"]["file"] = dtex
    jdump(trim_dressing(dside), out.root / "dressing.materials.json")
    out.files["dressing.materials.json"] = (out.root / "dressing.materials.json").stat().st_size
    patch_glb(dress / "dressing.glb", out.root / "dressing.glb", {"dressing_atlas.png": dtex})
    out.files["dressing.glb"] = (out.root / "dressing.glb").stat().st_size
    out.put("dressing.glb.import", GLB_IMPORT)

    jdump({"schema": 1, "id": map_id, "name": entry["name"], "school": entry["school"], "page": entry["page"], "times": ids, "variants": {t: f"{v}.json" for t, v in ids.items()}, "art": entry["art"]}, out.root / "stage.json")
    src_dirs = [work / "src" / map_id] + [work / "src" / f"donor_{s}" for s in sorted({n for spec in world_data["sources"].values() if spec != "self" for n in spec.values()})]
    src_dirs += [work / "src" / g for g in sorted({p["group"] for d in jload(data / "foliage.json")["donors"] for p in d["parts"]})]
    provenance.write(map_id, src_dirs, work / "cab_index.json", out.root / "PROVENANCE.json", list(entry["variants"].values()))
    total = sum(p.stat().st_size for p in out.root.rglob("*") if p.is_file())
    print(json.dumps({"stage": map_id, "files": len([p for p in out.root.rglob("*") if p.is_file()]), "bytes": total}))


def trim_dressing(side):
    out = {}
    for key, m in side["materials"].items():
        e = {"shader": m["shader"], "keywords": m["keywords"], "blend": {k: m["blend"][k] for k in ("src", "dst", "cull", "zoffset_factor")},
             "floats": {k: m["floats"][k] for k in FLOATS if k in m["floats"]}, "colors": {k: m["colors"][k]["raw"] for k in COLORS if k in m["colors"]},
             "textures": {"_MainTex": {"file": m["textures"]["_MainTex"]["file"], "scale": [1.0, 1.0], "offset": [0.0, 0.0]}}}
        out[key] = e
    return {"materials": out}


if __name__ == "__main__":
    if len(sys.argv) != 5:
        sys.exit("usage: publish_stage.py <map id> <maps.json> <work dir> <assets/ba/stages dir>")
    main(*sys.argv[1:5])
