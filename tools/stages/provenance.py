import hashlib
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def converter_tree():
    try:
        out = subprocess.run(["git", "rev-parse", "HEAD:tools/stages"], cwd=ROOT, capture_output=True, text=True, check=True)
        tree = out.stdout.strip()
        if subprocess.run(["git", "diff", "--quiet", "HEAD", "--", "tools/stages"], cwd=ROOT).returncode != 0:
            tree += "-dirty"
        return tree
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def collect(src_dirs, index_path):
    idx = json.load(open(index_path))["bundles"]
    rel = {}
    for r in sorted(idx):
        rel.setdefault(Path(r).name, r)
    seen = {}
    for d in sorted(src_dirs):
        for p in sorted(Path(d).glob("*.bundle")):
            if p.name not in seen:
                seen[p.name] = {"file": p.name, "sha256": sha256(p), "bytes": p.stat().st_size, "install_path": rel.get(p.name)}
    return [seen[k] for k in sorted(seen)]


def write(stage_id, src_dirs, index_path, out_path, scenes):
    doc = {
        "stage": stage_id,
        "scenes": sorted(scenes),
        "converter_tree": converter_tree(),
        "install": "BlueArchive_Data, read only, bundles copied out and never modified",
        "bundles": collect(src_dirs, index_path),
    }
    Path(out_path).write_text(json.dumps(doc, indent=1) + "\n")
    return doc


if __name__ == "__main__":
    if len(sys.argv) < 6:
        sys.exit("usage: provenance.py <stage id> <cab index json> <out json> <scene,...> <bundle dir>...")
    d = write(sys.argv[1], sys.argv[5:], sys.argv[2], sys.argv[3], sys.argv[4].split(","))
    print(len(d["bundles"]), "bundles")
