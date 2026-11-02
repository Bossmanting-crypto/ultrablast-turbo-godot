// The glass shell (world barrier): hex cells, proximity glow, impact ripples and the Iris countdown etch
// that climbs from the bottom while uCount runs 0 -> 1.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_front;
global uniform float uTime; uniform float uProx; uniform float uWarn; uniform float uCount;
uniform vec3 uPlayer;
uniform vec4 uImp[4];
varying vec3 vW;
vec2 hexC(vec2 p){ const vec2 s=vec2(1.0,1.7320508); vec4 hC=floor(vec4(p,p-vec2(0.5,1.0))/s.xyxy)+0.5; vec4 h=vec4(p-hC.xy*s, p-(hC.zw+0.5)*s); return dot(h.xy,h.xy)<dot(h.zw,h.zw)? h.xy : h.zw; }
float hexD(vec2 h){ h=abs(h); return max(dot(h, vec2(0.8660254,0.5)), h.x); }
void vertex(){ vW = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment(){
  vec2 uv = vec2(UV.x, 1.0 - UV.y); // three.js spheres run v bottom -> top
  vec2 p = vec2(uv.x*110.0, uv.y*64.0);
  float hd = hexD(hexC(p));
  float edge = smoothstep(0.465, 0.5, hd);
  float d = distance(vW, uPlayer);
  float glow = uProx*smoothstep(24.0, 0.0, d)*0.6;
  float ring = 0.0;
  for(int i=0;i<4;i++){ float age = uTime - uImp[i].w; if(age>0.0 && age<2.5){ float dd = distance(vW, uImp[i].xyz); ring += exp(-pow(dd - age*38.0, 2.0)/18.0)*exp(-age*1.6); ring += smoothstep(10.0,0.0,dd)*exp(-age*4.0); } }
  float shimmer = 0.5+0.5*sin(uv.y*80.0 + uTime*1.5 + uv.x*30.0);
  float etch = smoothstep(uCount + 0.025, uCount - 0.025, uv.y) * step(0.001, uCount);
  float front = smoothstep(0.03, 0.0, abs(uv.y - uCount)) * step(0.001, uCount);
  float a = edge*(0.012 + shimmer*0.008 + glow*0.55 + ring*0.9 + uWarn*0.08 + etch*0.16 + front*0.5) + (glow*0.02 + ring*0.05 + etch*0.02 + front*0.12);
  vec3 col = mix(vec3(0.45,0.9,1.0), vec3(1.0,0.8,0.45), clamp(glow+ring,0.0,1.0));
  col = mix(col, vec3(1.0,0.45,0.95), clamp(etch*0.8 + front, 0.0, 1.0));
  col = mix(col, vec3(1.0,0.35,0.25), uWarn*0.4);
  ALBEDO = col; ALPHA = clamp(a, 0.0, 1.0);
}
