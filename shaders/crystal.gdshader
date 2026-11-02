// Faceted jewel (instanced): saturated body, glowing rim, one sharp glint. Only the rim crosses the glow
// threshold. Instances shrink when the camera is about to pass through them. Colour comes per instance.
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float uGlow = 1.0;
varying vec3 vW;
varying vec3 vC;
void vertex(){
  vec3 ctr = (MODEL_MATRIX * vec4(0.0,0.0,0.0,1.0)).xyz;
  float near = smoothstep(2.5, 7.0, distance(CAMERA_POSITION_WORLD, ctr));
  VERTEX *= near;
  vW = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
  vC = COLOR.rgb * 2.0; // multimesh colours are stored halved so HDR values survive
}
void fragment(){
  vec3 N = normalize(cross(dFdx(vW), dFdy(vW))); vec3 V = normalize(CAMERA_POSITION_WORLD - vW); if(dot(N,V) < 0.0) N = -N;
  float fr = pow(1.0 - max(dot(N,V), 0.0), 2.2);
  vec3 L = normalize(vec3(-0.4,0.7,0.6)); float facet = 0.3 + 0.7*max(dot(N,L), 0.0);
  float spec = pow(max(dot(reflect(-V,N), L), 0.0), 36.0);
  vec3 c = normalize(vC + 1e-4) * min(length(vC), 1.6);
  ALBEDO = c*(0.16 + 0.42*facet) + c*fr*1.5*uGlow + vec3(1.0,0.97,0.9)*spec*0.85;
}
