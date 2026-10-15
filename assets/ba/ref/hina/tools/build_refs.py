#!/usr/bin/env python3
"""Rebuild the official Sorasaki Hina (10004) reference pack in assets/ba/ref/hina/.

Every picture written here is made ONLY of official Blue Archive pixels (the SchaleDB mirror of the game's
portrait / collection / icon textures and the game's own Spine standing sprite `hina_spr`), except the files
named chart_*.png, which are annotated measurement / palette charts built on top of those pixels.

    python3 assets/ba/ref/hina/tools/build_refs.py --dev "<repo>/.dev"

Inputs
  assets/ba/portrait|collection|icon/10004.webp      (SchaleDB CDN = game UI textures)
  assets/ba/rig/hina/*.png                            (the Spine atlas regions of hina_spr)
  <dev>/rig/hina/assembly.json                        (setup-pose placement + ORIGINAL Spine mesh uvs/triangles; used to
                                                       mask atlas-packing debris out of the body parts and to re-assemble)
Needs Pillow. dwebp (libwebp) is used when Pillow has no WebP support.
"""
import argparse, json, os, shutil, subprocess, sys, tempfile
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.dirname(HERE)                                   # assets/ba/ref/hina
ROOT = os.path.abspath(os.path.join(OUT, '..', '..', '..', '..'))  # repo root
RIG = os.path.join(ROOT, 'assets', 'ba', 'rig', 'hina')
BG = (157, 180, 200, 255)          # neutral sky-grey used behind transparent art in charts

def load_webp(path):
    try:
        return Image.open(path).convert('RGBA')
    except Exception:
        tmp = os.path.join(tempfile.mkdtemp(), 'x.png')
        subprocess.run(['dwebp', '-quiet', path, '-o', tmp], check=True)
        return Image.open(tmp).convert('RGBA')

def font(sz):
    for f in ['/System/Library/Fonts/Supplemental/Arial.ttf', '/System/Library/Fonts/Helvetica.ttc',
              os.path.join(ROOT, 'assets', 'fonts', 'NotoSans-Regular.ttf')]:
        if os.path.exists(f):
            try: return ImageFont.truetype(f, sz)
            except Exception: pass
    return ImageFont.load_default()

def on_bg(im, bg=BG):
    b = Image.new('RGBA', im.size, bg); b.alpha_composite(im); return b

def part_png(slot_png):
    return Image.open(os.path.join(RIG, slot_png)).convert('RGBA')

# ---------------------------------------------------------------- Spine re-assembly (setup pose)
def solve_affine(uvs, verts):
    """least-squares affine uv -> vert ; returns (a,b,c,d,e,f) with x=a*u+b*v+c, y=d*u+e*v+f and max residual"""
    import itertools
    n = len(uvs)
    # normal equations for 3 unknowns, twice
    def lsq(target):
        S = [[0.0]*3 for _ in range(3)]; t = [0.0]*3
        for (u, v), z in zip(uvs, target):
            r = (u, v, 1.0)
            for i in range(3):
                t[i] += r[i]*z
                for j in range(3): S[i][j] += r[i]*r[j]
        # gaussian elimination
        M = [S[i] + [t[i]] for i in range(3)]
        for i in range(3):
            p = max(range(i, 3), key=lambda k: abs(M[k][i])); M[i], M[p] = M[p], M[i]
            for k in range(3):
                if k != i:
                    f = M[k][i] / M[i][i]
                    for j in range(4): M[k][j] -= f*M[i][j]
        return [M[i][3]/M[i][i] for i in range(3)]
    ax = lsq([p[0] for p in verts]); ay = lsq([p[1] for p in verts])
    res = max(abs(ax[0]*u+ax[1]*v+ax[2]-x) + abs(ay[0]*u+ay[1]*v+ay[2]-y) for (u, v), (x, y) in zip(uvs, verts))
    return ax + ay, res

def mesh_mask(size, uvs, tris):
    m = Image.new('L', size, 0); d = ImageDraw.Draw(m)
    for i in range(0, len(tris), 3):
        d.polygon([tuple(uvs[tris[i]]), tuple(uvs[tris[i+1]]), tuple(uvs[tris[i+2]])], fill=255)
    return m

def clean_parts(assembly):
    """returns {slot: (clean RGBA part, affine, residual)} using the ORIGINAL Spine triangles as the mask"""
    out = {}
    pngs = {'hina_01': 'hina_01__hina_01.png', 'hina_02': 'hina_02__hina_02.png', 'hina_03': 'hina_03__hina_03.png',
            'hina_04': 'hina_04__hina_04.png'}
    for s in assembly['slots']:
        a = s['atts'][s['default']] if s['default'] in s['atts'] else next(iter(s['atts'].values()))
        if s['slot'] in pngs:
            im = part_png(pngs[s['slot']])
            m = mesh_mask(im.size, a['uvs'], a['tris'])
            clean = Image.new('RGBA', im.size, (0, 0, 0, 0)); clean.paste(im, (0, 0), m)
            aff, res = solve_affine(a['uvs'], a['verts'])
            out[s['slot']] = (clean, aff, res)
    return out

def assemble(assembly, parts, face_png='00_defalt__01_nomal.png', only=None):
    """Paint the setup pose at native texel scale. Returns RGBA image and the transform (assembly->image)."""
    k = 1.0 / parts['hina_04'][1][0]            # assembly units -> texels (hina_04's u scale)
    # bounds over EVERY slot (assembly['bounds'] leaves the halo out)
    pts = [p for s in assembly['slots'] for a in s['atts'].values() for p in (a.get('verts') or a.get('corners'))]
    x0, x1 = min(p[0] for p in pts), max(p[0] for p in pts)
    y0, y1 = min(p[1] for p in pts), max(p[1] for p in pts)
    pad = 20
    W, H = int((x1 - x0)*k) + 2*pad, int((y1 - y0)*k) + 2*pad
    canvas = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    def to_img(x, y): return ((x - x0)*k + pad, (y - y0)*k + pad)
    for s in assembly['slots']:
        slot = s['slot']
        if slot in ('eyeclose',) or (only and slot not in only): continue
        a = s['atts'][s['default']] if s['default'] in s['atts'] else next(iter(s['atts'].values()))
        if slot in parts:
            im, aff, _ = parts[slot]
        else:
            png = {'01_halo': '01_halo__01_halo.png', '01_halo2': '01_halo2__01_halo.png', '02_halo': '02_halo__02_halo.png',
                   'halo': 'halo__halo.png', '00_defalt': face_png}[slot]
            im = part_png(png)
            if 'uvs' in a:
                aff, _ = solve_affine(a['uvs'], a['verts'])
            else:   # region: corners are (BL, BR, TR, TL) in the assembly space -> map texture corners
                c = a['corners']; w, h = im.size
                aff, _ = solve_affine([(0, h), (w, h), (w, 0), (0, 0)], c)
        # forward affine uv->assembly, then assembly->image; PIL wants image->uv (inverse)
        A, B, C, D, E, F = aff
        a2, b2, c2 = A*k, B*k, (C - x0)*k + pad
        d2, e2, f2 = D*k, E*k, (F - y0)*k + pad
        det = a2*e2 - b2*d2
        ia, ib = e2/det, -b2/det; idd, ie = -d2/det, a2/det
        ic = -(ia*c2 + ib*f2); iff = -(idd*c2 + ie*f2)
        layer = im.transform((W, H), Image.AFFINE, (ia, ib, ic, idd, ie, iff), resample=Image.BICUBIC)
        if s.get('blend') == 'additive':
            # official idle pulses this glow copy between 30% and 90% alpha; bake it at 60%
            r, g, b, al = layer.split(); al = al.point(lambda v: int(v*0.6)); layer = Image.merge('RGBA', (r, g, b, al))
            base = canvas.copy(); glow = Image.new('RGBA', (W, H), (0, 0, 0, 0)); glow.alpha_composite(layer)
            from PIL import ImageChops
            gl = Image.new('RGB', (W, H)); gl.paste(glow.convert('RGB'), (0, 0), glow.split()[3])
            rgb = ImageChops.add(base.convert('RGB'), gl)
            canvas = Image.merge('RGBA', (*rgb.split(), ImageChops.lighter(base.split()[3], glow.split()[3])))
        else:
            canvas.alpha_composite(layer)
    return canvas, (lambda x, y: to_img(x, y)), k

# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dev', required=True, help='<repo>/.dev')
    args = ap.parse_args()
    os.makedirs(os.path.join(OUT, 'crops'), exist_ok=True)

    # 1. SchaleDB-mirrored official textures, decoded losslessly to PNG
    for kind in ('portrait', 'collection', 'icon'):
        load_webp(os.path.join(ROOT, 'assets', 'ba', kind, '10004.webp')).save(os.path.join(OUT, f'official_{kind}_10004.png'), optimize=True)
    portrait = Image.open(os.path.join(OUT, 'official_portrait_10004.png')).convert('RGBA')

    # 2. Spine parts, cleaned with the original mesh triangles, and the clean high-res re-assembly
    assembly = json.load(open(os.path.join(args.dev, 'rig', 'hina', 'assembly.json')))
    parts = clean_parts(assembly)
    names = {'hina_04': 'official_part_upper_body.png', 'hina_02': 'official_part_lower_body.png',
             'hina_01': 'official_part_wing_right.png', 'hina_03': 'official_part_wing_left.png'}
    for slot, fn in names.items():
        im = parts[slot][0]; im.crop(im.getbbox()).save(os.path.join(OUT, fn), optimize=True)
        print(slot, 'affine residual %.2f' % parts[slot][2])
    full, to_img, k = assemble(assembly, parts)
    full = full.crop(full.getbbox()); full.save(os.path.join(OUT, 'official_assembled_hires.png'), optimize=True)
    print('assembled', full.size, 'texels per assembly unit %.4f' % k)

    # 3. official expression sheet (all 22 Spine face overlays at native size, on the default skin tone)
    faces = [l for l in json.load(open(os.path.join(RIG, 'rig.json')))['layers'] if l['group'] == 'face']
    faces.sort(key=lambda l: (l['name'] != '00_defalt/01_nomal', l['name']))
    cw, ch, cols = 200, 250, 6
    rows = (len(faces) + cols - 1)//cols
    sheet = Image.new('RGBA', (cols*cw, rows*ch), (253, 243, 242, 255))   # official skin base #fdf3f2
    d = ImageDraw.Draw(sheet); f = font(14)
    for i, l in enumerate(faces):
        im = part_png(l['png']); x, y = (i % cols)*cw, (i//cols)*ch
        sheet.alpha_composite(im, (x + (cw - im.width)//2, y + 24))
        d.text((x + 6, y + 4), l['name'].replace('00_defalt/', ''), fill=(60, 30, 60), font=f)
    sheet.save(os.path.join(OUT, 'official_faces_sheet.png'), optimize=True)

    # 4. official halo layers (the three Spine halo textures + how they stack)
    hl = [part_png(p) for p in ('01_halo2__01_halo.png', '02_halo__02_halo.png', 'halo__halo.png')]
    hs = Image.new('RGBA', (920, 560), BG); d = ImageDraw.Draw(hs)
    y = 10
    for im, label in zip(hl, ('01_halo: spiked crown + side blades (also drawn a 2nd time, additive, pulsing 30-90%)',
                              '02_halo: thin black under-ring', 'halo: magenta ring + hanging crystal')):
        d.text((10, y), label, fill=(20, 10, 30), font=f); hs.alpha_composite(im, (10, y + 18)); y += im.height + 40
    hs.save(os.path.join(OUT, 'official_halo_layers.png'), optimize=True)

    # 5. native-resolution crops from the clean assembly (1 texel = 1 px of the game's Spine texture)
    upper = Image.new('RGBA', parts['hina_04'][0].size); upper.alpha_composite(parts['hina_04'][0])
    face = part_png('00_defalt__01_nomal.png'); upper.alpha_composite(face, (609, 239))
    serious = parts['hina_04'][0].copy(); serious.alpha_composite(part_png('00_defalt__05_serious.png'), (609, 239))
    crops = {
        'face_default.png': (upper, (480, 110, 880, 470)),
        'face_serious.png': (serious, (560, 180, 800, 400)),
        'horns_and_ribbon.png': (upper, (480, 0, 990, 320)),
        'hands_gloves.png': (upper, (440, 300, 700, 600)),
        'collar_chain_hairpins.png': (upper, (600, 230, 800, 520)),
        'weapon_muzzle_prism.png': (upper, (0, 120, 340, 669)),
    }
    lower = parts['hina_02'][0]
    crops.update({
        'boots.png': (lower, (140, 520, 520, 998)),
        'torso_medals_skirt.png': (lower, (150, 0, 560, 220)),
        'stockings_legs.png': (lower, (150, 120, 520, 640)),
        'weapon_rear_stock_bipod.png': (lower, (330, 220, 949, 998)),
    })
    for fn, (src, box) in crops.items():
        c = src.crop(box); c.crop(c.getbbox()).save(os.path.join(OUT, 'crops', fn), optimize=True)
    wr = parts['hina_01'][0]; wr.crop(wr.getbbox()).save(os.path.join(OUT, 'crops', 'wing_right.png'), optimize=True)
    # halo: crop the assembled render's top band (crown + blades + under-ring + crystal), native scale
    halo, _, _ = assemble(assembly, parts, only=('01_halo', '01_halo2', '02_halo', 'halo'))
    halo.crop(halo.getbbox()).save(os.path.join(OUT, 'crops', 'halo_assembled.png'), optimize=True)
    # from the clean assembly (pieces that straddle two Spine parts). Boxes are in official_assembled_hires.png px.
    for fn, box in {'armband_fuuki.png': (1480, 715, 1650, 850),
                    'coat_sleeve_armband.png': (1460, 680, 2010, 1010),
                    'weapon_full.png': (560, 250, 1860, 1760)}.items():
        c = full.crop(box); c.crop(c.getbbox()).save(os.path.join(OUT, 'crops', fn), optimize=True)

    # 6. palette.json + charts (derived from the official pixels above)
    json.dump({'name': 'Sorasaki Hina (10004) official palette, 32 colours',
               'source': 'k-means / pixel picks on official_assembled_hires.png (game Spine texture, native scale) and the '
                         'Spine face overlays',
               'roles': {r: h for h, r, _ in PALETTE}, 'colors': [h for h, _, _ in PALETTE],
               'notes': {r: n for _, r, n in PALETTE}},
              open(os.path.join(OUT, 'palette.json'), 'w'), indent=1)
    chart_palette(os.path.join(OUT, 'chart_palette.png'))
    chart_proportions(full, os.path.join(OUT, 'chart_proportions_165px.png'))
    print('done')

# ---------------------------------------------------------------- palette (hex, role, where it is used)
PALETTE = [
    ('#0d0b12', 'outline_black', 'darkest line + deepest shadow: uniform folds, fur, gloves, wing black, gun body shadow'),
    ('#1f1c2b', 'black_shade', 'fur / glove / gun / boot body (the "black" read)'),
    ('#3d3a45', 'black_hi', 'gloss on gloves, fur tips, gun metal edges, boot toe shine'),
    ('#29273c', 'navy_shadow', 'uniform + boot base in shadow, coat outer deep fold'),
    ('#48435a', 'slate_mid', 'coat outer body, skirt, boot body lit'),
    ('#5d5882', 'indigo_lit', 'uniform (jacket/dress) lit plane - the blue-violet read of the uniform'),
    ('#645e7c', 'coat_lit', 'coat outer lit edge, sleeve top'),
    ('#d2cee2', 'lining', 'coat lining (pale lavender-white), lit'),
    ('#f4f3f6', 'white', 'hair highlight, armband lettering, eye white, wing crystal core'),
    ('#e3dfe7', 'hair_base', 'hair base white-lavender'),
    ('#bfb8cc', 'hair_shade1', 'hair first shade; coat lining shade'),
    ('#a697b5', 'hair_shade2', 'hair second shade (under-layers, behind the head)'),
    ('#776d83', 'hair_line', 'hair deepest shade / coloured line art of hair and lining'),
    ('#fef4f1', 'skin', 'skin lit (very pale, warm)'),
    ('#fbe1e8', 'skin_shade', 'skin shade, cheek blush'),
    ('#d8b2c8', 'skin_deep', 'nose dot, mouth, skin contour, knee/thigh shadow edge'),
    ('#34122f', 'plum_black', 'upper lash line + pupil; horn base shadow'),
    ('#a855ad', 'iris', 'iris ring (violet-magenta)'),
    ('#e594ef', 'iris_light', 'iris lower glow / inner rings'),
    ('#581d5d', 'horn_plum', 'horn body mid-tone, halo band, hair-ribbon base'),
    ('#c03ccc', 'glow_magenta', 'glowing crack veins on horns + halo blades, halo stripes, gun slits'),
    ('#f08af8', 'glow_bright', 'halo rim + crystal, gun prism core glow, glow halos (use sparingly)'),
    ('#553858', 'wing_membrane', 'wing membrane base (mauve-plum)'),
    ('#8f6189', 'wing_membrane_lit', 'wing membrane lit streak along each panel'),
    ('#62507a', 'gun_violet', 'gun bipod, grip box, stock panels (blue-violet plastic)'),
    ('#5e3f59', 'stocking_lit', 'thigh-high stockings lit'),
    ('#3a2840', 'stocking_shadow', 'thigh-high stockings shadow / band'),
    ('#96102f', 'armband_red', 'Prefect armband, red-cross medal, ribbon stripes'),
    ('#5a0c22', 'armband_shadow', 'armband shadow + spiky top edge'),
    ('#e2cc96', 'gold_light', 'gold highlight: buttons, chains, buckles, hairpins, wing claw cap'),
    ('#b8925f', 'gold_mid', 'gold body'),
    ('#6e5636', 'gold_dark', 'gold shadow / outline'),
]

def chart_palette(path):
    f = font(13); fb = font(15)
    W, rowh = 980, 30
    im = Image.new('RGB', (W, 40 + rowh*len(PALETTE)//2 + 10), (245, 245, 248)); d = ImageDraw.Draw(im)
    d.text((10, 10), 'Hina (10004) official 32-colour palette - from the game Spine texture (palette.json)', fill=(0, 0, 0), font=fb)
    half = (len(PALETTE) + 1)//2
    for i, (h, role, _) in enumerate(PALETTE):
        x = 10 + (i//half)*(W//2); y = 40 + (i % half)*rowh
        d.rectangle((x, y, x + 60, y + rowh - 4), fill=h, outline=(0, 0, 0))
        d.text((x + 70, y + 6), f'{i:2d} {h}  {role}', fill=(0, 0, 0), font=f)
    im.save(path, optimize=True)

# landmarks measured on official_assembled_hires.png (y px, native texel scale)
LM = [('halo spike tips', 12), ('halo ring bottom', 119), ('halo crystal', 192), ('upper horn tips', 175),
      ('ahoge tip', 237), ('CROWN (0)', 247), ('eye line', 440), ('chin', 527), ('shoulder seam', 600),
      ('waist / gold chain belt', 800), ('wing wrist claws', 845), ('skirt hem', 975), ('crotch', 990),
      ('stocking top', 1050), ('knee', 1290), ('boot top', 1350), ('SOLE (165)', 1789)]
CROWN, SOLE = 247, 1789

def chart_proportions(full, path):
    H165 = 165; s4 = 4                                    # chart drawn at 4x the 165 px sprite scale
    k = H165*s4/(SOLE - CROWN)
    fig = full.resize((int(full.width*k), int(full.height*k)), Image.LANCZOS)
    pad_top = 40; LBL = 300
    one = full.resize((max(1, int(full.width*H165/(SOLE - CROWN))), max(1, int(full.height*H165/(SOLE - CROWN)))), Image.LANCZOS)
    big = one.resize((one.width*3, one.height*3), Image.NEAREST)
    W = fig.width + LBL + big.width + 30; Hh = max(fig.height, big.height + one.height + 80) + pad_top + 30
    im = Image.new('RGBA', (W, Hh), BG); im.alpha_composite(fig, (0, pad_top)); d = ImageDraw.Draw(im); f = font(14)
    last = -99
    for name, y in sorted(LM, key=lambda t: t[1]):
        Y = pad_top + int(y*k); px = (y - CROWN)*H165/(SOLE - CROWN)
        major = 'CROWN' in name or 'SOLE' in name
        d.line((0, Y, fig.width + 6, Y), fill=(200, 0, 60, 255) if major else (40, 40, 160, 255), width=2 if major else 1)
        ty = max(Y - 8, last + 16); last = ty                      # de-overlap labels, leader line to the true height
        d.line((fig.width + 6, Y, fig.width + 22, ty + 8), fill=(40, 40, 160, 255))
        d.text((fig.width + 26, ty), f'{name}: {px:+.0f} px', fill=(10, 10, 40), font=f)
    d.text((10, 8), 'Official proportions at a 165 px standing height (crown -> sole). Left chart = 4x. Values = px from the crown at 1x '
                    '(negative = above the crown).', fill=(10, 10, 40), font=f)
    # the official art itself at the real 1x sprite size, and 3x nearest of that, to show what survives at sprite scale
    bx = fig.width + LBL
    d.text((bx, pad_top), '1x (165 px standing): what reads at sprite scale', fill=(10, 10, 40), font=f)
    im.alpha_composite(one, (bx, pad_top + 20))
    d.text((bx, pad_top + one.height + 34), '3x nearest of the 1x', fill=(10, 10, 40), font=f)
    im.alpha_composite(big, (bx, pad_top + one.height + 54))
    im.convert('RGB').save(path, optimize=True)

if __name__ == '__main__':
    main()
