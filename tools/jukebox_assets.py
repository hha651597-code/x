#!/usr/bin/env python3
"""The jukebox's album art -> assets/ba/jukebox: the Blue Archive Original Soundtrack covers of the volumes our 14 tracks are on
(512x512 JPEG), a generic cover for a track that is on none of them, albums.json (which track is on which album) and PROVENANCE.json.

The covers come from the Blue Archive wiki's file host (https://bluearchive.wiki/wiki/Blue_Archive_Original_Soundtrack lists the
volumes, their tracks and these file paths). PACHAD is not on that page, so it has no album here and gets the generic cover.

usage: python3 -I tools/jukebox_assets.py [--cache DIR]      (stdlib and Pillow; downloads about 7 MB unless the cache has them)"""
import argparse
import hashlib
import json
import urllib.request
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/ba/jukebox"
HOST = "https://static.wikitide.net/bluearchivewiki/"
SIZE = 512
# volume -> (wiki file path, name, subtitle)
ALBUMS = {
    "vol1": ("f/f2/Blue_Archive_Original_Soundtrack_Vol.1_%EF%BD%9ELonging_for_the_Memorable_Days%EF%BD%9E.jpg",
             "Blue Archive Original Soundtrack Vol.1", "Longing for the Memorable Days"),
    "vol3": ("e/e6/Blue_Archive_Original_Soundtrack_Vol.3_%EF%BD%9EReaching_for_the_precious_time%EF%BD%9E.jpg",
             "Blue Archive Original Soundtrack Vol.3", "Reaching for the Precious Time"),
    "vol4": ("7/7d/Blue_Archive_Original_Soundtrack_Vol.4_%EF%BD%9EAiming_for_the_ideal_freedom%EF%BD%9E.jpg",
             "Blue Archive Original Soundtrack Vol.4", "Aiming for the Ideal Freedom"),
    "vol5": ("a/af/Blue_Archive_Original_Soundtrack_Vol.5_%EF%BD%9EStriving_for_the_bloomy_festival%EF%BD%9E.jpg",
             "Blue Archive Original Soundtrack Vol.5", "Striving for the Bloomy Festival"),
    "vol7": ("a/a7/Blue_Archive_Original_Soundtrack_Vol.7_%EF%BD%9EHarmonizing_for_the_Hearts_of_Each%EF%BD%9E.jpg",
             "Blue Archive Original Soundtrack Vol.7", "Harmonizing for the Hearts of Each"),
}
# Bgm track id -> volume, from the wiki page's tracklists; None where the page does not list the track
TRACKS = {
    "constant-moderato": "vol1", "signal-of-abydos": "vol1", "mechanical-jungle": "vol1", "virtual-storm": "vol1", "alert": "vol1",
    "crossfire": "vol1", "out-of-control": "vol1", "aoharu": "vol3", "unwelcome-school": "vol4", "final-destination-of-ark": "vol4",
    "step-of-terror": "vol4", "dark-shadows": "vol5", "fury-of-set": "vol7", "pachad": None,
}
GENERIC = ("Blue Archive Original Soundtrack", "")


def sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def fetch(path: str, cache: Path) -> bytes:
    f = cache / path.replace("/", "_")
    if f.exists():
        return f.read_bytes()
    req = urllib.request.Request(HOST + path, headers={"User-Agent": "Mozilla/5.0"})
    data = urllib.request.urlopen(req, timeout=60).read()
    cache.mkdir(parents=True, exist_ok=True)
    f.write_bytes(data)
    return data


def generic_cover() -> Image.Image:
    """A navy to sky card with the Blue Archive logo, for tracks on no listed volume and for AUTO."""
    img = Image.new("RGB", (SIZE, SIZE))
    d = ImageDraw.Draw(img)
    top, bot = (46, 152, 254), (167, 229, 254)   # BaTokens.SKY_TOP and SKY_BOT
    for y in range(SIZE):
        t = y / (SIZE - 1)
        d.line([(0, y), (SIZE, y)], fill=tuple(round(top[i] + (bot[i] - top[i]) * t) for i in range(3)))
    logo = Image.open(ROOT / "assets/ba/title/Title_Logo.png").convert("RGBA")
    w = int(SIZE * 0.82)
    logo = logo.resize((w, w * logo.height // logo.width), Image.LANCZOS)
    img.paste(logo, ((SIZE - w) // 2, (SIZE - logo.height) // 2), logo)
    return img


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cache", default="/tmp/ba-jukebox-cache")
    a = ap.parse_args()
    cache = Path(a.cache)
    OUT.mkdir(parents=True, exist_ok=True)
    prov, albums = {}, {}
    for vol, (path, name, sub) in ALBUMS.items():
        raw = fetch(path, cache)
        out = OUT / (vol + ".jpg")
        Image.open(__import__("io").BytesIO(raw)).convert("RGB").resize((SIZE, SIZE), Image.LANCZOS).save(out, quality=90, optimize=True)
        prov[out.name] = {"source": HOST + path, "source_sha256": sha(raw), "derived_from": "tools/jukebox_assets.py: scaled to %dx%d, JPEG q90" % (SIZE, SIZE),
                          "sha256": sha(out.read_bytes())}
        albums[vol] = {"name": name, "subtitle": sub, "cover": out.name}
    gen = OUT / "generic.jpg"
    generic_cover().save(gen, quality=92, optimize=True)
    prov[gen.name] = {"source": "assets/ba/title/Title_Logo.png on BaTokens.SKY_TOP to SKY_BOT", "derived_from": "tools/jukebox_assets.py generic_cover()", "sha256": sha(gen.read_bytes())}
    albums["generic"] = {"name": GENERIC[0], "subtitle": GENERIC[1], "cover": gen.name}
    (OUT / "albums.json").write_text(json.dumps({"albums": albums, "tracks": TRACKS}, indent=1) + "\n")
    (OUT / "PROVENANCE.json").write_text(json.dumps(prov, indent=1, sort_keys=True) + "\n")
    print("wrote", len(prov), "images to", OUT)


if __name__ == "__main__":
    main()
