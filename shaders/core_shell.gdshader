// The world core's glass shell: fresnel glass with latitude/meridian lines, hex plates in defense mode and a
// noise dissolve when the core breaks open.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;
#include "res://shaders/include/noise.gdshaderinc"
#include "res://shaders/include/std_varyings.gdshaderinc"
global uniform float uTime; uniform float uDissolve; uniform float uDefense; uniform float uAlarm;
void vertex(){ STD_VERTEX; }
void fragment(){
  float n = fbm(vP*0.22 + vec3(0.0, uTime*0.05, 0.0));
  float thr = uDissolve*1.1 - 0.05;
  if(n < thr) discard;
  float edge = smoothstep(0.07, 0.0, n - thr) * step(0.001, uDissolve);
  vec3 V = normalize(CAMERA_POSITION_WORLD - vW); float fr = pow(1.0 - abs(dot(normalize(vN), V)), 2.5);
  vec3 d = normalize(vP); float lon = atan(d.z,d.x);
  float eq = smoothstep(0.014, 0.0, abs(d.y));
  float mer = smoothstep(0.02, 0.0, abs(sin(lon*1.0))*sqrt(1.0-d.y*d.y));
  float lat2 = smoothstep(0.01,0.0,abs(abs(d.y)-0.5));
  vec3 glass = vec3(0.22,0.5,1.0), defc = vec3(1.0,0.32,0.12);
  vec3 base = mix(glass, defc, uDefense);
  float sw = fbm(vP*0.3 + vec3(uTime*0.08));
  vec2 hp = vec2(lon*9.0, d.y*14.0); vec2 hc = abs(fract(hp)-0.5); float plate = smoothstep(0.46,0.5,max(hc.x,hc.y))*uDefense;
  vec3 col = base*(0.12 + fr*1.5 + sw*0.12) + vec3(1.0,0.32,0.28)*eq*1.2 + vec3(0.45,1.0,0.5)*(mer*0.8+lat2*0.4) + defc*plate*1.5;
  col += vec3(1.0,0.75,0.5)*edge*1.4 + uAlarm*vec3(1.0,0.25,0.1)*(fr+0.2);
  float a = 0.14 + fr*0.65 + eq*0.6 + mer*0.4 + lat2*0.25 + edge + plate*0.5;
  ALBEDO = col; ALPHA = clamp(a,0.0,1.0);
}
