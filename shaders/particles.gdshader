// Shape particles (the web build's Points shader): camera-facing quads sized like gl_PointSize
// (capped at 110 px, faded out right at the lens). INSTANCE_CUSTOM = (size, shape, rotation, -).
// Shapes: 0 soft dot, 1 triangle outline, 2 ring, 3 square outline, 4 cross, 5 star glint.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform;
varying vec4 vC;
varying float vS;
varying float vR;
void vertex(){
  vec3 c = (MODELVIEW_MATRIX * vec4(0.0,0.0,0.0,1.0)).xyz;
  float z = max(0.2, -c.z);
  float H = VIEWPORT_SIZE.y;
  float px = min(110.0, INSTANCE_CUSTOM.x * 0.9 * H / z) * smoothstep(1.5, 4.0, -c.z);
  float w = px * 2.0 * z / (H * PROJECTION_MATRIX[1][1]);
  if (COLOR.a <= 0.0) w = 0.0;
  VERTEX = c + vec3(VERTEX.xy * w, 0.0);
  vC = COLOR; vS = INSTANCE_CUSTOM.y; vR = INSTANCE_CUSTOM.z;
}
float sdTri(vec2 p, float r){ const float k=1.7320508; p.x=abs(p.x)-r; p.y=p.y+r/k; if(p.x+k*p.y>0.0) p=vec2(p.x-k*p.y,-k*p.x-p.y)/2.0; p.x-=clamp(p.x,-2.0*r,0.0); return -length(p)*sign(p.y); }
float sdBox(vec2 p, vec2 b){ vec2 d=abs(p)-b; return length(max(d,0.0))+min(max(d.x,d.y),0.0); }
void fragment(){
  vec2 p = UV*2.0-1.0; float c=cos(vR), s=sin(vR); p = mat2(vec2(c,-s),vec2(s,c))*p;
  float a = 0.0, d;
  if(vS<0.5){ a = pow(max(0.0,1.0-length(p)),2.0); }
  else if(vS<1.5){ d = sdTri(p*vec2(1.0,-1.0), 0.6); a = smoothstep(0.1,0.0,abs(d)) + 0.3*smoothstep(0.35,0.0,abs(d)); }
  else if(vS<2.5){ d = length(p)-0.68; a = smoothstep(0.1,0.0,abs(d)) + 0.3*smoothstep(0.32,0.0,abs(d)); }
  else if(vS<3.5){ d = sdBox(p, vec2(0.55)); a = smoothstep(0.1,0.0,abs(d)) + 0.3*smoothstep(0.32,0.0,abs(d)); }
  else if(vS<4.5){ d = min(sdBox(p,vec2(0.75,0.08)), sdBox(p,vec2(0.08,0.75))); a = smoothstep(0.08,0.0,d) + 0.3*smoothstep(0.3,0.0,d); }
  else { a = max(0.0,1.0-abs(p.x*p.y)*14.0-length(p)*0.8)*1.4 + pow(max(0.0,1.0-length(p)),3.0); }
  if(a<0.01) discard;
  ALBEDO = vC.rgb; ALPHA = clamp(a*vC.a, 0.0, 1.0);
}
