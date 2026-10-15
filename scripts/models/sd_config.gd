extends RefCounted
## Per-character SD model data: assets/ba/sd/<roster key>/sd.json over these defaults, cached per key.
## "anims" maps each state anim (Fighter.STATE_NAMES but attack, plus walk_back, block_low, block_air, carried, intro_cut,
## intro_run and intro_stop) to a descriptor. "carried" is what a fighter wears while a throw carries it and while it tumbles
## after the release (the throw's carry dict names it, sync() plays it from f.carry_anim before any state anim); the view rolls
## the body about the pelvis by f.carry_roll, so it is a standing pose.
## The stage entry plays intro_cut in the fighter's own solo shot (idle before it, held through the pan and the other shot)
## and intro on the wide block; intro_run and intro_stop are the old run-in's, dormant,
## "moves" maps kit move keys, and "move_default" covers every move key that "moves" lacks.
## A kit can also name an anim of its own (dash_air, glide): while the fighter is in JUMP, sync() plays the anim named in
## f.kv["anim"] at tick f.kv["anim_t"] when this file has it, else the plain jump. A crushed fighter (BLOCK with
## crush_t > 0) plays "hit" from its first tick. A descriptor:
##   clip        source clip name
##   from, to    seconds window inside the clip (default: the whole clip)
##   mode        "loop" (default) wraps at speed; "fit" stretches the span over from..to; "hold" plays at speed and
##               stops at `to`. A negative speed runs backwards (loop wraps back, fit goes to..from, hold starts at `to`)
##   speed       clip seconds per sim second (default 1)
##   stride      [left, right]: body px per sim tick at speed 1.0 that keep the planted foot still on the floor, per facing (the
##               yaw makes the foot's screen speed differ). On walk, walk_back and dash, sync() then plays the clip by the
##               distance the body travelled, signed along the facing (walking back runs the clip backwards from the same phase;
##               a walk or dash starts at 0), at most 1.6x a tick. A walk follows any sim speed (class, debuff, buff); the dash stride is fitted to the 1.3x stat, so sd_foot_test checks it.
##               Leave speed at 1.0 there. A stride is the planted foot's screen speed over the part of the clip the anim plays:
##               a walk loops, so it is the mean over its stances; a dash only plays the first 15 to 25 clip ticks, so its stride
##               is fitted to those (tools/sd_measure.sh does not measure it; scripts/models/tests/sd_foot_test.gd checks it)
##   frames      a state's span in ticks, for fit and keyframed layers (a move's span is its own frames)
##   phases      descriptors played in turn, each lasting its "over" ("startup", "active", "recovery" or a frame count);
##               the last one runs to the end. Keys on the parent (layers, overlays) apply to every phase. A loop phase
##               keeps running while a held move holds its frame
##   overlays    [{clip, at | from/to/mode/speed, bones: [glob, ...]}]: those bones' local poses from another clip.
##               Overlays never set the grip hand, its ancestors (arm, spine, pelvis) or its children, so the gun arm
##               always comes from the base clip
##   tilt        whole-model pitch in degrees, negative leans back; about the planted foot ("tilt_pivot": "feet",
##               default), the lower foot ("plant", for a kick: "feet" rolls over the kicking foot and lifts the other)
##               or the pelvis ("hips", for air poses). Keep it to a lean for weight; aiming is "aim"
##   aim         upper-body pitch in degrees toward the line of fire, negative aims up: the spine bends and both arms
##               swing about the shoulders while hips and legs keep the clip's stance; the head follows about half.
##               "aim_spine" is the spine's share (default 0.6); air shots aim more with the arms (0.4)
##   aim_arms    degrees the arms swing past what aim gives them, down when positive: the gun held clear of a leg or the floor
##   twist, twist_head  degrees the spine turns about the vertical axis, negative bringing the left shoulder forward; the
##               neck gives twist_head (default 0.7) of it back so the face stays on the foe. Hips and feet stay
##   kick, kick_up  the forward foot's offset from where the clip puts it, model units forward and up, by leg IK; the other
##               foot and the hips stay (a kick). Numbers or keyframes like tilt
##   kick_in     0 to 1: draws that foot's sideways position to the pelvis's, so the kick reaches the same in both facings
##   kick_pitch  degrees that foot turns about the lateral axis, negative lifting the toes (-90: the sole faces forward)
##   reach, reach_up  the free left hand's offset from where the clip puts it, model units forward and up, by arm IK (a
##               grab). The grip hand and the gun stay
##   grip, grip_up, grip_pitch  the gun hand's offset like reach, then its turn in degrees about the lateral axis, down
##               when positive; the gun follows the hand
##   clip_aim    the degrees a clip authored in Blender already aims down (tools/sd_author), for the SD suite's level check
## "extra_clips" names a sidecar GLB of clips authored in Blender; the actor adds them to the model's player
##   turn        whole-model yaw in degrees about the pelvis's vertical axis, only to undo a clip set's turned root (Hina's Stand_Idle kneel,
##               Hoshino's Move_Ing), so every anim keeps the facing yaw
##   lift        the whole model's rise in world units, a number or keyframes like tilt (the backdash hop: no foot is on the floor, so there is
##               no planted foot to skate). It is part of the crossfade's snapshot, so a landing eases down instead of popping
##   crouch      pelvis drop in world units (the model is height_units tall); leg IK keeps each foot where the clip put it
##   blend       ticks of crossfade into this anim from the pose shown before (default 3, 0 snaps); top level only
## Layer values (tilt, aim, turn, crouch) are a number or keyframes [[t, value], ...] over t = 0..1 of the span.
## "ankle" is the foot bones' height above the floor in the idle clip's first frame (setup() stands the model there).
## setup() also stands that frame's pelvis on the feet origin, the axis of the facing yaw (+-"yaw"), so a fighter turns
## around in place.
## "crown" is the top of the hair above the head bone, world units, without halo, horns or ahoge; tools/sd_measure.sh
## takes the hurtbox height from it.
## "camera" y is the view centre in world units; it sits low so lying poses keep room under the floor line.

const DEFAULTS := {
	"height_meshes": ["Body"], "height_units": 2.15, "yaw": 65.0, "camera": {"size": 3.65, "y": 0.97}, "ankle": 0.045, "crown": 0.53,
	"bones": {"weapon": "Bip001_Weapon", "head": "Bip001 Head", "grip": "", "foot_suffix": " Foot",
		"spine": ["Bip001 Spine", "Bip001 Spine1"], "neck": "Bip001 Neck", "arms": ["Bip001 R Clavicle", "Bip001 L Clavicle"],
		"arm_l": ["Bip001 L UpperArm", "Bip001 L Forearm", "Bip001 L Hand"]},
	"muzzle": ["fire_01", "fire_02"], "hide": [], "halo_overlay": false, "hide_shield_fx": false,
	"anims": {}, "moves": {}, "move_default": {"clip": "Normal_Idle", "mode": "hold", "speed": 0},
}

static var _cache := {}

## The merged config, or {} when the fighter has no sd.json.
static func of(key: String) -> Dictionary:
	if _cache.has(key):
		return _cache[key]
	var cfg := {}
	var path := "res://assets/ba/sd/%s/sd.json" % key
	if key != "" and FileAccess.file_exists(path):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary:
			cfg = DEFAULTS.duplicate(true)
			cfg.merge(data, true)
			for k in ["camera", "bones"]:
				cfg[k] = DEFAULTS[k].merged(data.get(k, {}), true)
		else:
			push_error("SD config is not a JSON object: " + path)
	_cache[key] = cfg
	return cfg
