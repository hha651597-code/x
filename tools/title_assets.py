#!/usr/bin/env python3
"""The title screen's art -> assets/ba/title: Blue Archive's eight title films as Theora (the one video format Godot plays), its
Title_Logo texture, and our own "Fighting Game" lettering set to match the logo, with PROVENANCE.json.

Copy the sources out of the install first and never run anything from it (SRC is a scratch folder):
  cp .../BlueArchive_Data/StreamingAssets/Video/title.mp4 SRC/title_0.mp4
  cp .../PUB/Resource/Preload/MediaResources/Video/title_*.mp4 SRC/              (2nd_1, 3rd_1, 4nd_2, 4nd_Ep, 5th_1, 6th_1, 7th_1)
  cp .../PUB/Resource/Preload/Windows/*uis-00_images-imagefont-*2024-11-18_000_* SRC/    (the bundle that holds Title_Logo)
  Orbitron[wght].ttf (Google Fonts, SIL OFL 1.1) next to them, for the lettering.

usage: ~/Tools/venv-stages/bin/python -I tools/title_assets.py SRC [--ffmpeg PATH] [--only videos|logo|lettering] [--quality N] [--out DIR]
UnityPy and Pillow; the ffmpeg must have libtheora (the Homebrew one does not; `pip install imageio-ffmpeg` in a scratch venv ships
one: python -c "import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())").
The films are 2340x1080 but a 16:9 screen only ever shows the middle 1920 of them (the title covers the canvas), so the unseen
210 px each side are cropped away before encoding: no visible change, 18% fewer pixels. The audio is dropped (Bgm plays the title
theme). Theora quality 6 by default (chosen over q7: about 40 MB smaller). Measured on the 6th film against the source (SSIM): q6 0.984, q7 0.988, q8 0.990; q6 is visibly
smudgier on fine detail beside the source, q7 is not. Sizes of all eight: q8 156 MB uncropped, about 128 cropped; q7 about 100; q6 about 62."""
import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/ba/title"
# output name -> source file in SRC
FILMS = {"opening": "title_0.mp4", "2nd": "title_2nd_1.mp4", "3rd": "title_3rd_1.mp4", "4th": "title_4nd_2.mp4",
         "4th_ep": "title_4nd_Ep.mp4", "5th": "title_5th_1.mp4", "6th": "title_6th_1.mp4", "7th": "title_7th_1.mp4"}
QUALITY = 6
CROP = "crop=1920:1080"   # centred: x = (2340 - 1920) / 2
CYAN = (0, 208, 248, 255)    # the logo's two flat colours, sampled from Title_Logo
WHITE = (248, 248, 248, 255)
LETTER = "Orbitron[wght].ttf"
SHEAR = 0.25


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def prov_load():
    p = OUT / "PROVENANCE.json"
    return json.loads(p.read_text()) if p.exists() else {}


def videos(src, ffmpeg, prov):
    (OUT / "video").mkdir(parents=True, exist_ok=True)
    for name, f in FILMS.items():
        out = OUT / "video" / (name + ".ogv")
        subprocess.run([ffmpeg, "-v", "error", "-y", "-i", str(src / f), "-an", "-vf", CROP, "-c:v", "libtheora", "-q:v", str(QUALITY),
                        "-g", "60", "-pix_fmt", "yuv420p", str(out)], check=True)
        prov["video/%s.ogv" % name] = {"source": f, "source_sha256": sha(src / f), "derived_from":
                                       "tools/title_assets.py: VP9 -> Theora q%d, centre 1920x1080, audio dropped" % QUALITY, "sha256": sha(out)}
        print(out.name, round(out.stat().st_size / 1048576, 1), "MB")


def logo(src, prov):
    import UnityPy
    for b in sorted(src.glob("*uis-00_images-imagefont-*.bundle")):
        for o in UnityPy.load(str(b)).objects:
            if o.type.name == "Texture2D":
                d = o.read()
                if d.m_Name == "Title_Logo":
                    d.image.save(OUT / "Title_Logo.png")
                    prov["Title_Logo.png"] = {"source": "UIs/00_Images/ImageFont/Title_Logo", "source_bundle": b.name,
                                              "derived_from": "UnityPy Texture2D export, unchanged", "sha256": sha(OUT / "Title_Logo.png")}
                    return
    sys.exit("Title_Logo not found in %s" % src)


def lettering(src, prov):
    """'Fighting' in the logo's cyan and 'Game' in its white, Orbitron Black leaned 0.25: the closest open face to the logo's wide
    squared italic. Drawn at 2x the size it is used at so it stays sharp when the window is scaled up."""
    font = ImageFont.truetype(str(src / LETTER), 200)
    font.set_variation_by_axes([900])
    layer = Image.new("RGBA", (2600, 360), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x = 40
    for word, col in (("Fighting ", CYAN), ("Game", WHITE)):
        d.text((x, 20), word, font=font, fill=col)
        x += int(font.getlength(word))
    layer = layer.transform((layer.width + int(layer.height * SHEAR), layer.height), Image.AFFINE, (1, SHEAR, -layer.height * SHEAR, 0, 1, 0),
                            resample=Image.BICUBIC)
    layer = layer.crop(layer.getbbox())
    pad = Image.new("RGBA", (layer.width + 24, layer.height + 24), (0, 0, 0, 0))
    pad.alpha_composite(layer, (12, 12))
    pad.save(OUT / "Title_FightingGame.png")
    prov["Title_FightingGame.png"] = {"source": "tools/title_assets.py lettering", "font": "Orbitron variable, wght 900, Google Fonts, SIL OFL 1.1",
                                      "derived_from": "'Fighting' #00D0F8 and 'Game' #F8F8F8 (the logo's colours), sheared %.2f" % SHEAR,
                                      "sha256": sha(OUT / "Title_FightingGame.png")}


def main():
    global OUT, QUALITY
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src")
    ap.add_argument("--ffmpeg", default="ffmpeg")
    ap.add_argument("--only", choices=["videos", "logo", "lettering"])
    ap.add_argument("--quality", type=int, default=QUALITY)
    ap.add_argument("--out", default=str(OUT))
    a = ap.parse_args()
    OUT, QUALITY = Path(a.out), a.quality
    src = Path(a.src)
    OUT.mkdir(parents=True, exist_ok=True)
    prov = prov_load()
    if a.only in (None, "videos"):
        videos(src, a.ffmpeg, prov)
    if a.only in (None, "logo"):
        logo(src, prov)
    if a.only in (None, "lettering"):
        lettering(src, prov)
    (OUT / "PROVENANCE.json").write_text(json.dumps(prov, indent=1, sort_keys=True) + "\n")
    print("provenance entries:", len(prov))


if __name__ == "__main__":
    main()
