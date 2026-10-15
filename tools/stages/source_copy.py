import fnmatch
import json
import os
import re
import shutil
import sys
from pathlib import Path

import UnityPy

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import cab_index

UnityPy.config.FALLBACK_UNITY_VERSION = "2021.3.56f2"


class Index:
    def __init__(self, data_dir, cache):
        self.root = Path(data_dir)
        self.idx = cab_index.load_or_build(str(self.root), str(cache))["bundles"]
        self.cab2b = {}
        for b in sorted(self.idx):
            for n, _ in self.idx[b]:
                if n.startswith("CAB-"):
                    self.cab2b[n.lower().split(".")[0]] = b

    def externals(self, rel):
        env = UnityPy.load(str(self.root / rel))
        out = set()
        for f in env.files.values():
            for sf in f.files.values():
                for e in getattr(sf, "externals", []):
                    m = re.search(r"(CAB-[0-9a-f]{32})", e.path)
                    if m:
                        out.add(m.group(1))
        return sorted(out)

    def scene(self, name):
        hits = sorted(b for b in self.idx if os.path.basename(b).startswith(name + "_mxload"))
        if not hits:
            raise SystemExit(f"no scene bundle for {name}")
        return hits[0]

    def closure(self, rels):
        seen = set(rels)
        stack = sorted(rels)
        missing = {}
        while stack:
            b = stack.pop()
            own = {n.lower().split(".")[0] for n, _ in self.idx[b]}
            for cab in self.externals(b):
                if cab.lower() in own:
                    continue
                t = self.cab2b.get(cab.lower())
                if t is None:
                    missing[cab] = b
                elif t not in seen:
                    seen.add(t)
                    stack.append(t)
        return sorted(seen), missing

    def glob(self, pattern):
        return sorted(b for b in self.idx if fnmatch.fnmatch(os.path.basename(b), pattern))


def copy_all(index, rels, dest):
    dest = Path(dest)
    dest.mkdir(parents=True, exist_ok=True)
    for b in sorted(rels):
        d = dest / os.path.basename(b)
        if not d.exists():
            shutil.copyfile(index.root / b, d)
    return sorted(p.name for p in dest.glob("*.bundle"))


def unit(index, scenes, patterns, dest):
    rels = [index.scene(n) for n in scenes]
    closure, missing = index.closure(rels)
    extra = []
    for pat in patterns:
        hits = index.glob(pat)
        if not hits:
            raise SystemExit(f"no bundle matches {pat}")
        extra += hits
    names = copy_all(index, sorted(set(closure) | set(extra)), dest)
    return names, missing


def main():
    if len(sys.argv) < 5:
        sys.exit("usage: source_copy.py <BlueArchive_Data dir> <cab index cache> <dest dir> <scene name,...> [bundle glob ...]")
    index = Index(sys.argv[1], sys.argv[2])
    scenes = [s for s in sys.argv[4].split(",") if s]
    names, missing = unit(index, scenes, sys.argv[5:], sys.argv[3])
    print(json.dumps({"bundles": len(names), "missing": missing}))
    if missing:
        sys.exit(1)


if __name__ == "__main__":
    main()
