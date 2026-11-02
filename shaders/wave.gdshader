// Orb superblast wave: hot magenta fresnel shell with a scrolling hex-ish grid. Boost through it.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
#include "res://shaders/include/std_varyings.gdshaderinc"
global uniform float uTime;
uniform float uA = 1.0;
void vertex(){ STD_VERTEX; }
void fragment(){
  vec3 V=normalize(CAMERA_POSITION_WORLD-vW); float fr=pow(1.0-abs(dot(normalize(vN),V)),2.0);
  vec2 uv = vec2(UV.x, 1.0-UV.y);
  float hex = step(0.85, fract(uv.x*60.0)) + step(0.85, fract(uv.y*30.0 + uTime));
  ALBEDO = vec3(1.0,0.45,0.9)*1.5; ALPHA = clamp((fr*0.7+hex*0.15)*uA, 0.0, 1.0);
}
