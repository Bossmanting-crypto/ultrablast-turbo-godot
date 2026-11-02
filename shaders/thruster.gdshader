// Jet exhaust. Reference: Louis du Mont's realtime thruster FX for Blender (CG Boost, shown on blender.fi,
// 2024): a mesh-and-shader plume, no simulation. Three nested cones per nozzle, picked by uLayer:
//   0 sheath  - wide, made of thin filaments: noise stretched along the cone and scrolling out of the nozzle,
//               breaking into loose wisps toward the tail
//   1 jet     - narrower, denser and lighter, gone by mid-plume
//   2 needle  - a hair-thin near-white line down the axis
// Thin shock rings and sparks are spawned by the ship script. One throttle value (uPow) drives brightness,
// reach and scroll speed, like the reference's single slider.
// Colour: the thruster state (uC1 hot -> uC2 tail: blue cruise, cyan thrust, gold blast, white homing,
// magenta turbo), kept saturated so it reads as colour under the bloom instead of a white blob, with a
// pearlescent thin-film sheen sliding along it (uPearl).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
global uniform float uTime;
uniform vec3 uC1 = vec3(1.0, 0.75, 0.35);
uniform vec3 uC2 = vec3(1.0, 0.25, 0.1);
uniform float uPow = 1.0;
uniform float uPearl = 1.0;
uniform int uLayer = 0;
uniform float uSeed = 0.0;
varying float vH;

vec3 film(float t) { return 0.5 + 0.5 * cos(6.28318 * (t + vec3(0.0, 0.33, 0.67))); }
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
// noise that wraps around the cone (UV.x is the angle) so there is no seam
float ring_noise(float ang, float along, float cells) {
	float a = ang * cells;
	return mix(vnoise(vec2(a, along)), vnoise(vec2(a - cells, along)), fract(ang));
}
// keep the hue, peak channel = 1 (so a hot cyan stays cyan instead of clipping to white)
vec3 hue_of(vec3 c) { return c / max(max(c.r, c.g), max(c.b, 1e-3)); }

void vertex() {
	vec3 p = VERTEX;
	float h = -p.z;
	float flare = uLayer == 0 ? 0.4 : (uLayer == 1 ? 0.15 : 0.0);
	float w = 1.0 + (uLayer == 2 ? 0.0 : 0.06 * sin(uTime * 55.0 + h * 18.0 + uSeed));
	w *= 1.0 + flare * smoothstep(0.0, 0.5, h);
	p.xy *= w;
	vH = h;
	VERTEX = p;
}

void fragment() {
	float t = clamp(vH, 0.0, 1.0);
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float scroll = uTime * (4.0 + uPow * 5.0);
	float n1 = ring_noise(UV.x, t * 1.6 - scroll + uSeed, 11.0);
	float n2 = ring_noise(UV.x, t * 3.6 - scroll * 1.6 + uSeed * 3.0, 23.0);
	float streak = smoothstep(0.45, 0.95, n1 * 0.55 + n2 * 0.55);     // thin bright filaments
	float reach = clamp(0.55 + uPow * 0.45, 0.45, 1.0);
	vec3 hue = mix(hue_of(uC1), hue_of(uC2), smoothstep(0.0, 0.8, t));
	vec3 sheen = film(t * 0.9 - uTime * 0.4 + n1 * 0.35 + (1.0 - facing) * 0.6 + uSeed * 0.1);
	vec3 pearl = mix(hue, hue * (0.45 + 0.85 * sheen) + sheen * 0.15, uPearl * 0.65);
	float gain = 0.35 + uPow;
	vec3 col;
	float a;
	if (uLayer == 0) {
		float soft = pow(facing, 1.3);   // soft volume: no hard cone silhouette
		float fade = 1.0 - smoothstep(reach * 0.25, reach, t);
		a = (0.12 + 0.88 * streak) * mix(1.0, streak, smoothstep(0.05, 0.45, t)) * fade * soft;
		col = pearl * 0.85 * gain;
	} else if (uLayer == 1) {
		float soft = pow(facing, 1.1);
		a = (0.4 + 0.6 * streak) * (1.0 - smoothstep(0.0, reach * 0.5, t)) * soft;
		col = mix(vec3(1.0), pearl, 0.9) * 0.26 * gain;   // dense but still coloured: the white is left to the needle and rings
	} else {
		a = (1.0 - smoothstep(0.0, reach * 0.85, t)) * (0.85 + 0.15 * sin(uTime * 80.0 + uSeed));
		col = mix(vec3(1.0), hue, 0.35 + 0.4 * t) * 0.75 * gain;
	}
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
}
