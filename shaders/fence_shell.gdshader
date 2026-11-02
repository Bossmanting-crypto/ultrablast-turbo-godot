// Electric fence shell around the core in defense mode: crackling additive fresnel.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
#include "res://shaders/include/noise.gdshaderinc"
#include "res://shaders/include/std_varyings.gdshaderinc"
global uniform float uTime; uniform float uOn;
void vertex(){ STD_VERTEX; }
void fragment(){
  vec3 V=normalize(CAMERA_POSITION_WORLD-vW); float fr=pow(1.0-abs(dot(normalize(vN),V)),3.0);
  float n = vnoise(vP*0.6 + vec3(uTime*4.0)); float crack = smoothstep(0.52,0.5,abs(n-0.5)+0.48);
  ALBEDO = vec3(0.5,0.95,1.0); ALPHA = (fr*0.35 + crack*0.25)*uOn;
}
