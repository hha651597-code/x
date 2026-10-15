extends SceneTree
## Hina's five close and command moves, every displayed frame, both facings: what sd_anim_test does not measure on them.
## The face stays within 90 degrees of the camera, the gun stays in the hand and off the floor, the lowest foot stays on the
## floor line, and the kicks reach the same on screen in both facings.
## Run with TEST=res://scripts/models/tests/hina_melee_pose_test.gd tools/sd_test.sh (a real small window).

## key: [frames, startup, active]
const MOVES := {"close_L": [22, 6, 3], "close_H": [37, 11, 4], "6L": [27, 9, 3], "6H": [48, 20, 4], "throw": [38, 7, 3]}
const KICKS := ["close_L", "6L", "6H"]
## The planted foot may sit this far from the sd.json ankle: the raw Normal_Attack_Delay clip holds its rear foot 0.027 high.
const FLOOR_TOL := 0.05
## The two facings' kick feet, projected, fight px. The yaw adds the foot's sideways offset to one facing and takes it from
## the other, so a kick pulled in line with the pelvis (kick_in) stays within a few px.
const REACH_TOL := 15.0

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("HINA_MELEE_POSE FAIL ", label)

func _run() -> void:
	await process_frame
	var actor: Node = (load("res://scripts/models/sd_fighter_actor.gd") as Script).new()
	root.add_child(actor)
	actor.setup({"key": "hina"})
	actor.blending = false
	var sk: Skeleton3D = actor.grip_skeleton
	var ankle := float(actor.cfg["ankle"])
	var head := sk.find_bone(String(actor.cfg["bones"]["head"]))
	actor.pose("idle", 0, "", {}, 0, 0, 1)
	var rest: Basis = (actor.pivot.global_transform.affine_inverse() * sk.global_transform * sk.get_bone_global_pose(head)).basis
	var axis := Vector3.BACK
	for v in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD]:
		if (rest * v).dot(Vector3.RIGHT) > (rest * axis).dot(Vector3.RIGHT):
			axis = v
	for key in MOVES:
		var m: Array = MOVES[key]
		var move := {"frames": m[0], "startup": m[1], "active": m[2]}
		for face in [1, -1]:
			for mf in range(-1, int(m[0]) - 1):
				actor.pose("attack", 0, key, move, mf, 0, face)
				var tag := "%s f%d mf %d" % [key, face, mf]
				var look: Vector3 = ((sk.global_transform * sk.get_bone_global_pose(head)).basis * axis).cross(Vector3.UP)
				check(absf(rad_to_deg(atan2(look.x, look.z))) < 90.0, tag + ": the face stays within 90 degrees of the camera")
				var hand: Transform3D = sk.global_transform * sk.get_bone_global_pose(actor.grip_bone) * actor.grip_offset
				check(hand.origin.distance_to(sk.global_transform * sk.get_bone_global_pose(actor.weapon_bone).origin) < 0.001, tag + ": the gun stays in the hand")
				var socket: Dictionary = actor.muzzle_socket
				var muzzle: Vector3 = socket["skeleton"].global_transform * socket["skeleton"].get_bone_global_pose(socket["bone"]) * socket["local"]
				check(muzzle.y >= 0.0, tag + ": the muzzle stays above the floor (%.3f)" % muzzle.y)
				var lowest := INF
				for leg in actor.legs:
					lowest = minf(lowest, (sk.global_transform * sk.get_bone_global_pose(leg[2]).origin).y)
				check(absf(lowest - ankle) <= FLOOR_TOL, tag + ": a foot stays on the floor line (%.3f, ankle %.3f)" % [lowest, ankle])
	for key in KICKS:
		var m: Array = MOVES[key]
		var reach := {}
		for face in [1, -1]:
			actor.pose("attack", 0, key, {"frames": m[0], "startup": m[1], "active": m[2]}, int(m[1]), 0, face)
			var best := Vector2.INF
			for leg in actor.legs:
				var px: Vector2 = (actor.camera.unproject_position(sk.global_transform * sk.get_bone_global_pose(leg[2]).origin) + actor.body.offset) * actor.body.scale
				if best == Vector2.INF or px.y < best.y:
					best = px
			reach[face] = best.x * float(face)
		check(absf(reach[1] - reach[-1]) <= REACH_TOL, "%s: the kick foot reaches %.0f px facing right and %.0f facing left (tol %.0f)" % [key, reach[1], reach[-1], REACH_TOL])
	print("HINA_MELEE_POSE ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
