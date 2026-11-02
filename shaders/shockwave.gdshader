// Expanding shockwave shell: fresnel rim with faint latitude bands.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
#include "res://shaders/include/std_varyings.gdshaderinc"
uniform float uA = 0.0;
uniform vec3 uC = vec3(1.0);
void vertex(){ STD_VERTEX; }
void fragment(){
  vec3 V=normalize(CAMERA_POSITION_WORLD-vW); float fr=pow(1.0-abs(dot(normalize(vN),V)),2.5);
  float bands = 0.5+0.5*sin(UV.y*60.0);
  ALBEDO = uC; ALPHA = clamp((fr*0.9+bands*0.05)*uA, 0.0, 1.0);
}
