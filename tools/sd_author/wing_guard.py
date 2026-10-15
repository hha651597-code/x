"""Authors Hina's wing poses (guard, air dash, glide) and writes them to a sidecar GLB.

Run with Blender in background mode:
  blender -b --factory-startup --python tools/sd_author/wing_guard.py -- <Hina.glb> <out_extra.glb>
Writes one action per pose, each keying the wing bones' local rotations only (the game drops scale tracks, see
SdFighterActor._merge_clips):
  Wing_Guard      wings folded across the chest, over Normal_Attack_Delay (block, block_air)
  Wing_Guard_Low  the same over Stand_Idle (block_low)
  Wing_Dash       wings swept back, over Normal_Attack_Delay (dash_air)
  Wing_Glide      wings spread from the Exs pose, flapping slowly in a loop (glide)
The game plays them as a bone overlay (sd.json: {"clip": "Wing_Guard", "at": 0.0, "bones": ["Bone_Wing_*"]}), so each
action holds the wings' local poses on its own base. A pose whose size is not the base clips' 0.65 also keys Wing_Root
and the overlay names it: the sidecar cannot carry a scale, so an overlay that includes Wing_Root plays the wings at 1.0.

A static pose aims each wing joint to joint along three directions in the body's frame (forward, own-side lateral, up;
lateral is positive toward the wing's own side and the right wing mirrors it): bone 01 so the elbow (the head of bone 02)
lies along `upper` from the wing root, bone 02 so the wrist (the head of bone 03) lies along `fore` from the elbow, bone 03
so its tip lies along `tip` from the wrist. The bones keep their own lengths, so a direction places a joint, not a point.
Then each bone twists about its own axis until the side its membrane hangs on faces `hang`. SD_WING_<NAME> ("fw,lat,up"
x4: upper, fore, tip, hang) overrides a pose without a code edit. SD_RENDER=<prefix> also writes stills of the static
poses from the game's two camera sides, the front and the back.
"""
import bpy, sys, os, math
from mathutils import Vector, Quaternion, Matrix

POSES = {
    # base: (clip, seconds) the pose is authored over; size: Wing_Root scale (the base clips play 0.65); aim: upper, fore, tip, hang
    "Wing_Guard": {"base": ("Normal_Attack_Delay", 0.5), "size": 0.65, "aim": ((0.8, 0.3, 0.4), (0.1, -0.85, 0.3), (-0.1, -0.9, 0.1), (0, 0, -1))},
    "Wing_Guard_Low": {"base": ("Stand_Idle", 0.5), "size": 0.65, "aim": ((0.8, 0.3, 0.4), (0.1, -0.85, 0.3), (-0.1, -0.9, 0.1), (0, 0, -1))},
    "Wing_Dash": {"base": ("Normal_Attack_Delay", 0.5), "size": 1.0, "aim": ((-0.6, 0.7, 0.5), (-0.8, 0.3, 0.5), (-0.9, 0.1, 0.4), (0, 0, -1))},
    # flap: loop length in frames, then per wing bone (degrees raised on average, degrees flapped about the body's forward
    # axis, phase lag in cycles)
    "Wing_Glide": {"base": ("Exs", 2.0), "size": 1.0, "flap": (36, ((10.0, 7.0, 0.0), (6.0, 12.0, 0.12), (0.0, 9.0, 0.24)))},
}
SIDES = {"L": 1.0, "R": -1.0}

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


def sample(action, seconds):
    arm.animation_data.action = bpy.data.actions[action]
    frame = 1.0 + seconds * fps
    scene.frame_set(int(math.floor(frame)), subframe=frame - math.floor(frame))
    update()
    return {pb.name: pb.matrix_basis.copy() for pb in pose}


def rotate(pb, q, pivot=None):
    """Turns a pose bone by q (armature space) about `pivot` (default: its head)."""
    m = pb.matrix.copy()
    p = m.translation.copy() if pivot is None else pivot
    pb.matrix = Matrix.Translation(p) @ q.to_matrix().to_4x4() @ Matrix.Translation(-p) @ m
    update()


def aim(name, along, target):
    """Swings a pose bone about its head so `along` (armature space) points at `target`."""
    pb = pose[name]
    rotate(pb, along.normalized().rotation_difference((target - pb.head).normalized()))


def chain_axis(n):
    """The direction a wing bone points along its chain: to the next bone's head, or for the last bone to its own tail."""
    pb = pose[n]
    if n.endswith("03"):
        return (pb.tail - pb.head).normalized()
    return (pose[n[:-1] + str(int(n[-1]) + 1)].head - pb.head).normalized()


def membrane_sides():
    """Per wing bone, the mean offset of the vertices it moves most from its axis, in the bone's own frame: the side its
    membrane hangs on. Read off the base pose, so twisting a bone to point that side somewhere is exact on any pose."""
    body = bpy.data.objects["Hina_Original_Body.001"]
    mesh_obj = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = mesh_obj.to_mesh()
    names = {g.index: g.name for g in body.vertex_groups}
    total = {}
    for v in mesh.vertices:
        if not v.groups:
            continue
        n = names[max(v.groups, key=lambda g: g.weight).group]
        if n.startswith("Bone_Wing_"):
            axis = chain_axis(n)
            o = arm.matrix_world.inverted() @ (mesh_obj.matrix_world @ v.co) - pose[n].head
            total.setdefault(n, []).append(o - axis * o.dot(axis))
    mesh_obj.to_mesh_clear()
    return {n: pose[n].matrix.inverted().to_3x3() @ (sum(o, Vector()) / len(o)) for n, o in total.items()}


def twist(pb, hang, sail):
    """Twists a wing bone about its own axis so its membrane side points along `hang` as far as the axis allows."""
    axis = chain_axis(pb.name)
    cur = pb.matrix.to_3x3() @ sail[pb.name]
    cur -= axis * cur.dot(axis)
    hang = hang - axis * hang.dot(axis)
    if cur.length > 1e-6 and hang.length > 1e-6:
        angle = cur.angle(hang)
        rotate(pb, Quaternion(axis, angle if cur.cross(hang).dot(axis) >= 0 else -angle))


def start(spec):
    """Poses the armature on the pose's base with the wings at the pose's size. Returns the base bases and the body's
    axes (pelvis, forward, lateral toward the left wing, up) in armature space."""
    base = sample(*spec["base"])
    # no action while posing: an assigned action is re-evaluated on update() and would undo the aims. The armature
    # object keeps this frame's transform, so the axes below are this frame's.
    arm.animation_data.action = None
    for pb in pose:
        pb.matrix_basis = base[pb.name]
    size = spec["size"]
    pose["Wing_Root"].scale = Vector((size, size, size))
    update()
    up = (arm.matrix_world.inverted().to_3x3() @ Vector((0, 0, 1))).normalized()
    pelvis = pose["Bip001 Pelvis"].head.copy()
    lat = pose["Bip001 L Thigh"].head - pose["Bip001 R Thigh"].head
    lat = (lat - up * lat.dot(up)).normalized()
    fw = lat.cross(up).normalized()
    if fw.dot(pose["Wing_Root"].head - pelvis) > 0:
        fw = -fw
    return base, (pelvis, fw, lat, up)


def aimed(name, spec):
    """A static pose: [the wing bones' local rotations], the axes."""
    upper, fore, tip, hang = spec["aim"]
    env = os.environ.get("SD_WING_" + name.upper())
    if env:
        v = [float(x) for x in env.split(",")]
        upper, fore, tip, hang = tuple(v[0:3]), tuple(v[3:6]), tuple(v[6:9]), tuple(v[9:12])
    _, axes = start(spec)
    pelvis, fw, lat, up = axes
    sail = membrane_sides()
    for side, sign in SIDES.items():
        def toward(joint, t):
            return joint + fw * t[0] + lat * (sign * t[1]) + up * t[2]
        b1, b2, b3 = [pose["Bone_Wing_%s0%d" % (side, i)] for i in (1, 2, 3)]
        hang_at = fw * hang[0] + lat * (sign * hang[1]) + up * hang[2]
        aim(b1.name, b2.head - b1.head, toward(b1.head, upper))
        twist(b1, hang_at, sail)
        aim(b2.name, b3.head - b2.head, toward(b2.head, fore))
        twist(b2, hang_at, sail)
        aim(b3.name, b3.tail - b3.head, toward(b3.head, tip))
        twist(b3, hang_at, sail)
    report = []
    for side in SIDES:
        for label, point in [("elbow", pose["Bone_Wing_%s02" % side].head), ("wrist", pose["Bone_Wing_%s03" % side].head), ("tip", pose["Bone_Wing_%s03" % side].tail)]:
            d = point - pelvis
            report.append("%s %s (%+.3f %+.3f %+.3f)" % (side, label, d.dot(fw), d.dot(lat), d.dot(up)))
    print("SD_AUTHOR", name, "(fw lat up):", "  ".join(report))
    return [{pb.name: pb.matrix_basis.copy() for pb in pose}] * 2, axes


def flapped(name, spec):
    """A loop: the base wing pose with each wing raised and lowered about the body's forward axis, each bone a little behind
    the one before it."""
    frames, amps = spec["flap"]
    base, axes = start(spec)
    pelvis, fw, lat, up = axes
    out_frames = []
    for i in range(frames + 1):
        for pb in pose:
            pb.matrix_basis = base[pb.name]
        pose["Wing_Root"].scale = Vector((spec["size"],) * 3)
        update()
        for side, sign in SIDES.items():
            for n, (raise_by, amp, lag) in enumerate(amps):
                a = raise_by + amp * math.sin(2.0 * math.pi * (float(i) / frames - lag))
                rotate(pose["Bone_Wing_%s0%d" % (side, n + 1)], Quaternion(fw, math.radians(sign * a)))
        out_frames.append({pb.name: pb.matrix_basis.copy() for pb in pose})
    print("SD_AUTHOR", name, "loops", frames, "frames")
    return out_frames, axes


def render(prefix, name, axes):
    pelvis, fw, lat, up = axes
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 0.95
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x, scene.render.resolution_y = 420, 420
    scene.display.shading.color_type = "TEXTURE"
    scene.display.shading.light = "FLAT"
    w = arm.matrix_world
    centre = w @ (pelvis + up * 0.1)
    c65, s65 = math.cos(math.radians(65)), math.sin(math.radians(65))
    for view, c in {"R": fw * c65 - lat * s65, "L": fw * c65 + lat * s65, "front": fw, "back": -fw}.items():
        look = (w.to_3x3() @ c).normalized()
        cam.location = centre + look * 3.0
        cam.rotation_euler = (-look).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = "%s_%s_%s.png" % (prefix, name, view)
        bpy.ops.render.render(write_still=True)


actions = {}
for name, spec in POSES.items():
    frames, axes = flapped(name, spec) if "flap" in spec else aimed(name, spec)
    if os.environ.get("SD_RENDER") and "flap" not in spec:
        render(os.environ["SD_RENDER"], name, axes)
    act = bpy.data.actions.new(name)
    arm.animation_data.action = act
    keyed = [pb for pb in pose if pb.name.startswith("Bone_Wing_") or (pb.name == "Wing_Root" and spec["size"] != 0.65)]
    for i, basis in enumerate(frames):
        for pb in pose:
            pb.matrix_basis = basis[pb.name]
        for pb in keyed:
            pb.keyframe_insert("rotation_quaternion", frame=i)
    actions[name] = act

# the sidecar: the model's node tree without meshes, and these actions only
arm.animation_data.action = None
for a in list(bpy.data.actions):
    if a.name not in actions:
        bpy.data.actions.remove(a)
for o in bpy.data.objects:
    if o.animation_data:
        o.animation_data.action = None
for name, act in actions.items():
    track = arm.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, 0, act)
bpy.ops.object.select_all(action="DESELECT")
for o in bpy.data.objects:
    if o.type in ("ARMATURE", "EMPTY"):
        o.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.gltf(filepath=out, use_selection=True, export_animations=True, export_animation_mode="ACTIONS",
                          export_skins=True, export_morph=False, export_materials="NONE")
print("SD_AUTHOR wrote", out, ", ".join(actions))
