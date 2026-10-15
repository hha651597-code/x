"""Authors Hoshino's close strikes, command normals and throw, and writes them to a sidecar GLB.

Run with Blender in background mode:
  blender -b --factory-startup --python tools/sd_author/stock_bash.py -- <Hoshino.glb> <out_extra.glb>

The game keeps the weapon at a fixed offset from the grip hand, so everything the gun does has to be baked into the clip.
Each action starts as a copy of Normal_Attack_Delay (her legs, her breathing and the node motion come along) and keys the
pose bones on every frame of it:
  Shoulder_Bump  the gun is brought up to her shoulder and she coils, then drives her shoulder in    (close_L)
  Stock_Bash     the gun is turned over (muzzle back, stock forward), drawn back, then driven forward    (close_H)
  Muzzle_Jab     the gun is drawn in to her chest, then thrust out at arm's length                      (6L)
  Stock_Drop     the gun is turned over and raised stock up over her head, then dropped forward         (6H)
  Shoulder_Toss  the gun hangs at her hip, the free left hand grabs, hoists overhead and heaves down    (throw)
Every blow lands on the clip time of the move's first active tick: the descriptors in sd.json map startup, active and
recovery onto fixed spans of the clip, so a key's time is the game's time (the sim runs 60 ticks a second).
All rest after the last key, so a descriptor can read any part of the clip. Per frame a key table gives the gun's turn
about the vertical (yaw, from her aim stance, whose barrel stands 52 degrees left of her hips' forward: -52 points it
along her hips' forward, -232 turns it straight back), its pitch, where the right hand goes (forward, up, left, in armature
units: her arm is 0.21, her height 0.6, a unit is about 280 px), and how far the torso twists and leans. The neck and head
give back most of that twist and lean so the face never turns 90 degrees from the camera. Both arms reach their places
on the gun by two-bone IK in their own bend plane. The legs are not authored here: sd.json layers (crouch, kick, tilt)
step and sink them.
"""
import bpy, sys, math
from mathutils import Vector, Quaternion, Matrix

SOURCE = "Normal_Attack_Delay"
GAZE = 0.8        # the share of the torso's twist and lean the head gives back
SLIDE = 0.03      # how far past the fore-end the left hand slides along the barrel, in armature units (her arm is 0.21, her height 0.6)
# seconds, ease into the key (s smooth, o fast then settling, i slow then fast), then yaw, pitch (muzzle up), forward, up,
# left (armature units), torso twist (toward her left), torso lean (forward), degrees where not units
KEYS = {
    "Shoulder_Bump": [
        (0.000, "s", 0, 0, 0.000, 0.000, 0.000, 0, 0),
        (0.040, "s", 0, 40, -0.020, 0.030, -0.020, -26, -8),
        (0.083, "o", 0, 55, -0.010, 0.040, -0.020, 24, 16),
        (0.150, "s", 0, 55, -0.010, 0.040, -0.020, 24, 16),
        (0.330, "s", 0, 0, 0.000, 0.000, 0.000, 0, 0),
    ],
    "Muzzle_Jab": [
        (0.000, "s", 0, 0, 0.000, 0.000, 0.000, 0, 0),
        (0.080, "s", -52, 8, -0.110, -0.010, -0.020, -22, -6),
        (0.150, "o", -52, 0, 0.070, 0.010, 0.000, 18, 10),
        (0.220, "s", -52, 0, 0.070, 0.010, 0.000, 18, 10),
        (0.430, "s", 0, 0, 0.000, 0.000, 0.000, 0, 0),
    ],
    "Shoulder_Toss": [
        (0.000, "s", 0, 0, 0.000, 0.000, 0.000, 0, 0),
        (0.070, "s", 0, -10, -0.020, -0.040, 0.000, 0, 2),
        (0.133, "o", 0, -15, -0.020, -0.060, 0.000, 14, 8),
        (0.183, "s", 0, -15, -0.020, -0.060, 0.000, 14, 8),
        (0.233, "s", 0, -15, -0.020, -0.060, 0.000, 20, -10),
        (0.300, "o", 0, -15, -0.020, -0.060, 0.000, 4, 30),
        (0.400, "s", 0, -15, -0.020, -0.060, 0.000, 4, 30),
        (0.683, "s", 0, 0, 0.000, 0.000, 0.000, 0, 0),
    ],
    "Stock_Bash": [
        (0.00, "s", 0, 0, 0.000, 0.000, 0.000, 0, 0),
        (0.06, "s", -100, 15, -0.040, 0.010, 0.010, -16, -2),
        (0.12, "s", -232, 10, -0.090, -0.010, 0.000, -32, -8),
        (0.20, "o", -232, -4, 0.090, 0.010, 0.000, 22, 6),
        (0.32, "s", -232, -4, 0.090, 0.010, 0.000, 22, 6),
        (0.65, "s", 0, 0, 0.000, 0.000, 0.000, 0, 0),
    ],
    "Stock_Drop": [
        (0.000, "s", 0, 0, 0.000, 0.000, 0.000, 0, 0),
        (0.120, "s", -100, 20, -0.030, 0.050, 0.010, -10, 0),
        (0.260, "s", -232, -55, -0.020, 0.140, 0.010, -16, -12),
        (0.310, "s", -232, -55, -0.020, 0.140, 0.010, -20, -14),
        (0.367, "o", -232, 18, 0.110, 0.020, 0.000, 20, 12),
        (0.450, "s", -232, 18, 0.110, 0.020, 0.000, 20, 12),
        (0.870, "s", 0, 0, 0.000, 0.000, 0.000, 0, 0),
    ],
}

# how far the right hand moves up the gun to the fore-end (and the left on past it), where a clip does not turn the gun
# over: a jab keeps both hands forward so the left arm can reach
GRIP = {
    "Muzzle_Jab": [(0.000, "s", 0.0), (0.060, "s", 1.0), (0.360, "s", 1.0), (0.430, "s", 0.0)],
}

# the free left hand, where a clip lets it off the gun: grab (0 on the gun, 1 free), then forward, up, left from where the
# turned torso carries it
FREE_LEFT = {
    "Shoulder_Toss": [
        (0.000, "s", 0, 0.000, 0.000, 0.000),
        (0.070, "s", 1, 0.060, 0.030, 0.000),
        (0.133, "o", 1, 0.100, 0.040, -0.030),
        (0.183, "s", 1, 0.100, 0.040, -0.030),
        (0.233, "s", 1, -0.040, 0.300, -0.030),
        (0.300, "o", 1, 0.120, -0.120, 0.020),
        (0.400, "s", 1, 0.120, -0.120, 0.020),
        (0.683, "s", 0, 0.000, 0.000, 0.000),
    ],
}

args = sys.argv[sys.argv.index("--") + 1:]
src, out = args[0], args[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
scene = bpy.context.scene
fps = scene.render.fps
arm = bpy.data.objects["Bip001"]
pose = arm.pose.bones


def update():
    bpy.context.view_layer.update()


def sample(action, frame):
    arm.animation_data.action = bpy.data.actions[action]
    scene.frame_set(int(math.floor(frame)), subframe=frame - math.floor(frame))
    update()
    return {pb.name: pb.matrix_basis.copy() for pb in pose}


def rotate(pb, q, pivot=None):
    """Turns a pose bone by q (armature space) about `pivot` (default: its head)."""
    m = pb.matrix.copy()
    p = m.translation.copy() if pivot is None else pivot
    pb.matrix = Matrix.Translation(p) @ q.to_matrix().to_4x4() @ Matrix.Translation(-p) @ m
    update()


def two_bone(upper, lower, end, target):
    """Bends upper and lower so `end`'s head reaches target (armature space), keeping the current bend plane."""
    hip, knee, foot = upper.head.copy(), lower.head.copy(), end.head.copy()
    a, b = (knee - hip).length, (foot - knee).length
    d = target - hip
    reach = max(abs(a - b) + 1e-5, min(d.length, a + b - 1e-5))
    dirn = d.normalized()
    bend = (knee - hip) - dirn * (knee - hip).dot(dirn)
    if bend.length < 1e-6:
        bend = Vector((0, 0, -1))
    along = (a * a - b * b + reach * reach) / (2 * reach)
    side = math.sqrt(max(0.0, a * a - along * along))
    want = hip + dirn * along + bend.normalized() * side
    rotate(upper, (knee - hip).normalized().rotation_difference((want - hip).normalized()))
    knee, foot = lower.head.copy(), end.head.copy()
    rotate(lower, (foot - knee).normalized().rotation_difference((hip + dirn * reach - knee).normalized()))


EASE = {"s": lambda k: k * k * (3.0 - 2.0 * k), "o": lambda k: 1.0 - (1.0 - k) ** 2, "i": lambda k: k * k}


def smooth(t):
    return EASE["s"](t)


def key_at(table, t):
    """The key table's values at second t, eased between keys, resting before the first and holding after the last."""
    if t <= table[0][0]:
        return table[0][2:]
    for a, b in zip(table, table[1:]):
        if t <= b[0]:
            k = EASE[b[1]]((t - a[0]) / (b[0] - a[0]))
            return tuple(x + (y - x) * k for x, y in zip(a[2:], b[2:]))
    return table[-1][2:]


def axes():
    """Up, toward her left, forward, in armature space, from this frame's pelvis and thighs."""
    up = (arm.matrix_world.inverted().to_3x3() @ Vector((0, 0, 1))).normalized()
    lat = pose["Bip001 L Thigh"].head - pose["Bip001 R Thigh"].head
    lat = (lat - up * lat.dot(up)).normalized()
    fw = lat.cross(up).normalized()
    hands = (pose["Bip001 R Hand"].head + pose["Bip001 L Hand"].head) / 2.0
    if fw.dot(hands - pose["Bip001 Pelvis"].head) < 0:
        fw = -fw
    return up, lat, fw


start, end = bpy.data.actions[SOURCE].frame_range
made = {}
short = {}
for name, table in KEYS.items():
    act = bpy.data.actions[SOURCE].copy()
    act.name = name
    frames = {}
    for f in range(int(start), int(end) + 1):
        base = sample(SOURCE, f)
        # no action while posing: an assigned action is re-evaluated on update() and would feed the last frame back in
        arm.animation_data.action = None
        for pb in pose:
            pb.matrix_basis = base[pb.name]
        update()
        up, lat, fw = axes()
        yaw, pitch, fwd, rise, left, twist, lean = key_at(table, (f - start) / fps)
        rh, lh, wp = pose["Bip001 R Hand"], pose["Bip001 L Hand"], pose["Bip001_Weapon"]
        wp_base = wp.matrix.copy()
        # the hands' places on the gun, in the gun's frame: the right on the grip, the left on the fore-end
        rgl, lgl = wp_base.inverted() @ rh.matrix, wp_base.inverted() @ lh.matrix
        along = (lgl.translation - rgl.translation).normalized()
        # the barrel's direction in the gun's frame, from the muzzle empty
        barrel = (wp_base.to_3x3().inverted() @ (arm.matrix_world.inverted() @ bpy.data.objects["fire_01"].matrix_world.translation - wp.head)).normalized()
        if name in GRIP:
            flip = key_at(GRIP[name], (f - start) / fps)[0]
        else:
            flip = smooth(min(1.0, abs(yaw) / 90.0)) if name in ("Stock_Bash", "Stock_Drop") else 0.0
        r_local = rgl.copy()
        r_local.translation = rgl.translation.lerp(lgl.translation, flip)
        l_local = lgl.copy()
        l_local.translation = lgl.translation.lerp(lgl.translation + along * SLIDE, flip)
        # the torso twists toward her left and leans forward, carrying the shoulders; the hands' keyed places count from there
        for spine in ("Bip001 Spine", "Bip001 Spine1"):
            rotate(pose[spine], Quaternion(up, math.radians(twist / 2.0)))
            rotate(pose[spine], Quaternion(lat, math.radians(lean / 2.0)))
        # the head keeps its eyes on the foe: the neck and head give back most of the twist and lean, so the face never
        # turns 90 degrees from the camera
        for part in ("Bip001 Neck", "Bip001 Head"):
            rotate(pose[part], Quaternion(up, math.radians(-twist * GAZE / 2.0)))
            rotate(pose[part], Quaternion(lat, math.radians(-lean * GAZE / 2.0)))
        rh0, lh0 = rh.matrix.copy(), lh.matrix.copy()
        wp0 = rh0 @ rgl.inverted()
        # the gun turns about the vertical to its aim (yaw), then its muzzle rises (pitch) about the axis across that aim
        yawed = Quaternion(up, math.radians(yaw)).to_matrix()
        aim = yawed @ (wp0.to_3x3() @ barrel)
        aim = (aim - up * aim.dot(up)).normalized()
        rise_m = Quaternion(aim.cross(up).normalized(), math.radians(pitch)).to_matrix()
        # the right hand's keyed place counts from where the turned torso carries it
        spot = rh0.translation + fw * fwd + up * rise + lat * left
        m3 = rise_m @ yawed @ wp0.to_3x3()
        gun = Matrix.Translation(spot - m3 @ r_local.translation) @ m3.to_4x4()
        for hand, local in (("R", r_local), ("L", l_local)):
            target = gun @ local
            if hand == "L" and name in FREE_LEFT:
                grab, a, b, c = key_at(FREE_LEFT[name], (f - start) / fps)
                if grab > 0.0:
                    free = lh0.to_quaternion().slerp(target.to_quaternion(), 1.0 - grab).to_matrix().to_4x4()
                    free.translation = target.translation.lerp(lh0.translation + fw * a + up * b + lat * c, grab)
                    target = free
            two_bone(pose["Bip001 %s UpperArm" % hand], pose["Bip001 %s Forearm" % hand], pose["Bip001 %s Hand" % hand], target.translation)
            pb = pose["Bip001 %s Hand" % hand]
            short[name] = max(short.get(name, 0.0), (pb.head - target.translation).length)
            m = target.copy()
            m.translation = pb.matrix.translation
            pb.matrix = m
            update()
        wp.matrix = rh.matrix @ r_local.inverted()      # the gun rides the right hand, as the game reattaches it
        update()
        frames[f] = {pb.name: pb.matrix_basis.copy() for pb in pose}
    arm.animation_data.action = act
    for f, basis in frames.items():
        for pb in pose:
            pb.matrix_basis = basis[pb.name]
            pb.keyframe_insert("location", frame=f)
            pb.keyframe_insert("rotation_quaternion", frame=f)
            pb.keyframe_insert("scale", frame=f)
    made[name] = act

# the sidecar: the model's node tree without meshes, and these actions only, each kept alive on its own NLA track
for a in list(bpy.data.actions):
    if a.name not in made:
        bpy.data.actions.remove(a)
for o in bpy.data.objects:
    if o.animation_data:
        o.animation_data.action = None
for name, act in made.items():
    track = arm.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, int(start), act)
bpy.ops.object.select_all(action="DESELECT")
for o in bpy.data.objects:
    if o.type in ("ARMATURE", "EMPTY"):
        o.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.gltf(filepath=out, use_selection=True, export_animations=True, export_animation_mode="ACTIONS",
                          export_skins=True, export_morph=False, export_materials="NONE")
print("SD_AUTHOR a hand ends short of the gun by at most", {k: round(v, 3) for k, v in short.items()})
print("SD_AUTHOR wrote", out, ", ".join(made), int(end - start + 1), "frames at", fps, "fps")
