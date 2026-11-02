extends Node
## FX (port of 30_fx.js): shape particles, shockwaves, bubble-pop tentacles, speed lines, turbo ring pool,
## wingtip ribbons, the lens state, screen shake, and the 2D overlay (crash doodles, slam-and-shatter event
## text, popups, reticle, off-screen threat arrows). The overlay draws through three Overlay controls:
## layer 0 (normal) for HUD-in-world marks, layer 1 (additive) for crash doodles, layer 2 (normal) for text.

const GOLD := Color(1.6, 1.1, 0.5)
const PEACH := Color(1.4, 1.0, 0.75)
const CYAN := Color(0.45, 1.2, 1.6)
const MAG := Color(1.6, 0.4, 1.2)
const CORAL := Color(1.8, 0.5, 0.25)
const LIME := Color(1.0, 1.5, 0.6)
const WHITE := Color(1.4, 1.4, 1.4)

# ---------- lens (post) ----------
var LENS := {"blur": 0.0, "chroma": 0.0, "flash": Color(0, 0, 0), "warp": 0.0, "sat": 1.0, "tint": Color(1, 1, 1)}
func flash(r: float, g: float, b: float) -> void: LENS.flash = Color(r, g, b)

var root: Node3D
var W := 1600.0    # FXW / FXH: overlay size in canvas units
var H := 900.0

# ---------- 3D shape particles ----------
const PMAX := 4500
var p_pos := PackedVector3Array()
var p_vel := PackedVector3Array()
var p_col := PackedColorArray()
var p_life := PackedFloat32Array()
var p_max := PackedFloat32Array()
var p_s0 := PackedFloat32Array()
var p_s1 := PackedFloat32Array()
var p_shape := PackedFloat32Array()
var p_rot := PackedFloat32Array()
var p_spin := PackedFloat32Array()
var p_drag := PackedFloat32Array()
var p_alive := PackedByteArray()
var p_head := 0
var p_buf := PackedFloat32Array()
var p_mm: MultiMeshInstance3D

# ---------- other 3D fx ----------
var shockwaves: Array = []
var tentacles: Array = []
const SL := 150
var sl_pts := PackedVector3Array()
var sl_mesh: ImmediateMesh
var sl_mat: StandardMaterial3D
var sl_opacity := 0.0
var turbo_ring_pool: Array = []
var ring_tex: Texture2D = preload("res://assets/textures/glyph_ring_fx.png")
var ribbons: Array = []
var cam_fwd := Vector3.FORWARD

# ---------- 2D overlay state ----------
var crashes: Array = []
var popups: Array = []
var texts: Array = []
var specks: Array = []
var DOOD := {"t": 9.0, "s": 0.0, "base": 0.0}
const SHAPES2D := ["tri", "sq", "circ", "squig", "cross", "chev", "spiral"]
const PALETTES := {
	"gold": {"top": "#fffbe0", "mid": "#ffd067", "bot": "#ff7a2e", "ex1": "#8a2a3a", "ex2": "#2a0a22", "line": "#22091c"},
	"red": {"top": "#ffe2d6", "mid": "#ff6a45", "bot": "#c0142a", "ex1": "#5a0a18", "ex2": "#14030a", "line": "#140308"},
	"violet": {"top": "#f3e6ff", "mid": "#b98aff", "bot": "#6a3ad0", "ex1": "#2a1050", "ex2": "#0a0420", "line": "#0a0420"},
	"cyan": {"top": "#f0ffff", "mid": "#8fe9ff", "bot": "#2a8aff", "ex1": "#0a2a5a", "ex2": "#040a20", "line": "#040a20"},
	"mag": {"top": "#fff0fa", "mid": "#ff8ad6", "bot": "#ff3a6a", "ex1": "#5a0a3a", "ex2": "#1a0414", "line": "#1a0414"},
}

func _ready() -> void:
	p_pos.resize(PMAX); p_vel.resize(PMAX); p_col.resize(PMAX); p_life.resize(PMAX); p_max.resize(PMAX)
	p_s0.resize(PMAX); p_s1.resize(PMAX); p_shape.resize(PMAX); p_rot.resize(PMAX); p_spin.resize(PMAX); p_drag.resize(PMAX)
	p_alive.resize(PMAX)
	p_buf.resize(PMAX * 20)
	for i in PMAX:
		var o := i * 20
		p_buf[o] = 1.0; p_buf[o + 5] = 1.0; p_buf[o + 10] = 1.0
		p_buf[o + 7] = -99999.0

func setup(r: Node3D) -> void:
	root = r
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = Meshes.quad(1, 1)
	mm.instance_count = PMAX
	mm.buffer = p_buf
	p_mm = MultiMeshInstance3D.new(); p_mm.name = "Particles"; p_mm.multimesh = mm
	var pm := ShaderMaterial.new(); pm.shader = preload("res://shaders/particles.gdshader"); pm.render_priority = 10
	p_mm.material_override = pm
	p_mm.custom_aabb = AABB(Vector3(-1000, -1000, -1000), Vector3(2000, 2000, 2000))
	root.add_child(p_mm)
	# shockwaves
	var sw_mesh := Meshes.sphere(1, 40, 24)
	var sw_shader: Shader = preload("res://shaders/shockwave.gdshader")
	for i in 10:
		var m := MeshInstance3D.new(); m.mesh = sw_mesh
		var mat := ShaderMaterial.new(); mat.shader = sw_shader; mat.render_priority = 11
		m.material_override = mat; m.visible = false; root.add_child(m)
		shockwaves.append({"m": m, "mat": mat, "t": 0.0, "dur": 1.0, "r": 1.0, "on": false, "amp": 1.0})
	# tentacles (bubble pop)
	for i in 18:
		var im := ImmediateMesh.new()
		var mi := MeshInstance3D.new(); mi.mesh = im; mi.visible = false
		var lm := Meshes.unshaded(Color(1, 1, 1), true); lm.vertex_color_use_as_albedo = true
		mi.material_override = lm; mi.extra_cull_margin = 1000.0
		root.add_child(mi)
		tentacles.append({"mi": mi, "im": im, "N": 14, "t": 0.0, "on": false, "o": Vector3.ZERO, "d": Vector3.ZERO, "ax": Vector3.ZERO, "len": 6.0, "curl": 2.0, "life": 0.8})
	# speed lines
	sl_pts.resize(SL)
	for i in SL: sl_pts[i] = Vector3(1e5, 0, 0)
	sl_mesh = ImmediateMesh.new()
	var slm := MeshInstance3D.new(); slm.name = "SpeedLines"; slm.mesh = sl_mesh; slm.extra_cull_margin = 16384.0
	sl_mat = Meshes.unshaded(Color(1.5, 1.4, 1.2, 0.0), true); slm.material_override = sl_mat
	root.add_child(slm)
	# ribbons
	for i in 2:
		var im := ImmediateMesh.new()
		var mi := MeshInstance3D.new(); mi.mesh = im; mi.extra_cull_margin = 16384.0
		var rm := Meshes.unshaded(Color(1, 1, 1), true); rm.vertex_color_use_as_albedo = true; rm.render_priority = 9
		mi.material_override = rm; root.add_child(mi)
		ribbons.append({"pts": [], "im": im})

# ---------- particles ----------
func spawn(o: Dictionary) -> void:
	var i := p_head
	p_head = (p_head + 1) % PMAX
	p_pos[i] = o.pos
	p_vel[i] = o.get("vel", Vector3.ZERO)
	var c: Color = o.get("color", GOLD)
	p_col[i] = c
	var life: float = o.get("life", 0.8)
	p_life[i] = life; p_max[i] = life
	var sz: float = o.get("size", 0.5)
	p_s0[i] = sz
	p_s1[i] = o.size1 if o.has("size1") else sz * 0.2
	p_shape[i] = o.get("shape", 0)
	p_rot[i] = randf() * TAU
	p_spin[i] = o.spin if o.has("spin") else U.rand(-6, 6)
	p_drag[i] = o.drag if o.has("drag") else 1.5
	p_alive[i] = 1

func update_particles(dt: float) -> void:
	var buf := p_buf
	for i in PMAX:
		if p_alive[i] == 0: continue
		var o := i * 20
		if p_life[i] <= 0.0:
			p_alive[i] = 0
			buf[o + 7] = -99999.0; buf[o + 15] = 0.0; buf[o + 16] = 0.0
			continue
		p_life[i] -= dt
		var k := exp(-p_drag[i] * dt)
		var v := p_vel[i] * k
		p_vel[i] = v
		var p := p_pos[i] + v * dt
		p_pos[i] = p
		var f := maxf(0.0, p_life[i] / p_max[i])
		var a := f / 0.3 if f < 0.3 else 1.0
		p_rot[i] += p_spin[i] * dt
		var c := p_col[i]
		buf[o + 3] = p.x; buf[o + 7] = p.y; buf[o + 11] = p.z
		buf[o + 12] = c.r; buf[o + 13] = c.g; buf[o + 14] = c.b; buf[o + 15] = a
		buf[o + 16] = lerpf(p_s1[i], p_s0[i], f); buf[o + 17] = p_shape[i]; buf[o + 18] = p_rot[i]
	p_buf = buf
	p_mm.multimesh.buffer = buf

func burst_shapes(pos: Vector3, n: int, shapes: Array, spd: float = 20.0, color = null) -> void:
	for i in n:
		var sh: int = U.pick(shapes)
		spawn({"pos": pos, "vel": U.rand_unit() * (U.rand(0.3, 1) * spd), "color": color if color != null else (GOLD if randf() < 0.75 else PEACH),
			"size": U.rand(0.3, 0.7) if sh == 0 else U.rand(0.8, 1.8), "size1": 0.1, "life": U.rand(0.6, 1.3), "shape": sh, "drag": 2.2})

func sparks(pos: Vector3, n: int, color: Color = GOLD, spd: float = 14.0) -> void:
	for i in n:
		spawn({"pos": pos, "vel": U.rand_unit() * (U.rand(0.2, 1) * spd), "color": color, "size": U.rand(0.25, 0.6), "life": U.rand(0.3, 0.7), "shape": 5 if randf() < 0.2 else 0, "drag": 3.0})

# ---------- shockwaves ----------
func shockwave(pos: Vector3, r: float, color: Color, dur: float = 0.7) -> void:
	var cp: Vector3 = GAME.camera.global_position
	if pos.distance_to(cp) < r + 6: return
	var s = null
	for x in shockwaves:
		if not x.on: s = x; break
	if s == null: s = shockwaves[0]
	s.on = true; s.t = 0.0; s.dur = dur; s.r = r; s.amp = 0.12 if pos.distance_to(cp) < r + 4 else 1.0
	s.m.position = pos; s.mat.set_shader_parameter("uC", Vector3(color.r, color.g, color.b)); s.m.visible = true

func update_shockwaves(dt: float) -> void:
	for s in shockwaves:
		if not s.on: continue
		s.t += dt
		var k: float = s.t / s.dur
		if k >= 1: s.on = false; s.m.visible = false; continue
		var e := 1.0 - pow(1.0 - k, 3)
		s.m.scale = Vector3.ONE * (0.5 + s.r * e)
		s.mat.set_shader_parameter("uA", (1.0 - k) * s.amp)

# ---------- tentacle lines (bubble pop) ----------
func spawn_tentacles(pos: Vector3, n: int, base_vel = null) -> void:
	for k in n:
		var t = null
		for x in tentacles:
			if not x.on: t = x; break
		if t == null: return
		t.on = true; t.t = 0.0; t.o = pos; t.d = U.rand_unit()
		if base_vel != null: t.d = (t.d - base_vel * 0.5).normalized()
		t.ax = U.rand_unit(); t.len = U.rand(5, 11); t.curl = U.rand(1.5, 4); t.life = U.rand(0.6, 1.0); t.mi.visible = true

func update_tentacles(dt: float) -> void:
	for t in tentacles:
		if not t.on: continue
		t.t += dt
		var k: float = t.t / t.life
		if k >= 1: t.on = false; t.mi.visible = false; continue
		var im: ImmediateMesh = t.im
		im.clear_surfaces(); im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		var ext: float = (1.0 - pow(1.0 - minf(1.0, k * 2.2), 3)) * t.len
		var last := Vector3.ZERO
		for i in t.N:
			var s: float = float(i) / (t.N - 1)
			var p: Vector3 = t.o + t.d * (s * ext)
			p += t.d.rotated(t.ax, PI / 2) * (sin(s * t.curl * 3 + t.t * 10) * s * 1.5)
			var tail := maxf(0.0, 1.0 - absf(s - k * 1.1) * 1.4) * (1.0 - k)
			im.surface_set_color(Color(2.2 * tail, 1.7 * tail, 1.0 * tail))
			im.surface_add_vertex(p)
			last = p
		im.surface_end()
		if randf() < 0.3: spawn({"pos": last, "vel": Vector3.ZERO, "color": GOLD, "size": 0.3, "life": 0.4, "shape": 5, "drag": 1.0})

# ---------- speed lines ----------
func update_speed_lines(dt: float) -> void:
	var tun: bool = P.mode == "tunnel"
	var sf := clampf((P.speed - 34) / 80, 0, 1) + (0.9 if tun else 0.0) + (0.4 if P.mode == "supercut" else 0.0) + (0.6 if P.mode == "homing" else 0.0)
	sl_opacity = U.damp(sl_opacity, minf(0.75 if tun else 0.55, sf * 0.7), 5, dt)
	sl_mat.albedo_color.a = sl_opacity
	var length: float = (2 + P.speed * 0.07) * (2.6 if tun else 1.0)
	var extra := 60.0 if tun else (40.0 if P.mode == "homing" else 0.0) # lines rush past faster than the ship really moves
	var cp: Vector3 = GAME.camera.global_position
	sl_mesh.clear_surfaces()
	if sl_opacity < 0.003: return
	sl_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in SL:
		var p := sl_pts[i]
		if extra: p -= P.fwd * (extra * dt)
		var rel := p - cp
		var ahead := rel.dot(P.fwd)
		if ahead < -3 or ahead > 90 or rel.length_squared() > 9000:
			var a := U.rand(0, TAU)
			var r := U.rand(1.4, 3.5) if tun else U.rand(2.5, 16)
			p = P.pos + P.fwd * U.rand(20, 85) + P.right * (cos(a) * r) + P.up * (sin(a) * r)
		sl_pts[i] = p
		sl_mesh.surface_add_vertex(p); sl_mesh.surface_add_vertex(p + P.fwd * length)
	sl_mesh.surface_end()

# ---------- turbo ring meshes ----------
func get_turbo_ring() -> Dictionary:
	var r = null
	for x in turbo_ring_pool:
		if not x.on: r = x; break
	if r == null:
		var g := Node3D.new()
		var tor := MeshInstance3D.new(); tor.mesh = Meshes.torus(1.7, 0.09, 8, 72)
		var tm := Meshes.unshaded(Color(2.4, 1.7, 0.8), false); tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tor.material_override = tm
		var gl := MeshInstance3D.new(); gl.mesh = Meshes.quad(5.0, 5.0)
		var gm := World.glow_mat(Color(1.1, 0.8, 0.5), ring_tex); gl.material_override = gm
		g.add_child(tor); g.add_child(gl); root.add_child(g)
		r = {"g": g, "tor": tor, "gl": gl, "tor_mat": tm, "gl_mat": gm, "on": false}
		turbo_ring_pool.append(r)
	r.on = true; r.g.visible = true; r.g.scale = Vector3.ONE * 0.01
	ring_opacity(r, 1.0)
	return r

func ring_opacity(r: Dictionary, a: float) -> void:
	r.tor_mat.albedo_color.a = a
	var c: Color = r.gl_mat.get_shader_parameter("color"); c.a = a; r.gl_mat.set_shader_parameter("color", c)

func free_turbo_ring(r: Dictionary) -> void:
	r.on = false; r.g.visible = false

# ---------- wingtip ribbon trails ----------
const RIB_N := 26
func _ribbon_update(rb: Dictionary, p: Vector3, intensity: float, color: Color, width: float) -> void:
	var pts: Array = rb.pts
	if pts.is_empty() or pts[0].distance_to(p) > 0.55:
		pts.push_front(p)
		if pts.size() > RIB_N: pts.pop_back()
	else: pts[0] = p
	var im: ImmediateMesh = rb.im
	im.clear_surfaces()
	var n := pts.size()
	if n < 2 or intensity <= 0.001: return
	var cp: Vector3 = GAME.camera.global_position
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in n:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[mini(i + 1, n - 1)]
		var c: Vector3 = pts[maxi(i - 1, 0)]
		var dir := c - b
		if dir.length_squared() < 1e-6: dir = P.fwd
		var side := dir.cross(cp - a).normalized()
		var f := 1.0 - float(i) / (RIB_N - 1)
		var w := width * (0.25 + 0.75 * f)
		var ahead := (a - cp).dot(cam_fwd)
		var k := intensity * pow(f, 1.6) * (0.0 if i == 0 else 1.0) * U.smooth(2.5, 7, ahead)
		var col := Color(color.r * k, color.g * k, color.b * k)
		im.surface_set_color(col); im.surface_add_vertex(a + side * w)
		im.surface_set_color(col); im.surface_add_vertex(a - side * w)
	im.surface_end()

func update_ribbons(_rdt: float) -> void:
	cam_fwd = -GAME.camera.global_basis.z
	var lvl: int = BL.sc.level if BL.sc else 0
	var k := clampf((P.speed - 30) / 50, 0, 1) * 0.55 + clampf(P.boost / 40, 0, 1) * 0.45
	if P.mode == "supercut": k = 1
	if P.mode == "puzzle": k *= 0.5
	if GAME.state == "over" and not P.ship.visible: k = 0
	var rc: Color = (MAG if lvl == 2 else (GOLD if lvl else (CYAN if P.mode == "tunnel" else PEACH))) * 0.55
	for i in 2:
		var tip: Vector3 = P.ship.inner.to_global(Vector3(-1.5 if i else 1.5, 0, -0.78))
		_ribbon_update(ribbons[i], tip, k, rc, 0.09 + k * 0.06)

# ---------- 2D overlay ----------
func screen_crash(n: int, kinds = null) -> void:
	if kinds == null: kinds = [0, 1, 2]
	for i in n:
		var type: String = SHAPES2D[U.pick(kinds)]
		var ang := U.rand(0, TAU)
		var rr := U.rand(0.24, 0.48)
		var k := clampf(H / 900.0, 0.55, 1)
		crashes.append({"type": type, "x0": 0.5 + U.rand(-0.04, 0.04), "y0": 0.5 + U.rand(-0.04, 0.04), "x": 0.5 + cos(ang) * rr * (H / W) * 1.6, "y": 0.5 + sin(ang) * rr,
			"s": U.rand(20, 46) * k, "rot": U.rand(0, TAU), "vr": U.rand(-2, 2), "t": -U.rand(0, 0.25), "stick": U.rand(0.3, 0.6), "dis": U.rand(0.5, 0.8), "lw": U.rand(2.2, 3.8) * maxf(0.75, k)})

func popup(text: String, color: String = "#ffd27a", big := false) -> void:
	for p in popups:
		if p.text == text and p.t < 0.5: p.t = 0.0; return
	popups.append({"text": text, "color": color, "t": 0.0, "y": null, "big": big})
	if popups.size() > 4: popups.pop_front()

## Each event text is painted once into a transparent SubViewport (extruded Bungee, gradient fill, shine),
## then slammed onto the screen and shattered into textured shards.
class TextPainter:
	extends Node2D
	var text := ""
	var pal := {}
	var fs := 150
	var cx := 0.0
	var cy := 0.0
	var mode := 0   # 0 extrusion + thick outline, 1 gradient fill, 2 thin outline
	func _draw() -> void:
		var f: Font = D2.display
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var base := cy + (f.get_ascent(fs) - f.get_descent(fs)) / 2.0
		var x0 := cx - tw / 2.0
		if mode == 0:
			for i in range(16, 0, -1):
				draw_string(f, Vector2(x0 + i * 0.8, base + i * 1.05), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.html(pal.ex2 if i > 8 else pal.ex1))
			draw_string_outline(f, Vector2(x0, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 18, Color.html(pal.line))
		elif mode == 1:
			draw_string(f, Vector2(x0, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		else:
			draw_string_outline(f, Vector2(x0, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(1, 1, 0.94, 0.85))

func _render_text(text: String, pal: Dictionary) -> Dictionary:
	var fs := 150
	var pad := 70
	var w := int(ceil(D2.display.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)) + pad * 2 + 60
	var h := int(ceil(fs * 1.7))
	var vp := SubViewport.new()
	vp.size = Vector2i(w, h); vp.transparent_bg = true; vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var skew := Transform2D(Vector2(1, 0), Vector2(-0.2, 1), Vector2(h * 0.12, 0))
	var y := h / 2.0 - 8
	var grad := ShaderMaterial.new(); grad.shader = preload("res://shaders/text_gradient.gdshader")
	grad.set_shader_parameter("top", Color.html(pal.top)); grad.set_shader_parameter("mid", Color.html(pal.mid)); grad.set_shader_parameter("bot", Color.html(pal.bot))
	grad.set_shader_parameter("y0", y - fs * 0.5); grad.set_shader_parameter("y1", y + fs * 0.5)
	grad.set_shader_parameter("shine0", y - fs * 0.48); grad.set_shader_parameter("shine1", y - fs * 0.30)
	for m in 3:
		var tp := TextPainter.new(); tp.text = text; tp.pal = pal; tp.fs = fs; tp.cx = w / 2.0; tp.cy = y; tp.mode = m
		tp.transform = skew
		if m == 1: tp.material = grad
		vp.add_child(tp)
	return {"vp": vp, "tex": vp.get_texture(), "w": float(w), "h": float(h)}

func _make_shards(w: float, h: float) -> Array:
	var cols := 10
	var rows := 4
	var P2 := []
	for j in rows + 1:
		for i in cols + 1:
			var ex := i == 0 or i == cols
			var ey := j == 0 or j == rows
			P2.append(Vector2(float(i) / cols * w + (0.0 if ex else U.rand(-0.35, 0.35) * w / cols), float(j) / rows * h + (0.0 if ey else U.rand(-0.35, 0.35) * h / rows)))
	var sh := []
	for j in rows:
		for i in cols:
			var a: Vector2 = P2[j * (cols + 1) + i]
			var b: Vector2 = P2[j * (cols + 1) + i + 1]
			var c: Vector2 = P2[(j + 1) * (cols + 1) + i]
			var d: Vector2 = P2[(j + 1) * (cols + 1) + i + 1]
			for tri in ([[a, b, d], [a, d, c]] if randf() < 0.5 else [[a, b, c], [b, d, c]]):
				var ctr: Vector2 = (tri[0] + tri[1] + tri[2]) / 3.0
				var dv := ctr - Vector2(w / 2, h / 2)
				var L := dv.length() + 1.0
				sh.append({"tri": tri, "cx": ctr.x, "cy": ctr.y, "vx": dv.x / L * U.rand(300, 900) + U.rand(-100, 100), "vy": dv.y / L * U.rand(200, 700) - U.rand(100, 300), "vr": U.rand(-8, 8)})
	return sh

func event_text(text: String, pal_name: String = "gold", slow := true) -> void:
	for t in texts:
		if t.phase != "shatter": t.phase = "shatter"; t.t = 0.0; AudioSys.shatter()
	var card := _render_text(text, PALETTES.get(pal_name, PALETTES.gold))
	texts.append({"text": text, "card": card, "t": 0.0, "phase": "slam", "shards": _make_shards(card.w, card.h)})
	if slow: GAME.slowmo(0.22, 0.42)
	AudioSys.slam()
	shake(0.35); P.CAM.punch += 6

func clear_texts() -> void:
	for t in texts: t.card.vp.queue_free()
	texts.clear()

func doodle_flash(s: float = 1.0) -> void:
	DOOD.s = minf(0.8, maxf(s * 0.8, DOOD.s * exp(-DOOD.t * 1.8))); DOOD.t = 0.0

func shake(a: float) -> void:
	P.CAM.trauma = minf(1.2, P.CAM.trauma + a)
	if a >= 0.1: Ctl.rumble(a * 0.9, minf(1, a * 1.4), 60 + a * 220)

## Per-frame bookkeeping for the overlay (the drawing itself happens in draw_layer).
func tick_2d(rdt: float) -> void:
	var vs := GAME.get_viewport().get_visible_rect().size
	W = vs.x; H = vs.y
	DOOD.t += rdt
	var d_op := clampf(DOOD.s * exp(-DOOD.t * 1.8) + DOOD.base, 0, 1)
	var dood: TextureRect = GAME.doodle
	if dood:
		dood.modulate.a = d_op
		dood.pivot_offset = dood.size / 2
		dood.scale = Vector2.ONE * (1 + 0.22 * exp(-DOOD.t * 2.5) + DOOD.base * 0.03 * sin(Ctl.now * 3))
		dood.rotation = deg_to_rad(sin(Ctl.now * 0.7) * 1.5)
	for i in range(crashes.size() - 1, -1, -1):
		crashes[i].t += rdt
	for i in range(specks.size() - 1, -1, -1):
		var s = specks[i]; s.t += rdt
		if s.t > s.life: specks.remove_at(i); continue
		s.x += s.vx * rdt; s.y += s.vy * rdt
	for i in range(texts.size() - 1, -1, -1):
		var t = texts[i]; t.t += rdt
		if t.phase == "slam" and t.t > 0.13: t.phase = "hold"; t.t = 0.0; shake(0.25)
		elif t.phase == "hold" and t.t > 0.55: t.phase = "shatter"; t.t = 0.0; AudioSys.shatter()
		elif t.phase == "shatter" and t.t / 0.9 >= 1: t.card.vp.queue_free(); texts.remove_at(i)
	for i in range(popups.size() - 1, -1, -1):
		popups[i].t += rdt
		if popups[i].t > 1.25: popups.remove_at(i)

func draw_layer(c: CanvasItem, layer: int) -> void:
	if layer == 0:
		if GAME.state == "play" or GAME.state == "title": draw_reticle(c)
		if GAME.state == "play":
			draw_edge_threats(c); Threats.draw_threats(c); HOM.draw_indicators(c); BL.draw_puzzle_and_lock(c)
	elif layer == 1: _draw_crashes(c)
	elif layer == 2: _draw_texts(c); _draw_popups(c)

func _crash_paths(type: String, s: float) -> Array:
	var out := []
	match type:
		"tri":
			var p := PackedVector2Array()
			for i in 4: var a := i / 3.0 * TAU - PI / 2; p.append(Vector2(cos(a) * s, sin(a) * s))
			out.append(p)
		"sq":
			out.append(PackedVector2Array([Vector2(-s * 0.8, -s * 0.8), Vector2(s * 0.8, -s * 0.8), Vector2(s * 0.8, s * 0.8), Vector2(-s * 0.8, s * 0.8), Vector2(-s * 0.8, -s * 0.8)]))
			out.append(PackedVector2Array([Vector2(-s * 0.6, -s), Vector2(s, -s), Vector2(s, s * 0.6)]))
		"circ":
			out.append(D2.arc_points(0, 0, s * 0.8, 0, TAU, 28)); out.append(D2.arc_points(0, 0, s * 0.32, 0, TAU * 0.8, 14))
		"squig":
			var p := PackedVector2Array()
			var c0 := Vector2(-s * 1.4, 0)
			for i in 13: p.append(_bez(c0, Vector2(-s * 0.7, -s * 1.3), Vector2(0, s * 1.3), Vector2(s * 0.7, 0), i / 12.0))
			for i in range(1, 9): p.append(_bez(Vector2(s * 0.7, 0), Vector2(s * 1.0, -s * 0.6), Vector2(s * 1.3, -s * 0.4), Vector2(s * 1.5, -s * 0.2), i / 8.0))
			out.append(p)
		"cross":
			out.append(PackedVector2Array([Vector2(-s, 0), Vector2(s, 0)])); out.append(PackedVector2Array([Vector2(0, -s), Vector2(0, s)]))
		"chev":
			out.append(PackedVector2Array([Vector2(-s, -s * 0.8), Vector2(s * 0.4, 0), Vector2(-s, s * 0.8)]))
		"spiral":
			var p := PackedVector2Array()
			for i in 31: var a := i / 30.0 * TAU * 1.6; var r := s * i / 30.0; p.append(Vector2(cos(a) * r, sin(a) * r))
			out.append(p)
	return out

static func _bez(a: Vector2, b: Vector2, c: Vector2, d: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return a * u * u * u + b * 3 * u * u * t + c * 3 * u * t * t + d * t * t * t

func _draw_crashes(c: CanvasItem) -> void:
	for i in range(crashes.size() - 1, -1, -1):
		var cr = crashes[i]
		if cr.t < 0: continue
		var fly := 0.18
		var T: float = cr.t
		var x: float; var y: float; var s: float
		var a := 1.0
		var dash = null
		if T < fly:
			var k := T / fly
			var e := k * k
			x = lerpf(cr.x0, cr.x, e); y = lerpf(cr.y0, cr.y, e); s = cr.s * (0.15 + e * 0.85); a = 0.5 + k * 0.5
		else:
			x = cr.x; y = cr.y + (T - fly) * 0.01; s = cr.s
			if T < fly + 0.06: D2.disc(c, x * W, y * H, s * 1.5, Color(1, 0.94, 0.78, 0.5))
			var td: float = T - fly - cr.stick
			if td > 0:
				var k: float = td / cr.dis
				if k >= 1: crashes.remove_at(i); continue
				a = 1.0 - k * 0.7; dash = [maxf(1.0, 26 * (1 - k)), 4 + 40 * k]
				if randf() < 0.5: specks.append({"x": x * W + U.rand(-s, s), "y": y * H + U.rand(-s, s), "vx": U.rand(-20, 20), "vy": U.rand(10, 60), "t": 0.0, "life": U.rand(0.4, 0.9)})
		cr.rot += cr.vr * get_process_delta_time() * (4.0 if T < fly else 0.3)
		var xf := Transform2D(cr.rot, Vector2(x * W, y * H))
		for path in _crash_paths(cr.type, s):
			var pts: PackedVector2Array = xf * (path as PackedVector2Array)
			for pass_i in 2:
				var colr := Color(1, 0.745, 0.353, 0.22 * a) if pass_i == 0 else Color(1, 0.925, 0.745, 0.95 * a)
				var lw: float = cr.lw * (4.0 if pass_i == 0 else 1.0)
				if dash: D2.dashed(c, pts, dash[0], dash[1], colr, lw)
				else: c.draw_polyline(pts, colr, lw, true)
	for s in specks:
		c.draw_rect(Rect2(s.x, s.y, 2, 2), Color(1, 0.86, 0.59, 1.0 - s.t / s.life))

func _draw_texts(c: CanvasItem) -> void:
	for t in texts:
		var card: Dictionary = t.card
		var scl := minf(minf(W * 0.88 / card.w, H * 0.24 / card.h), 1.1)
		var Wd: float = card.w * scl
		var Hd: float = card.h * scl
		var cx := W / 2
		var cy := H * 0.36
		var tex: Texture2D = card.tex
		if t.phase == "slam":
			var k := minf(1.0, t.t / 0.13)
			var s := lerpf(2.4, 1.0, 1.0 - pow(1.0 - k, 3))
			c.draw_texture_rect(tex, Rect2(cx - Wd * s / 2, cy - Hd * s / 2, Wd * s, Hd * s), false, Color(1, 1, 1, k))
		elif t.phase == "hold":
			var j := maxf(0.0, 0.12 - t.t) * 30
			c.draw_texture_rect(tex, Rect2(cx - Wd / 2 + U.rand(-j, j), cy - Hd / 2 + U.rand(-j, j), Wd, Hd), false)
		else:
			var k: float = t.t / 0.9
			var alpha := maxf(0.0, 1.0 - k * k)
			for s in t.shards:
				var ox: float = s.vx * t.t * scl
				var oy: float = (s.vy * t.t + 900 * t.t * t.t) * scl
				var xf := Transform2D(s.vr * t.t, Vector2(scl, scl), 0.0, Vector2(cx - Wd / 2 + s.cx * scl + ox, cy - Hd / 2 + s.cy * scl + oy))
				var pts := PackedVector2Array(); var uvs := PackedVector2Array()
				for v in s.tri:
					pts.append(xf * (v - Vector2(s.cx, s.cy))); uvs.append(Vector2(v.x / card.w, v.y / card.h))
				c.draw_polygon(pts, PackedColorArray([Color(1, 1, 1, alpha)]), uvs, tex)
				var outline := pts.duplicate(); outline.append(pts[0])
				c.draw_polyline(outline, Color(1, 1, 1, 0.5 * alpha), 1.5, true)

func _draw_popups(c: CanvasItem) -> void:
	var base := H * 0.66
	var quiet: bool = GAME.state == "play" and (P.mode == "puzzle" or P.mode == "loadup")
	if quiet: return
	var rdt := get_process_delta_time()
	for i in popups.size():
		var p = popups[i]
		var slot := base - (popups.size() - 1 - i) * 27
		p.y = slot + 14 if p.y == null else U.damp(p.y, slot, 14, rdt)
		var a: float = minf(1.0, p.t * 10) if p.t < 0.95 else 1.0 - (p.t - 0.95) / 0.3
		var s: float = 1.25 - p.t * 3 if p.t < 0.08 else 1.0
		var col := Color.html(p.color); col.a = maxf(0.0, a)
		D2.text_base(c, D2.ui_bold, roundi((24 if p.big else 17) * s), p.text, W / 2, p.y, col, HORIZONTAL_ALIGNMENT_CENTER, 4, Color(0.04, 0.03, 0.12, 0.85 * maxf(0.0, a)))

## World point -> overlay pixels. {x, y, behind}
func project(v: Vector3) -> Dictionary:
	var cam: Camera3D = GAME.camera
	var behind := cam.is_position_behind(v)
	var p := cam.unproject_position(v)
	return {"x": p.x, "y": p.y, "behind": behind}

func draw_reticle(c: CanvasItem) -> void:
	if P.mode == "puzzle" or P.mode == "supercut": return
	var sp := project(P.pos + P.fwd * 30)
	if sp.behind: return
	var x: float = sp.x
	var y: float = sp.y
	var r: float = 20 + BL.rings * 5
	var lc := Color(0.957, 0.776, 0.627, 0.75)
	for i in 4:
		var a := i * PI / 2 + Ctl.now * 0.6
		D2.arc(c, x, y, r, a + 0.25, a + PI / 2 - 0.25, lc, 1.6)
	D2.disc(c, x, y, 2.2, Color(1, 0.9, 0.745, 0.9))
	if BL.charging:
		D2.arc(c, x, y, r + 7, -PI / 2, -PI / 2 + TAU * clampf(BL.ct / (BL.ringEvery * 4), 0, 1), Color(1, 0.824, 0.478, 0.95), 3)
	# homing charges: three pips under the reticle (red flash when empty, gold after a perfect)
	if GAME.state == "play" and ST.unlocked("homing") and P.mode != "tunnel":
		var col := Color.html("#ff6a4a") if HOM.emptyT > 0 and int(floor(Ctl.now * 12)) % 2 else (Color.html("#ffd27a") if HOM.perfectT > 0 else Color.html("#8fe9ff"))
		for i in HOM.HOMING.max:
			var px: float = x + (i - 1) * 14 - 5
			var py: float = y + r + 12
			var f := clampf(HOM.charges - i, 0, 1)
			c.draw_rect(Rect2(px, py, 10, 4), Color(0.04, 0.03, 0.12, 0.55))
			var cc := col; cc.a = 1.0 if f >= 1 else 0.55
			if f > 0: c.draw_rect(Rect2(px, py, 10 * f, 4), cc)

# ---------- off-screen threat markers ----------
func draw_edge_threats(c: CanvasItem) -> void:
	if P.mode == "puzzle" or P.mode == "loadup": return
	var list := []
	for e in Enemies.enemies:
		if e.alive: list.append([e, "#b8f55a"])
	for p in Enemies.probes:
		if p.alive: list.append([p, "#ff6ad0"])
	for item in list:
		var t: Dictionary = item[0]
		var d: float = t.pos.distance_to(P.pos)
		if d > 75: continue
		var sp := project(t.pos)
		var on: bool = not sp.behind and sp.x > 30 and sp.y > 30 and sp.x < W - 30 and sp.y < H - 30
		if on: continue
		var cx := W / 2
		var cy := H / 2
		var dx: float = sp.x - cx
		var dy: float = sp.y - cy
		if sp.behind: dx = -dx; dy = -dy
		var ang := atan2(dy, dx)
		var m := 34.0
		var ca := absf(cos(ang)); if ca < 1e-3: ca = 1e-3
		var sa := absf(sin(ang)); if sa < 1e-3: sa = 1e-3
		var k := minf((W / 2 - m) / ca, (H / 2 - m) / sa)
		var x := cx + cos(ang) * k
		var y := cy + sin(ang) * k
		var s := 7 + 9 * U.smooth(75, 10, d)
		var alpha := 0.45 + 0.5 * U.smooth(75, 15, d)
		var xf := Transform2D(ang, Vector2(x, y))
		var pts: PackedVector2Array = xf * PackedVector2Array([Vector2(s, 0), Vector2(-s * 0.7, -s * 0.75), Vector2(-s * 0.3, 0), Vector2(-s * 0.7, s * 0.75)])
		D2.poly_fill(c, pts, D2.col(item[1], alpha))
		D2.poly_line(c, pts, Color(0.04, 0.03, 0.12, 0.7 * alpha), 2, true)
