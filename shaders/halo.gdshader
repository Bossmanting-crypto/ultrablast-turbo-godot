// Soft glow disc with a breathing ring, behind charge crystals.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform float uT = 0.0;
uniform vec3 uC = vec3(0.5, 1.6, 2.0);
void fragment(){
  vec2 p = UV*2.0-1.0; float r = length(p);
  float a = pow(max(0.0,1.0-r),3.0)*0.9 + smoothstep(0.03,0.0,abs(r-0.62-0.04*sin(uT*4.0)))*0.6;
  ALBEDO = uC; ALPHA = clamp(a, 0.0, 1.0);
}
