shader_type particles;
// look at the fx_<variant>.json next to the stage (BA ParticleSystem module values) for reference as to why i picked these numbers.
// look at tools/stage_test.sh (the freeze check) for reference as to why i picked this. Every slot is recomputed from stage_time, so a frozen stage_time freezes the smoke.

uniform float stage_time = 0.0;

uniform float time_offset = 0.0;
uniform uint seed = 0u;
uniform float rate = 5.0;
uniform float slots = 6.0;
uniform vec2 life_rng = vec2(1.0, 1.2);
uniform vec2 size_rng = vec2(0.4, 0.6);
uniform float start_speed = -0.1;
uniform vec3 accel = vec3(0.0, 1.962, 0.0);
uniform vec2 force_z_rng = vec2(-0.8, -0.4);
uniform vec2 roll_rng = vec2(-0.5236, 0.5236);
uniform vec2 roll_vel_rng = vec2(-0.6109, 0.6109);
uniform vec3 dir = vec3(0.0, 1.0, 0.0);
uniform float hscale = 1.4023;

uint hash(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return x;
}

float rnd(uint n, uint salt) {
	return float(hash(n * 0x9e3779b1u + salt * 0x85ebca6bu + seed)) / 4294967295.0;
}

void sim(uint idx, inout mat4 xf, inout vec4 cd) {
	float per = 1.0 / rate;
	float t = stage_time + time_offset;
	float k = floor((t - float(idx) * per) / (slots * per));
	float age = t - (k * slots + float(idx)) * per;
	uint n = uint(max(k, 0.0)) * uint(slots) + idx;
	float life = mix(life_rng.x, life_rng.y, rnd(n, 1u));
	xf = mat4(1.0);
	if (k < 0.0 || age >= life) {
		cd = vec4(0.0, -1.0, 0.0, 0.0);
		return;
	}
	float fz = mix(force_z_rng.x, force_z_rng.y, rnd(n, 2u));
	vec3 a = (accel + vec3(0.0, 0.0, fz)) * hscale;
	vec3 p = dir * start_speed * hscale * age + 0.5 * a * age * age;
	xf[3] = vec4(p, 1.0);
	float roll = mix(roll_rng.x, roll_rng.y, rnd(n, 3u)) + mix(roll_vel_rng.x, roll_vel_rng.y, rnd(n, 4u)) * age;
	cd = vec4(roll, age / life, 0.0, mix(size_rng.x, size_rng.y, rnd(n, 5u)) * hscale);
}

void start() {
	ACTIVE = true;
	sim(INDEX, TRANSFORM, CUSTOM);
}

void process() {
	sim(INDEX, TRANSFORM, CUSTOM);
}
