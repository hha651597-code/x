import struct
import imagecodecs
import numpy as np


def load_dds_bc6h(path):
    d = open(path, "rb").read()
    h, w, mips = struct.unpack_from("<III", d, 12)[0], struct.unpack_from("<I", d, 16)[0], struct.unpack_from("<I", d, 28)[0]
    assert d[84:88] == b"DX10", "not a DX10 dds"
    fmt = struct.unpack_from("<I", d, 128)[0]
    assert fmt == 95, fmt
    raw = d[148:]
    mip0 = raw[: ((w + 3) // 4) * ((h + 3) // 4) * 16]
    px = imagecodecs.bcn_decode(mip0, 6, shape=(h, w, 3)).astype(np.float32)
    return px


def box_down(px, k):
    h, w, _ = px.shape
    return px[: h // k * k, : w // k * k].reshape(h // k, k, w // k, k, 3).mean(axis=(1, 3))


def sample(px, u, v_unity):
    h, w, _ = px.shape
    x = np.clip(u * w - 0.5, 0, w - 1.0001)
    y = np.clip(v_unity * h - 0.5, 0, h - 1.0001)
    x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int)
    fx, fy = (x - x0)[:, None], (y - y0)[:, None]
    return (px[y0, x0] * (1 - fx) * (1 - fy) + px[y0, x0 + 1] * fx * (1 - fy) + px[y0 + 1, x0] * (1 - fx) * fy + px[y0 + 1, x0 + 1] * fx * fy)


def bake_vertices(px, uv2):
    return sample(px, uv2[:, 0], 1.0 - uv2[:, 1])
