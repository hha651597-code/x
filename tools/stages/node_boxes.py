import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import scene_to_glb as S


def node_matrix(n):
    if "matrix" in n:
        return np.array(n["matrix"]).reshape(4, 4).T
    m = np.eye(4)
    m[:3, :3] = S.quat_to_mat(n.get("rotation", [0, 0, 0, 1])) * np.array(n.get("scale", [1, 1, 1]))[None, :]
    m[:3, 3] = n.get("translation", [0, 0, 0])
    return m


def boxes(glb_path):
    doc, _ = S.read_glb(glb_path)
    rows = []
    for n in doc["nodes"]:
        if "mesh" not in n:
            continue
        W = node_matrix(n)
        lo, hi, used = np.full(3, np.inf), np.full(3, -np.inf), set()
        for p in doc["meshes"][n["mesh"]]["primitives"]:
            a = doc["accessors"][p["attributes"]["POSITION"]]
            corners = np.array([[x, y, z, 1.0] for x in (a["min"][0], a["max"][0]) for y in (a["min"][1], a["max"][1]) for z in (a["min"][2], a["max"][2])])
            w = (W @ corners.T).T[:, :3]
            lo, hi = np.minimum(lo, w.min(0)), np.maximum(hi, w.max(0))
            if "material" in p:
                used.add(doc["materials"][p["material"]]["name"])
        rows.append({"node": n["name"], "lo": lo.round(3).tolist(), "hi": hi.round(3).tolist(), "materials": sorted(used)})
    return rows


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: node_boxes.py <glb> <out json>")
    json.dump(boxes(sys.argv[1]), open(sys.argv[2], "w"))
