import math

import numpy as np


def solve(lane, cam, cam_x=0.0, zoom=1.0, shake=(0.0, 0.0), lift=0.0):
    ppu = cam["px_per_unit"]
    half_h = cam["view"][1] / 2.0
    f = half_h / math.tan(math.radians(cam["fov"] / 2))
    d = f / (ppu * zoom)
    py = cam["feet_row"] + lift * zoom + shake[1] - half_h
    a = math.atan(py / f)
    dist = d / math.cos(a)
    pitch = math.radians(cam["pitch"])
    el = pitch + a
    up = np.array(lane["up"], dtype=float)
    axis = np.array(lane["axis"], dtype=float)
    face = np.cross(up, axis)
    pos = np.array(lane["origin"], dtype=float) + axis * (cam_x / ppu) - axis * (shake[0] / (ppu * zoom)) - face * (dist * math.cos(el)) + up * (dist * math.sin(el))
    forward = face * math.cos(pitch) - up * math.sin(pitch)
    cam_up = up * math.cos(pitch) + face * math.sin(pitch)
    return pos, forward, cam_up


def ray(lane, cam, cam_x, zoom, px, py):
    pos, fwd, cup = solve(lane, cam, cam_x, zoom)
    axis = np.array(lane["axis"], dtype=float)
    half_h = cam["view"][1] / 2.0
    th = math.tan(math.radians(cam["fov"] / 2))
    v = fwd + ((px - cam["view"][0] / 2) / half_h * th) * axis + (-(py - half_h) / half_h * th) * cup
    return pos, v / np.linalg.norm(v)
