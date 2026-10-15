#!/usr/bin/env python3
"""Rebuilds the official-art reference pack for Takanashi Hoshino (roster id 10005).

    python3 assets/ba/ref/hoshino/_build/build_refs.py <repo-root> <dev-root>

<dev-root> is the folder that holds .dev/ (normally the repo root).

Inputs are ONLY official game textures already on disk:
  * <repo-root>/assets/ba/portrait|collection|icon/10005.webp   (SchaleDB mirror of the game's UI textures)
  * <repo-root>/assets/ba/rig/hoshino/*.png                     (parts cut from the game's Spine standing sprite)
  * <repo-root>/assets/ba/school_color/abydos.png               (SchaleDB mirror of the game's school icon)
  * <dev-root>/.dev/spine/hoshino_spr/hoshino_spr.png           (the game's Spine atlas texture, untouched)
  * <dev-root>/.dev/rig/hoshino/assembly.json                   (slot placement extracted from the game's .skel)
  * <dev-root>/.dev/samples/hoshino_lobby.webp                  (SchaleDB student/lobby thumbnail)
Outputs (all into assets/ba/ref/hoshino/): official_*.png copies/compositions, crops/*.png (native-resolution crops),
proportions_165px.png, palette_swatches.png. palette.json and sources.json are hand-written.
Nothing is redrawn: every pixel in official_* and crops/* is a game pixel (labels/guide lines live only in the two
annotated sheets: official_faces_sheet.png has a label strip above each tile; proportions_165px.png is an annotated
measurement sheet).
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

W, R = sys.argv[1], sys.argv[2]
OUT = os.path.join(W, 'assets/ba/ref/hoshino')
CROPS = os.path.join(OUT, 'crops')
os.makedirs(CROPS, exist_ok=True)
RIG = os.path.join(W, 'assets/ba/rig/hoshino')
FONT = os.path.join(W, 'assets/fonts/BarlowCondensed-SemiBold.ttf')


def font(size):
    try:
        return ImageFont.truetype(FONT, size)
    except Exception:
        return ImageFont.load_default()


def save(im, name, folder=OUT):
    p = os.path.join(folder, name)
    im.save(p, optimize=True)
    print(f'{os.path.relpath(p, W):60s} {im.size[0]}x{im.size[1]} {os.path.getsize(p)//1024} KB')


# ---------------------------------------------------------------- straight copies (decoded to PNG, no resampling)
portrait = Image.open(os.path.join(W, 'assets/ba/portrait/10005.webp')).convert('RGBA')
save(portrait, 'official_portrait_10005.png')
save(Image.open(os.path.join(W, 'assets/ba/collection/10005.webp')).convert('RGB'), 'official_collection_10005.png')
save(Image.open(os.path.join(W, 'assets/ba/icon/10005.webp')).convert('RGBA'), 'official_icon_10005.png')
save(Image.open(os.path.join(R, '.dev/samples/hoshino_lobby.webp')).convert('RGBA'), 'official_memorial_lobby_thumb_10005.png')
atlas = Image.open(os.path.join(R, '.dev/spine/hoshino_spr/hoshino_spr.png')).convert('RGBA')
save(atlas, 'official_spine_atlas.png')
save(Image.open(os.path.join(W, 'assets/ba/school_color/abydos.png')).convert('RGBA'), 'official_abydos_crest.png')

# ---------------------------------------------------------------- Spine standing sprite, re-assembled in its setup pose
asm = json.load(open(os.path.join(R, '.dev/rig/hoshino/assembly.json')))
OX, OY, CW, CH = 300, 680, 600, 1060


def _arr(v):
    return np.array(json.loads(v) if isinstance(v, str) else v, dtype=float)


def assemble(face='01_normal', halo=True, body=True, extra=None):
    canvas = Image.new('RGBA', (CW, CH), (0, 0, 0, 0))
    for s in asm['slots']:
        key = s['default']
        if s['slot'] == '00_default':
            key = face
        if extra and s['slot'] in extra:
            key = extra[s['slot']]
        if key is None or s['blend'] == 'additive':   # additive copies only brighten the halo in-game
            continue
        if s['slot'].startswith('halo') and not halo:
            continue
        if s['slot'] in ('hoshino', 'object_fronthair', '00_default', 'eyeclose', 'eyeclose2') and not body:
            continue
        att = s['atts'][key]
        im = Image.open(os.path.join(RIG, f"{s['slot'].replace(' ', '_')}__{key.replace(' ', '_')}.png")).convert('RGBA')
        w, h = im.size
        if 'corners' in att:
            c = _arr(att['corners'])
        else:  # face meshes sit in their setup pose = an axis-aligned w x h rectangle
            v = _arr(att['verts'])
            x0, yb = v[:, 0].min(), v[:, 1].max()
            c = np.array([[x0, yb], [x0 + w, yb], [x0 + w, yb - h], [x0, yb - h]])
        c0, c1, c2, c3 = c
        M = np.array([[(c2 - c3)[0] / w, (c0 - c3)[0] / h], [(c2 - c3)[1] / w, (c0 - c3)[1] / h]])
        t = c3 + np.array([OX, OY])
        Mi = np.linalg.inv(M)
        data = (Mi[0, 0], Mi[0, 1], -(Mi[0] @ t), Mi[1, 0], Mi[1, 1], -(Mi[1] @ t))
        canvas.alpha_composite(im.transform((CW, CH), Image.AFFINE, data, resample=Image.BICUBIC))
    return canvas


standing = assemble('01_normal')
bb = standing.getbbox()
save(standing.crop(bb), 'official_standing_eyes_open.png')

# halo layers in their in-game arrangement (normal-blend layers only)
halo = assemble(halo=True, body=False)
save(halo.crop(halo.getbbox()), 'official_halo.png')

# all 18 official faces (+ the blink overlay) on the standing head, native resolution
faces = [k for k in next(s for s in asm['slots'] if s['slot'] == '00_default')['atts'].keys()]
faces = sorted(faces)
HEAD = (OX - 115, OY - 640, OX + 120, OY - 395)   # canvas box around head + ahoge
tiles = [(f, assemble(f, halo=False).crop(HEAD)) for f in faces]
blink = assemble('01_normal', halo=False, extra={'eyeclose2': 'eyeclose'}).crop(HEAD)
tiles.append(('eyeclose (blink overlay)', blink))
tw, th, lab = HEAD[2] - HEAD[0], HEAD[3] - HEAD[1], 22
cols = 5
rows = (len(tiles) + cols - 1) // cols
sheet = Image.new('RGBA', (cols * tw, rows * (th + lab)), (232, 238, 246, 255))
d = ImageDraw.Draw(sheet)
for i, (name, t) in enumerate(tiles):
    x, y = (i % cols) * tw, (i // cols) * (th + lab)
    d.rectangle([x, y, x + tw - 1, y + lab - 1], fill=(30, 44, 74, 255))
    d.text((x + 6, y + 2), name, fill=(255, 230, 120, 255), font=font(17))
    sheet.alpha_composite(t, (x, y + lab))
save(sheet, 'official_faces_sheet.png')

# ---------------------------------------------------------------- native-resolution crops of the official art
P = portrait
crops = {
    'face_wink_portrait.png': (P, (240, 60, 460, 300)),
    'face_eyes_open_spine.png': (standing.crop(bb), None),
    'eyes_01_normal_part.png': (Image.open(os.path.join(RIG, '00_default__01_normal.png')).convert('RGBA'), None),
    'hair_ahoge.png': (P, (325, 25, 455, 140)),
    'hair_tips_left.png': (P, (30, 400, 260, 720)),
    'hand_left_glove.png': (P, (330, 225, 420, 305)),
    'hand_right_on_grip.png': (atlas, (505, 440, 600, 520)),
    'hand_right_glove_lobby_thumb.png': (Image.open(os.path.join(R, '.dev/samples/hoshino_lobby.webp')).convert('RGBA'), (8, 85, 60, 135)),
    'torso_harness_tie_badge.png': (P, (220, 250, 470, 425)),
    'skirt_plaid.png': (P, (200, 385, 450, 600)),
    'legs_socks_shoes.png': (P, (245, 590, 400, 1024)),
    'shoes.png': (P, (255, 835, 395, 1024)),
    'shotgun_side_view.png': (atlas, (375, 425, 920, 550)),
    'shotgun_in_hand.png': (P, (130, 400, 250, 945)),
    'shield_case.png': (P, (300, 385, 590, 685)),
}
for name, (src, box) in crops.items():
    if name == 'face_eyes_open_spine.png':
        st = standing.crop(bb)
        # face box relative to the cropped standing image
        im = st.crop((HEAD[0] - bb[0] + 10, HEAD[1] - bb[1] + 40, HEAD[2] - bb[0] - 10, HEAD[3] - bb[1] + 20))
    elif box is None:
        im = src
    else:
        im = src.crop(box)
    save(im, name, CROPS)

# ---------------------------------------------------------------- the official art at the sprite's target size
# crown (top of the hair on the skull, NOT the ahoge) y=80, ground y=1015 in portrait px -> 935 px = 165 sprite px.
CROWN, SOLE, TARGET = 80, 1015, 165
k = TARGET / (SOLE - CROWN)
small = P.resize((round(P.width * k), round(P.height * k)), Image.LANCZOS)
Z = 4
pad_l, pad_t = 150, 40
big = small.resize((small.width * Z, small.height * Z), Image.NEAREST)
sheet = Image.new('RGBA', (pad_l + big.width + 260, pad_t + big.height + 30), (236, 242, 250, 255))
sheet.alpha_composite(big, (pad_l, pad_t))
d = ImageDraw.Draw(sheet)
f = font(18)
marks = [  # (portrait y, label)
    (37, 'ahoge tip  -8'), (80, 'crown  0'), (185, 'eye line  18'), (243, 'chin  29 (head = 29 px, 5.7 heads)'),
    (272, 'shoulders  34'), (355, 'chest strap  48'), (392, 'waistband  55'), (575, 'skirt hem  87'),
    (690, 'hair tips  104-110'), (712, 'knee  112'), (822, 'sock top  ~129'), (935, 'high-top collar  ~152'),
    (1015, 'ground  165'),
]
for y, label in marks:
    yy = pad_t + round((y) * k) * Z
    col = (230, 40, 80, 255) if y in (80, 1015) else (40, 110, 220, 255)
    d.line([(pad_l - 10, yy), (pad_l + big.width + 10, yy)], fill=col, width=1)
    d.text((pad_l + big.width + 16, yy - 10), label, fill=col, font=f)
d.text((8, 8), f'Official portrait at sprite scale: crown->ground = {TARGET} px (x{Z} nearest). Numbers = px below crown.',
       fill=(20, 30, 60, 255), font=f)
save(sheet, 'proportions_165px.png')
small_path = os.path.join(CROPS, 'portrait_at_165px.png')
small.save(small_path, optimize=True)
print(f'{os.path.relpath(small_path, W):60s} {small.size[0]}x{small.size[1]}')

# ---------------------------------------------------------------- palette swatches from palette.json
pal = json.load(open(os.path.join(OUT, 'palette.json')))
roles = pal['roles']
items = list(roles.items())
sw, sh = 300, 46
cols = 2
im = Image.new('RGBA', (cols * sw, ((len(items) + cols - 1) // cols) * sh), (255, 255, 255, 255))
d = ImageDraw.Draw(im)
for i, (role, v) in enumerate(items):
    hexc = v['hex'] if isinstance(v, dict) else v
    x, y = (i % cols) * sw, (i // cols) * sh
    d.rectangle([x + 4, y + 4, x + 70, y + sh - 4], fill=hexc, outline=(60, 60, 60, 255))
    d.text((x + 78, y + 4), f'{i + 1:02d} {role}', fill=(20, 20, 30, 255), font=font(18))
    d.text((x + 78, y + 24), hexc, fill=(90, 90, 110, 255), font=font(16))
save(im, 'palette_swatches.png')
