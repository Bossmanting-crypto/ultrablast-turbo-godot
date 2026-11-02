// Equirectangular panorama on a camera-centred sphere (drawn behind everything), with the slow rotation,
// tint, brightness and saturation the game drives (darker during puzzles, brighter in supercuts).
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, fog_disabled;
uniform sampler2D map : source_color, filter_linear, repeat_enable;
uniform vec3 uTint = vec3(1.0);
uniform float uBright = 0.95;
uniform float uRot = 0.0;
uniform float uSat = 1.0;
varying vec3 vDir;
void vertex(){ vDir = VERTEX; }
void fragment(){
  vec3 d = normalize(vDir); float c=cos(uRot), s=sin(uRot); d.xz = mat2(vec2(c,-s),vec2(s,c))*d.xz;
  float u = atan(d.z, d.x)/6.2831853 + 0.5; float v = asin(clamp(d.y,-1.0,1.0))/3.1415926 + 0.5;
  vec3 col = texture(map, vec2(u, 1.0 - v)).rgb;
  float l = dot(col, vec3(0.299,0.587,0.114)); col = mix(vec3(l), col, uSat);
  ALBEDO = col*uTint*uBright;
}
