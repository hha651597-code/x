"""Minimal Spine 4.2 setup-pose renderer: meshes (weighted or not) and regions, normal and additive blend.
No constraints and no motion: a face animation only swaps the attachment on its slots (the sampled key at time t).
Coordinates are skeleton units, y up; crop is (x0, y0, x1, y1) in those units."""
import json, math, os
import numpy as np
from PIL import Image

def parse_atlas(txt):
    regs = {}; page = {}
    lines = [l.rstrip('\r') for l in txt.split('\n')]
    cur = None
    i = 0
    # first non-empty line = page filename
    while i < len(lines) and not lines[i].strip(): i += 1
    page['file'] = lines[i].strip(); i += 1
    while i < len(lines):
        l = lines[i]
        if not l.strip(): i += 1; continue
        if ':' in l and not l.startswith(' ') and cur is None or (':' in l and cur is None):
            k, v = l.split(':', 1); page[k.strip()] = v.strip(); i += 1; continue
        if ':' not in l:
            cur = {'name': l.strip(), 'rotate': 0}; regs[cur['name']] = cur; i += 1; continue
        k, v = [s.strip() for s in l.split(':', 1)]
        if k == 'bounds': cur['x'], cur['y'], cur['w'], cur['h'] = map(int, v.split(','))
        elif k == 'offsets': cur['ox'], cur['oy'], cur['ow'], cur['oh'] = map(int, v.split(','))
        elif k == 'rotate': cur['rotate'] = 90 if v == 'true' else (0 if v == 'false' else int(v))
        elif k == 'xy': cur['x'], cur['y'] = map(int, v.split(','))
        elif k == 'size' and cur is not None: cur['w'], cur['h'] = map(int, v.split(','))
        elif k == 'orig': cur['ow'], cur['oh'] = map(int, v.split(','))
        elif k == 'offset': cur['ox'], cur['oy'] = map(int, v.split(','))
        i += 1
    for r in regs.values():
        r.setdefault('ox', 0); r.setdefault('oy', 0); r.setdefault('ow', r['w']); r.setdefault('oh', r['h'])
    return page, regs

def bone_world(bones):
    W = {}
    for b in bones:
        x, y = b.get('x', 0), b.get('y', 0); rot = math.radians(b.get('rotation', 0))
        sx, sy = b.get('scaleX', 1), b.get('scaleY', 1)
        a, c = math.cos(rot) * sx, math.sin(rot) * sx
        bb, d = -math.sin(rot) * sy, math.cos(rot) * sy
        if 'parent' in b:
            p = W[b['parent']]
            W[b['name']] = (p[0]*a + p[2]*c, p[1]*a + p[3]*c, p[0]*bb + p[2]*d, p[1]*bb + p[3]*d,
                            p[0]*x + p[2]*y + p[4], p[1]*x + p[3]*y + p[5])
        else:
            W[b['name']] = (a, c, bb, d, x, y)
    return W   # (a,c,b,d,tx,ty): wx = a*x + b*y + tx ; wy = c*x + d*y + ty

def apply(m, x, y): return (m[0]*x + m[2]*y + m[4], m[1]*x + m[3]*y + m[5])

def mesh_world(att, slot_bone, bones, W):
    uvs = np.array(att['uvs'], float).reshape(-1, 2); n = len(uvs); v = att['vertices']
    if len(v) == n * 2:
        m = W[slot_bone]; pts = np.array([apply(m, v[2*i], v[2*i+1]) for i in range(n)])
    else:
        pts = []; i = 0
        for _ in range(n):
            cnt = int(v[i]); i += 1; px = py = 0
            for _ in range(cnt):
                bi, vx, vy, wt = int(v[i]), v[i+1], v[i+2], v[i+3]; i += 4
                wx, wy = apply(W[bones[bi]['name']], vx, vy); px += wx*wt; py += wy*wt
            pts.append((px, py))
        pts = np.array(pts)
    return pts, uvs

def region_world(att, slot_bone, W):
    x, y = att.get('x', 0), att.get('y', 0); rot = math.radians(att.get('rotation', 0))
    sx, sy = att.get('scaleX', 1), att.get('scaleY', 1); w, h = att['width']*sx, att['height']*sy
    cs = [(-w/2, -h/2), (-w/2, h/2), (w/2, h/2), (w/2, -h/2)]
    pts = []
    for cx, cy in cs:
        lx = cx*math.cos(rot) - cy*math.sin(rot) + x; ly = cx*math.sin(rot) + cy*math.cos(rot) + y
        pts.append(apply(W[slot_bone], lx, ly))
    uvs = np.array([[0, 1], [0, 0], [1, 0], [1, 1]], float)
    return np.array(pts), uvs, [0, 1, 2, 0, 2, 3]

def uv_to_atlas(uv, r, tw, th):
    """uv in original (untrimmed, y-down) frame -> atlas pixel coords (y-down)."""
    px = uv[:, 0] * r['ow']; py = uv[:, 1] * r['oh']
    lx = px - r['ox']; ly = py - (r['oh'] - r['oy'] - r['h'])      # inside trimmed region, y-down
    d = r['rotate']
    if d == 0: ax, ay = r['x'] + lx, r['y'] + ly
    elif d == 180: ax, ay = r['x'] + (r['w'] - lx), r['y'] + (r['h'] - ly)
    elif d == 90: ax, ay = r['x'] + ly, r['y'] + (r['w'] - lx)        # packed rect is h wide, w tall
    else: ax, ay = r['x'] + (r['h'] - ly), r['y'] + lx
    return np.stack([ax, ay], 1)

def sample(tex, ax, ay):
    H, Wd = tex.shape[:2]
    ax = np.clip(ax - 0.5, 0, Wd - 1.001); ay = np.clip(ay - 0.5, 0, H - 1.001)
    x0 = ax.astype(int); y0 = ay.astype(int); fx = (ax - x0)[:, None]; fy = (ay - y0)[:, None]
    return (tex[y0, x0]*(1-fx)*(1-fy) + tex[y0, x0+1]*fx*(1-fy) + tex[y0+1, x0]*(1-fx)*fy + tex[y0+1, x0+1]*fx*fy)

def draw_tri(out, tex, P, A, color=(1, 1, 1, 1), additive=False):
    # P screen px (y-down) 3x2, A atlas px 3x2; premultiplied over
    x0 = int(max(0, math.floor(P[:, 0].min()))); x1 = int(min(out.shape[1] - 1, math.ceil(P[:, 0].max())))
    y0 = int(max(0, math.floor(P[:, 1].min()))); y1 = int(min(out.shape[0] - 1, math.ceil(P[:, 1].max())))
    if x1 < x0 or y1 < y0: return
    xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
    xs = xs.ravel(); ys = ys.ravel()
    (ax, ay), (bx, by), (cx, cy) = P
    den = (by - cy)*(ax - cx) + (cx - bx)*(ay - cy)
    if abs(den) < 1e-9: return
    l1 = ((by - cy)*(xs - cx) + (cx - bx)*(ys - cy)) / den
    l2 = ((cy - ay)*(xs - cx) + (ax - cx)*(ys - cy)) / den
    l3 = 1 - l1 - l2
    eps = -0.002
    m = (l1 >= eps) & (l2 >= eps) & (l3 >= eps)
    if not m.any(): return
    l1, l2, l3 = l1[m], l2[m], l3[m]
    sx = l1*A[0, 0] + l2*A[1, 0] + l3*A[2, 0]; sy = l1*A[0, 1] + l2*A[1, 1] + l3*A[2, 1]
    s = sample(tex, sx, sy)     # premultiplied RGBA 0..1: filtering straight alpha bleeds the colour of transparent texels
    s *= np.array(color)[None, :]
    xi = (xs[m] - 0.5).astype(int); yi = (ys[m] - 0.5).astype(int)
    dst = out[yi, xi]
    if additive:
        add = s[:, :3]
        a = dst[:, 3:4] + (1 - dst[:, 3:4]) * np.minimum(1.0, add.max(1, keepdims=True))
        out[yi, xi] = np.concatenate([dst[:, :3] + add, a], 1)
    else:
        out[yi, xi] = s + dst * (1 - s[:, 3:4])

def render(skel, regs, tex, anim, scale, crop, hide=()):
    bones = skel['bones']; W = bone_world(bones)
    slots = skel['slots']; skin = {s['name']: s['attachments'] for s in skel['skins'] if s['name'] == 'default'}
    skin = skin['default'] if 'default' in skin else {}
    cur = {s['name']: s.get('attachment') for s in slots}
    t = 0.0
    if anim and '@' in anim: anim, t = anim.split('@'); t = float(t)
    if anim:
        for sl, tl in skel['animations'][anim].get('slots', {}).items():
            if 'attachment' in tl:
                ks = [k for k in tl['attachment'] if k.get('time', 0) <= t] or tl['attachment'][:1]
                cur[sl] = ks[-1].get('name')
    x0, y0, x1, y1 = crop
    Wp, Hp = int((x1 - x0)*scale), int((y1 - y0)*scale)
    out = np.zeros((Hp, Wp, 4), float)
    th, tw = tex.shape[:2]
    tex = np.concatenate([tex[..., :3] * tex[..., 3:4], tex[..., 3:]], -1)    # atlases are straight alpha
    for s in slots:
        name = s['name']; an = cur.get(name)
        if not an or name in hide: continue
        att = skin.get(name, {}).get(an)
        if att is None: continue
        path = att.get('path', an)
        if path not in regs: continue
        t = att.get('type', 'region')
        hx = s.get('color') or 'ffffffff'
        hx = hx + 'ff' * ((8 - len(hx)) // 2)
        color = tuple(int(hx[i:i+2], 16) / 255 for i in (0, 2, 4, 6))
        add = s.get('blend') == 'additive'
        if t == 'mesh':
            pts, uvs = mesh_world(att, s['bone'], bones, W); tris = att['triangles']
        elif t == 'region':
            pts, uvs, tris = region_world(att, s['bone'], W)
        else: continue
        scr = np.stack([(pts[:, 0] - x0)*scale, (y1 - pts[:, 1])*scale], 1)
        atl = uv_to_atlas(uvs, regs[path], tw, th)
        for i in range(0, len(tris), 3):
            a, b, c = tris[i:i+3]
            draw_tri(out, tex, scr[[a, b, c]], atl[[a, b, c]], color, add)
    rgb = np.where(out[..., 3:4] > 1e-6, out[..., :3] / np.maximum(out[..., 3:4], 1e-6), 0)
    img = np.concatenate([rgb, out[..., 3:4]], -1)
    return Image.fromarray((np.clip(img, 0, 1)*255).astype(np.uint8), 'RGBA')

def load(dirp, name):
    """<dir>/<name>.json (SkelToJson), .atlas.txt and .png -> (skeleton, atlas regions, RGBA float texture)."""
    skel = json.load(open(os.path.join(dirp, name + '.json')))
    page, regs = parse_atlas(open(os.path.join(dirp, name + '.atlas.txt'), encoding='utf-8', errors='replace').read())
    tex = np.asarray(Image.open(os.path.join(dirp, name + '.png')).convert('RGBA'), float) / 255
    return skel, regs, tex
