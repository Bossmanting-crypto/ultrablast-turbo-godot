// Lens post-process (LensShader in the web build): radial zoom blur, chromatic split, barrel warp,
// saturation, tint, additive flash and vignette. Runs on a full-screen ColorRect over the 3D view.
// Also the engine heat haze: the ship script projects each exhaust plume to a screen-space segment
// (uHazeSeg = nozzle.xy, tail.zw in UV) and the frame is refracted through a rippling band along it.
// Doing it here instead of on a 3D mesh keeps it to one screen read and works on every renderer.
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float uBlur = 0.0;
uniform float uChroma = 0.002;
uniform float uVig = 1.0;
uniform float uSat = 1.0;
uniform float uWarp = 0.0;
uniform vec3 uTint = vec3(1.0);
uniform vec3 uFlash = vec3(0.0);
uniform vec2 uCenter = vec2(0.5);
uniform vec4 uHazeSeg[2];
uniform float uHazeAmt = 0.0;
uniform float uHazeW = 0.03;
float seg_dist(vec2 p, vec2 a, vec2 b, out float t) {
  vec2 pa = p - a; vec2 ba = b - a;
  t = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
  return length(pa - ba * t);
}
void fragment(){
  float uAspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
  vec2 vUv = SCREEN_UV;
  vec2 dir = vUv - uCenter; vec2 da = dir*vec2(uAspect,1.0);
  float r2 = dot(da,da);
  vec2 uv = uCenter + dir*(1.0 - uWarp*r2);
  if (uHazeAmt > 0.001) {
    vec2 asp = vec2(uAspect, 1.0);
    vec2 hz = vec2(0.0);
    for (int i = 0; i < 2; i++) {
      float t;
      float d = seg_dist(vUv * asp, uHazeSeg[i].xy * asp, uHazeSeg[i].zw * asp, t);
      float w = uHazeW * (0.5 + t * 1.3);                       // the plume spreads toward its tail
      float m = smoothstep(w, 0.0, d) * (1.0 - t) * smoothstep(0.0, 0.06, t);
      vec2 q = vec2(d / w * 2.0, t * 5.0 - TIME * 8.0 + float(i) * 1.7);
      hz += vec2(sin(q.y * 3.1 + q.x) + sin(q.y * 5.3 - q.x * 1.7), cos(q.y * 2.6 + q.x * 1.3) + sin(q.y * 6.4 + q.x * 0.8)) * m;
    }
    uv += hz * 0.0018 * uHazeAmt;
  }
  vec3 col = vec3(0.0);
  for(int i=0;i<10;i++){
    float t = float(i)/9.0;
    float s = 1.0 - uBlur*t*0.09*(0.3+r2*2.0);
    vec2 suv = uCenter + (uv-uCenter)*s;
    float ch = uChroma*(1.0+r2*3.0);
    col.r += textureLod(screen_tex, uCenter+(suv-uCenter)*(1.0+ch), 0.0).r;
    col.g += textureLod(screen_tex, suv, 0.0).g;
    col.b += textureLod(screen_tex, uCenter+(suv-uCenter)*(1.0-ch), 0.0).b;
  }
  col /= 10.0;
  float l = dot(col, vec3(0.299,0.587,0.114)); col = mix(vec3(l), col, uSat);
  col *= uTint; col += uFlash;
  float vig = smoothstep(1.25, 0.25, length(da)*uVig);
  COLOR = vec4(col*mix(0.55,1.0,vig), 1.0);
}
