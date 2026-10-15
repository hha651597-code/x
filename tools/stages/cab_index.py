import json
import lzma
import os
import struct
import sys
from concurrent.futures import ThreadPoolExecutor

import lz4.block


def cstr(b, o):
    e = b.index(b"\0", o)
    return b[o:e].decode("utf-8", "replace"), e + 1


def block_info(path):
    with open(path, "rb") as f:
        head = f.read(512)
        if not head.startswith(b"UnityFS\0"):
            return None
        o = 8
        ver = struct.unpack_from(">I", head, o)[0]; o += 4
        _, o = cstr(head, o)
        _, o = cstr(head, o)
        size, csize, usize, flags = struct.unpack_from(">qIII", head, o); o += 20
        if ver >= 7:
            o = (o + 15) & ~15
        if flags & 0x80:
            f.seek(-csize, 2)
        else:
            f.seek(o)
        raw = f.read(csize)
    comp = flags & 0x3F
    if comp == 0:
        data = raw
    elif comp in (2, 3):
        data = lz4.block.decompress(raw, uncompressed_size=usize)
    elif comp == 1:
        props = raw[0]
        lc, lp, pb = props % 9, (props // 9) % 5, props // 45
        dict_size = struct.unpack_from("<I", raw, 1)[0]
        d = lzma.LZMADecompressor(format=lzma.FORMAT_RAW, filters=[{"id": lzma.FILTER_LZMA1, "dict_size": dict_size, "lc": lc, "lp": lp, "pb": pb}])
        data = d.decompress(raw[5:], max_length=usize)
    else:
        return None
    o = 16
    nb = struct.unpack_from(">i", data, o)[0]; o += 4 + nb * 10
    nn = struct.unpack_from(">i", data, o)[0]; o += 4
    nodes = []
    for _ in range(nn):
        off, sz, fl = struct.unpack_from(">qqI", data, o); o += 20
        name, o = cstr(data, o)
        nodes.append([name, sz])
    return nodes


def one(path):
    try:
        return path, block_info(path), None
    except Exception as e:
        return path, None, repr(e)


def build(root):
    paths = []
    for dp, dn, fs in os.walk(root):
        dn.sort()
        for fn in sorted(fs):
            if fn.endswith(".bundle"):
                paths.append(os.path.join(dp, fn))
    idx, errs = {}, {}
    with ThreadPoolExecutor(8) as ex:
        for p, nodes, err in ex.map(one, paths):
            if err:
                errs[os.path.relpath(p, root)] = err
            elif nodes:
                idx[os.path.relpath(p, root)] = nodes
    return {"bundles": idx, "errors": errs}


def load_or_build(root, cache):
    if os.path.exists(cache):
        return json.load(open(cache))
    data = build(root)
    os.makedirs(os.path.dirname(cache), exist_ok=True)
    json.dump(data, open(cache, "w"))
    return data


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: cab_index.py <BlueArchive_Data dir> <out json>")
    d = build(sys.argv[1])
    json.dump(d, open(sys.argv[2], "w"))
    print(len(d["bundles"]), "indexed", len(d["errors"]), "errors")
