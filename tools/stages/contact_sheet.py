import json
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
FONTS = ["/System/Library/Fonts/Helvetica.ttc", "/System/Library/Fonts/Supplemental/Arial.ttf"]
PAN_K = [-1.6, -0.8, 0.0, 0.8, 1.6]
ZOOMS = [0.7, 1.0, 1.24]


def font(size):
    for f in FONTS:
        if Path(f).exists():
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


def pan_centres(lane_z, ppu, view_w):
    half = view_w / 2.0 / ppu
    return [round(lane_z + k * half, 2) for k in PAN_K], half


def shots(stage, times, lane_z, ppu, view_w, out_dir):
    out = []
    pan_z, _ = pan_centres(lane_z, ppu, view_w)
    for t in times:
        for z in ZOOMS:
            out.append({"stage": stage, "time": t, "zoom": z, "cam_x": 0.0, "fighters": "hina:-250:1:idle:0,hoshino:250:-1:idle:0", "out": str(out_dir / f"{t}_zoom_{z}.png"), "label": f"{t}  zoom {z}"})
        for zc in pan_z:
            cx = (zc - lane_z) * ppu
            out.append({"stage": stage, "time": t, "zoom": 1.0, "cam_x": cx, "fighters": f"hina:{cx - 230:.1f}:1:idle:0,hoshino:{cx + 230:.1f}:-1:idle:0", "out": str(out_dir / f"{t}_pan_{zc}.png"), "label": f"{t}  zoom 1.0  view centre z {zc}"})
    return out


def compose(batch, times, sheet, title):
    W = 1920
    f, fs = font(22), font(18)
    rows = []
    y = 44
    cells = []
    for t in times:
        zs = [s for s in batch if s["time"] == t and "zoom_" in s["out"]]
        ps = [s for s in batch if s["time"] == t and "pan_" in s["out"]]
        for group, w in ((zs, 640), (ps, 384)):
            h = w * 9 // 16
            for i, s in enumerate(group):
                cells.append((s, i * w, y, w, h))
            y += h + 26
    img = Image.new("RGB", (W, y + 8), (24, 24, 28))
    d = ImageDraw.Draw(img)
    d.text((12, 10), title, fill=(235, 235, 235), font=f)
    for s, x, yy, w, h in cells:
        im = Image.open(s["out"]).convert("RGB").resize((w, h), Image.LANCZOS)
        img.paste(im, (x, yy))
        d.text((x + 6, yy + h + 3), s["label"], fill=(215, 215, 215), font=fs)
    img.save(sheet)


def main(stage, out_dir, sheet):
    out_dir = Path(out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    sj = json.load(open(ROOT / "assets/ba/stages" / stage / "stage.json"))
    times = sorted(sj["times"], key=lambda t: t != "day")
    v = json.load(open(ROOT / "assets/ba/stages" / stage / (sj["times"][times[0]] + ".json")))
    lane_z, ppu, view_w = v["lane"]["origin"][2], v["camera"]["px_per_unit"], v["camera"]["view"][0]
    batch = shots(stage, times, lane_z, ppu, view_w, out_dir)
    pan_z, half = pan_centres(lane_z, ppu, view_w)
    bj = out_dir / "batch.json"
    bj.write_text(json.dumps(batch))
    r = subprocess.run([str(ROOT / "tools/stage_shots.sh"), str(out_dir / "unused.png"), f"--batch={bj}"], capture_output=True, text=True)
    sys.stdout.write(r.stdout)
    if r.returncode:
        sys.exit(f"stage_shots.sh failed ({r.returncode}), no sheet written")
    compose(batch, times, Path(sheet).resolve(), f"{stage}: Hina and Hoshino on the lane, {view_w}x{v['camera']['view'][1]} frames, zoom {' / '.join(str(z) for z in ZOOMS)} and a pan along z {pan_z[0] - half:.0f} to {pan_z[-1] + half:.0f}")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit("usage: contact_sheet.py <stage id> <frames dir> <sheet png>")
    main(*sys.argv[1:4])
