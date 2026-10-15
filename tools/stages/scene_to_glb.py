#!/usr/bin/env python
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
from UnityPy.helpers.MeshHelper import MeshHandler

UnityPy.config.FALLBACK_UNITY_VERSION = "2021.3.56f2"

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))


VC_SHADERS = {"MX/VertexColor"}
MIRROR = np.diag([-1.0, 1.0, 1.0, 1.0])
LM_NONE = 65534
GLB_IMPORT = """[remap]

importer="scene"
importer_version=1
type="PackedScene"

[params]

nodes/use_name_suffixes=false
nodes/use_node_type_suffixes=false
meshes/generate_lods=false
meshes/create_shadow_meshes=false
meshes/ensure_tangents=false
meshes/force_disable_compression=true
gltf/texture_map_mode=1
"""


def gamma_to_linear(c):
    if c <= 0.04045:
        return c / 12.92
    if c < 1.0:
        return ((c + 0.055) / 1.055) ** 2.4
    return c ** 2.2


def lin_rgba(c):
    return [gamma_to_linear(c[0]), gamma_to_linear(c[1]), gamma_to_linear(c[2]), c[3]]


def rgba(d):
    return [d["r"], d["g"], d["b"], d["a"]]


def safe_name(s):
    return re.sub(r"_+", "_", re.sub(r"[^A-Za-z0-9_]", "_", s)).strip("_")


def quat_mul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    )


def quat_rotate(q, v):
    x, y, z, w = q
    vx, vy, vz = v
    tx, ty, tz = 2 * (y * vz - z * vy), 2 * (z * vx - x * vz), 2 * (x * vy - y * vx)
    return (vx + w * tx + (y * tz - z * ty), vy + w * ty + (z * tx - x * tz), vz + w * tz + (x * ty - y * tx))


def quat_to_mat(q):
    x, y, z, w = q
    return np.array(
        [
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
        ]
    )


def mat_to_quat(m):
    t = m[0, 0] + m[1, 1] + m[2, 2]
    if t > 0:
        s = math.sqrt(t + 1) * 2
        return ((m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s, 0.25 * s)
    if m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = math.sqrt(1 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        return (0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s, (m[2, 1] - m[1, 2]) / s)
    if m[1, 1] > m[2, 2]:
        s = math.sqrt(1 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        return ((m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s, (m[0, 2] - m[2, 0]) / s)
    s = math.sqrt(1 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
    return ((m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s, (m[1, 0] - m[0, 1]) / s)


def trs_matrix(t, q, s):
    m = np.eye(4)
    m[:3, :3] = quat_to_mat(q) * np.array(s)[None, :]
    m[:3, 3] = t
    return m


def to_gltf_vec(v):
    return [-v[0], v[1], v[2]]


class Scene:
    def __init__(self, scene_path, deps_dir):
        deps = [p for p in sorted(Path(deps_dir).glob("*.bundle")) if "_scenes_all" not in p.name]
        self.env = UnityPy.load(*[str(p) for p in deps], str(scene_path))
        self.files = {}
        for bf in self.env.files.values():
            for name, f in getattr(bf, "files", {}).items():
                if hasattr(f, "objects"):
                    self.files[name.lower()] = f
        bf = next(b for k, b in self.env.files.items() if Path(k).name == Path(scene_path).name)
        cands = [f for f in bf.files.values() if hasattr(f, "objects") and any(o.type.name == "GameObject" for o in f.objects.values())]
        assert len(cands) == 1, [f.name for f in cands]
        self.sf = cands[0]
        self.objs = self.sf.objects
        self._tt, self._mesh = {}, {}
        self.go, self.tr, self.go2tr = {}, {}, {}
        for pid, o in self.objs.items():
            if o.type.name == "GameObject":
                self.go[pid] = self.tt(o)
            elif o.type.name == "Transform":
                self.tr[pid] = self.tt(o)
        for pid, t in self.tr.items():
            self.go2tr[t["m_GameObject"]["m_PathID"]] = pid

    def tt(self, o):
        k = (id(o.assets_file), o.path_id)
        if k not in self._tt:
            self._tt[k] = o.read_typetree()
        return self._tt[k]

    def ref(self, sf, p):
        fid, pid = p["m_FileID"], p["m_PathID"]
        if pid == 0:
            return None, "null"
        if fid == 0:
            o = sf.objects.get(pid)
            return o, ("ok" if o else "missing_object")
        ext = sf.externals[fid - 1]
        m = re.search(r"(CAB-[0-9a-fA-F]{32})", ext.path)
        if not m:
            return None, "builtin:" + ext.path
        tf = self.files.get(m.group(1).lower())
        if tf is None:
            return None, "missing_file:" + m.group(1)
        o = tf.objects.get(pid)
        return o, ("ok" if o else "missing_object:" + m.group(1))

    def ids(self, o):
        return f"{o.assets_file.name}/{o.path_id}"

    def go_path(self, gpid):
        names, p = [], self.go2tr[gpid]
        while p:
            names.append(self.go[self.tr[p]["m_GameObject"]["m_PathID"]]["m_Name"])
            p = self.tr[p]["m_Father"]["m_PathID"]
        return "/".join(reversed(names))

    def go_active(self, gpid):
        p = self.go2tr[gpid]
        while p:
            if not self.go[self.tr[p]["m_GameObject"]["m_PathID"]]["m_IsActive"]:
                return False
            p = self.tr[p]["m_Father"]["m_PathID"]
        return True

    def world_trs(self, gpid):
        chain, p = [], self.go2tr[gpid]
        while p:
            chain.append(self.tr[p])
            p = self.tr[p]["m_Father"]["m_PathID"]
        m, q = np.eye(4), (0.0, 0.0, 0.0, 1.0)
        for t in reversed(chain):
            lr, lp, ls = t["m_LocalRotation"], t["m_LocalPosition"], t["m_LocalScale"]
            lq = (lr["x"], lr["y"], lr["z"], lr["w"])
            m = m @ trs_matrix((lp["x"], lp["y"], lp["z"]), lq, (ls["x"], ls["y"], ls["z"]))
            q = quat_mul(q, lq)
        return m, q, m[:3, 3].copy()

    def mesh(self, o):
        k = (id(o.assets_file), o.path_id)
        if k in self._mesh:
            return self._mesh[k]
        m = o.read()
        h = MeshHandler(m)
        h.process()
        d = {
            "name": m.m_Name,
            "obj": o,
            "mesh": m,
            "handler": h,
            "pos": np.array(h.m_Vertices, dtype=np.float64)[:, :3],
            "nrm": np.array(h.m_Normals, dtype=np.float64)[:, :3] if h.m_Normals else None,
            "uv0": np.array(h.m_UV0, dtype=np.float64)[:, :2] if h.m_UV0 else None,
            "uv1": np.array(h.m_UV1, dtype=np.float64)[:, :2] if h.m_UV1 else None,
            "col": None,
            "idx": np.array(h.m_IndexBuffer, dtype=np.int64),
        }
        if h.m_Colors:
            c = np.array(h.m_Colors, dtype=np.float64)
            d["col"] = c / 255.0 if c.max() > 1.0001 else c
        self._mesh[k] = d
        return d


def read_material(sc, o):
    tt = sc.tt(o)
    sh, shst = sc.ref(o.assets_file, tt["m_Shader"])
    shname = None
    if sh is not None:
        try:
            shname = sh.read().m_ParsedForm.m_Name
        except Exception as e:
            shname = f"<shader unreadable: {e!r}>"
    sp = tt["m_SavedProperties"]
    mat = {
        "name": tt["m_Name"],
        "ids": [sc.ids(o)],
        "shader": shname,
        "shader_status": shst,
        "keywords": list(tt.get("m_ValidKeywords") or []) or [k for k in (tt.get("m_ShaderKeywords") or "").split(" ") if k],
        "invalid_keywords": list(tt.get("m_InvalidKeywords") or []),
        "render_queue": tt["m_CustomRenderQueue"],
        "lightmap_flags": tt["m_LightmapFlags"],
        "floats": {k: v for k, v in sp["m_Floats"]},
        "ints": {k: v for k, v in sp.get("m_Ints", [])},
        "colors": {k: {"raw": rgba(v), "linear": lin_rgba(rgba(v))} for k, v in sp["m_Colors"]},
        "tex_envs": {},
    }
    for k, v in sp["m_TexEnvs"]:
        tobj, tst = sc.ref(o.assets_file, v["m_Texture"])
        mat["tex_envs"][k] = {
            "obj": tobj,
            "status": tst,
            "scale": [v["m_Scale"]["x"], v["m_Scale"]["y"]],
            "offset": [v["m_Offset"]["x"], v["m_Offset"]["y"]],
        }
    f = mat["floats"]
    mat["blend"] = {
        "src": f.get("_SrcBlend"),
        "dst": f.get("_DstBlend"),
        "cull": f.get("_Cull"),
        "zwrite": f.get("_ZWrite"),
        "zoffset_factor": f.get("_ZOffsetFactor"),
        "zoffset_units": f.get("_ZOffsetUnits"),
    }
    mat["vertex_colors"] = shname in VC_SHADERS
    return mat


class Glb:
    def __init__(self):
        self.buf = bytearray()
        self.views, self.accessors = [], []

    def add(self, arr, comp, typ, target, minmax=False):
        data = np.ascontiguousarray(arr).tobytes()
        while len(self.buf) % 4:
            self.buf.append(0)
        self.views.append({"buffer": 0, "byteOffset": len(self.buf), "byteLength": len(data), "target": target})
        self.buf += data
        a = {"bufferView": len(self.views) - 1, "componentType": comp, "count": int(arr.shape[0]), "type": typ}
        if minmax:
            a["min"] = [float(x) for x in arr.min(axis=0)]
            a["max"] = [float(x) for x in arr.max(axis=0)]
        self.accessors.append(a)
        return len(self.accessors) - 1


def write_glb(path, doc, buf):
    doc = dict(doc)
    doc["buffers"] = [{"byteLength": len(buf)}]
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    b = bytes(buf) + b"\0" * (-len(buf) % 4)
    total = 12 + 8 + len(js) + 8 + len(b)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(b), 0x004E4942) + b)


def read_glb(path):
    d = Path(path).read_bytes()
    jl = struct.unpack_from("<I", d, 12)[0]
    doc = json.loads(d[20 : 20 + jl])
    bl = struct.unpack_from("<I", d, 20 + jl)[0]
    return doc, d[28 + jl : 28 + jl + bl]


def repack_glb(doc, buf, drop):
    doc = json.loads(json.dumps(doc))
    for node in doc["nodes"]:
        if "mesh" not in node:
            continue
        for p in doc["meshes"][node["mesh"]]["primitives"]:
            for an in list(p["attributes"]):
                if drop(node, p, an):
                    del p["attributes"][an]
    used = sorted({a for me in doc["meshes"] for p in me["primitives"] for a in list(p["attributes"].values()) + [p["indices"]]})
    g = Glb()
    remap = {}
    for old in used:
        a = doc["accessors"][old]
        v = doc["bufferViews"][a["bufferView"]]
        while len(g.buf) % 4:
            g.buf.append(0)
        g.views.append({"buffer": 0, "byteOffset": len(g.buf), "byteLength": v["byteLength"], "target": v["target"]})
        g.buf += buf[v["byteOffset"] : v["byteOffset"] + v["byteLength"]]
        na = dict(a)
        na["bufferView"] = len(g.views) - 1
        g.accessors.append(na)
        remap[old] = len(g.accessors) - 1
    for me in doc["meshes"]:
        for p in me["primitives"]:
            p["attributes"] = {k: remap[v] for k, v in p["attributes"].items()}
            p["indices"] = remap[p["indices"]]
    doc["accessors"], doc["bufferViews"] = g.accessors, g.views
    return doc, g.buf


def write_dds_bc6h(path, w, h, mips, raw):
    flags = 0x1 | 0x2 | 0x4 | 0x1000 | 0x20000 | 0x80000
    top = ((w + 3) // 4) * ((h + 3) // 4) * 16
    hdr = b"DDS " + struct.pack("<7I", 124, flags, h, w, top, 0, mips) + b"\0" * 44
    hdr += struct.pack("<II4s5I", 32, 0x4, b"DX10", 0, 0, 0, 0, 0)
    hdr += struct.pack("<5I", 0x401008, 0, 0, 0, 0)
    hdr += struct.pack("<5I", 95, 3, 0, 1, 0)
    assert len(hdr) == 148, len(hdr)
    Path(path).write_bytes(hdr + raw)


def bc6h_mip0_stats(raw, w, h):
    px = imagecodecs.bcn_decode(raw[: w * h], 6, shape=(h, w, 3)).astype(np.float32)
    lum = px @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    return {
        "max": float(px.max()),
        "mean": float(px.mean()),
        "fraction_texels_above_1": float((px.max(axis=2) > 1.0).mean()),
        "luminance_p50": float(np.percentile(lum, 50)),
        "luminance_p99": float(np.percentile(lum, 99)),
    }


def save_png(t, path):
    a = np.array(t.image.convert("RGBA"))
    if (a[..., 3] == 255).all():
        Image.fromarray(a[..., :3], "RGB").save(path)
        return "RGB"
    Image.fromarray(a, "RGBA").save(path)
    return "RGBA"


def collect_renderers(sc):
    mf = {}
    for o in sc.objs.values():
        if o.type.name == "MeshFilter":
            d = sc.tt(o)
            mf[d["m_GameObject"]["m_PathID"]] = d["m_Mesh"]
    exported, skipped = [], []
    for pid in sorted(sc.objs):
        o = sc.objs[pid]
        if o.type.name not in ("MeshRenderer", "SkinnedMeshRenderer"):
            continue
        d = sc.tt(o)
        g = d["m_GameObject"]["m_PathID"]
        r = {
            "pid": pid,
            "gpid": g,
            "go": sc.go[g]["m_Name"],
            "path": sc.go_path(g),
            "enabled": bool(d["m_Enabled"]),
            "active": sc.go_active(g),
            "lm": d["m_LightmapIndex"],
            "st": [d["m_LightmapTilingOffset"][k] for k in "xyzw"],
            "batch": [d["m_StaticBatchInfo"]["firstSubMesh"], d["m_StaticBatchInfo"]["subMeshCount"]],
            "mats": d["m_Materials"],
            "cast_shadows": d["m_CastShadows"],
            "receive_shadows": d["m_ReceiveShadows"],
            "layer": sc.go[g]["m_Layer"],
            "mesh_ref": mf.get(g),
            "kind": o.type.name,
        }
        if r["enabled"] and r["active"]:
            exported.append(r)
        else:
            s = {"renderer": f"{sc.sf.name}/{pid}", "path": r["path"], "enabled": r["enabled"], "active": r["active"], "lightmap_index": r["lm"], "mesh": None}
            if r["mesh_ref"]:
                mo, st = sc.ref(sc.sf, r["mesh_ref"])
                s["mesh"] = {"ref": [r["mesh_ref"]["m_FileID"], r["mesh_ref"]["m_PathID"]], "status": st, "resolves": mo is not None, "name": sc.mesh(mo)["name"] if mo is not None and mo.type.name == "Mesh" and st == "ok" else None}
            skipped.append(s)
    return exported, skipped


class Exporter:
    def __init__(self, sc, variant, out):
        self.sc, self.variant, self.out = sc, variant, Path(out)
        self.glb = Glb()
        self.mats, self.mat_by_id = {}, {}
        self.tex_files, self.tex_info, self.used_tex_names = {}, {}, set()
        self.gl_materials, self.gl_images, self.gl_textures, self.gl_samplers = [], [], [], []
        self.gl_meshes, self.gl_nodes = [], []
        self.nodes_info, self.prims_info, self.geo, self.unresolved, self.notes = [], {}, [], [], []
        self.expected_tris = self.exported_tris = 0
        self.serial = 0

    def material_for(self, mp, sf):
        o, st = self.sc.ref(sf, mp)
        if o is None:
            return None, st
        mid = self.sc.ids(o)
        if mid in self.mat_by_id:
            return self.mat_by_id[mid], "ok"
        m = read_material(self.sc, o)
        key = m["name"]
        if key in self.mats:
            key = f"{key}__{o.path_id & 0xFFFFFF:06x}"
        m["key"] = key
        self.mats[key] = m
        self.mat_by_id[mid] = key
        return key, "ok"

    def texture_file(self, tobj):
        tid = self.sc.ids(tobj)
        if tid in self.tex_files:
            return self.tex_files[tid]
        t = tobj.read()
        name = f"{self.variant}_{safe_name(t.m_Name) or 'tex'}"
        if name in self.used_tex_names:
            name += f"__{tobj.path_id & 0xFFFFFF:06x}"
        self.used_tex_names.add(name)
        fn = name + ".png"
        mode = save_png(t, self.out / fn)
        self.tex_files[tid] = fn
        self.tex_info[fn] = {
            "id": tid,
            "name": t.m_Name,
            "width": t.m_Width,
            "height": t.m_Height,
            "unity_format": int(t.m_TextureFormat),
            "png_mode": mode,
            "srgb": bool(t.m_ColorSpace == 1),
            "wrap_u": t.m_TextureSettings.m_WrapU,
            "wrap_v": t.m_TextureSettings.m_WrapV,
            "filter": t.m_TextureSettings.m_FilterMode,
            "mips": t.m_MipCount,
        }
        return fn

    def add_renderer(self, r):
        sc = self.sc
        mref = r["mesh_ref"]
        mo, mst = sc.ref(sc.sf, mref) if mref else (None, "no_meshfilter")
        if mo is None or mo.type.name != "Mesh":
            self.unresolved.append({"renderer": r["pid"], "path": r["path"], "status": mst})
            return
        md = sc.mesh(mo)
        sm = md["mesh"].m_SubMeshes
        batched = r["batch"][1] > 0
        first, count = (r["batch"][0], r["batch"][1]) if batched else (0, len(sm))
        if len(r["mats"]) != count:
            self.notes.append(f"{r['path']}: {len(r['mats'])} materials for {count} submeshes")
        lmtag = "n" if r["lm"] >= LM_NONE else str(r["lm"])
        nodename = f"lm{lmtag}_{self.serial:04d}_{safe_name(r['go'])}"
        self.serial += 1
        W, WQ, WP = sc.world_trs(r["gpid"])
        prims, prim_mats = [], []
        for j in range(count):
            k = first + j
            s = sm[k]
            mp = r["mats"][j] if j < len(r["mats"]) else None
            if mp is None:
                self.unresolved.append({"renderer": r["pid"], "path": r["path"], "submesh": k, "status": "no_material_slot"})
                continue
            key, st = self.material_for(mp, sc.sf)
            if key is None:
                self.unresolved.append({"renderer": r["pid"], "path": r["path"], "submesh": k, "status": "material:" + st})
                continue
            m = self.mats[key]
            fi = s.firstByte // (2 if md["handler"].m_Use16BitIndices else 4)
            idx = md["idx"][fi : fi + s.indexCount] + s.baseVertex
            lo, hi = s.firstVertex, s.firstVertex + s.vertexCount
            assert s.topology == 0 and len(idx) % 3 == 0, (r["path"], k)
            assert idx.min() >= lo and idx.max() < hi, (r["path"], k, int(idx.min()), int(idx.max()), lo, hi)
            self.expected_tris += s.indexCount // 3
            tri = (idx - lo).reshape(-1, 3)[:, [0, 2, 1]]
            used = np.unique(tri)
            remap = np.full(s.vertexCount, -1, dtype=np.int64)
            remap[used] = np.arange(len(used))
            tri = remap[tri]
            sel = used + lo
            P = md["pos"][sel].copy()
            P[:, 0] *= -1
            attrs = {"POSITION": P.astype("<f4")}
            if md["nrm"] is not None:
                N = md["nrm"][sel].copy()
                N[:, 0] *= -1
                ln = np.linalg.norm(N, axis=1)
                bad = ln < 1e-8
                N[~bad] /= ln[~bad, None]
                N[bad] = (0, 1, 0)
                attrs["NORMAL"] = N.astype("<f4")
            for ch, an in (("uv0", "TEXCOORD_0"), ("uv1", "TEXCOORD_1")):
                if md[ch] is not None:
                    U = md[ch][sel].copy()
                    U[:, 1] = 1.0 - U[:, 1]
                    attrs[an] = U.astype("<f4")
            if m["vertex_colors"] and md["col"] is not None:
                attrs["COLOR_0"] = md["col"][sel].astype("<f4")
            acc = {an: self.glb.add(a, 5126, {1: "SCALAR", 2: "VEC2", 3: "VEC3", 4: "VEC4"}[a.shape[1]], 34962, minmax=(an == "POSITION")) for an, a in attrs.items()}
            if len(used) > 65535:
                ia = self.glb.add(tri.astype("<u4").reshape(-1, 1), 5125, "SCALAR", 34963)
            else:
                ia = self.glb.add(tri.astype("<u2").reshape(-1, 1), 5123, "SCALAR", 34963)
            prims.append({"attributes": acc, "indices": ia, "mode": 4, "_mat": key})
            prim_mats.append({"submesh": k, "material": key, "material_id": m["ids"][0], "triangles": int(len(tri)), "vertices": int(len(used))})
            self.exported_tris += len(tri)
            Pg, Ng = attrs["POSITION"].astype(np.float64), attrs.get("NORMAL")
            if not batched:
                Wg = MIRROR @ W @ MIRROR
                Pg = (np.c_[Pg, np.ones(len(Pg))] @ Wg.T)[:, :3]
                if Ng is not None:
                    Ng = Ng.astype(np.float64) @ np.linalg.inv(Wg[:3, :3])
                    Ng /= np.maximum(np.linalg.norm(Ng, axis=1, keepdims=True), 1e-12)
            self.geo.append({"node": nodename, "submesh": k, "P": Pg.astype(np.float32), "N": None if Ng is None else Ng.astype(np.float32), "tri": tri.astype(np.int32), "material": key, "shader": m["shader"], "lm": r["lm"]})
        if not prims:
            return
        self.gl_meshes.append({"name": nodename, "primitives": prims})
        node = {"name": nodename, "mesh": len(self.gl_meshes) - 1}
        if not batched:
            A = W[:3, :3]
            sx = np.linalg.norm(A, axis=0)
            Rm = A / sx
            if np.linalg.det(Rm) < 0:
                sx[0], Rm[:, 0] = -sx[0], -Rm[:, 0]
            if np.abs(Rm.T @ Rm - np.eye(3)).max() < 1e-4:
                qx, qy, qz, qw = mat_to_quat(Rm)
                t = W[:3, 3]
                node["translation"] = [float(-t[0]), float(t[1]), float(t[2])]
                node["rotation"] = [float(qx), float(-qy), float(-qz), float(qw)]
                node["scale"] = [float(v) for v in sx]
            else:
                node["matrix"] = [float(v) for v in (MIRROR @ W @ MIRROR).T.reshape(-1)]
                self.notes.append(f"{nodename}: sheared world transform written as a matrix")
        self.gl_nodes.append(node)
        self.nodes_info.append(
            {
                "node": nodename,
                "go_path": r["path"],
                "renderer_id": f"{sc.sf.name}/{r['pid']}",
                "lightmap": None if r["lm"] >= LM_NONE else r["lm"],
                "lightmap_index_raw": r["lm"],
                "lightmap_st_not_applied": r["st"],
                "static_batch": r["batch"],
                "mesh": md["name"],
                "mesh_id": sc.ids(mo),
                "identity_node": batched,
                "trs_unity": {"pos": [float(v) for v in WP], "quat": [float(v) for v in WQ], "scale": [float(v) for v in np.einsum("ij,ij->j", quat_to_mat(WQ), W[:3, :3])]},
                "primitives": prim_mats,
            }
        )
        self.prims_info[nodename] = prim_mats

    def finish_gltf(self):
        mat_index = {}
        sampler_idx, tex_idx = {}, {}
        for key, m in self.mats.items():
            mt = m["tex_envs"].get("_MainTex")
            gm = {
                "name": key,
                "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0, "roughnessFactor": 1.0},
                "extensions": {"KHR_materials_unlit": {}},
                "doubleSided": m["blend"]["cull"] == 0,
            }
            kws = set(m["keywords"])
            if "_ENV_ALPHA_MODE" in kws or m["shader"] in VC_SHADERS or (m["blend"]["src"] == 5 and m["blend"]["dst"] == 10):
                gm["alphaMode"] = "BLEND"
            elif "_ENV_CUTOUT_MODE" in kws:
                gm["alphaMode"] = "MASK"
                gm["alphaCutoff"] = m["floats"].get("_Cutoff", 0.5)
            if mt and mt["obj"] is not None:
                fn = self.texture_file(mt["obj"])
                ti = self.tex_info[fn]
                sk = (ti["wrap_u"], ti["wrap_v"], ti["mips"] > 1)
                if sk not in sampler_idx:
                    self.gl_samplers.append({"magFilter": 9729, "minFilter": 9987 if sk[2] else 9729, "wrapS": 10497 if sk[0] == 0 else 33071, "wrapT": 10497 if sk[1] == 0 else 33071})
                    sampler_idx[sk] = len(self.gl_samplers) - 1
                if fn not in [i["uri"] for i in self.gl_images]:
                    self.gl_images.append({"uri": fn})
                img = [i["uri"] for i in self.gl_images].index(fn)
                if (img, sampler_idx[sk]) not in tex_idx:
                    self.gl_textures.append({"sampler": sampler_idx[sk], "source": img})
                    tex_idx[(img, sampler_idx[sk])] = len(self.gl_textures) - 1
                gm["pbrMetallicRoughness"]["baseColorTexture"] = {"index": tex_idx[(img, sampler_idx[sk])]}
            mat_index[key] = len(self.gl_materials)
            self.gl_materials.append(gm)
            for tn, te in m["tex_envs"].items():
                if te["obj"] is not None:
                    self.texture_file(te["obj"])
        for me in self.gl_meshes:
            for p in me["primitives"]:
                p["material"] = mat_index[p.pop("_mat")]

        nodes = [{"name": self.variant, "children": list(range(1, len(self.gl_nodes) + 1))}] + self.gl_nodes
        doc = {
            "asset": {"version": "2.0", "generator": "scene_to_glb.py"},
            "extensionsUsed": ["KHR_materials_unlit"],
            "scene": 0,
            "scenes": [{"name": self.variant, "nodes": [0]}],
            "nodes": nodes,
            "meshes": self.gl_meshes,
            "materials": self.gl_materials,
            "accessors": self.glb.accessors,
            "bufferViews": self.glb.views,
        }
        if self.gl_images:
            doc["images"], doc["textures"], doc["samplers"] = self.gl_images, self.gl_textures, self.gl_samplers
        write_glb(self.out / f"{self.variant}.glb", doc, self.glb.buf)
        (self.out / f"{self.variant}.glb.import").write_text(GLB_IMPORT)

    def materials_json(self):
        out = {}
        for key, m in self.mats.items():
            e = {k: v for k, v in m.items() if k not in ("tex_envs", "key")}
            e["textures"] = {}
            for tn, te in m["tex_envs"].items():
                ent = {"status": te["status"], "scale": te["scale"], "offset": te["offset"], "file": None}
                if te["obj"] is not None:
                    fn = self.tex_files[self.sc.ids(te["obj"])]
                    ent["file"] = fn
                    ent["srgb"] = self.tex_info[fn]["srgb"]
                    ent["width"], ent["height"] = self.tex_info[fn]["width"], self.tex_info[fn]["height"]
                e["textures"][tn] = ent
            out[key] = e
        return {"variant": self.variant, "materials": out, "primitives": self.prims_info, "textures": self.tex_info}


def light_infos(sc):
    out = []
    for pid in sorted(sc.objs):
        o = sc.objs[pid]
        if o.type.name != "Light":
            continue
        d = sc.tt(o)
        g = d["m_GameObject"]["m_PathID"]
        _, q, pos = sc.world_trs(g)
        fwd = quat_rotate(q, (0.0, 0.0, 1.0))
        col = rgba(d["m_Color"])
        out.append(
            {
                "id": f"{sc.sf.name}/{pid}",
                "path": sc.go_path(g),
                "type": {0: "spot", 1: "directional", 2: "point", 3: "area", 4: "disc"}.get(d["m_Type"], d["m_Type"]),
                "mode": {1: "mixed", 2: "baked", 4: "realtime"}.get(d.get("m_Lightmapping"), d.get("m_Lightmapping")),
                "enabled": bool(d["m_Enabled"]),
                "active": sc.go_active(g),
                "color_raw": col,
                "color_linear": lin_rgba(col),
                "intensity": d["m_Intensity"],
                "range": d["m_Range"],
                "spot_angle": d.get("m_SpotAngle"),
                "shadow_type": {0: "none", 1: "hard", 2: "soft"}.get(d["m_Shadows"]["m_Type"], d["m_Shadows"]["m_Type"]),
                "shadow_strength": d["m_Shadows"]["m_Strength"],
                "culling_mask": hex(d["m_CullingMask"]["m_Bits"]),
                "forward_unity": list(fwd),
                "forward_gltf": to_gltf_vec(fwd),
                "position_gltf": to_gltf_vec(pos),
            }
        )
    return out


def scene_info(sc, ex):
    rs_o = next(o for o in sc.objs.values() if o.type.name == "RenderSettings")
    rs = sc.tt(rs_o)

    def col(k):
        return {"raw": rgba(rs[k]), "linear": lin_rgba(rgba(rs[k]))}

    sky_o, sky_st = sc.ref(sc.sf, rs["m_SkyboxMaterial"])
    sky = None
    if sky_o is not None:
        sm = read_material(sc, sky_o)
        sky = {k: v for k, v in sm.items() if k != "tex_envs"}
        sky["textures"] = {tn: {"status": te["status"], "has_texture": te["obj"] is not None} for tn, te in sm["tex_envs"].items()}
    info = {
        "ambient": {
            "mode": {0: "skybox", 1: "trilight", 3: "flat", 4: "custom"}.get(rs["m_AmbientMode"], rs["m_AmbientMode"]),
            "mode_raw": rs["m_AmbientMode"],
            "intensity": rs["m_AmbientIntensity"],
            "sky": col("m_AmbientSkyColor"),
            "equator": col("m_AmbientEquatorColor"),
            "ground": col("m_AmbientGroundColor"),
            "probe_sh_l0_rgb": [rs["m_AmbientProbe"]["sh[ 0]"], rs["m_AmbientProbe"]["sh[ 9]"], rs["m_AmbientProbe"]["sh[18]"]],
            "probe": [rs["m_AmbientProbe"][k] for k in sorted(rs["m_AmbientProbe"], key=lambda s: int(re.search(r"\d+", s).group()))],
        },
        "subtractive_shadow_color": col("m_SubtractiveShadowColor"),
        "fog": {"enabled": rs["m_Fog"], "mode": rs["m_FogMode"], "color": col("m_FogColor"), "density": rs["m_FogDensity"], "start": rs["m_LinearFogStart"], "end": rs["m_LinearFogEnd"]},
        "skybox_material": sky,
        "skybox_status": sky_st,
        "skybox_material_ref": [rs["m_SkyboxMaterial"]["m_FileID"], rs["m_SkyboxMaterial"]["m_PathID"]],
        "reflection": {"default_mode": rs["m_DefaultReflectionMode"], "intensity": rs["m_ReflectionIntensity"]},
        "sun_ref": rs["m_Sun"]["m_PathID"],
    }
    lights = light_infos(sc)
    info["lights"] = lights
    counts = {}
    for l in lights:
        counts[(l["type"], l["mode"])] = counts.get((l["type"], l["mode"]), 0) + 1
    info["light_counts"] = {f"{t}/{m}": n for (t, m), n in counts.items()}
    rt = [l for l in lights if l["type"] == "directional" and l["mode"] == "realtime" and l["enabled"] and l["active"]]
    info["main_light_id"] = rt[0]["id"] if rt else None
    kinds = {}
    for o in sc.objs.values():
        kinds[o.type.name] = kinds.get(o.type.name, 0) + 1
    info["object_types"] = kinds
    scripts = []
    for o in sc.objs.values():
        if o.type.name == "MonoBehaviour":
            try:
                scripts.append(o.read().m_Script.read().m_Name)
            except Exception as e:
                scripts.append(f"<unreadable {e!r}>")
    info["scripts"] = sorted(scripts)
    info["animated_objects"] = [o.type.name for o in sc.objs.values() if o.type.name in ("Animation", "Animator", "AnimationClip", "PlayableDirector")]
    parts = []
    for pid in sorted(sc.objs):
        o = sc.objs[pid]
        if o.type.name == "ParticleSystemRenderer":
            d = sc.tt(o)
            g = d["m_GameObject"]["m_PathID"]
            mats = []
            for mp in d["m_Materials"]:
                mo, st = sc.ref(sc.sf, mp)
                mats.append(sc.tt(mo)["m_Name"] if mo is not None else st)
            parts.append({"path": sc.go_path(g), "enabled": bool(d["m_Enabled"]), "active": sc.go_active(g), "materials": mats})
    info["particle_systems"] = parts
    info["ba_markers"] = ba_markers(sc)
    return info


def ba_markers(sc):
    out = {"collision_boxes": []}
    for pid in sorted(sc.go):
        n = sc.go[pid]["m_Name"]
        if n not in ("CanMoveArea", "CameraLookTarget", "LookTargetCamera", "RenderingArea", "RenderingAreaController", "Cam") and not n.startswith("Cube ("):
            continue
        W, q, pos = sc.world_trs(pid)
        fwd = quat_rotate(q, (0.0, 0.0, 1.0))
        e = {
            "position": to_gltf_vec(pos),
            "scale": [float(v) for v in np.linalg.norm(W[:3, :3], axis=0)],
            "forward": to_gltf_vec(fwd),
            "axis_x": to_gltf_vec(W[:3, 0] / np.linalg.norm(W[:3, 0])),
            "axis_y": to_gltf_vec(W[:3, 1] / np.linalg.norm(W[:3, 1])),
        }
        if n.startswith("Cube ("):
            e["half_extent_world_aabb"] = [float(v) for v in 0.5 * np.abs(W[:3, :3]).sum(axis=1)]
            out["collision_boxes"].append({"name": n, **e})
        else:
            out[n] = e
    for o in sc.objs.values():
        if o.type.name == "MonoBehaviour":
            d = sc.tt(o)
            if "forward" in d and "backward" in d:
                out["camera_constraint_area"] = {k: d[k] for k in ("left", "right", "forward", "backward")}
        if o.type.name == "Camera":
            d = sc.tt(o)
            out["native_camera"] = {"fov": d["field of view"], "near": d["near clip plane"], "far": d["far clip plane"], "hdr": bool(d["m_HDR"])}
    return out


def selfcheck(ex):
    doc, buf = read_glb(ex.out / f"{ex.variant}.glb")
    tris = 0
    agree = total = 0
    for me in doc["meshes"]:
        for p in me["primitives"]:
            tris += doc["accessors"][p["indices"]]["count"] // 3
    for g in ex.geo:
        if g["N"] is None:
            continue
        P, N, T = g["P"].astype(np.float64), g["N"].astype(np.float64), g["tri"]
        a, b, c = P[T[:, 0]], P[T[:, 1]], P[T[:, 2]]
        fn = np.cross(b - a, c - a)
        vn = N[T[:, 0]] + N[T[:, 1]] + N[T[:, 2]]
        area = np.linalg.norm(fn, axis=1)
        ok = area > 1e-12
        d = (fn[ok] * vn[ok]).sum(axis=1)
        agree += int((d > 0).sum())
        total += int(ok.sum())
    return {
        "triangles_in_glb": tris,
        "triangles_expected_from_source_submeshes": ex.expected_tris,
        "triangles_written": ex.exported_tris,
        "triangle_counts_match": tris == ex.expected_tris == ex.exported_tris,
        "face_vs_vertex_normal_agree": agree,
        "face_vs_vertex_normal_total": total,
        "face_vs_vertex_normal_fraction": agree / max(total, 1),
    }


def export(scene_bundle, out_dir, deps_dir):
    scene_bundle = Path(scene_bundle).resolve()
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    variant = scene_bundle.name.split("_mxload")[0]
    sc = Scene(scene_bundle, deps_dir)
    renderers, skipped = collect_renderers(sc)
    ex = Exporter(sc, variant, out)
    for r in renderers:
        ex.add_renderer(r)

    lm_o = next(o for o in sc.objs.values() if o.type.name == "LightmapSettings")
    lms = sc.tt(lm_o)
    used_lm = sorted({n["lightmap"] for n in ex.nodes_info if n["lightmap"] is not None})
    lightmaps = []
    for i, e in enumerate(lms["m_Lightmaps"]):
        to, st = sc.ref(lm_o.assets_file, e["m_Lightmap"])
        ent = {"index": i, "status": st, "referenced_by_renderers": i in used_lm, "id": sc.ids(to) if to is not None else None}
        if to is not None:
            t = to.read()
            raw = t.get_image_data()
            ent.update({"name": t.m_Name, "width": t.m_Width, "height": t.m_Height, "unity_format": int(t.m_TextureFormat), "mips": t.m_MipCount, "color_space": t.m_ColorSpace, "bytes": len(raw)})
            if ent["unity_format"] == 24 and i in used_lm:
                fn = f"{variant}_lm{i}.dds"
                write_dds_bc6h(out / fn, t.m_Width, t.m_Height, t.m_MipCount, raw)
                ent["file"] = fn
                ent.update(bc6h_mip0_stats(raw, t.m_Width, t.m_Height))
        lightmaps.append(ent)
    missing_lm = [i for i in used_lm if i >= len(lms["m_Lightmaps"])]

    ex.finish_gltf()
    (out / f"{variant}.materials.json").write_text(json.dumps(ex.materials_json(), indent=1) + "\n")
    check = selfcheck(ex)

    by_lm = {}
    for n in ex.nodes_info:
        k = "none" if n["lightmap"] is None else str(n["lightmap"])
        by_lm[k] = by_lm.get(k, 0) + 1
    mesh_ids = {}
    for n in ex.nodes_info:
        mesh_ids[n["mesh_id"]] = mesh_ids.get(n["mesh_id"], 0) + 1
    info = {
        "variant": variant,
        "source_bundle": scene_bundle.name,
        "unity_version": sc.sf.unity_version if hasattr(sc.sf, "unity_version") else None,
        "conventions": "glTF: X mirrored vs Unity, winding reversed, V = 1 - v on TEXCOORD_0 and TEXCOORD_1. DDS lightmaps keep Unity row order: sample at vec2(UV2.x, 1.0 - UV2.y). UV2 already contains the lightmap scale/offset.",
        "lightmaps": lightmaps,
        "lightmaps_missing_for_renderers": missing_lm,
        "renderers_exported_by_lightmap_index": by_lm,
        "renderers_exported": len(ex.nodes_info),
        "renderer_shadow_flags": {f"cast={r['cast_shadows']} receive={r['receive_shadows']} layer={r['layer']}": sum(1 for q in renderers if (q["cast_shadows"], q["receive_shadows"], q["layer"]) == (r["cast_shadows"], r["receive_shadows"], r["layer"])) for r in renderers},
        "renderers_skipped": skipped,
        "unresolved": ex.unresolved,
        "combined_meshes_used": mesh_ids,
        "notes": ex.notes,
        "selfcheck": check,
        "scene": scene_info(sc, ex),
        "nodes": ex.nodes_info,
    }
    (out / f"{variant}.json").write_text(json.dumps(info, indent=1) + "\n")
    return ex, info


if __name__ == "__main__":
    if len(sys.argv) < 4:
        sys.exit("usage: scene_to_glb.py <variant scene bundle> <out dir> <deps dir> [--lane lane_x,z_centre | --no-lane]")
    ex, info = export(sys.argv[1], sys.argv[2], sys.argv[3])
    if "--no-lane" in sys.argv:
        print(json.dumps({k: info[k] for k in ("variant", "renderers_exported", "selfcheck", "unresolved", "notes")}))
        sys.exit(0 if info["selfcheck"]["triangle_counts_match"] and not info["unresolved"] else 1)
    lane = None
    if "--lane" in sys.argv:
        lx, lz = sys.argv[sys.argv.index("--lane") + 1].split(",")
        lane = {"lane_x": float(lx), "z_centre": float(lz)}
    import lane_analysis

    try:
        lane_analysis.analyse(sys.argv[2], lane)
    except (AssertionError, KeyError, StopIteration) as e:
        print("lane analysis failed:", repr(e))
        sys.exit(2)
    print(json.dumps({k: info[k] for k in ("variant", "renderers_exported", "renderers_exported_by_lightmap_index", "selfcheck", "unresolved", "notes")}, indent=1))
    if not info["selfcheck"]["triangle_counts_match"] or info["unresolved"]:
        sys.exit(1)
