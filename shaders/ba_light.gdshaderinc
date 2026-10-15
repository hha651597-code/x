// Stage light for the SD fighters' Blue Archive shaders (ba_body, ba_hair, ba_face, ba_outline).
// Provenance: our rewrite from the disassembled pixel and vertex shaders of Blue Archive (MX/C-General/Layer4, C-Hair, C-Face,
// Outline passes); the layout of the four stage vectors follows BA's _MxCharLightDir,
// _MxCharLightTone, _MxCharShadowTone and _MxCharLightData. Their values are not in the game files; scripts/models/ba_light_rig.gd
// derives ours from the stage's "light" descriptor. Not for redistribution.
//
// The globals are registered in project.godot [shader_globals] (a global must exist before a shader naming it is parsed) and set
// by ba_light_rig.gd. All are raw linear numbers, as BA feeds them into the lighting math.

global uniform vec3 ba_light_dir;    // toward the key light, camera view space, fixed per character so shadow shapes do not change an action's read
global uniform vec3 ba_light_tone;   // colour of lit areas
global uniform vec3 ba_shadow_tone;  // multiplier on every material's shadow tint
global uniform vec4 ba_light_data;   // x = light intensity (scales lit tone and rim), y = shadow bias (1 = none, below 1 raises every shadow threshold by (1 - y) * 0.15)
global uniform vec3 ba_ambient;      // flat ambient added to the tone

float ba_thr_bias() {
	return (1.0 - ba_light_data.y) * 0.15;
}

// lit tone or shadow tone for a given shade amount, scaled by intensity, plus ambient
vec3 ba_tone(vec3 shadow_colour, float shade) {
	return mix(ba_light_tone, shadow_colour, shade) * ba_light_data.x + ba_ambient;
}

// colour of the rim light: stronger on the lit side, never below 0.3 of the light tone
vec3 ba_rim_light(float n_dot_l) {
	return (clamp(n_dot_l * 4.0 + 0.25, 0.0, 1.0) * 0.4 + 0.3) * ba_light_tone;
}
