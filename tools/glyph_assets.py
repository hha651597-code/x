#!/usr/bin/env python3
"""Rebuild assets/glyphs from Kenney's Input Prompts pack (CC0).

usage: ~/Tools/venv-sprites/bin/python -I tools/glyph_assets.py KENNEY_ROOT [ZIP]
  KENNEY_ROOT  the unzipped pack (the folder holding License.txt)
  ZIP          the downloaded archive, only to record its sha256

Download: https://kenney.nl/assets/input-prompts (kenney_input-prompts_1.5.zip). Read-only on the pack.
Writes assets/glyphs/<family>/<action>.png, keyboard/<key>.png, bodies/<family>.svg, LICENSE.txt and PROVENANCE.json.
"""
import hashlib
import json
import re
import shutil
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "glyphs"
PAGE = "https://kenney.nl/assets/input-prompts"
# Godot's JOY_BUTTON_A is the south button on every pad, so an action maps to a POSITION and each family
# supplies its own printed glyph there (Cross on PlayStation, B on Switch).
FAMILIES = {
    "xbox": ("Xbox Series", "xbox", "controller_xboxseries", {
        "confirm": "button_a", "back": "button_b", "aux": "button_x", "aux2": "button_y", "lb": "lb", "rb": "rb",
        "start": "button_menu", "dpad": "dpad", "stick_l": "stick_l"}),
    "playstation": ("PlayStation Series", "playstation", "controller_playstation5", {
        "confirm": "button_cross", "back": "button_circle", "aux": "button_square", "aux2": "button_triangle",
        "lb": "trigger_l1", "rb": "trigger_r1", "start": "5_button_options", "dpad": "dpad", "stick_l": "stick_l"}),
    "switch": ("Nintendo Switch", "switch", "controller_switch_pro", {
        "confirm": "button_b", "back": "button_a", "aux": "button_y", "aux2": "button_x", "lb": "button_l", "rb": "button_r",
        "start": "button_plus", "dpad": "dpad", "stick_l": "stick_l"}),
    "steamdeck": ("Steam Deck", "steamdeck", "controller_steamdeck", {
        "confirm": "button_a", "back": "button_b", "aux": "button_x", "aux2": "button_y", "lb": "button_l1", "rb": "button_r1",
        "start": "button_options", "dpad": "dpad", "stick_l": "stick_l"}),
    "steam": ("Steam Controller", "steam", "controller_steam_new", {
        "confirm": "button_a", "back": "button_b", "aux": "button_x", "aux2": "button_y", "lb": "lb", "rb": "rb",
        "start": "button_start_icon", "dpad": "dpad", "stick_l": "stick"}),
}
KEYS = {
    "w": "w", "a": "a", "s": "s", "d": "d", "f": "f", "g": "g", "r": "r", "t": "t",
    "up": "arrow_up", "down": "arrow_down", "left": "arrow_left", "right": "arrow_right",
    "enter": "enter", "backspace": "backspace", "semicolon": "semicolon", "apostrophe": "apostrophe", "space": "space",
}


BODY_SCALE = 5  # Godot rasterizes an SVG at its width and height: the bodies are drawn up to about 220 px wide


def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def stem(prefix: str, name: str) -> str:
    return "playstation" + name if name.startswith("5_") else f"{prefix}_{name}"


def check_white(img: Image.Image, label: str) -> None:
    """Tinting at runtime needs white plus alpha only: any coloured pixel (a baked highlight) would survive the tint."""
    px = img.convert("RGBA").getdata()
    bad = sum(1 for r, g, b, a in px if a > 8 and min(r, g, b) < 250)
    if bad:
        sys.exit(f"{label}: {bad} pixels are not white")


def crop_svg(src: Path, dst: Path) -> None:
    """The pack's body icons sit in a padded 64 box. Crop the viewBox to the path bounds (control points, so a hair loose)
    and size the file BODY_SCALE times that, which is the size Godot imports it at."""
    s = src.read_text()
    xs, ys = [], []
    for d in re.findall(r' d="([^"]*)"', s):
        if re.search(r"[^MLQ0-9.\-\s]", d):
            sys.exit(f"{src.name}: path commands other than M, L, Q")
        for part in re.findall(r"[MLQ]?[^MLQ]*", d):
            n = [float(v) for v in re.findall(r"-?[0-9.]+", part)]
            xs += n[0::2]
            ys += n[1::2]
    x0, y0, x1, y1 = min(xs), min(ys), max(xs), max(ys)
    w, h = x1 - x0, y1 - y0
    head = f'<svg width="{w * BODY_SCALE:g}" height="{h * BODY_SCALE:g}" viewBox="{x0:g} {y0:g} {w:g} {h:g}" xmlns="http://www.w3.org/2000/svg">'
    dst.write_text(re.sub(r"<svg[^>]*>", head, s, count=1))


def main() -> None:
    kenney = Path(sys.argv[1])
    archive = Path(sys.argv[2]) if len(sys.argv) > 2 else None
    licence = (kenney / "License.txt").read_text()
    if "Creative Commons Zero, CC0" not in licence:
        sys.exit("the pack's License.txt is not CC0")
    # Godot's .import files (and their uids) live next to the pictures and are tracked: clear the pictures only.
    for old in OUT.rglob("*"):
        if old.is_file() and old.suffix in (".png", ".svg", ".json", ".txt"):
            old.unlink()
    files = []

    def record(src: Path, dst: Path, kind: str) -> None:
        item = {"kind": kind, "source_path": str(src.relative_to(kenney)), "runtime_path": str(dst.relative_to(ROOT)),
                "sha256": sha(dst), "bytes": dst.stat().st_size}
        if dst.suffix == ".png":
            with Image.open(dst) as im:
                item["width"], item["height"] = im.size
        elif dst.suffix == ".svg":
            head = re.match(r'<svg width="([0-9.]+)" height="([0-9.]+)"', dst.read_text())
            item["width"], item["height"] = float(head[1]), float(head[2])
        files.append(item)

    for fam, (folder, prefix, body, acts) in FAMILIES.items():
        for act, name in acts.items():
            src = kenney / folder / "Double" / f"{stem(prefix, name)}.png"
            dst = OUT / fam / f"{act}.png"
            dst.parent.mkdir(parents=True, exist_ok=True)
            with Image.open(src) as im:
                check_white(im, str(src))
            shutil.copyfile(src, dst)
            record(src, dst, "copied")
        src = kenney / folder / "Vector" / f"{body}.svg"
        dst = OUT / "bodies" / f"{fam}.svg"
        dst.parent.mkdir(parents=True, exist_ok=True)
        crop_svg(src, dst)
        record(src, dst, "derived: viewBox cropped to the silhouette")
    for key, name in KEYS.items():
        src = kenney / "Keyboard & Mouse" / "Double" / f"keyboard_{name}.png"
        dst = OUT / "keyboard" / f"{key}.png"
        dst.parent.mkdir(parents=True, exist_ok=True)
        with Image.open(src) as im:
            check_white(im, str(src))
        shutil.copyfile(src, dst)
        record(src, dst, "copied")
    shutil.copyfile(kenney / "License.txt", OUT / "LICENSE.txt")
    prov = {
        "source": "Kenney, Input Prompts 1.5A (CC0), downloaded from the page below",
        "source_url": PAGE,
        "archive_sha256": sha(archive) if archive else None,
        "licence": "Creative Commons Zero, CC0 (http://creativecommons.org/publicdomain/zero/1.0/). License.txt: "
                   "'You can use this content for personal, educational, and commercial purposes. Support by crediting "
                   "Kenney or www.kenney.nl (this is not a requirement)'. The full text is in LICENSE.txt next to this file.",
        "extraction_scripts": "tools/glyph_assets.py",
        "files": files,
    }
    (OUT / "PROVENANCE.json").write_text(json.dumps(prov, indent=2) + "\n")
    print(len(files), "files")


if __name__ == "__main__":
    main()
