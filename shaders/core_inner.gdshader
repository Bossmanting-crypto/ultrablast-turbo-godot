// The purple heart inside the core: flowing glyph bands that flare with the alarm.
shader_type spatial;
render_mode unshaded, cull_back;
#include "res://shaders/include/noise.gdshaderinc"
#include "res://shaders/include/std_varyings.gdshaderinc"
global uniform float uTime; uniform float uDissolve; uniform float uDefense; uniform float uAlarm;
void vertex(){ STD_VERTEX; }
void fragment(){
  float n = fbm(vP*0.5 + 3.0);
  if(n < uDissolve*1.1 - 0.05) discard;
  vec3 d = normalize(vP); float lon = atan(d.z,d.x), lat = asin(d.y);
  float f = fbm(vP*0.6 + vec3(0.0,uTime*0.2,0.0));
  float s = sin(lon*3.0 + lat*5.0 + f*5.0 - uTime*1.6);
  float glyph = smoothstep(0.16, 0.0, abs(s));
  vec3 V = normalize(CAMERA_POSITION_WORLD - vW); float fr = pow(1.0 - abs(dot(normalize(vN), V)), 2.0);
  vec3 purple = mix(vec3(0.22,0.05,0.42), vec3(0.6,0.05,0.12), uDefense);
  ALBEDO = purple*(0.6+f) + vec3(1.0,0.75,0.3)*glyph*(1.6+uAlarm*2.0) + vec3(1.0,0.3,0.8)*fr*1.4;
}
