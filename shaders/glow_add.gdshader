// Generic additive glow (three.js MeshBasicMaterial + AdditiveBlending): linear HDR colour, optional texture.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform vec4 color = vec4(1.0); // linear, may exceed 1 for glow
uniform float energy = 1.0;
uniform bool use_tex = false;
uniform sampler2D tex : source_color, filter_linear_mipmap;
void fragment(){
  vec4 c = color; c.rgb *= energy;
  if(use_tex){ c *= texture(tex, UV); }
  ALBEDO = c.rgb * COLOR.rgb; ALPHA = clamp(c.a * COLOR.a, 0.0, 1.0);
}
