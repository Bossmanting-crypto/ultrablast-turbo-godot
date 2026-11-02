// Mini-planet (orb) body: toon-lit cream hull with green bands and ports, red alarm pulse, white hit flash.
shader_type spatial;
render_mode unshaded, cull_back;
#include "res://shaders/include/std_varyings.gdshaderinc"
uniform float uAlarm; uniform float uHit; global uniform float uTime; uniform float uFade = 1.0;
void vertex(){ STD_VERTEX; }
void fragment(){
  vec3 N = normalize(vN); vec3 V = normalize(CAMERA_POSITION_WORLD - vW); vec3 L = normalize(vec3(-0.5,0.6,0.6));
  float diff = dot(N,L)*0.5+0.5; float toon = diff>0.55?1.0:(diff>0.3?0.82:0.66);
  float fr = 1.0 - abs(dot(N,V));
  vec3 d = normalize(vP);
  float bands = smoothstep(0.03,0.0,abs(abs(d.y)-0.35)) + smoothstep(0.025,0.0,abs(d.x*0.8+d.z*0.6));
  float ports = smoothstep(0.08,0.06,distance(d, normalize(vec3(0.5,0.3,0.8)))) + smoothstep(0.1,0.08,distance(d, normalize(vec3(-0.7,-0.2,0.4))));
  vec3 cream = vec3(0.78,0.8,0.72)*toon;
  vec3 green = vec3(0.45,0.95,0.35);
  vec3 col = mix(cream, green*1.6, smoothstep(0.62,0.8,fr));
  col = mix(col, green*1.4, clamp(bands+ports*0.7,0.0,1.0));
  col = mix(col, vec3(2.0,0.3,0.15), uAlarm*(0.35+0.35*sin(uTime*20.0)));
  col += uHit*vec3(3.0,2.5,2.0);
  ALBEDO = col*uFade;
}
