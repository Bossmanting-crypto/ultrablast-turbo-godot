// Wingtip vapour trail: a camera-facing ribbon (UV.x = age, 0 at the wingtip; UV.y = across) in the thruster state
// colour with the same pearl sheen as the exhaust. COLOR.a carries the per-point intensity (speed, turn rate).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
global uniform float uTime;
uniform vec3 uCol = vec3(0.6, 0.9, 1.4);
uniform float uPearl = 1.0;
vec3 film(float t) { return 0.5 + 0.5 * cos(6.28318 * (t + vec3(0.0, 0.33, 0.67))); }
void fragment() {
	float age = UV.x;
	float across = 1.0 - pow(abs(UV.y * 2.0 - 1.0), 1.6);
	vec3 sheen = film(age * 1.4 - uTime * 0.5 + UV.y * 0.35);
	vec3 col = mix(uCol, uCol * (0.45 + sheen) * 0.9 + sheen * 0.25, uPearl);
	float near_cam = smoothstep(3.0, 7.0, length(VERTEX));   // never smear across the lens
	ALBEDO = col * pow(1.0 - age, 1.6) * across * COLOR.a * 0.4 * near_cam;
}
