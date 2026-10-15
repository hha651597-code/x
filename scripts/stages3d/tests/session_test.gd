extends SceneTree

var checks := 0
var failures := 0


func _initialize() -> void:
	var s := Session.new()
	_is(s.stage.is_empty(), "a new session has no stage")
	for entry: Dictionary in Stages.LIST:
		s.stage = entry
		_is(s.stage["id"] == entry["id"], "%s keeps its id" % entry["id"])
		_is(not is_same(s.stage, entry), "%s is copied, not shared with Stages.LIST" % entry["id"])
		_is(s.stage.has("map") == entry.has("map"), "%s keeps its map" % entry["id"])
		_is(s.stage.has("map") == s.stage.has("light") and s.stage.has("map") == s.stage.has("time") and s.stage.has("map") == s.stage.has("light_full"), "%s has time, light and light_full only when it has a map" % entry["id"])
	var g: Dictionary = {}
	for entry: Dictionary in Stages.LIST:
		if entry.has("map"):
			g = entry
	_is(not g.is_empty(), "Stages.LIST has a 3D stage")
	s.stage = g
	_is(s.stage["time"] == "day" and not s.stage["light"]["night"], "default time is day")
	s.stage_time = "night"
	_is(s.stage["time"] == "night" and s.stage["light"]["night"], "stage_time re-derives time and light on the stage already picked")
	s.stage = {}
	_is(s.stage.is_empty(), "begin-style reset to {} works")
	s.stage = g
	_is(s.stage["time"] == "night", "a stage picked after stage_time takes it")
	s.stage_time = "dusk"
	_is(s.stage["time"] == g["times"][0], "a time the stage lacks falls back to its first")
	s.stage["light_full"]["key_color"][0] = 99.0
	s.stage = g
	_is(float(s.stage["light_full"]["key_color"][0]) != 99.0, "the cached light is copied on every read")
	_is(not Stages.LIST.is_empty() and not Stages.LIST[0].has("time"), "Stages.LIST itself never gains keys")
	s.stage_time = "day"
	s.stage = g
	var l: Dictionary = s.stage["light"]
	_is(l["key_color"] is Color and l["ambient"] is Color and l["key_dir"] is Vector3 and l["night"] is bool, "light is published as Color, Vector3 and bool")
	_is(absf(l["key_dir"].length() - 1.0) < 0.001, "key_dir is a unit vector")
	_is(l["key_dir"].distance_to(Vector3(-0.4438, 0.8951, 0.0423)) < 0.002, "day key_dir is BA's realtime key in view space")
	_is(_near(l["key_color"], Color(1.0, 1.0, 1.0)) and _near(l["ambient"], Color(0.723, 0.723, 0.723)), "day key_color and ambient")
	s.stage_time = "night"
	l = s.stage["light"]
	_is(l["night"] and l["key_dir"].distance_to(Vector3(-0.4452, 0.8926, 0.0708)) < 0.002, "night key_dir and flag")
	_is(l["fighter_dir"].distance_to(Vector3(-0.3856, 0.7755, 0.5).normalized()) < 0.002, "night fighter_dir is the kit's front-biased key")
	_is(_near(l["key_color"], Color(0.683, 0.75, 1.0)) and _near(l["ambient"], Color(0.391, 0.391, 0.76)), "night key_color and ambient")
	_is(s.stage.has("light_full") and s.stage["light_full"].has("points"), "the kit's own descriptor stays on the stage as light_full")
	s.stage_time = "day"
	l = s.stage["light"]
	_is(l["fighter_dir"] is Vector3 and absf(l["fighter_dir"].length() - 1.0) < 0.001, "fighter_dir is a unit vector")
	_is(l["fighter_dir"].distance_to(Vector3(0.5964, 0.4964, 0.6308)) < 0.002, "day fighter_dir is the baked sun, which lights the faces")
	var ghost := {"id": "ghost", "name": "Ghost", "plate": "bg/BG_View_Kivotos.jpg", "map": "no-such-map", "times": ["day"]}
	s.stage = ghost
	_is(not s.stage.has("map") and not s.stage.has("times") and not s.stage.has("light") and not s.stage.has("time"), "a 3D stage with no assets becomes a plate stage")
	_is(s.stage["plate"] == ghost["plate"] and s.stage["id"] == "ghost", "and keeps its id and plate")
	s.begin("training")
	_is(s.stage.is_empty(), "begin() clears the stage")
	print("SESSION_TEST %s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)


func _is(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", what)


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.002 and absf(a.g - b.g) < 0.002 and absf(a.b - b.b) < 0.002
