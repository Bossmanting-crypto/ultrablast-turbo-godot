// The ride zone around an orb's rail: marching dashes that brighten while riding.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
global uniform float uTime; uniform float uRail; uniform float uFade = 1.0;
void fragment(){
  float dash = smoothstep(0.6,1.0,sin(UV.x*120.0 - uTime*14.0)); float edge = sin(UV.y*3.14159);
  ALBEDO = vec3(0.7,1.0,0.45); ALPHA = clamp((0.05 + dash*0.18 + uRail*0.25)*edge*uFade, 0.0, 1.0);
}
