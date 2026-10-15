class_name RigMotion
extends RefCounted
## Turns a Fighter's simulation state into bone poses + an expression for its SpriteRig.
## Each rigged student has a subclass (motion_<name>.gd) that overrides sample(); everything shared lives here.
##
## Bone pose = {bone: [rot_deg, dx, dy]} (rig px, art space — see SpriteRig). `fl` is the art's native facing
## (1 = art faces right, -1 = art faces left), `L` = the Fighter, `rig` = the SpriteRig.

var rig: SpriteRig
var L: Fighter
var fl := 1
var cur: Dictionary = {}          # smoothed bone pose
var extra: Dictionary = {}        # additive bone offsets from the view's spring channels (lean/twist/hair wobble)
var face_now := ""
var _blink_t := -1.0
var _next_blink := 2.2
var _face_hold := ""
var _face_until := 0.0

func setup(r: SpriteRig, fighter: Fighter, native: int) -> void:
	rig = r
	L = fighter
	fl = native

## Override: return {"pose": {...}, "face": "key", "rate": smoothing speed (1/s), "blink": true}
func sample(_t: float, _mff: float) -> Dictionary:
	return {"pose": {}, "face": "", "rate": 14.0}

## Called every render frame by FighterView. t = view time (s), mff = smoothed move frame.
func update(delta: float, t: float, mff: float) -> void:
	var s := sample(t, mff)
	var target: Dictionary = s.get("pose", {})
	var rate := float(s.get("rate", 14.0))
	var k := 1.0 - exp(-rate * delta)
	var out := {}
	var names := {}
	for b in cur:
		names[b] = true
	for b in target:
		names[b] = true
	for b in names:
		var a: Array = cur.get(b, [0.0, 0.0, 0.0])
		var g: Array = target.get(b, [0.0, 0.0, 0.0])
		var n := []
		for i in 3:
			var av: float = a[i] if i < a.size() else 0.0
			var gv: float = g[i] if i < g.size() else 0.0
			n.append(av + (gv - av) * k)
		if absf(n[0]) < 0.01 and absf(n[1]) < 0.01 and absf(n[2]) < 0.01 and not target.has(b):
			continue
		out[b] = n
	cur = out
	var posed := out.duplicate(true)
	add(posed, extra)
	rig.set_pose(posed)
	_apply_face(delta, t, String(s.get("face", "")), bool(s.get("blink", true)), bool(s.get("closed", false)))

func _apply_face(delta: float, t: float, face: String, blink_ok: bool, closed := false) -> void:
	if face != "" and face != face_now:
		if rig.set_face(face):
			face_now = face
	if closed:
		rig.set_blink(true)
		_blink_t = -1.0
		return
	if not blink_ok:
		rig.set_blink(false)
		_blink_t = -1.0
		return
	if _blink_t >= 0.0:
		_blink_t -= delta
		if _blink_t < 0.0:
			rig.set_blink(false)
	elif t >= _next_blink:
		rig.set_blink(true)
		_blink_t = 0.13
		_next_blink = t + 2.6 + 1.7 * absf(sin(t * 1.37))

# ── helpers for subclasses ───────────────────────────────────────────────────
## Add pose `src` scaled by w into `dst` (per-bone accumulate).
static func add(dst: Dictionary, src: Dictionary, w := 1.0) -> void:
	if w == 0.0:
		return
	for b in src:
		var s: Array = src[b]
		var d: Array = dst.get(b, [0.0, 0.0, 0.0])
		dst[b] = [d[0] + s[0] * w, d[1] + (s[1] if s.size() > 1 else 0.0) * w, d[2] + (s[2] if s.size() > 2 else 0.0) * w]

static func mix(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	add(out, a, 1.0 - t)
	add(out, b, t)
	return out

static func smooth01(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

## Move phases from the simulation: w = wind-up 0..1 (during startup), s = strike 0..1 (1 while active), r = recovery 1..0.
func phases(mff: float) -> Dictionary:
	var m: Dictionary = L.move
	if m.is_empty():
		return {"w": 0.0, "s": 0.0, "r": 0.0, "u": 0.0}
	var st := float(m["startup"])
	var ac := float(m["active"])
	var rc := float(m["recovery"])
	var fr := mff
	if fr < st:
		return {"w": smooth01((fr + 1.0) / maxf(st, 1.0)), "s": 0.0, "r": 0.0, "u": fr / maxf(st, 1.0)}
	if fr < st + ac + 1.0:
		return {"w": 1.0, "s": 1.0, "r": 0.0, "u": (fr - st) / maxf(ac, 1.0)}
	return {"w": 0.0, "s": smooth01(1.0 - (fr - st - ac - 1.0) / maxf(rc * 0.85, 1.0)), "r": 1.0, "u": (fr - st - ac) / maxf(rc, 1.0)}
