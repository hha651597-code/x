class_name SpriteSet
extends RefCounted
## One character's baked sprite frames (frames.json + PNGs) and its hand-authored animation
## data (anims.json). Read-only after load; shared by every caller.
##
## Coordinates: a frame record keeps the baker's anchors in TEXELS of the PNG (origin = feet / floor, head = top of the
## head). Per-frame overrides in anims.json are given as fractions of the PNG size ([u, v]) so they survive re-bakes at a
## different scale; nudges (dx / dy) are in WORLD px (+x = forward, the way the art faces; +y = down).
##
## PIXEL MODE (frames.json "pixel": true): one art pixel = Arena.SPRITE_H / ref_height
## world px EXACTLY (art_px, 2.0 for ref_height 165) — the "stand" / "height" / global "scale" keys are ignored — origins are whole
## texels (a pixel corner at the feet), textures are plain (no mipmaps, no edge bleed) for nearest sampling, there is no
## sticker outline and every nudge is snapped to whole art pixels at draw time (SpriteActor.place). Per-frame / per-anim
## "scale" (size fixes) still apply but are reported by validate() as not pixel-exact.

const PAD := 24                       # transparent texels added around every frame (room for the shader outline / glow)

## State slots the runtime asks for (see SpriteMotion). When a slot has no authored animation the first available
## fallback below is used ("name~" = that slot played in reverse), finally "idle".
const SLOTS := ["intro", "idle", "walk", "walk_back", "crouch", "jump_rise", "jump_apex", "jump_fall", "land", "dash",
	"backdash", "block", "block_crouch", "hit", "hit_crouch", "hit_heavy", "stun", "airhit_rise", "airhit_fall", "down",
	"getup", "ko", "win"]
const SLOT_FALLBACK := {
	"intro": ["idle"], "win": ["idle"], "walk": ["idle"], "walk_back": ["walk~"], "crouch": ["idle"],
	"jump_rise": ["jump_apex", "jump_fall"], "jump_apex": ["jump_rise", "jump_fall"], "jump_fall": ["jump_apex", "jump_rise"],
	"land": ["crouch"], "dash": ["walk"], "backdash": ["walk_back", "walk~"],
	"block": ["idle"], "block_crouch": ["block", "crouch"], "hit": ["idle"], "hit_crouch": ["hit"], "hit_heavy": ["hit"],
	"stun": ["hit"], "airhit_rise": ["airhit_fall", "hit"], "airhit_fall": ["airhit_rise", "jump_fall", "hit"],
	"down": ["ko", "airhit_fall", "hit"], "ko": ["down", "airhit_fall", "hit"], "getup": ["crouch"],
}
## Slots that loop by default when they are written inline in "states" (anything else plays once and holds its last frame).
const LOOP_SLOTS := ["idle", "walk", "walk_back"]
const PHASES := ["startup", "active", "recovery"]

var key := ""
var dir := ""                        # res:// folder of the set (frames, anims.json, halo PNGs)
var enabled := true
var pixel := false                   # pixel-art frames (see PIXEL MODE above)
var art_px := 1.0                    # pixel mode: world px per art pixel (= world_scale, a whole-pixel grid step)
var ref_height := 480.0
var world_scale := 0.6875            # world px per baked texel (before per-frame / per-anim scale)
var outline_px := 2.0                # world px of the white sticker outline (like the portrait fighters)
var frames := {}                     # name -> {name, tex, size, origin, top, halo, halo_rot, halo_on, fx, has_fx, dx, dy, scale}
var anims := {}                      # name -> {name, frames: [[frame, ticks, opts]], total, loop, stride, opts}
var states := {}                     # slot -> {anim, reverse}
var moves := {}                      # move key -> parsed spec (see _parse_move)
var transitions := {}                # "from>to" (state names, "*" wildcard) -> anim name
var halo := {}                       # halo config (SpriteHalo)
var problems: Array = []             # load-time problems, reported by validate()
var _overrides := {}
var _slot_cache := {}
var _move_cache := {}

static var _mip_cache := {}

static func load_set(k: String) -> SpriteSet:
	var s := SpriteSet.new()
	s.key = k
	s._load()
	return s

# ── loading ──────────────────────────────────────────────────────────────────
func _load() -> void:
	dir = SpriteSets.ROOT + key + "/"
	var fj := _read_json(dir + "frames.json")
	if fj.is_empty():
		problems.append("frames.json missing or invalid")
		enabled = false
		return
	ref_height = float(fj.get("ref_height", 480.0))
	var aj := _read_json(dir + "anims.json")
	if aj.is_empty():
		problems.append("anims.json missing or invalid")
	enabled = bool(aj.get("enabled", true)) and not aj.is_empty()
	pixel = bool(aj.get("pixel", fj.get("pixel", false)))
	if pixel:
		art_px = Arena.SPRITE_H / maxf(ref_height, 1.0)
	_overrides = _dict(aj.get("frames", {}))
	var fr := _dict(fj.get("frames", {}))
	for fname in fr:
		var n := String(fname)
		var e := _dict(fr[fname])
		var file := String(e.get("file", n + ".png"))
		var img := _load_image(dir + file)
		if img == null:
			problems.append("frame %s: cannot load %s" % [n, file])
			continue
		frames[n] = _make_frame(n, e, img, _dict(_overrides.get(n, {})))
	# world scale: measured on the standing frame when anims.json names one (robust to re-bakes at another scale),
	# else the contract's SPRITE_H / ref_height. Pixel art: exactly SPRITE_H / ref_height, nothing else (every art pixel
	# the same size on screen), and no sticker outline (the art has its own 1 px outline).
	var stand := String(aj.get("stand", ""))
	var stand_h := ref_height
	if frames.has(stand):
		var sr: Dictionary = frames[stand]
		stand_h = maxf(1.0, (sr["origin"] as Vector2).y - (sr["top"] as Vector2).y)
	world_scale = float(aj.get("height", Arena.SPRITE_H)) / stand_h * float(aj.get("scale", 1.0))
	outline_px = float(aj.get("outline", 2.0))
	if pixel:
		world_scale = art_px
		outline_px = 0.0
	halo = _dict(aj.get("halo", {}))
	# animations
	var an := _dict(aj.get("anims", {}))
	for aname in an:
		if String(aname).begins_with("_"):
			continue
		var a := _parse_anim(String(aname), an[aname], false)
		if not a.is_empty():
			anims[String(aname)] = a
	# state slots (a value may be an anim name, {"anim", "reverse"} or an inline frame list / anim object)
	var st := _dict(aj.get("states", {}))
	for sname in st:
		var s := String(sname)
		if s.begins_with("_"):
			continue
		var v: Variant = st[sname]
		if v is String:
			states[s] = {"anim": String(v), "reverse": false}
		elif v is Dictionary and (v as Dictionary).has("anim"):
			states[s] = {"anim": String((v as Dictionary)["anim"]), "reverse": bool((v as Dictionary).get("reverse", false))}
		else:
			var inl := _parse_anim("@" + s, v, s in LOOP_SLOTS)
			if not inl.is_empty():
				anims["@" + s] = inl
				states[s] = {"anim": "@" + s, "reverse": false}
	var tr := _dict(aj.get("transitions", {}))
	for tname in tr:
		var t := String(tname)
		if t.begins_with("_"):
			continue
		var tv: Variant = tr[tname]
		if tv is String:
			transitions[t] = String(tv)
		else:
			var ta := _parse_anim("@" + t, tv, false)
			if not ta.is_empty():
				anims["@" + t] = ta
				transitions[t] = "@" + t
	var mv := _dict(aj.get("moves", {}))
	for mname in mv:
		if String(mname).begins_with("_"):
			continue
		var sp := _parse_move(mv[mname])
		if not sp.is_empty():
			moves[String(mname)] = sp

func _make_frame(n: String, e: Dictionary, img: Image, o: Dictionary) -> Dictionary:
	var size := Vector2(img.get_width(), img.get_height())
	var origin := _vec(e.get("origin"), Vector2(size.x * 0.5, size.y))
	if o.has("origin"):
		origin = _uv(o["origin"], size, origin)
	if pixel:
		origin = origin.round()           # the feet sit on a pixel corner (keeps the grid when flipped)
	var top := _vec(e.get("head"), Vector2(size.x * 0.5, 0.0))
	var halo_at := top
	var halo_rot := 0.0
	var halo_on := true
	# the baker's head crown + head tilt (frames.json head / head_rot, + = crown tipped to the LEFT) place the halo when
	# anims.json has no per-frame "halo" override; halo_rot is in screen degrees (+ = clockwise)
	if e.has("head_rot") and e.get("head") is Array:
		halo_rot = -float(e["head_rot"])
	# anims.json "head_rot": the baker's head tilt is wrong on this frame: the crown is re-derived from head_c at that tilt
	if o.has("head_rot") and e.get("head_c") is Array:
		var hc := _vec(e["head_c"], top)
		halo_rot = -float(o["head_rot"])
		halo_at = hc + Vector2(0.0, -(top - hc).length()).rotated(deg_to_rad(halo_rot))
	if o.has("halo"):
		var h: Variant = o["halo"]
		if h is bool:
			halo_on = bool(h)
		elif h is Array and (h as Array).size() >= 2:
			halo_at = _uv(h, size, top)
			if (h as Array).size() >= 3:
				halo_rot = float((h as Array)[2])
	halo_rot += float(o.get("halo_rot", 0.0))
	var fx := Vector2.ZERO
	var has_fx := false
	if o.get("fx") is Array:
		fx = _uv(o["fx"], size, Vector2.ZERO)
		has_fx = true
	elif e.get("muzzle") is Array:
		fx = _vec(e["muzzle"], Vector2.ZERO)
		has_fx = true
	return {
		"name": n, "tex": _texture_px(img) if pixel else _texture(img), "size": size, "origin": origin, "top": top,
		"halo": halo_at, "halo_rot": halo_rot, "halo_on": halo_on, "fx": fx, "has_fx": has_fx,
		"dx": float(o.get("dx", 0.0)), "dy": float(o.get("dy", 0.0)), "scale": float(o.get("scale", 1.0)),
	}

## anim value: [entries] | {"frames": [entries], "loop", "stride", "dx", "dy", "scale", "flip"} | "frame_name".
## entry: "frame" | [frame, ticks] | [frame, ticks, {dx, dy, scale, flip}]   (ticks @ 60 Hz, default 6)
func _parse_anim(aname: String, v: Variant, loop_default: bool) -> Dictionary:
	var d := {}
	var list: Array = []
	if v is Array:
		list = v
	elif v is Dictionary:
		d = v
		list = _arr(d.get("frames", []))
	elif v is String:
		list = [v]
	var out: Array = []
	var total := 0
	for it in list:
		var en := _entry(it, 6.0)
		if en.is_empty():
			continue
		en[1] = maxi(1, int(round(float(en[1]))))
		out.append(en)
		total += int(en[1])
	if out.is_empty():
		problems.append("anim %s: no frames" % aname)
		return {}
	return {"name": aname, "frames": out, "total": maxi(total, 1), "loop": bool(d.get("loop", loop_default)),
		"stride": float(d.get("stride", 0.0)), "opts": _opts(d)}

## move value: {"startup": [..], "active": [..], "recovery": [..], "dx", "dy", "scale", "flip", "smear"}
##   phase entries: "frame" | [frame, weight] | [frame, weight, opts]  — a phase's frames share the SIM's phase length by weight
## | {"at": [[move_frame, frame], [move_frame, frame, opts], ...]}     — absolute timeline on the move frame (f.mf)
## | {"anim": name} / ["frame", ...]                                  — one animation stretched over the whole move
## | "other_move_key" or "anim_name"                                  — alias
func _parse_move(v: Variant) -> Dictionary:
	if v is String:
		return {"alias": String(v)}
	if v is Array:
		var a := _parse_anim("@move", v, false)
		return {"list": a["frames"] if not a.is_empty() else [], "opts": {}, "smear": null}
	if not (v is Dictionary):
		return {}
	var d: Dictionary = v
	var sp := {"opts": _opts(d), "smear": d.get("smear", null)}
	if d.has("alias"):
		sp["alias"] = String(d["alias"])
	if d.has("anim"):
		sp["anim"] = String(d["anim"])
	if d.has("at"):
		var at: Array = []
		for it in _arr(d["at"]):
			if it is Array and (it as Array).size() >= 2:
				var ia: Array = it
				at.append([int(ia[0]), String(ia[1]), _dict(ia[2]) if ia.size() >= 3 else {}])
		at.sort_custom(func(x: Array, y: Array) -> bool: return int(x[0]) < int(y[0]))
		if not at.is_empty():
			sp["at"] = at
	for ph in PHASES:
		if d.has(ph):
			var lst: Array = []
			var src: Variant = d[ph]
			if src is String:
				src = [src]
			for it in _arr(src):
				var en := _entry(it, 1.0)
				if not en.is_empty():
					en[1] = maxf(0.01, float(en[1]))
					lst.append(en)
			sp[ph] = lst
	return sp

static func _entry(it: Variant, def: float) -> Array:
	if it is String:
		return [String(it), def, {}]
	if it is Array and (it as Array).size() >= 1:
		var a: Array = it
		return [String(a[0]), float(a[1]) if a.size() >= 2 else def, _opts(_dict(a[2])) if a.size() >= 3 else {}]
	return []

static func _opts(d: Dictionary) -> Dictionary:
	var o := {}
	for k in ["dx", "dy", "scale"]:
		if d.has(k):
			o[k] = float(d[k])
	if d.has("flip"):
		o["flip"] = bool(d["flip"])
	return o

## Combine two nudge sets: dx / dy add, scale multiplies, flip toggles.
static func merge(a: Dictionary, b: Dictionary) -> Dictionary:
	if b.is_empty():
		return a
	if a.is_empty():
		return b
	var o := a.duplicate()
	o["dx"] = float(a.get("dx", 0.0)) + float(b.get("dx", 0.0))
	o["dy"] = float(a.get("dy", 0.0)) + float(b.get("dy", 0.0))
	o["scale"] = float(a.get("scale", 1.0)) * float(b.get("scale", 1.0))
	o["flip"] = bool(a.get("flip", false)) != bool(b.get("flip", false))
	return o

# ── queries ──────────────────────────────────────────────────────────────────
## The frame entry of animation `a` at time t (ticks). Returns [entry, index]; entry = [frame, ticks, opts].
func anim_at(a: Dictionary, t: float, reverse := false) -> Array:
	var list: Array = a["frames"]
	var total := float(a["total"])
	var tt := fposmod(t, total) if bool(a["loop"]) else clampf(t, 0.0, total - 0.001)
	if reverse:
		tt = total - 0.001 - tt
	var acc := 0.0
	for i in list.size():
		acc += float(list[i][1])
		if tt < acc:
			return [list[i], i]
	return [list[list.size() - 1], list.size() - 1]

func has_slot(slot: String) -> bool:
	return not _slot_direct(slot).is_empty()

## {anim, reverse, authored, via}: the animation to play for a state slot, following SLOT_FALLBACK when it is not
## authored (`via` = the slot whose drawing is actually used).
func resolve_slot(slot: String) -> Dictionary:
	if _slot_cache.has(slot):
		return _slot_cache[slot]
	var r := _slot_direct(slot)
	if not r.is_empty():
		r["authored"] = true
		r["via"] = slot
	else:
		for fb in SLOT_FALLBACK.get(slot, []):
			var nm := String(fb)
			var rev := nm.ends_with("~")
			if rev:
				nm = nm.substr(0, nm.length() - 1)
			var d := _slot_direct(nm)
			if not d.is_empty():
				r = d
				r["via"] = nm
				if rev:
					r["reverse"] = not bool(r["reverse"])
				break
		if r.is_empty() and slot != "idle":
			r = resolve_slot("idle").duplicate()
		if r.is_empty():
			r = {"anim": String(anims.keys()[0]) if not anims.is_empty() else "", "reverse": false, "via": ""}
		r["authored"] = false
	_slot_cache[slot] = r
	return r

func _slot_direct(slot: String) -> Dictionary:
	if states.has(slot):
		var s: Dictionary = states[slot]
		if anims.has(s["anim"]):
			return {"anim": String(s["anim"]), "reverse": bool(s["reverse"])}
	if anims.has(slot):
		return {"anim": slot, "reverse": false}
	return {}

## Transition animation to play when the state changes from `a` to `b` (state names, see Fighter.STATE_NAMES), or "".
func transition_for(a: String, b: String) -> String:
	for k in [a + ">" + b, a + ">*", "*>" + b]:
		if transitions.has(k) and anims.has(transitions[k]):
			return String(transitions[k])
	return ""

## {spec, authored, via}: the animation spec for a move. Unauthored moves borrow the nearest sensible one
## (2H → 2L → 5H…, air moves → jL, projectile moves → skill, supers → ex…), finally the idle pose.
func move_spec(mkey: String, m: Dictionary) -> Dictionary:
	if _move_cache.has(mkey):
		return _move_cache[mkey]
	var chain := _move_chain(mkey, m)
	var r := {}
	for i in chain.size():
		var sp := _resolve_move(String(chain[i]), 0)
		if not sp.is_empty():
			r = {"spec": sp, "authored": i == 0, "via": String(chain[i])}
			break
	if r.is_empty():
		r = {"spec": {"anim": String(resolve_slot("idle")["anim"]), "opts": {}, "smear": false}, "authored": false, "via": "idle"}
	_move_cache[mkey] = r
	return r

func _resolve_move(k: String, depth: int) -> Dictionary:
	if moves.has(k):
		var sp: Dictionary = moves[k]
		if sp.has("alias") and not sp.has("startup") and not sp.has("active") and not sp.has("at") and not sp.has("anim"):
			if depth > 4:
				return {}
			return _resolve_move(String(sp["alias"]), depth + 1)
		return sp
	if anims.has(k):
		return {"anim": k, "opts": {}, "smear": null}
	return {}

static func _move_chain(k: String, m: Dictionary) -> Array:
	var c: Array = [k]
	match k:
		"skill_air": c.append_array(["jL", "skill", "jH"])
		"2H": c.append_array(["2L", "5H"])
		"2L": c.append_array(["5L"])
		"jH": c.append_array(["jL", "5H"])
		"jL": c.append_array(["5L"])
		"5H": c.append_array(["5L"])
		"ex": c.append_array(["skill", "5H"])
	if bool(m.get("cutin", false)):
		c.append("ex")
	if bool(m.get("air", false)):
		c.append_array(["jL", "jH"])
	if k.begins_with("skill") or not (m.get("spawns", []) as Array).is_empty():
		c.append("skill")
	if bool(m.get("crouch", false)):
		c.append_array(["2L", "2H"])
	if not (m.get("hit", {}) as Dictionary).is_empty():
		c.append("5H" if int(m.get("startup", 0)) >= 12 else "5L")
	c.append_array(["5L", "skill"])
	return c

## The pose of move `m` (sim data) at move frame mf, following spec `sp`.
## Returns {frame, opts, phase ("startup"|"active"|"recovery"), t (ticks into the phase), first_active (bool)}.
func move_pose(sp: Dictionary, m: Dictionary, mf: int) -> Dictionary:
	var st := maxi(1, int(m.get("startup", 1)))
	var ac := maxi(1, int(m.get("active", 1)))
	var rc := maxi(1, int(m.get("recovery", 1)))
	var phase := "startup"
	var t := mf
	var plen := st
	if mf >= st + ac:
		phase = "recovery"
		t = mf - st - ac
		plen = rc
	elif mf >= st:
		phase = "active"
		t = mf - st
		plen = ac
	var base: Dictionary = sp.get("opts", {})
	var out := {"frame": "", "opts": base, "phase": phase, "t": t, "first_active": false}
	if sp.has("at"):
		var at: Array = sp["at"]
		var pick: Array = at[0]
		for e in at:
			if int(e[0]) <= mf:
				pick = e
		out["frame"] = String(pick[1])
		out["opts"] = merge(base, pick[2])
		return out
	var list: Array = []
	if sp.has("list") or sp.has("anim"):
		var a: Dictionary = {}
		if sp.has("anim"):
			a = anims.get(String(sp["anim"]), {})
		else:
			a = {"frames": sp["list"], "total": 0, "loop": false}
			var tot := 0
			for e2 in (sp["list"] as Array):
				tot += int(e2[1])
			a["total"] = maxi(tot, 1)
		if a.is_empty() or (a["frames"] as Array).is_empty():
			return out
		var total_f := float(maxi(1, int(m.get("frames", st + ac + rc))))
		var r := anim_at(a, float(mf) / total_f * float(a["total"]))
		out["frame"] = String(r[0][0])
		out["opts"] = merge(merge(base, a.get("opts", {})), r[0][2])
		return out
	list = _phase_list(sp, phase)
	if list.is_empty():
		return out
	var wsum := 0.0
	for e3 in list:
		wsum += float(e3[1])
	var x := (float(clampi(t, 0, plen - 1)) + 0.5) / float(plen) * wsum
	var acc := 0.0
	var idx := list.size() - 1
	for i in list.size():
		acc += float(list[i][1])
		if x < acc:
			idx = i
			break
	out["frame"] = String(list[idx][0])
	out["opts"] = merge(base, list[idx][2])
	out["first_active"] = phase == "active" and idx == 0
	return out

func _phase_list(sp: Dictionary, phase: String) -> Array:
	var l: Array = sp.get(phase, [])
	if not l.is_empty():
		return l
	var act: Array = sp.get("active", [])
	var stu: Array = sp.get("startup", [])
	var rec: Array = sp.get("recovery", [])
	match phase:
		"startup":
			if not act.is_empty():
				return [act[0]]
			if not rec.is_empty():
				return [rec[0]]
		"active":
			if not stu.is_empty():
				return [stu[stu.size() - 1]]
			if not rec.is_empty():
				return [rec[0]]
		"recovery":
			if not act.is_empty():
				return [act[act.size() - 1]]
			if not stu.is_empty():
				return [stu[stu.size() - 1]]
	return []

# ── validation (sprite test screen) ──────────────────────────────────────────
## Human-readable report lines: load problems, unknown frame names, slots / kit moves without an authored animation,
## unused frames. `kit_moves` = Fighter.moves of the character (key -> move dict), may be empty.
func validate(kit_moves: Dictionary) -> Array:
	var out: Array = []
	for p in problems:
		out.append("ERROR load: " + String(p))
	var used := {}
	for an in anims:
		for e in (anims[an]["frames"] as Array):
			_check_frame(String(e[0]), "anim " + String(an), out, used)
	for mk in moves:
		var sp: Dictionary = moves[mk]
		if sp.has("alias") and _resolve_move(String(mk), 0).is_empty():
			out.append("ERROR move %s: alias '%s' is neither a move nor an anim" % [mk, sp["alias"]])
		if sp.has("anim") and not anims.has(String(sp["anim"])):
			out.append("ERROR move %s: unknown anim '%s'" % [mk, sp["anim"]])
		for e in (sp.get("at", []) as Array):
			_check_frame(String(e[1]), "move " + String(mk), out, used)
		for e in (sp.get("list", []) as Array):
			_check_frame(String(e[0]), "move " + String(mk), out, used)
		for ph in PHASES:
			for e in (sp.get(ph, []) as Array):
				_check_frame(String(e[0]), "move %s.%s" % [mk, ph], out, used)
	for s in states:
		if not anims.has(String(states[s]["anim"])):
			out.append("ERROR state %s: unknown anim '%s'" % [s, states[s]["anim"]])
		if not (s in SLOTS):
			out.append("WARN state '%s' is not a slot the runtime uses (slots: %s)" % [s, ", ".join(PackedStringArray(SLOTS))])
	for t in transitions:
		if not anims.has(String(transitions[t])):
			out.append("ERROR transition %s: unknown anim '%s'" % [t, transitions[t]])
	for fname in _overrides:
		if not frames.has(String(fname)) and not String(fname).begins_with("_"):
			out.append("ERROR frames.%s: override for a frame that is not in frames.json" % fname)
	if pixel:
		for fname in frames:
			if absf(float(frames[fname]["scale"]) - 1.0) > 0.001:
				out.append("WARN frames.%s: \"scale\" %.2f on pixel art: its art pixels are %.2f world px instead of %.1f (not pixel-exact) — redraw this frame at the right size and drop the scale" % [
					fname, float(frames[fname]["scale"]), art_px * float(frames[fname]["scale"]), art_px])
		for an in anims:
			if absf(float((anims[an]["opts"] as Dictionary).get("scale", 1.0)) - 1.0) > 0.001:
				out.append("WARN anim %s: \"scale\" on pixel art is not pixel-exact — redraw instead" % an)
	for slot in SLOTS:
		if not has_slot(slot):
			var r := resolve_slot(slot)
			out.append("TODO slot %-12s not authored -> plays '%s'%s" % [slot, r["anim"], " reversed" if bool(r["reverse"]) else ""])
	for mk in kit_moves:
		var ms := move_spec(String(mk), kit_moves[mk])
		if not bool(ms["authored"]):
			out.append("TODO move %-12s not authored -> uses '%s'" % [mk, ms["via"]])
	for fname in frames:
		if not used.has(fname):
			out.append("INFO frame %s is not used by any animation" % fname)
	return out

func _check_frame(n: String, where: String, out: Array, used: Dictionary) -> void:
	used[n] = true
	if not frames.has(n):
		out.append("ERROR %s: frame '%s' is not in frames.json" % [where, n])

# ── helpers ──────────────────────────────────────────────────────────────────
func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(path)) != OK:
		problems.append("%s: JSON error line %d: %s" % [path.get_file(), j.get_error_line(), j.get_error_message()])
		return {}
	return _dict(j.data)

static func _dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}

static func _arr(v: Variant) -> Array:
	return v if v is Array else []

static func _vec(v: Variant, def: Vector2) -> Vector2:
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return def

static func _uv(v: Variant, size: Vector2, def: Vector2) -> Vector2:
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]) * size.x, float(v[1]) * size.y)
	return def

## Raw PNG bytes first (never stale after a re-bake, no import needed), the imported texture as a fallback (exports).
static func _load_image(path: String) -> Image:
	var img: Image = null
	if FileAccess.file_exists(path):
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.size() > 0:
			img = Image.new()
			if img.load_png_from_buffer(bytes) != OK:
				img = null
	if img == null and ResourceLoader.exists(path):
		var t := load(path) as Texture2D
		if t != null:
			img = t.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img

## Pixel art: padded only (room for the 2-ring pixel glow), no mipmaps and no edge bleed — sampled texel by texel.
static func _texture_px(img: Image) -> Texture2D:
	var big := Image.create_empty(img.get_width() + PAD * 2, img.get_height() + PAD * 2, false, Image.FORMAT_RGBA8)
	big.blit_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i(PAD, PAD))
	return ImageTexture.create_from_image(big)

## Padded (PAD texels of transparency all round), alpha-edge-fixed and mipmapped, so ~480 px frames downscale cleanly.
static func _texture(img: Image) -> Texture2D:
	var big := Image.create_empty(img.get_width() + PAD * 2, img.get_height() + PAD * 2, false, Image.FORMAT_RGBA8)
	big.blit_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i(PAD, PAD))
	big.fix_alpha_edges()
	big.generate_mipmaps()
	return ImageTexture.create_from_image(big)

## Mipmapped copy of an imported texture (halo layers), cached by path.
static func mip(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	var k := tex.resource_path
	if k != "" and _mip_cache.has(k):
		return _mip_cache[k]
	var img := tex.get_image()
	if img == null:
		return tex
	if img.is_compressed():
		img.decompress()
	img.fix_alpha_edges()
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	if k != "":
		_mip_cache[k] = t
	return t
