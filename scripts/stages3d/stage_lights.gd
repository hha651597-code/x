class_name StageLights
extends RefCounted

const FRONT_N := Vector3(0.5736, 0.0, 0.8192)
const BAND_LO := 0.12
const BAND_HI := 0.15
const CHEST_PX := 120.0
const FALLBACK := {
	"night": false,
	"key_color": [1.0, 1.0, 1.0],
	"key_dir": [-0.35, 0.75, 0.6],
	"shadow": [0.73, 0.73, 0.93],
	"under": [1.0, 1.0, 1.0],
	"points": [],
}


static func descriptor(variant: Dictionary) -> Dictionary:
	var d: Dictionary = FALLBACK.duplicate(true)
	var l: Variant = variant.get("light")
	if l is Dictionary:
		d.merge(l, true)
	return d


# not fully functional. min_front is ours, BA's own unit light is almost straight down and leaves one facing in shadow.
static func toon_dir(dir_map: Vector3, min_front: float) -> Vector3:
	var d := dir_map.normalized()
	if d.z >= min_front:
		return d
	var xy := Vector2(d.x, d.y)
	if xy.length() < 0.0001:
		return Vector3(0.0, 0.0, 1.0)
	xy = xy.normalized() * sqrt(1.0 - min_front * min_front)
	return Vector3(xy.x, xy.y, min_front)


static func band(n: Vector3, dir: Vector3) -> float:
	return smoothstep(BAND_LO, BAND_HI, n.normalized().dot(dir.normalized()))


static func front_bands(dir: Vector3) -> Vector2:
	return Vector2(band(FRONT_N, dir), band(Vector3(-FRONT_N.x, FRONT_N.y, FRONT_N.z), dir))


static func front_lit(dir: Vector3) -> bool:
	var b := front_bands(dir)
	return b.x > 0.99 and b.y > 0.99


static func falloff(dist: float, radius: float) -> float:
	if radius <= 0.0:
		return 0.0
	var q := clampf(dist / radius, 0.0, 1.0)
	var w := 1.0 - q * q
	return w * w


static func flicker(stage_time: float, amount: float, seed_value: float) -> float:
	var t := stage_time + seed_value * 7.31
	return 1.0 + amount * (0.6 * sin(t * 13.0) + 0.4 * sin(t * 5.3 + 1.7))


static func point_light(points: Array, pos: Vector3, stage_time := 0.0) -> Dictionary:
	var sum := Vector3.ZERO
	var weight := 0.0
	for i in points.size():
		var p: Dictionary = points[i]
		var d := pos.distance_to(Vector3(p["x"], p["y"], p["z"]))
		var w := falloff(d, float(p["radius"])) * float(p["gain"])
		if p.has("flicker"):
			w *= flicker(stage_time, float(p["flicker"]), float(p.get("seed", i)))
		var c: Array = p["color"]
		sum += Vector3(c[0], c[1], c[2]) * w
		weight += w
	var peak := maxf(sum.x, maxf(sum.y, sum.z))
	if weight <= 0.0 or peak <= 0.0:
		return {"color": Vector3.ONE, "weight": 0.0}
	return {"color": sum / peak, "weight": minf(weight, 1.0)}


static func point_dir(points: Array, pos: Vector3) -> Vector3:
	var sum := Vector3.ZERO
	for p: Dictionary in points:
		var to := Vector3(p["x"], p["y"], p["z"]) - pos
		var w := falloff(to.length(), float(p["radius"])) * float(p["gain"])
		if to.length() > 0.001:
			sum += Vector3(to.x, to.y, -to.z).normalized() * w
	return sum.normalized() if sum.length() > 0.0001 else Vector3(0.0, 0.0, 1.0)


static func fighter_params(desc: Dictionary, x_px: float, stage_time := 0.0, use_points := true, shade_mix := 1.0) -> Dictionary:
	var under: Array = desc["under"]
	var k: Array = desc["key_color"]
	var lit := Vector3(k[0], k[1], k[2])
	var sh: Array = desc["shadow"]
	var shade := lit * Vector3.ONE.lerp(Vector3(sh[0], sh[1], sh[2]), shade_mix)
	var chest := Vector3(x_px, CHEST_PX, 0.0)
	var pl := {"color": Vector3.ONE, "weight": 0.0}
	if use_points:
		pl = point_light(desc["points"], chest, stage_time)
	var dir: Array = desc["key_dir"]
	return {
		"key_dir": Vector3(dir[0], dir[1], dir[2]),
		"lit_color": lit,
		"shade_color": shade,
		"under_color": Vector3(under[0], under[1], under[2]),
		"point_color": pl["color"],
		"point_weight": pl["weight"],
		"point_dir": point_dir(desc["points"], chest) if use_points else Vector3(0.0, 0.0, 1.0),
	}
