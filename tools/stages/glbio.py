import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import scene_to_glb as S

CT = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def acc(doc, buf, i):
    a = doc["accessors"][i]
    v = doc["bufferViews"][a["bufferView"]]
    n = NC[a["type"]]
    arr = np.frombuffer(buf, CT[a["componentType"]], a["count"] * n, v["byteOffset"] + a.get("byteOffset", 0))
    return arr.reshape(a["count"], n) if n > 1 else arr


def node_matrix(n):
    m = np.eye(4)
    if "matrix" in n:
        return np.array(n["matrix"]).reshape(4, 4).T
    t = n.get("translation", [0, 0, 0]); q = n.get("rotation", [0, 0, 0, 1]); s = n.get("scale", [1, 1, 1])
    m[:3, :3] = S.quat_to_mat(q) * np.array(s)[None, :]
    m[:3, 3] = t
    return m


class Glb:
    def __init__(self, path):
        self.doc, self.buf = S.read_glb(path)
        self.nodes = {n["name"]: n for n in self.doc["nodes"] if "mesh" in n}

    def prims(self, name):
        n = self.nodes[name]
        W = node_matrix(n)
        for p in self.doc["meshes"][n["mesh"]]["primitives"]:
            at = p["attributes"]
            P = acc(self.doc, self.buf, at["POSITION"]).astype(np.float64)
            P = (np.c_[P, np.ones(len(P))] @ W.T)[:, :3]
            d = {"P": P, "idx": acc(self.doc, self.buf, p["indices"]).astype(np.int64).reshape(-1, 3), "material": self.doc["materials"][p["material"]]["name"]}
            if "NORMAL" in at:
                N = acc(self.doc, self.buf, at["NORMAL"]).astype(np.float64)
                N = N @ np.linalg.inv(W[:3, :3])
                d["N"] = N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)
            for k, a in (("UV0", "TEXCOORD_0"), ("UV1", "TEXCOORD_1"), ("COL", "COLOR_0")):
                if a in at:
                    d[k] = acc(self.doc, self.buf, at[a]).astype(np.float64)
            yield d
