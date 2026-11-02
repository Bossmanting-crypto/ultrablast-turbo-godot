// Bubblegum thruster bubble behind the ship during turbo moments: swirling pink/gold fresnel.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
#include "res://shaders/include/std_varyings.gdshaderinc"
global uniform float uTime;
uniform float uAmt = 0.0;
void vertex(){ STD_VERTEX; }
void fragment(){
  vec3 V=normalize(CAMERA_POSITION_WORLD-vW); float fr=pow(1.0-abs(dot(normalize(vN),V)),2.2);
  float sw = 0.5+0.5*sin(vP.y*8.0+uTime*6.0+vP.x*5.0);
  vec3 col = mix(vec3(1.0,0.45,0.75), vec3(1.0,0.85,0.4), sw);
  ALBEDO = col*0.9; ALPHA = clamp((0.04+fr*0.5)*uAmt, 0.0, 1.0);
}
