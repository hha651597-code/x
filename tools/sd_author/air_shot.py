"""Authors Air_Shot_Down, an aimed-down air shot, from a student's own clips, and writes it to a sidecar GLB.

Run with Blender in background mode:
  blender -b --factory-startup --python tools/sd_author/air_shot.py -- <Model.glb> <out_extra.glb> <legs_clip> <legs_seconds> <x> <y> <z>
x, y, z: the game's aim axis (the SD actor's pivot RIGHT, after its idle-heading turn) in the glTF scene's space.

Upper body: the student's firing clip (Normal_Attack_Ing), frame by frame. Legs: one frame of a jump-like clip.
The gun turns AIM degrees down about the right (trigger) hand, which drops and pulls in toward the hip; both arms reach
the gun by two-bone IK in their own bend plane, so the elbows fold instead of the shoulders swinging; the spine leans
in a little and the head looks down part of the way. The game's GLB is not changed: the sidecar holds the armature and
this action only. The action starts as a copy of the firing clip, so the clip's node motion (the armature object, the
body node, the muzzle) comes along, and the export keeps the model's node tree so the track paths match.
"""
import bpy, sys, math
from mathutils import Vector, Quaternion, Matrix

AIM = float(__import__("os").environ.get("SD_AIM", "35"))          # gun pitch down, degrees; the game's aim layer adds per-move tweaks on top
SPINE = float(__import__("os").environ.get("SD_SPINE", "0.3"))   # share of AIM the spine leans in
HEAD = float(__import__("os").environ.get("SD_HEAD", "0.35"))     # share of AIM the head looks down, on top of the spine
DROP = float(__import__("os").environ.get("SD_DROP", "0.0"))         # hands drop this far (model units, the model is about 0.6 tall here)
REACH = float(__import__("os").environ.get("SD_REACH", "0.02"))     # and reach this far out along the line of fire
SOURCE = "Normal_Attack_Ing"
NAME = "Air_Shot_Down"
LEGS = ["Thigh", "Calf", "Foot", "Toe0", "Thigh Twist"]

args = sys.argv[sys.argv.index("--") + 1:]
src, out, legs_clip, legs_s = args[0], args[1], args[2], float(args[3])
coords = [float(a) for a in args[4:7]]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
scene = bpy.context.scene
fps = scene.render.fps
arm = bpy.data.objects["Bip001"]
pose = arm.pose.bones
to_arm = arm.matrix_world.inverted().to_3x3()


def update():
    bpy.context.view_layer.update()


def sample(action, frame):
    arm.animation_data.action = bpy.data.actions[action]
    scene.frame_set(int(math.floor(frame)), subframe=frame - math.floor(frame))
    update()
    return {pb.name: pb.matrix_basis.copy() for pb in pose}


def rotate(pb, q, pivot=None):
    """Turn a pose bone by q (armature space) about `pivot` (default: its head)."""
    m = pb.matrix.copy()
    p = m.translation.copy() if pivot is None else pivot
    r = q.to_matrix().to_4x4()
    new = Matrix.Translation(p) @ r @ Matrix.Translation(-p) @ m
    pb.matrix = new
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


def side_world():
    """The game's aim axis (the SD actor's pivot RIGHT) in Blender world space. The game gives it in the glTF scene's
    space, Y up; the importer turns that into Blender's Z up as (x, y, z) -> (x, -z, y)."""
    return Vector((coords[0], -coords[2], coords[1])).normalized()


side_w = side_world()
legs_pose = sample(legs_clip, legs_s * fps + 1)
start, end = bpy.data.actions[SOURCE].frame_range
act = bpy.data.actions[SOURCE].copy()
act.name = NAME
frames = {}
for f in range(int(start), int(end) + 1):
    base = sample(SOURCE, f)
    # no action while posing: an assigned action is re-evaluated on update() and would feed the last frame back in.
    # The armature object keeps frame f's transform, so the axes below are this frame's.
    arm.animation_data.action = None
    to_arm = arm.matrix_world.inverted().to_3x3()
    axis = (to_arm @ side_w).normalized()
    up = (to_arm @ Vector((0, 0, 1))).normalized()
    fwd = axis.cross(up).normalized()
    for pb in pose:
        legs = any(pb.name.endswith(" " + k) for k in LEGS)
        pb.matrix_basis = legs_pose[pb.name] if legs else base[pb.name]
    update()
    rh, lh, wp = pose["Bip001 R Hand"], pose["Bip001 L Hand"], pose["Bip001_Weapon"]
    grip = rh.matrix.inverted() @ wp.matrix          # the gun rides the trigger hand (the game reattaches it so)
    # 1. the spine leans in, carrying the arms
    for name in ["Bip001 Spine", "Bip001 Spine1"]:
        rotate(pose[name], Quaternion(axis, math.radians(AIM * SPINE / 2.0)))
    rh0, lh0 = rh.matrix.copy(), lh.matrix.copy()
    # 2. the arms swing the rest of the aim about the shoulders, then reach out along the new line of fire
    chest = (pose["Bip001 R Clavicle"].head + pose["Bip001 L Clavicle"].head) / 2.0
    swing = Quaternion(axis, math.radians(AIM * (1.0 - SPINE))).to_matrix().to_4x4()
    line = Quaternion(axis, math.radians(AIM)) @ fwd
    move = Matrix.Translation(line * REACH - up * DROP) @ Matrix.Translation(chest) @ swing @ Matrix.Translation(-chest)
    rh1, lh1 = move @ rh0, move @ lh0
    # 3. two-bone IK puts each hand on the gun; the elbows find their own bend
    for hand, target in [("R", rh1), ("L", lh1)]:
        two_bone(pose["Bip001 %s UpperArm" % hand], pose["Bip001 %s Forearm" % hand], pose["Bip001 %s Hand" % hand], target.translation)
        pb = pose["Bip001 %s Hand" % hand]
        m = target.copy()
        m.translation = pb.matrix.translation
        pb.matrix = m
        update()
    wp.matrix = rh.matrix @ grip
    update()
    rotate(pose["Bip001 Head"], Quaternion(axis, math.radians(AIM * HEAD)))
    frames[f] = {pb.name: pb.matrix_basis.copy() for pb in pose}

arm.animation_data.action = act
for f, basis in frames.items():
    for pb in pose:
        pb.matrix_basis = basis[pb.name]
        pb.keyframe_insert("location", frame=f)
        pb.keyframe_insert("rotation_quaternion", frame=f)
        pb.keyframe_insert("scale", frame=f)

RENDER = __import__("os").environ.get("SD_RENDER", "")
if RENDER:
    # dev: side-on stills of the new clip next to the source clip, from the game's side (the camera looks along the
    # aim axis), so a pose can be judged before it goes into the game
    users = [o for o in bpy.data.objects if o.animation_data]
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 0.9
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x, scene.render.resolution_y = 360, 360
    scene.display.shading.color_type = "TEXTURE"
    world_up = Vector((0, 0, 1))
    views = {"side": side_w, "cross": side_w.cross(world_up).normalized()}
    for name, action in [("src", bpy.data.actions[SOURCE]), ("new", act)]:
        for o in users:
            o.animation_data.action = action
        fr = int(start) + 8
        scene.frame_set(fr)
        centre = arm.matrix_world @ pose["Bip001 Pelvis"].head + Vector((0, 0, 0.08))
        for vname, v in views.items():
            for sign in (1, -1):
                look = -v * sign
                cam.location = centre - look * 3.0
                cam.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()
                scene.render.filepath = "%s_%s_%s%+d.png" % (RENDER, name, vname, sign)
                bpy.ops.render.render(write_still=True)
    for o in users:
        o.animation_data.action = bpy.data.actions[SOURCE]
    arm.animation_data.action = act

# the sidecar: the model's node tree without meshes, and this action only
users = [o for o in bpy.data.objects if o.animation_data and o.animation_data.action == bpy.data.actions[SOURCE]]
for o in users:
    o.animation_data.action = act
for a in list(bpy.data.actions):
    if a != act:
        bpy.data.actions.remove(a)
bpy.ops.object.select_all(action="DESELECT")
for o in bpy.data.objects:
    if o.type in ("ARMATURE", "EMPTY"):
        o.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.gltf(filepath=out, use_selection=True, export_animations=True, export_animation_mode="ACTIONS",
                          export_skins=True, export_morph=False, export_materials="NONE")
print("SD_AUTHOR wrote", out, NAME, int(end - start + 1), "frames")
