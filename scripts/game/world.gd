extends Node
## WORLD (port of 10_world.js): the core, the two mini-planets (orbs) with rails, the glass barrier,
## rift tunnels, charge/homing crystals, gem rows and weapon pickups.
## Visual nodes are built under GAME.root3d by setup(); state lives in plain dictionaries like the web build.

const CORE_R := 12.0
const CORE_FIELD := 34.0
const ROUND_TIME := 180.0
const TUNNEL_R := 3.8
const TUN_SAMPLES := 300
const N_CRYS := 90
const N_HOME := 12
const N_GEM := 320

var R := 110.0          # WORLD.R: current barrier radius (the Iris narrows it)
var R0 := 110.0
var Rmin := 60.0

var root: Node3D
var core := {}
var core_group: Node3D
var core_shell: MeshInstance3D
var core_inner: MeshInstance3D
var core_turrets: Array = []
var fence: MeshInstance3D
var fence_mesh: ImmediateMesh
var fence_mat: StandardMaterial3D
var fence_shell: MeshInstance3D
var fence_pts := PackedVector3Array()
var orbs: Array = []
var barrier: MeshInstance3D
var barrier_mat: ShaderMaterial
var _imp := [Vector4(0, 0, 0, -99), Vector4(0, 0, 0, -99), Vector4(0, 0, 0, -99), Vector4(0, 0, 0, -99)]
var _imp_idx := 0
var tunnels: Array = []
var crystals: Array = []
var homers: Array = []
var crystal_mm: MultiMeshInstance3D
var homing_mm: MultiMeshInstance3D
var gem_mm: MultiMeshInstance3D
var gems: Array = []
var gem_rows: Array = []
var pickups: Array = []
var CRYS_COLORS := [Color(0.25, 0.85, 1.0), Color(1.0, 0.7, 0.25), Color(0.6, 0.45, 1.0)]
var WEAPONS := {
	"homing": {"name": "HOMING RINGS", "ammo": 3, "color": Color(2.0, 1.5, 0.5), "css": "#ffd27a"},
	"nova": {"name": "NOVA BOOM", "ammo": 2, "color": Color(2.0, 0.5, 1.6), "css": "#ff7ad9"},
	"magnet": {"name": "MAGNET", "ammo": 1, "color": Color(0.5, 1.8, 2.2), "css": "#8fe9ff", "time": 15},
}
var crystal_shader: Shader = preload("res://shaders/crystal.gdshader")
var glow_shader: Shader = preload("res://shaders/glow_add.gdshader")
var portal_tex: Texture2D = preload("res://assets/textures/glyph_ring_portal.png")
var hoop_mesh: ArrayMesh

func _ready() -> void:
	R = R0

func shader_mat(path: String, params := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	for k in params: m.set_shader_parameter(k, params[k])
	return m

## Additive glow material: linear colour, optional texture (MeshBasicMaterial + AdditiveBlending).
func glow_mat(col: Color, tex: Texture2D = null) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = glow_shader
	m.set_shader_parameter("color", col)
	if tex:
		m.set_shader_parameter("use_tex", true)
		m.set_shader_parameter("tex", tex)
	return m

func crystal_material(glow: float) -> ShaderMaterial:
	var m := ShaderMaterial.new(); m.shader = crystal_shader; m.set_shader_parameter("uGlow", glow); return m

func _mm(mesh: Mesh, count: int, mat: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.extra_cull_margin = 16384.0
	mi.custom_aabb = AABB(Vector3(-500, -500, -500), Vector3(1000, 1000, 1000))
	root.add_child(mi)
	return mi

func setup(r: Node3D) -> void:
	root = r
	_build_core()
	orbs = [_make_orb(0), _make_orb(1)]
	_build_barrier()
	hoop_mesh = Meshes.torus(TUNNEL_R * 1.04, 0.07, 6, 48)
	# crystals
	crystal_mm = _mm(Meshes.octahedron(0.75, Vector3(0.8, 1.6, 0.8)), N_CRYS, crystal_material(0.9))
	homing_mm = _mm(Meshes.icosahedron(0.85), N_HOME, crystal_material(1.3))
	gem_mm = _mm(Meshes.octahedron(0.42), N_GEM, crystal_material(1.2))
	crystals.clear(); homers.clear()
	for i in N_CRYS:
		var c := {"home": random_free_spot(), "pos": Vector3.ZERO, "ph": U.rand(0, 100), "alive": true, "kind": "crystal", "color": U.pick(CRYS_COLORS), "spawn": 1.0, "idx": i}
		crystals.append(c)
		crystal_mm.multimesh.set_instance_color(i, c.color * 0.5)
	for i in N_HOME:
		homers.append({"home": random_free_spot(), "pos": Vector3.ZERO, "vel": Vector3.ZERO, "ph": U.rand(0, 100), "alive": true, "kind": "homer", "spawn": 1.0, "idx": i, "active": false})
		homing_mm.multimesh.set_instance_color(i, Color(1.5, 0.5, 1.2) * 0.5)
	for i in N_GEM: gem_mm.multimesh.set_instance_color(i, Color(1.6, 1.2, 0.5) * 0.5)
	hide_all_gems()
	# red gem model for the homing crystals (CC BY 4.0 "Red Gem" by bang_m)
	var red := model_mesh("res://assets/models/red_gem.glb", 1.9, Basis(Vector3.RIGHT, PI))
	if red: homing_mm.multimesh.mesh = red

# ---------- models ----------
## First mesh of an imported glTF, baked into a new mesh centred at the origin with its largest side = size.
func model_mesh(path: String, size: float, extra := Basis.IDENTITY) -> ArrayMesh:
	var ps: PackedScene = load(path)
	if ps == null: return null
	var inst := ps.instantiate()
	var mi := _first_mesh(inst)
	if mi == null: inst.free(); return null
	var xf := Transform3D.IDENTITY
	var n: Node = mi
	while n and n != inst:
		if n is Node3D: xf = (n as Node3D).transform * xf
		n = n.get_parent()
	var src: Mesh = mi.mesh
	var out := ArrayMesh.new()
	var aabb := AABB()
	var first := true
	var surfaces := []
	for s in src.get_surface_count():
		var arr := src.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i in v.size():
			v[i] = extra * (xf * v[i])
			if first: aabb = AABB(v[i], Vector3.ZERO); first = false
			else: aabb = aabb.expand(v[i])
		arr[Mesh.ARRAY_VERTEX] = v
		if arr[Mesh.ARRAY_NORMAL] != null:
			var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for i in nn.size(): nn[i] = (extra * (xf.basis * nn[i])).normalized()
			arr[Mesh.ARRAY_NORMAL] = nn
		arr[Mesh.ARRAY_TANGENT] = null
		surfaces.append(arr)
	var c := aabb.get_center()
	var k := size / maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	for arr in surfaces:
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i in v.size(): v[i] = (v[i] - c) * k
		arr[Mesh.ARRAY_VERTEX] = v
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	inst.free()
	return out

## The first mesh's surface material (for textures to reuse in a custom material).
func model_material(path: String) -> Material:
	var ps: PackedScene = load(path)
	if ps == null: return null
	var inst := ps.instantiate()
	var mi := _first_mesh(inst)
	var m: Material = null
	if mi: m = mi.get_active_material(0)
	inst.free()
	return m

## A whole imported model as a node, scaled so its largest side is `size`; bottom-aligned to y = 0 if asked.
func model_node(path: String, size: float, bottom := false) -> Node3D:
	var ps: PackedScene = load(path)
	if ps == null: return null
	var inner: Node3D = ps.instantiate()
	var holder := Node3D.new()
	holder.add_child(inner)
	var box := _aabb_of(inner, Transform3D.IDENTITY)
	var k := size / maxf(box.size.x, maxf(box.size.y, box.size.z))
	inner.scale = Vector3.ONE * k
	var c := box.get_center() * k
	inner.position = Vector3(-c.x, -box.position.y * k if bottom else -c.y, -c.z)
	return holder

func _aabb_of(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var here := xf
	if n is Node3D: here = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out = here * (n as MeshInstance3D).mesh.get_aabb(); first = false
	for ch in n.get_children():
		var b := _aabb_of(ch, here)
		if b.size == Vector3.ZERO: continue
		if first: out = b; first = false
		else: out = out.merge(b)
	return out

func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh: return n
	for ch in n.get_children():
		var m := _first_mesh(ch)
		if m: return m
	return null

# ---------- core ----------
func _build_core() -> void:
	core_group = Node3D.new(); core_group.name = "Core"; root.add_child(core_group)
	core_inner = MeshInstance3D.new(); core_inner.mesh = Meshes.sphere(5, 64, 48)
	core_inner.material_override = shader_mat("res://shaders/core_inner.gdshader")
	core_group.add_child(core_inner)
	core_shell = MeshInstance3D.new(); core_shell.mesh = Meshes.sphere(CORE_R, 96, 64)
	core_shell.material_override = shader_mat("res://shaders/core_shell.gdshader")
	core_shell.material_override.render_priority = 2
	core_group.add_child(core_shell)
	var dirs := [[1, 0.2, 0], [-1, 0.2, 0], [0, 0.3, 1], [0, 0.3, -1], [0.5, 1, 0.3], [-0.4, -1, -0.3], [0.6, -0.6, 0.6], [-0.6, 0.6, -0.6]]
	var m_base := StandardMaterial3D.new(); m_base.albedo_color = Color.html("#2a2440"); m_base.metallic = 0.7; m_base.roughness = 0.35
	m_base.emission_enabled = true; m_base.emission = Color.html("#330a10")
	var m_bar := StandardMaterial3D.new(); m_bar.albedo_color = Color.html("#181428"); m_bar.metallic = 0.8; m_bar.roughness = 0.3
	m_bar.emission_enabled = true; m_bar.emission = Color.html("#ff3010"); m_bar.emission_energy_multiplier = 1.5
	var base_g := Meshes.cylinder(0.9, 1.3, 1.2, 8)
	var bar_g := Meshes.cylinder(0.22, 0.28, 2.0, 8)
	core_turrets.clear()
	for d in dirs:
		var dir := Vector3(d[0], d[1], d[2]).normalized()
		var g := Node3D.new()
		var b := MeshInstance3D.new(); b.mesh = base_g; b.material_override = m_base; b.position.y = 0.5
		var br := MeshInstance3D.new(); br.mesh = bar_g; br.material_override = m_bar; br.position.y = 1.6
		g.add_child(b); g.add_child(br)
		g.basis = U.basis_from_up(dir).scaled(Vector3.ONE * 0.001)
		g.position = dir * (CORE_R - 0.3)
		core_group.add_child(g)
		core_turrets.append({"g": g, "dir": dir, "cd": U.rand(0, 1)})
	# electric fence: 30 jagged arcs, rebuilt every few frames
	fence_mesh = ImmediateMesh.new()
	fence = MeshInstance3D.new(); fence.mesh = fence_mesh
	fence_mat = Meshes.unshaded(Color(1.6, 3.0, 3.4), true)
	fence.material_override = fence_mat; fence.visible = false
	fence.extra_cull_margin = 1000.0
	core_group.add_child(fence)
	fence_shell = MeshInstance3D.new(); fence_shell.mesh = Meshes.sphere(CORE_R + 6.5, 48, 32)
	fence_shell.material_override = shader_mat("res://shaders/fence_shell.gdshader", {"uOn": 0.0})
	fence_shell.visible = false
	core_group.add_child(fence_shell)
	core = {"pos": Vector3.ZERO, "r": CORE_R, "field": CORE_FIELD, "gravity": true, "solid": true, "kind": "core",
		"state": "normal", "t": 0.0, "next": 18.0, "pending": null, "dissolve": 0.0, "defense": 0.0, "alarm": 0.0, "fenceOn": false, "hum": 0.0}

func core_uniforms(dissolve: float, defense: float, alarm: float) -> void:
	for mi in [core_shell, core_inner]:
		var m: ShaderMaterial = mi.material_override
		m.set_shader_parameter("uDissolve", dissolve); m.set_shader_parameter("uDefense", defense); m.set_shader_parameter("uAlarm", alarm)

const FENCE_ARCS := 30
const FENCE_SEG := 9
func rebuild_fence() -> void:
	fence_mesh.clear_surfaces()
	fence_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var rr := CORE_R + U.rand(4.5, 6.5)
	for a in FENCE_ARCS:
		var p0 := U.rand_unit()
		var p1 := (p0 + U.rand_unit() * 0.55).normalized()
		var prev := p0 * rr
		for s in range(1, FENCE_SEG + 1):
			var t := float(s) / FENCE_SEG
			var cur := p0.lerp(p1, t).normalized() * (rr + (U.rand(-1.2, 1.2) if s < FENCE_SEG else 0.0))
			if s < FENCE_SEG: cur += U.rand_unit() * 0.6
			fence_mesh.surface_add_vertex(prev); fence_mesh.surface_add_vertex(cur)
			prev = cur
	fence_mesh.surface_end()

# ---------- mini orbs ----------
func _make_orb(i: int) -> Dictionary:
	var r := 4.6
	var g := Node3D.new(); g.name = "Orb%d" % i; root.add_child(g)
	var body := MeshInstance3D.new(); body.mesh = Meshes.sphere(r, 48, 32)
	var body_mat := shader_mat("res://shaders/orb_body.gdshader", {"uFade": 1.0})
	body.material_override = body_mat; g.add_child(body)
	var tm := StandardMaterial3D.new(); tm.albedo_color = Color.html("#e8f0d8"); tm.metallic = 0.3; tm.roughness = 0.4
	tm.emission_enabled = true; tm.emission = Color.html("#58c040"); tm.emission_energy_multiplier = 0.6
	var turrets := []
	for d in [[0.6, 0.75, 0.2], [-0.5, 0.2, 0.85]]:
		var dir := Vector3(d[0], d[1], d[2]).normalized()
		var t := Node3D.new()
		var c := MeshInstance3D.new(); c.mesh = Meshes.cylinder(0.8, 0.95, 1.1, 10); c.material_override = tm; c.position.y = 0.4
		var b1 := MeshInstance3D.new(); b1.mesh = Meshes.cylinder(0.16, 0.16, 1.4, 6); b1.material_override = tm; b1.position = Vector3(0.25, 1.2, 0)
		var b2 := MeshInstance3D.new(); b2.mesh = b1.mesh; b2.material_override = tm; b2.position = Vector3(-0.25, 1.2, 0)
		t.add_child(c); t.add_child(b1); t.add_child(b2)
		t.basis = U.basis_from_up(dir); t.position = dir * r * 0.95
		g.add_child(t); turrets.append({"t": t, "dir": dir})
	var rail_g := Node3D.new(); g.add_child(rail_g)
	var rail_r := r * 1.85
	var rail := MeshInstance3D.new(); rail.mesh = Meshes.torus(rail_r, 0.17, 8, 140); rail.material_override = Meshes.unshaded(Color(1.3, 2.2, 0.8))
	var zone := MeshInstance3D.new(); zone.mesh = Meshes.torus(rail_r, 1.9, 14, 140)
	var zone_mat := shader_mat("res://shaders/rail_zone.gdshader", {"uFade": 1.0, "uRail": 0.0}); zone.material_override = zone_mat
	var glyph_mat := glow_mat(Color(0.9, 1.3, 0.6), load("res://assets/textures/glyph_ring_orb%d.png" % i))
	var glyph := MeshInstance3D.new(); glyph.mesh = Meshes.quad(rail_r * 2.9, rail_r * 2.9); glyph.material_override = glyph_mat
	rail_g.add_child(rail); rail_g.add_child(zone); rail_g.add_child(glyph)
	rail_g.basis = Basis.from_euler(Vector3(U.rand(-0.9, 0.9), U.rand(0, TAU), U.rand(-0.6, 0.6)))
	return {"i": i, "r": r, "field": 16.0, "gravity": true, "solid": true, "kind": "orb", "g": g, "body": body, "body_mat": body_mat, "zone_mat": zone_mat,
		"railG": rail_g, "railR": rail_r, "glyph": glyph, "glyphMat": glyph_mat, "turrets": turrets,
		"orbitR": 42.0, "speed": (1.0 if i else -1.0) * 0.07, "phase": i * PI + 0.6,
		"incl": Basis.from_euler(Vector3(0.55 if i else -0.4, 0, 0.35 if i else -0.25), EULER_ORDER_XYZ),
		"pos": Vector3.ZERO, "railN": Vector3(0, 0, 1), "state": "idle", "t": 0.0, "next": U.rand(6, 10), "action": null, "hp": 8, "alive": true, "respawn": 0.0, "fade": 1.0,
		"shots": 0, "shotCd": 0.0, "hum": 0.0, "exposed": 0.0, "uHit": 0.0, "uAlarm": 0.0, "uRail": 0.0}

## The shader inputs the web build shared through one uniforms object per orb.
func orb_u(o: Dictionary, key: String, v) -> void:
	if key == "uRail": o.zone_mat.set_shader_parameter("uRail", v)
	elif key == "uFade":
		o.body_mat.set_shader_parameter("uFade", v); o.zone_mat.set_shader_parameter("uFade", v)
	else: o.body_mat.set_shader_parameter(key, v)

func place_orbs(time: float) -> void:
	for o in orbs:
		var a: float = o.phase + time * o.speed
		o.orbitR = minf(42.0, R * 0.6)
		o.pos = o.incl * Vector3(cos(a) * o.orbitR, 0, sin(a) * o.orbitR)
		o.g.position = o.pos
		o.railN = (o.railG.basis * Vector3(0, 0, 1)).normalized()

func bodies() -> Array:
	var list := []
	if core.gravity: list.append(core)
	for o in orbs:
		if o.alive and o.fade > 0.5: list.append(o)
	return list

# ---------- barrier (hex magic bounds) ----------
func _build_barrier() -> void:
	barrier = MeshInstance3D.new(); barrier.name = "Barrier"
	barrier.mesh = Meshes.sphere(1.0, 128, 64)
	barrier_mat = shader_mat("res://shaders/barrier.gdshader", {"uCount": 0.0, "uProx": 0.0, "uWarn": 0.0, "uPlayer": Vector3.ZERO})
	barrier_mat.set_shader_parameter("uImp", _imp)
	barrier_mat.render_priority = 5
	barrier.material_override = barrier_mat
	barrier.extra_cull_margin = 16384.0
	root.add_child(barrier)

func bar_u(key: String, v) -> void:
	barrier_mat.set_shader_parameter(key, v)

func bar_get(key: String):
	return barrier_mat.get_shader_parameter(key)

func barrier_impact(p: Vector3, time: float) -> void:
	_imp[_imp_idx] = Vector4(p.x, p.y, p.z, time)
	_imp_idx = (_imp_idx + 1) % 4
	barrier_mat.set_shader_parameter("uImp", _imp)

# ---------- draft tunnels (rift runnels) ----------
## Tunnels are not placed in the world: three charge crystals tear one open right where you are looking.
## Every tunnel is generated fresh (drift, corkscrew or swoop), rides slower than it looks, and collapses after use.
class Tunnel:
	extends RefCounted
	var curve: CatmullCurve
	var len: float
	var gold: bool
	var pts := PackedVector3Array()
	var tans := PackedVector3Array()
	var normals := PackedVector3Array()
	var mesh: MeshInstance3D
	var mat: ShaderMaterial
	var hoops: MultiMeshInstance3D
	var hoop_mat: ShaderMaterial
	var hoop_col: Color
	var hoop_t: Array = []
	var portal: Node3D
	var portal_glyph: MeshInstance3D
	var portal_ring: MeshInstance3D
	var portal_ring_mat: StandardMaterial3D
	var portal_glyph_mat: ShaderMaterial
	var mouth: Vector3
	var mouth_dir: Vector3
	var fade := 1.0
	var dying := false
	var state := "opening"
	var t := 0.0
	var life := 18.0
	var used := false
	var style := "drift"
	var active := 0.0       # uActive
	var open := 0.0         # uOpen
	var flow := 1.0         # uFlow

	func _init(points: PackedVector3Array, hue: float, is_gold: bool) -> void:
		var W = World
		curve = CatmullCurve.new(points)
		len = curve.get_length(); gold = is_gold
		var S: int = W.TUN_SAMPLES
		for i in S + 1:
			var u := float(i) / S
			pts.append(curve.get_point_at(u)); tans.append(curve.get_tangent_at(u))
		var fr := curve.frames(S)
		normals = fr.normals
		var ua := _hsl(hue, 0.9, 0.62)
		mat = W.shader_mat("res://shaders/tunnel.gdshader", {"uLen": len, "uFade": 1.0, "uActive": 0.0, "uOpen": 0.0, "uFlow": 1.0, "uGold": 1.0 if gold else 0.0,
			"uA": Vector3(ua.r, ua.g, ua.b), "uB": Vector3(1.6, 1.4, 1.0)})
		mat.render_priority = 4
		mesh = MeshInstance3D.new(); mesh.mesh = Meshes.tube(curve, fr, S, W.TUNNEL_R, 20); mesh.material_override = mat
		W.root.add_child(mesh)
		# glyph hoops every few metres: they whip past while riding and sell the speed
		var n := int(floor(len / 9.0))
		hoop_col = Color(2.2, 1.5, 0.6) if gold else Color(ua.r * 1.6, ua.g * 1.6, ua.b * 1.6)
		hoop_mat = W.glow_mat(Color(hoop_col.r, hoop_col.g, hoop_col.b, 0.0))
		var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.mesh = W.hoop_mesh; mm.instance_count = n
		hoops = MultiMeshInstance3D.new(); hoops.multimesh = mm; hoops.material_override = hoop_mat; hoops.extra_cull_margin = 16384.0
		for i in n:
			var ht := (i + 0.5) / n
			hoop_t.append(ht)
			var f := frame_at(ht)
			mm.set_instance_transform(i, Transform3D(Basis.looking_at(f.T, f.N), f.p))
		W.root.add_child(hoops)
		# the mouth: a glyph portal that tears open
		var f0 := frame_at(0.0)
		portal = Node3D.new()
		portal_ring = MeshInstance3D.new(); portal_ring.mesh = Meshes.torus(W.TUNNEL_R * 1.25, 0.14, 8, 64)
		portal_ring_mat = Meshes.unshaded(Color(2.6, 1.8, 0.6) if gold else Color(0.8, 2.2, 2.6))
		portal_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		portal_ring.material_override = portal_ring_mat
		portal_glyph_mat = W.glow_mat(Color(1.4, 1.0, 0.5) if gold else Color(0.6, 1.2, 1.4), W.portal_tex)
		portal_glyph = MeshInstance3D.new(); portal_glyph.mesh = Meshes.quad(W.TUNNEL_R * 4.2, W.TUNNEL_R * 4.2); portal_glyph.material_override = portal_glyph_mat
		portal.add_child(portal_ring); portal.add_child(portal_glyph)
		W.root.add_child(portal)
		portal.position = f0.p
		portal.basis = U.basis_face(f0.T)
		portal.scale = Vector3.ONE * 0.01
		mouth = f0.p; mouth_dir = f0.T

	static func _hsl(h: float, s: float, l: float) -> Color:
		var q := l * (1.0 + s) if l < 0.5 else l + s - l * s
		var p := 2.0 * l - q
		var f := func(t: float) -> float:
			if t < 0.0: t += 1.0
			if t > 1.0: t -= 1.0
			if t < 1.0 / 6.0: return p + (q - p) * 6.0 * t
			if t < 0.5: return q
			if t < 2.0 / 3.0: return p + (q - p) * 6.0 * (2.0 / 3.0 - t)
			return p
		# three.js setHSL works in sRGB and converts to linear
		return Color(f.call(h + 1.0 / 3.0), f.call(h), f.call(h - 1.0 / 3.0)).srgb_to_linear()

	## {p, T, N, B} at param t in [0,1]
	func frame_at(tt: float) -> Dictionary:
		var S: int = World.TUN_SAMPLES
		var f := clampf(tt, 0.0, 1.0) * S
		var i := mini(S - 1, int(floor(f)))
		var k := f - i
		var p := pts[i].lerp(pts[i + 1], k)
		var T := tans[i].lerp(tans[i + 1], k).normalized()
		var N := normals[i].lerp(normals[i + 1], k).normalized()
		var B := T.cross(N).normalized()
		return {"p": p, "T": T, "N": N, "B": B}

	func nearest(p: Vector3) -> Dictionary:
		var best := 1e18
		var bi := 0
		var S: int = World.TUN_SAMPLES
		for i in range(0, S + 1, 2):
			var d := pts[i].distance_squared_to(p)
			if d < best: best = d; bi = i
		return {"d": sqrt(best), "t": float(bi) / S, "i": bi}

	func set_active(v: float) -> void: active = v; mat.set_shader_parameter("uActive", v)
	func set_flow(v: float) -> void: flow = v; mat.set_shader_parameter("uFlow", v)

	func update(dt: float) -> void:
		t += dt
		if state == "opening":
			open = minf(1.0, t / 0.9); mat.set_shader_parameter("uOpen", open)
			if t >= 0.9: state = "open"
		if state == "open" and not used:
			life -= dt
			if life <= 0.0: collapse()
		if dying: fade = maxf(0.0, fade - dt * 1.4)
		var k := U.smooth(0, 0.6, t) if state == "opening" else 1.0
		portal.scale = Vector3.ONE * maxf(0.01, k * (1.0 + 0.06 * sin(t * 7.0)) * (fade if dying else 1.0))
		portal_glyph.rotate_object_local(Vector3.FORWARD, -dt * (6.0 if state == "opening" else 1.5))
		var op := (0.25 if used else 1.0) * fade * ((1.0 if int(floor(life * 5.0)) % 2 else 0.4) if life < 4.0 and not used else 1.0)
		portal_ring_mat.albedo_color.a = op
		var gc: Color = portal_glyph_mat.get_shader_parameter("color"); gc.a = op; portal_glyph_mat.set_shader_parameter("color", gc)
		mat.set_shader_parameter("uFade", fade)
		hoop_mat.set_shader_parameter("color", Color(hoop_col.r, hoop_col.g, hoop_col.b, fade * (0.25 + active * 0.55) * open))
		if state == "opening" and randf() < 0.7:
			var f := frame_at(randf() * open)
			FX.spawn({"pos": f.p + f.N * (World.TUNNEL_R * U.rand(-1, 1)) + f.B * (World.TUNNEL_R * U.rand(-1, 1)), "vel": U.rand_unit() * 4.0,
				"color": FX.GOLD if gold else FX.CYAN, "size": U.rand(0.4, 0.8), "life": 0.5, "shape": U.pick([1, 2, 5])})

	func collapse() -> void:
		if dying: return
		dying = true; state = "spent"

	func dispose() -> void:
		mesh.queue_free(); hoops.queue_free(); portal.queue_free()

## procedural path from a mouth in front of the camera
func tunnel_path(start: Vector3, dir: Vector3, length: float, style: String) -> PackedVector3Array:
	var seg := 14.0
	var n := maxi(6, roundi(length / seg))
	var pts := PackedVector3Array([start])
	var pos := start
	var d := dir.normalized()
	var side := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
	var up := side.cross(d).normalized()
	var axis := pos.normalized().cross(d).normalized() # for swoops around the core
	var helix_r := U.rand(5, 9)
	var helix_turns := U.rand(1.2, 2.2)
	var helix_ph := U.rand(0, TAU)
	var base := start
	for i in range(1, n + 1):
		if style == "corkscrew" and i > 1:
			base += d * seg
			var a := helix_ph + (float(i) / n) * helix_turns * TAU
			var r := helix_r * U.smooth(1, 3, i)
			pos = base + side * (cos(a) * r - cos(helix_ph) * r) + up * (sin(a) * r - sin(helix_ph) * r)
		else:
			if i > 2:
				if style == "swoop": d = (d.rotated(axis, 0.22 + U.rand(-0.04, 0.04)) + U.rand_unit() * 0.12).normalized()
				else: d = (d + U.rand_unit() * 0.55).normalized()
			pos = pos + d * seg
		var L := pos.length()
		if L > R - 12.0:
			d = (d - pos.normalized() * 1.2).normalized()
			pos = U.set_length(pos, R - 12.0)
		if L < CORE_R + 9.0:
			pos = U.set_length(pos, CORE_R + 11.0)
			d = (d + pos.normalized()).normalized()
		for o in orbs:
			var od: float = pos.distance_to(o.pos)
			if od < o.r + 7.0: pos += U.set_length(pos - o.pos, o.r + 7.0 - od)
		if style == "corkscrew" and i == 1: base = pos
		pts.append(pos)
	return pts

## open a tunnel where the camera is looking; returns the tunnel
func open_tunnel(gold: bool) -> Tunnel:
	# the mouth opens on the line you are actually flying (gravity curves you around the core)
	var pp: Array = HOM.predict_path(1, 1, 28 if gold else 32)
	var ahead = pp[0] if pp.size() else null
	var look: Vector3 = ahead.fwd if ahead else P.fwd
	var mouth: Vector3 = (ahead.pos if ahead else P.pos) + (ahead.up if ahead else P.up) * 0.8
	if mouth.length() > R - 16.0: mouth = U.set_length(mouth, R - 16.0)
	if mouth.length() < CORE_R + 8.0: mouth = U.set_length(mouth, CORE_R + 10.0)
	var style: String = U.pick(["drift", "corkscrew", "swoop"])
	var length := U.rand(230, 270) if gold else U.rand(160, 210)
	var tun := Tunnel.new(tunnel_path(mouth, look, length, style), 0.11 if gold else U.pick([0.53, 0.86, 0.6]), gold)
	tun.style = style; tunnels.append(tun); add_gem_rows(tun)
	return tun

func clear_tunnels() -> void:
	for t in tunnels: t.dispose()
	tunnels.clear(); gems = []; gem_rows = []; hide_all_gems()

# ---------- crystals ----------
func random_free_spot(r_min: float = CORE_R + 6.0, r_max: float = -1.0) -> Vector3:
	if r_max < 0.0: r_max = R * 0.88
	var out := Vector3.ZERO
	for k in 20:
		out = U.rand_unit() * U.rand(r_min, r_max)
		var ok := true
		for o in orbs:
			if out.distance_to(o.pos) < o.r + 4.0: ok = false
		if ok: break
	return out

func set_inst(mm: MultiMeshInstance3D, i: int, xf: Transform3D) -> void:
	mm.multimesh.set_instance_transform(i, xf)

var HIDDEN := Transform3D(Basis.from_scale(Vector3(0.0001, 0.0001, 0.0001)), Vector3(0, -9999, 0))

# ---------- gems (rows) ----------
func hide_all_gems() -> void:
	for i in N_GEM: gem_mm.multimesh.set_instance_transform(i, HIDDEN)

func reindex_gems() -> void:
	for i in gems.size(): gems[i].idx = i
	for i in range(gems.size(), N_GEM): gem_mm.multimesh.set_instance_transform(i, HIDDEN)

func add_gem_rows(tun: Tunnel) -> void:
	gems = gems.filter(func(g): return g.alive and g.row.tunnel and not g.row.tunnel.dying)
	var rows := maxi(2, int(floor(tun.len / 50.0)))
	for r in rows:
		var a := 0.1 + float(r) / rows * 0.82
		var b := a + 0.5 / rows
		var pattern: String = U.pick(["line", "helix", "zig", "ring"])
		var row := {"total": 0, "got": 0, "kind": pattern, "tunnel": tun}
		var n := 8 if pattern == "ring" else (12 if tun.gold else 9)
		for k in n:
			if gems.size() >= N_GEM: break
			var t := (a + b) / 2.0 if pattern == "ring" else lerpf(a, b, float(k) / (n - 1))
			var f := tun.frame_at(t)
			var ox := 0.0
			var oy := 0.0
			if pattern == "helix": var ang := k * 0.8; ox = cos(ang) * 2.0; oy = sin(ang) * 2.0
			if pattern == "zig": ox = 1.8 if k % 2 else -1.8
			if pattern == "ring": var ang := float(k) / n * TAU; ox = cos(ang) * 2.2; oy = sin(ang) * 2.2
			gems.append({"pos": f.p + f.N * ox + f.B * oy, "alive": true, "row": row, "idx": 0, "kind": "gem", "ph": U.rand(0, 10)})
			row.total += 1
		gem_rows.append(row)
	reindex_gems()

func build_gem_rows() -> void:
	gems = []; gem_rows = []; reindex_gems()

# ---------- weapon pickups ----------
func make_pickup_mesh(type: String) -> Node3D:
	var g := Node3D.new()
	var w: Dictionary = WEAPONS[type]
	var cage := MeshInstance3D.new(); cage.mesh = Meshes.wire(Meshes.icosahedron(1.3))
	cage.material_override = Meshes.unshaded(w.color)
	var core_m := MeshInstance3D.new(); core_m.mesh = Meshes.sphere(0.55, 12, 8); core_m.material_override = Meshes.unshaded(w.color)
	var ring := MeshInstance3D.new(); ring.mesh = Meshes.quad(4.2, 4.2)
	ring.material_override = glow_mat(w.color, load("res://assets/textures/glyph_ring_pickup%d.png" % (7 + type.length())))
	g.add_child(cage); g.add_child(core_m); g.add_child(ring)
	g.set_meta("cage", cage); g.set_meta("ring", ring)
	root.add_child(g)
	return g

func spawn_pickup() -> void:
	var type: String = U.pick(WEAPONS.keys())
	var pos := Vector3.ZERO
	# key points: next to an orb rail, or at a tunnel mouth
	var live := tunnels.filter(func(t): return not t.dying)
	if randf() < 0.5 and live.size():
		var tun: Tunnel = U.pick(live)
		var f := tun.frame_at(0.02 if randf() < 0.5 else 0.98)
		pos = f.p + f.T * (-6.0 if randf() < 0.5 else 6.0)
	else:
		var o: Dictionary = U.pick(orbs)
		pos = o.pos + U.rand_unit() * (o.railR + 3.0)
	if pos.length() > R - 6.0: pos = U.set_length(pos, R - 8.0)
	if pos.length() < CORE_R + 4.0: pos = U.set_length(pos, CORE_R + 6.0)
	var p := {"kind": "pickup", "type": type, "pos": pos, "mesh": make_pickup_mesh(type), "life": 32.0, "t": 0.0}
	p.mesh.position = pos
	pickups.append(p)
