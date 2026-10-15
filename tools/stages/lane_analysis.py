#!/usr/bin/env python
import json
import math
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import scene_to_glb as s2g
import verify_topdown as vt

FOV, PITCH, PX_PER_UNIT, FEET_ROW, VIEW_H, VIEW_W = 40.0, 5.0, 210.0, 612.0, 720.0, 1280.0
ZOOMS = (0.7, 1.0, 1.24)
RES = 0.1
FLAT_TOL = 0.05
MIN_FLAT_LEN = 16.0
PAN = 1.5
Z_HALF = 12.0


def camera_pose(zoom):
    th = math.tan(math.radians(FOV / 2))
    d = VIEW_H / (2 * th * PX_PER_UNIT * zoom)
    yc = -((FEET_ROW - VIEW_H / 2) / (VIEW_H / 2)) * th * d
    p = math.radians(PITCH)
    horiz = d * math.cos(p) + yc * math.sin(p)
    vert = -d * math.sin(p) + yc * math.cos(p)
    bottom_ray = math.radians(PITCH + FOV / 2)
    height = -vert
    return {
        "zoom": zoom,
        "distance_along_axis": d,
        "horizontal_to_lane": horiz,
        "height_above_ground": height,
        "lane_depth_visible_width_units": 2 * d * th * VIEW_W / VIEW_H,
        "floor_visible_from_dx": horiz - height / math.tan(bottom_ray),
    }


def world_triangles(out, variant):
    doc, buf = s2g.read_glb(out / f"{variant}.glb")
    mats = json.load(open(out / f"{variant}.materials.json"))["materials"]

    def acc(k):
        a = doc["accessors"][k]
        v = doc["bufferViews"][a["bufferView"]]
        dt = {5126: "<f4", 5123: "<u2", 5125: "<u4"}[a["componentType"]]
        nc = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
        return np.frombuffer(buf, dtype=dt, count=a["count"] * nc, offset=v["byteOffset"]).reshape(-1, nc)

    solid = []
    for n in doc["nodes"][1:]:
        for p in doc["meshes"][n["mesh"]]["primitives"]:
            mn = doc["materials"][p["material"]]["name"]
            if mats[mn]["shader"] in ("MX/VertexColor", "FX/General Unlit Texture") or "_ENV_ALPHA_MODE" in mats[mn]["keywords"]:
                continue
            P = acc(p["attributes"]["POSITION"]).astype(np.float64)
            if "translation" in n:
                R = s2g.quat_to_mat(tuple(n["rotation"]))
                P = (P * np.array(n["scale"])) @ R.T + np.array(n["translation"])
            assert "matrix" not in n
            solid.append(P[acc(p["indices"]).reshape(-1, 3).astype(np.int64)])
    return np.concatenate(solid)


def runs(col):
    out, s = [], None
    for i, v in enumerate(np.r_[col, False]):
        if v and s is None:
            s = i
        if not v and s is not None:
            out.append((s, i))
            s = None
    return out


def analyse(out_dir, override=None):
    out = Path(out_dir)
    variant = next(out.glob("*.glb")).stem
    info = json.load(open(out / f"{variant}.json"))
    mk = info["scene"]["ba_markers"]
    if override:
        z_centre, lane_x = round(override["z_centre"], 2), round(override["lane_x"], 2) + 0.0
    else:
        cma = mk["CanMoveArea"]
        long_axis = "z" if abs(cma["axis_x"][2]) > 0.5 else "x"
        assert long_axis == "z", "lane code assumes a Z lane"
        z_centre = round(mk["CameraLookTarget"]["position"][2], 2)
        lane_x = round(cma["position"][0], 2) + 0.0

    grid = dict(x0=float(round(lane_x - 30.0)), z0=float(round(z_centre - 70.0)), w=int(70 / RES), h=int(125 / RES))
    T = world_triangles(out, variant)
    nrm = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
    area = np.linalg.norm(nrm, axis=1)
    ny = nrm[:, 1] / np.maximum(area, 1e-12)
    g = grid
    zeros = lambda n: np.zeros((n, 3, 2))
    up = ny > 0.5
    vt.RES = RES
    _, _, top = vt.raster(T[up], zeros(up.sum()), zeros(up.sum()), g["x0"], g["z0"], g["w"], g["h"])
    xs = g["x0"] + (np.arange(g["w"]) + 0.5) * RES
    zs = g["z0"] + (np.arange(g["h"]) + 0.5) * RES

    flat = ny > 0.99
    hist, edges = np.histogram(T[flat][:, :, 1].mean(1), bins=np.arange(-1, 6, 0.01), weights=area[flat] / 2)
    ground = round(float(edges[np.argmax(hist)] + 0.005), 1) + 0.0
    covered = top > -1e8
    flatmask = covered & (np.abs(top - ground) < FLAT_TOL + 0.01)

    ix = int(np.argmin(np.abs(xs - lane_x)))
    zi = int(np.argmin(np.abs(zs - z_centre)))
    run = next((r for r in runs(flatmask[:, ix]) if r[0] <= zi < r[1]), None)
    flat_z = [float(zs[run[0]]), float(zs[run[1] - 1])]

    band = (zs >= z_centre - Z_HALF) & (zs <= z_centre + Z_HALF)
    colflat = flatmask[band].all(axis=0)
    cr = next(r for r in runs(colflat) if r[0] <= ix < r[1])
    corridor_x = [float(xs[cr[0]]), float(xs[cr[1] - 1])]


    down = (ny < -0.2) & (T[:, :, 1].min(1) > 0.3)
    Td = T[down].copy()
    Td[:, :, 1] *= -1
    win, _, neg = vt.raster(Td, zeros(len(Td)), zeros(len(Td)), g["x0"], g["z0"], g["w"], g["h"])
    low = np.where(win >= 0, -neg, np.inf)
    strip = (xs >= lane_x - 1) & (xs <= lane_x + 1)
    lowz = low[:, strip].min(axis=1)
    clear6 = runs(lowz >= 6.0)
    zr = next((r for r in clear6 if r[0] <= zi < r[1]), None)
    clear_z = [float(zs[zr[0]]), float(zs[zr[1] - 1])] if zr else None
    headroom_here = float(lowz[(zs >= z_centre - Z_HALF) & (zs <= z_centre + Z_HALF)].min())
    headroom_here = None if math.isinf(headroom_here) else headroom_here

    cams = {str(z): camera_pose(z) for z in ZOOMS}
    cam1 = cams["1.0"]
    cam_x_far = lane_x - cams["0.7"]["horizontal_to_lane"]
    floor_x_far = lane_x - cams["0.7"]["floor_visible_from_dx"]


    tall = covered & (top > ground + 0.15)
    XX, ZZ = np.meshgrid(xs, zs)
    hits = np.zeros_like(tall)
    tan_h = math.tan(math.radians(FOV / 2)) * VIEW_W / VIEW_H
    for c in cams.values():
        cx, cy = lane_x - c["horizontal_to_lane"], ground + c["height_above_ground"]
        dx = XX - cx
        for pan in (-PAN, 0.0, PAN):
            inside = (dx > 0.05) & (XX < lane_x - 0.3) & (np.abs(ZZ - (z_centre + pan)) <= dx * tan_h)
            bottom_ray = cy - dx * math.tan(math.radians(PITCH + FOV / 2))
            hits |= tall & inside & (top > bottom_ray)
    occ_x = XX[hits]
    occ_max = float(occ_x.max()) if len(occ_x) else None
    clip_x = None if occ_max is None else min(occ_max + 0.3, floor_x_far - 0.2)


    fb = (xs > lane_x + 0.5) & (xs <= lane_x + 14)
    far_tall = float(np.percentile(top[np.ix_(band, fb)][covered[np.ix_(band, fb)]], 90))

    lane = {
        "axis": "+Z",
        "centre": [lane_x, ground, z_centre],
        "ground_y": ground,
        "flat_z_range_at_lane_x": flat_z,
        "flat_length": flat_z[1] - flat_z[0],
        "flat_corridor_x_range_over_z_band": corridor_x,
        "z_band": [z_centre - Z_HALF, z_centre + Z_HALF],
        "min_flat_length_required": MIN_FLAT_LEN,
        "headroom_min_over_z_band_m": headroom_here,
        "z_range_with_6m_headroom_over_strip": clear_z,
        "sources": {
            "lane_x": "maps.json lane override" if override else "CanMoveArea centre x (BA's walkable quad is 16 wide in x, 75 long in z)",
            "z_centre": "maps.json lane override" if override else "CameraLookTarget z (BA's own battle look target)",
            "flat_floor": f"top-surface heightmap at {RES} m, cells within {FLAT_TOL} m of ground level",
        },
    }
    camera = {
        "fov_vertical": FOV,
        "pitch_down_deg": PITCH,
        "px_per_unit_zoom1": PX_PER_UNIT,
        "feet_row_of_720": FEET_ROW,
        "look_direction": "+X",
        "side": "-X (screen right is +Z)",
        "godot_rotation_degrees": [-PITCH, -90.0, 0.0],
        "position_at_zoom": {z: [lane_x - c["horizontal_to_lane"], ground + c["height_above_ground"], z_centre] for z, c in cams.items()},
        "poses": cams,
        "ba_native_camera": {"position": mk["Cam"]["position"], "forward": mk["Cam"]["forward"], "fov": mk["native_camera"]["fov"]} if "Cam" in mk else None,
        "far_side_90th_percentile_height_m": far_tall,
    }
    clip = {
        "plane": "world x >= clip_x is kept",
        "clip_x": clip_x,
        "nearest_visible_near_side_occluder_x": occ_max,
        "safe_x_range_if_used": [cam_x_far, floor_x_far - 0.2],
        "note": "needed is false when no tall cell lies inside the camera frustum for zooms 0.7 to 1.24 and a +-1.5 slide; any x in safe_x_range_if_used never cuts visible floor",
        "floor_first_visible_x_at_zoom_0.7": floor_x_far,
        "camera_x_at_zoom_0.7": cam_x_far,
        "needed": occ_max is not None,
    }


    main = next(l for l in info["scene"]["lights"] if l["id"] == info["scene"]["main_light_id"])
    p = math.radians(PITCH)
    right, up_v, fwd = np.array([0.0, 0.0, 1.0]), np.array([math.sin(p), math.cos(p), 0.0]), np.array([math.cos(p), -math.sin(p), 0.0])

    def view_dir(travel):
        to_light = -np.array(travel)
        return [float(to_light @ right), float(to_light @ up_v), float(to_light @ -fwd)]

    amb = info["scene"]["ambient"]
    baked = [l for l in info["scene"]["lights"] if l["type"] == "directional" and l["mode"] == "baked"]
    ld = {
        "convention": "to-light unit vector in camera view space: x right, y up, z toward the viewer",
        "key_color_raw": main["color_raw"][:3],
        "key_color_linear": main["color_linear"][:3],
        "key_intensity": main["intensity"],
        "key_travel_gltf": main["forward_gltf"],
        "key_dir_view": view_dir(main["forward_gltf"]),
        "key_shadow_strength": main["shadow_strength"],
        "key_culling_mask": main["culling_mask"],
        "ambient_mode": amb["mode"],
        "ambient_intensity": amb["intensity"],
        "ambient_sky_raw": amb["sky"]["raw"][:3],
        "ambient_sky_linear": amb["sky"]["linear"][:3],
        "ambient_equator_raw": amb["equator"]["raw"][:3],
        "ambient_equator_linear": amb["equator"]["linear"][:3],
        "ambient_ground_raw": amb["ground"]["raw"][:3],
        "ambient_ground_linear": amb["ground"]["linear"][:3],
        "ambient_probe_l0_rgb": amb["probe_sh_l0_rgb"],
        "subtractive_shadow_raw": info["scene"]["subtractive_shadow_color"]["raw"][:3],
        "subtractive_shadow_linear": info["scene"]["subtractive_shadow_color"]["linear"][:3],
        "baked_sun_travel_gltf": baked[0]["forward_gltf"] if baked else None,
        "baked_sun_dir_view": view_dir(baked[0]["forward_gltf"]) if baked else None,
        "baked_sun_color_raw": baked[0]["color_raw"][:3] if baked else None,
        "night": variant.endswith("_n"),
    }
    info["lane"], info["camera"], info["clip"], info["light_descriptor"] = lane, camera, clip, ld
    (out / f"{variant}.json").write_text(json.dumps(info, indent=1, allow_nan=False) + "\n")
    return lane, camera, clip, ld


if __name__ == "__main__":
    lane, camera, clip, ld = analyse(sys.argv[1])
    print(json.dumps({"lane": lane, "clip": clip, "light_descriptor": ld, "camera_pos": camera["position_at_zoom"], "far90": camera["far_side_90th_percentile_height_m"]}, indent=1))
