// Rift tunnel wall: flowing lane streaks, speed bands and a fresnel rim. uOpen reveals it from the mouth,
// uGold tints the quick-chain tunnel, and walls fade near the camera so the ride stays readable.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
global uniform float uTime; uniform float uLen; uniform float uFade = 1.0; uniform float uActive; uniform float uOpen; uniform float uFlow = 1.0; uniform float uGold;
uniform vec3 uA; uniform vec3 uB;
float h1(float n){ return fract(sin(n)*43758.5453); }
void fragment(){
  float along = UV.x*uLen;
  float reveal = 1.0 - smoothstep(uOpen*uLen - 8.0, uOpen*uLen, along);
  float lane = floor(UV.y*20.0);
  float ph = h1(lane)*10.0;
  float flow = uTime*(1.4+h1(lane+3.0)*1.2)*uFlow;
  float streak = smoothstep(0.86, 1.0, fract(along*0.05 - flow + ph));
  float laneMask = smoothstep(0.14,0.0,abs(fract(UV.y*20.0)-0.5));
  float bands = smoothstep(0.92, 1.0, fract(along*0.11 - uTime*uFlow*1.6));
  float wave = 0.5+0.5*sin(along*0.25 - uTime*6.0*uFlow + UV.y*12.566);
  float fr = pow(1.0-abs(dot(normalize(NORMAL), normalize(-VERTEX))), 2.0);
  float ends = smoothstep(0.0,0.04,UV.x)*smoothstep(1.0,0.95,UV.x);
  vec3 a = mix(uA, vec3(1.0,0.72,0.3), uGold);
  vec3 col = mix(a, uB, streak*laneMask);
  float al = (0.035 + fr*0.24 + streak*laneMask*0.34 + wave*fr*0.1 + bands*uActive*0.12 + uActive*0.04)*ends*uFade*reveal;
  float camD = length(VERTEX); al *= 0.12 + 0.88*smoothstep(2.0, 12.0, camD);
  ALBEDO = col*(1.0+uActive*0.45); ALPHA = clamp(al, 0.0, 1.0);
}
