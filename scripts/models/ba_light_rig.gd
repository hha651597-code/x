extends RefCounted
## Stage light descriptor -> the five global uniforms of shaders/ba_light.gdshaderinc (registered in project.godot [shader_globals]).
## A stage publishes Game.session.stage["light"] as a Dictionary; every key is optional and falls back to DEFAULT, as does a key
## of the wrong type or with a NaN, INF or negative colour:
##   night        bool     dims the lit tone and darkens the shadows
##   key_color    Color    the main light's colour times its intensity, as stored (not linearised; channels may exceed 1)
##   ambient      Color    the scene's equator ambient colour times its intensity
##   fighter_dir  Vector3  unit vector toward the light that shades fighters, camera view space (x right, y up, z toward the viewer)
## "key_dir" (the baked key light) is not read: it sits nearly edge-on to the camera (z 0.04 to 0.07), which leaves every
## camera-facing normal in shadow. The fighters keep one readable direction per stage and the stage drives colour and intensity.

const DEFAULT := {
	"night": false,
	"key_color": Color(1.0, 0.98, 0.95),
	"ambient": Color(0.7, 0.7, 0.7),
	"fighter_dir": Vector3(-0.35, 0.75, 0.6),
}
## Share of the key colour that reaches the lit tone and of the ambient hue that reaches the shadow tone.
const TONE_FOLLOW := 0.6
const SHADOW_FOLLOW := 0.4
const NIGHT_TONE := 0.85
const NIGHT_SHADOW := 0.9
const NIGHT_INTENSITY := 0.9
const AMBIENT_SCALE := 0.1

## One descriptor key: the stage's value when it has the default's type and is finite (a colour also not negative), else the default.
static func _read(light: Dictionary, key: String) -> Variant:
	var v: Variant = light.get(key)
	var d: Variant = DEFAULT[key]
	if typeof(v) != typeof(d):
		return d
	match typeof(v):
		TYPE_COLOR:
			var c: Color = v
			if not (is_finite(c.r) and is_finite(c.g) and is_finite(c.b) and c.r >= 0.0 and c.g >= 0.0 and c.b >= 0.0):
				return d
		TYPE_VECTOR3:
			if not (v as Vector3).is_finite():
				return d
	return v

## The five global uniforms for a descriptor, by name.
static func values(light: Dictionary) -> Dictionary:
	var night: bool = _read(light, "night")
	var key: Color = _read(light, "key_color")
	var amb: Color = _read(light, "ambient")
	var dir: Vector3 = _read(light, "fighter_dir")
	if dir.length() < 0.001:
		dir = DEFAULT["fighter_dir"]
	var amb_v := Vector3(amb.r, amb.g, amb.b)
	var hue := amb_v / maxf(maxf(amb.r, maxf(amb.g, amb.b)), 0.001)
	return {
		"ba_light_dir": dir.normalized(),
		"ba_light_tone": Vector3.ONE.lerp(Vector3(key.r, key.g, key.b), TONE_FOLLOW) * (NIGHT_TONE if night else 1.0),
		"ba_shadow_tone": Vector3.ONE.lerp(hue, SHADOW_FOLLOW) * (NIGHT_SHADOW if night else 1.0),
		"ba_light_data": Vector4(NIGHT_INTENSITY if night else 1.0, 1.0, 0.0, 0.0),
		"ba_ambient": amb_v * AMBIENT_SCALE,
	}

static func apply(light: Dictionary) -> void:
	var v := values(light)
	for name in v:
		RenderingServer.global_shader_parameter_set(name, v[name])
