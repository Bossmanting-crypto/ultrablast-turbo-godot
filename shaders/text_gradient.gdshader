// Event-text fill: vertical three-stop gradient with a shine band, applied to glyph coverage.
shader_type canvas_item;
uniform vec4 top : source_color = vec4(1.0);
uniform vec4 mid : source_color = vec4(1.0, 0.8, 0.4, 1.0);
uniform vec4 bot : source_color = vec4(1.0, 0.5, 0.2, 1.0);
uniform float y0 = 0.0;
uniform float y1 = 100.0;
uniform float shine0 = 0.0;
uniform float shine1 = 0.0;
varying vec2 lp;
void vertex(){ lp = VERTEX; }
void fragment(){
  float t = clamp((lp.y - y0)/(y1 - y0), 0.0, 1.0);
  vec3 g = t < 0.5 ? mix(top.rgb, mid.rgb, t*2.0) : mix(mid.rgb, bot.rgb, (t-0.5)*2.0);
  float sh = step(shine0, lp.y)*step(lp.y, shine1)*0.35;
  COLOR.rgb = mix(g, vec3(1.0), sh);
}
