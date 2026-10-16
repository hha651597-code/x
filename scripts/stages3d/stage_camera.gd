class_name StageCamera
extends RefCounted

static func focal(cam: Dictionary) -> float:
	return float(cam["view"][1]) * 0.5 / tan(deg_to_rad(float(cam["fov"]) * 0.5))


static func solve(lane: Dictionary, cam: Dictionary, cam_x: float, zoom: float, shake := Vector2.ZERO, lift := 0.0) -> Transform3D:
	var ppu := float(cam["px_per_unit"])
	var half_h := float(cam["view"][1]) * 0.5
	var f := focal(cam)
	var d := f / (ppu * zoom)
	var py := float(cam["feet_row"]) + lift * zoom + shake.y - half_h
	var a := atan(py / f)
	var dist := d / cos(a)
	var pitch := deg_to_rad(float(cam["pitch"]))
	var el := pitch + a
	var up := StageLoader.color3(lane["up"]).normalized()
	var axis := StageLoader.color3(lane["axis"]).normalized()
	var face := up.cross(axis)
	var pos := StageLoader.color3(lane["origin"]) + axis * (cam_x / ppu) - axis * (shake.x / (ppu * zoom)) - face * (dist * cos(el)) + up * (dist * sin(el))
	return Transform3D(Basis.looking_at(face * cos(pitch) - up * sin(pitch), up), pos)


static func feet(lane: Dictionary, cam: Dictionary, x_px: float) -> Vector3:
	return StageLoader.color3(lane["origin"]) + StageLoader.color3(lane["axis"]).normalized() * (x_px / float(cam["px_per_unit"]))
