extends Node
## ENEMIES / ENVIRONMENT BEHAVIOUR (port of 40_enemies.js): hostile projectiles, enemy jets, probes and
## tutorial drones, homing-ring weapon, orb superblast waves, the core and orb state machines, orb shields.
## Shot language (Star Fox / Starlink study): a white-hot core inside a coloured sheath, stretched along its
## motion, with a short sparking trail. Hostile shots are hot magenta (turrets) or coral (jets).

const N_PROJ := 90
const COL_JET := Color(2.6, 0.8, 0.5)
const COL_TURRET := Color(2.8, 0.3, 1.0)

var root: Node3D
var proj_mm: MultiMeshInstance3D
var proj_sheath: MultiMeshInstance3D
var projs: Array = []
var enemies: Array = []
var probes: Array = []
var h_rings: Array = []
var waves: Array = []
var wave_mesh: SphereMesh

## Two-layer bolt geometry: an octahedron stretched along +Z.
func bolt_mesh(w: float, l: float) -> ArrayMesh:
	return Meshes.octahedron(1.0, Vector3(w, w, l))

func setup(r: Node3D) -> void:
	root = r
	var core_mat := StandardMaterial3D.new(); core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; core_mat.vertex_color_use_as_albedo = true
	proj_mm = World._mm(bolt_mesh(0.16, 0.95), N_PROJ, core_mat)
	var sheath_mat := World.glow_mat(Color(1, 1, 1, 0.55))
	proj_sheath = World._mm(bolt_mesh(0.42, 1.7), N_PROJ, sheath_mat)
	for i in N_PROJ:
		proj_mm.multimesh.set_instance_color(i, Color(2.2, 2.0, 1.9))
		proj_sheath.multimesh.set_instance_color(i, COL_JET)
		proj_mm.multimesh.set_instance_transform(i, World.HIDDEN); proj_sheath.multimesh.set_instance_transform(i, World.HIDDEN)
		projs.append({"i": i, "on": false, "pos": Vector3.ZERO, "vel": Vector3.ZERO, "life": 0.0, "homing": 0.0, "col": COL_JET, "src": "jet", "minD": 99.0, "nm": false})
	# enemy jets
	for i in 5:
		var j := Jet.make(Color.html("#5fb81a"), Color(1.2, 2.4, 0.6), Color(0.6, 1.0, 0.3), Color(0.2, 0.9, 0.3), 0.85)
		root.add_child(j); j.visible = false
		enemies.append({"kind": "enemy", "j": j, "pos": Vector3.ZERO, "fwd": Vector3(1, 0, 0), "up": Vector3(0, 1, 0), "alive": false, "respawn": U.rand(1, 4), "cd": U.rand(1, 3),
			"wp": Vector3.ZERO, "wpT": 0.0, "speed": 23.0, "hp": 1, "spawnT": 0.0})
	# probes
	var probe_geo := Meshes.octahedron(0.8)
	var probe_mat := StandardMaterial3D.new(); probe_mat.albedo_color = Color.html("#2a0a20"); probe_mat.metallic = 0.8; probe_mat.roughness = 0.25
	probe_mat.emission_enabled = true; probe_mat.emission = Color(1.6, 0.2, 0.8).linear_to_srgb(); probe_mat.emission_energy_multiplier = 1.2
	var ring_mat := Meshes.unshaded(Color(2.2, 0.4, 1.3), false)
	var ring_mesh := Meshes.torus(1.1, 0.06, 6, 24)
	for i in 12:
		var g := Node3D.new()
		var b := MeshInstance3D.new(); b.mesh = probe_geo; b.material_override = probe_mat
		var rr := MeshInstance3D.new(); rr.mesh = ring_mesh; rr.material_override = ring_mat
		g.add_child(b); g.add_child(rr); g.visible = false; root.add_child(g)
		probes.append({"kind": "probe", "g": g, "ring": rr, "pos": Vector3.ZERO, "vel": Vector3.ZERO, "alive": false, "life": 0.0, "passive": false, "home": Vector3.ZERO, "ph": 0.0})
	wave_mesh = Meshes.sphere(1, 40, 24)

# ---------- projectiles ----------
func fire_proj(from: Vector3, dir: Vector3, spd: float = 34.0, homing: float = 0.0, col: Color = COL_JET, src: String = "jet") -> void:
	var p = null
	for x in projs:
		if not x.on: p = x; break
	if p == null: return
	p.on = true; p.pos = from; p.vel = dir.normalized() * spd; p.life = 4.0; p.homing = homing; p.minD = 99.0; p.nm = false
	if p.col != col: p.col = col; proj_sheath.multimesh.set_instance_color(p.i, col)
	p.src = src
	FX.spawn({"pos": from, "vel": p.vel * 0.05, "color": col, "size": 1.4, "life": 0.12, "shape": 0}) # muzzle flash
	AudioSys.shot(from.distance_to(P.pos), from)

func update_projs(dt: float) -> void:
	for p in projs:
		if not p.on:
			continue
		p.life -= dt
		if p.homing:
			var want: Vector3 = (P.pos - p.pos).normalized() * p.vel.length()
			p.vel = p.vel.lerp(want, 1.0 - exp(-p.homing * dt))
		p.pos += p.vel * dt
		var d: float = p.pos.distance_to(P.pos)
		if d < p.minD: p.minD = d
		var dead := false
		if not p.nm and p.minD < 3.4 and p.minD > 1.3 and d > p.minD + 1.5 and P.mode == "fly":
			p.nm = true; ST.gain("nearmiss", 10); FX.popup("NEAR MISS", "#8fe9ff")
		if d < 2.6 and (P.ram or P.mode == "supercut"): p.on = false; FX.sparks(p.pos, 8, p.col); dead = true
		elif d < 1.3: p.on = false; P.hurt(8, "TURRET" if p.src == "turret" else "HIT"); FX.sparks(p.pos, 14, p.col); dead = true
		elif p.life <= 0 or p.pos.length() > World.R or (World.core.solid and p.pos.length() < World.CORE_R - 0.5 and p.life < 3.8): p.on = false; dead = true
		if dead:
			proj_mm.multimesh.set_instance_transform(p.i, World.HIDDEN); proj_sheath.multimesh.set_instance_transform(p.i, World.HIDDEN)
			continue
		if randf() < 0.35: FX.spawn({"pos": p.pos, "vel": p.vel * -0.08 + U.rand_unit() * 1.2, "color": p.col, "size": 0.35, "life": 0.18, "shape": 0})
		var s: float = 0.9 + sin(Ctl.now * 30 + p.i) * 0.15
		var b := U.basis_face(p.vel.normalized()).scaled_local(Vector3(s, s, 1)) if p.vel.length() > 0.01 else Basis()
		var xf := Transform3D(b, p.pos)
		proj_mm.multimesh.set_instance_transform(p.i, xf); proj_sheath.multimesh.set_instance_transform(p.i, xf)

func kill_projs_in_radius(pos: Vector3, r: float) -> void:
	for p in projs:
		if p.on and p.pos.distance_to(pos) < r:
			p.on = false; FX.sparks(p.pos, 5, FX.CORAL)
			proj_mm.multimesh.set_instance_transform(p.i, World.HIDDEN); proj_sheath.multimesh.set_instance_transform(p.i, World.HIDDEN)

# ---------- enemy jets ----------
func spawn_enemy(e: Dictionary) -> void:
	e.pos = World.random_free_spot(World.CORE_R + 14, World.R * 0.8)
	if e.pos.distance_to(P.pos) < 35: e.pos = -e.pos
	e.fwd = U.rand_unit(); e.up = e.pos.normalized(); e.alive = true; e.j.visible = true; e.spawnT = 0.8; e.cd = U.rand(2, 4)
	FX.shockwave(e.pos, 5, FX.LIME, 0.5); FX.burst_shapes(e.pos, 14, [2, 5], 10, FX.LIME)

func _style_tag(by) -> String:
	return "ram" if by == "RAM" else ("boomkill" if by == "BOOM" else ("sckill" if by == "SUPERCUT" else ("homekill" if by == "HOMING" else "kill")))

func kill_enemy(e: Dictionary, by = null) -> void:
	if not e.alive: return
	e.alive = false; e.j.visible = false; e.respawn = U.rand(5, 8)
	FX.burst_shapes(e.pos, 40, [0, 1, 2, 5], 26, FX.LIME); FX.sparks(e.pos, 30, FX.GOLD, 30); FX.shockwave(e.pos, 7, FX.LIME, 0.5)
	AudioSys.explode(e.pos); GAME.kills += 1
	GAME.add_score(300, by if by else "TAKEDOWN")
	ST.gain(_style_tag(by), 28 if by == "RAM" else (14 if by == "HOMING" else 22))
	TUT.note("kill", by)

func update_enemies(dt: float) -> void:
	for e in enemies:
		if not e.alive:
			e.respawn -= dt
			var ph: Dictionary = ST.phase()
			var alive := enemies.filter(func(x): return x.alive).size()
			var early: bool = not TUT.active and ST.DIR.phase == 0 and GAME.time < ST.PHASES[0].firstEnemy
			if e.respawn <= 0 and GAME.state == "play" and alive < ph.enemies and not early: spawn_enemy(e)
			continue
		e.spawnT = maxf(0.0, e.spawnT - dt)
		var to_p: Vector3 = P.pos - e.pos
		var dP := to_p.length()
		e.wpT -= dt
		if e.wpT <= 0 or e.pos.distance_to(e.wp) < 6:
			e.wp = World.random_free_spot(World.CORE_R + 10, World.R * 0.8); e.wpT = U.rand(4, 8)
		var target: Vector3 = e.wp
		if dP < 55 and P.mode != "supercut": target = P.pos + P.fwd * 12 + P.right * (sin(Ctl.now + e.cd) * 8)
		var want: Vector3 = (target - e.pos).normalized()
		var cd: float = e.pos.length()
		if cd < World.CORE_R + 6: want = (want + e.pos.normalized() * 2).normalized()
		if cd > World.R - 8: want = (want - e.pos.normalized() * 2).normalized()
		for o in World.orbs:
			var od: float = e.pos.distance_to(o.pos)
			if od < o.r + 5: want = (want + (e.pos - o.pos).normalized() * 2).normalized()
		e.fwd = e.fwd.lerp(want, 1.0 - exp(-1.8 * dt)).normalized()
		e.up = e.up.lerp(e.pos.normalized(), 1.0 - exp(-2 * dt))
		e.up = (e.up - e.fwd * e.up.dot(e.fwd)).normalized()
		e.speed = 26.0 if dP < 55 else 22.0
		e.pos += e.fwd * e.speed * dt
		# shoot
		e.cd -= dt
		if e.cd <= 0 and dP < 60 and dP > 8 and e.fwd.dot(to_p.normalized()) > 0.8 and e.spawnT <= 0:
			var lead: Vector3 = P.pos + P.fwd * (P.speed * dP / 40)
			fire_proj(e.pos + e.fwd * 1.5, lead - e.pos, 40)
			e.cd = U.rand(1.8, 3.2)
		# ram / collide with player
		if e.pos.distance_to(P.pos) < 2.4:
			if P.ram or P.mode == "supercut": kill_enemy(e, "RAM")
			elif P.hurt(10, "COLLISION"): kill_enemy(e, "CRASH")
		var right: Vector3 = e.up.cross(e.fwd).normalized()
		var j: Jet = e.j
		j.basis = Basis(right, e.up, e.fwd).scaled_local(Vector3.ONE * 0.85 * (1 - e.spawnT * 0.8))
		j.position = e.pos
		j.inner.rotation.z = sin(Ctl.now * 2 + e.cd) * 0.3
		for f in j.flames: f.scale = Vector3(1, 1, 0.8 + randf() * 0.4)

# ---------- probes ----------
func spawn_probe(from: Vector3) -> void:
	var p = null
	for x in probes:
		if not x.alive: p = x; break
	if p == null: return
	p.alive = true; p.g.visible = true; p.pos = from; p.vel = U.rand_unit() * 15; p.life = 14.0; p.passive = false
	FX.sparks(from, 10, FX.MAG, 10); AudioSys.probe_spawn(from)

func kill_probe(p: Dictionary, by = null) -> void:
	if not p.alive: return
	p.alive = false; p.g.visible = false
	FX.burst_shapes(p.pos, 22, [1, 4, 5], 18, FX.MAG); FX.shockwave(p.pos, 4, FX.MAG, 0.4); AudioSys.explode(p.pos)
	if by:
		GAME.kills += 1; GAME.add_score(150, by); ST.gain(_style_tag(by), 6 if by == "HOMING" else 14)
	TUT.note("kill", by)

## passive tutorial target
func spawn_drone(pos: Vector3):
	var p = null
	for x in probes:
		if not x.alive: p = x; break
	if p == null: return null
	p.alive = true; p.g.visible = true; p.pos = pos; p.vel = Vector3.ZERO; p.life = 999.0; p.passive = true; p.home = pos; p.ph = U.rand(0, TAU)
	FX.sparks(pos, 12, FX.MAG, 8)
	return p

func update_probes(dt: float) -> void:
	for p in probes:
		if not p.alive: continue
		if p.passive:
			p.ph += dt
			p.pos = Vector3(p.home.x + sin(p.ph) * 1.5, p.home.y + cos(p.ph * 0.8) * 1.2, p.home.z + sin(p.ph * 0.6) * 1.5)
			if p.pos.distance_to(P.pos) < 2.6: kill_probe(p, "RAM" if P.ram or P.mode == "supercut" else "HIT")
			p.g.position = p.pos; p.g.rotation.x += dt * 2; p.g.rotation.y += dt * 3; p.ring.rotation.x += dt * 5
			continue
		p.life -= dt
		if p.life <= 0: kill_probe(p, null); GAME.score = maxi(0, GAME.score - 150); continue
		var want: Vector3 = P.pos - p.pos
		var d := want.length()
		want = want.normalized() * 29
		p.vel = p.vel.lerp(want, 1.0 - exp(-1.3 * dt))
		p.pos += p.vel * dt
		if d < 2.6 and (P.ram or P.mode == "supercut"): kill_probe(p, "RAM"); continue
		if d < 1.6: P.hurt(10, "PROBE"); kill_probe(p, null); continue
		p.g.position = p.pos; p.g.rotation.x += dt * 3; p.g.rotation.y += dt * 5; p.ring.rotation.x += dt * 7

# ---------- homing rings (weapon) ----------
func launch_homing_rings(n: int) -> void:
	AudioSys.ring_launch()
	for i in n:
		var r: Dictionary = FX.get_turbo_ring(); r.g.scale = Vector3.ONE * 0.6
		h_rings.append({"r": r, "pos": P.pos + P.right * ((i - (n - 1) / 2.0) * 2.5), "vel": P.fwd * 60 + U.rand_unit() * 10, "life": 3.5, "target": null})

func all_targets() -> Array:
	var t := []
	for e in enemies:
		if e.alive: t.append(e)
	for p in probes:
		if p.alive: t.append(p)
	return t

func update_homing_rings(dt: float) -> void:
	for i in range(h_rings.size() - 1, -1, -1):
		var h = h_rings[i]
		h.life -= dt
		if h.target == null or not h.target.alive:
			var best = null
			var bd := 120.0
			for t in all_targets():
				var d: float = t.pos.distance_to(h.pos)
				if d < bd: bd = d; best = t
			h.target = best
		if h.target: h.vel = h.vel.lerp((h.target.pos - h.pos).normalized() * 75, 1.0 - exp(-4 * dt))
		h.pos += h.vel * dt
		h.r.g.position = h.pos
		if h.vel.length() > 0.01: h.r.g.basis = U.basis_face(h.vel.normalized()).scaled_local(h.r.g.scale)
		h.r.gl.rotate_object_local(Vector3.BACK, dt * 6)
		if randf() < 0.6: FX.spawn({"pos": h.pos, "color": FX.GOLD, "size": 0.5, "life": 0.4, "shape": 1})
		if h.target and h.target.pos.distance_to(h.pos) < 2.5:
			if h.target.kind == "enemy": kill_enemy(h.target, "HOMING RING")
			else: kill_probe(h.target, "HOMING RING")
			h.life = 0.0
		if h.life <= 0: FX.free_turbo_ring(h.r); h_rings.remove_at(i)

# ---------- superblast waves (from orbs) ----------
func spawn_wave(pos: Vector3) -> void:
	var m := MeshInstance3D.new(); m.mesh = wave_mesh
	var mat := ShaderMaterial.new(); mat.shader = preload("res://shaders/wave.gdshader"); m.material_override = mat
	m.position = pos; root.add_child(m)
	waves.append({"m": m, "mat": mat, "pos": pos, "r": 1.0, "max": 44.0, "hit": false, "t": 0.0})

func update_waves(dt: float) -> void:
	for i in range(waves.size() - 1, -1, -1):
		var w = waves[i]
		w.t += dt; w.r = 4 + w.t * 20
		var k: float = w.r / w.max
		w.m.scale = Vector3.ONE * w.r; w.mat.set_shader_parameter("uA", 1.0 - k)
		var d: float = P.pos.distance_to(w.pos)
		if not w.hit and absf(d - w.r) < 1.8:
			w.hit = true
			if P.boost > 30 or P.mode != "fly":
				FX.popup("BURST THROUGH", "#ff8ad6"); GAME.add_score(200, null); ST.gain("burst", 15); AudioSys.ring_pass(3)
			else: P.hurt(15, "SUPERBLAST")
		if k >= 1: w.m.queue_free(); waves.remove_at(i)

func clear_waves() -> void:
	for w in waves: w.m.queue_free()
	waves.clear()

# ---------- core state machine ----------
func update_core(dt: float) -> void:
	var c: Dictionary = World.core
	c.t += dt
	var ph: Dictionary = ST.phase()
	if c.state == "normal":
		if not ph.get("core"): c.t = minf(c.t, 1.0)
		if c.t > c.next and ph.get("core"):
			c.state = "telegraph"; c.t = 0.0; c.pending = "phase" if randf() < 0.5 else "defense"
			AudioSys.alarm(0.14); AudioSys.play("bell", {"vol": 0.5, "rate": 0.8})
			GAME.banner_set("CORE ▸ PHASE OUT" if c.pending == "phase" else "CORE ▸ DEFENSE MODE", true)
	elif c.state == "telegraph":
		c.alarm = 0.5 + 0.5 * sin(c.t * 18)
		if floor(c.t / 0.85) != floor((c.t - dt) / 0.85): AudioSys.alarm(0.12)
		if c.t > 2.6:
			c.state = c.pending; c.t = 0.0; c.alarm = 0.0
			GAME.banner_set("CORE GONE ▸ NO GRAVITY" if c.pending == "phase" else "CORE ▸ TURRETS + FENCE", false)
			if c.pending == "defense": FX.shake(0.3)
	elif c.state == "phase":
		c.dissolve = minf(1.0, c.dissolve + dt * 1.2)
		if c.t > 8.5: c.state = "rephase"; c.t = 0.0; GAME.banner_set("CORE RETURNING", true); AudioSys.alarm(0.08)
	elif c.state == "rephase":
		c.dissolve = maxf(0.0, c.dissolve - dt * 1.0)
		if c.dissolve <= 0:
			var rng: Array = ph.get("core") if ph.get("core") else [15, 21]
			c.state = "normal"; c.t = 0.0; c.next = U.rand(rng[0], rng[1]); GAME.banner_set("")
	elif c.state == "defense":
		c.defense = minf(1.0, c.defense + dt * 2)
		if c.t > 10: c.state = "undefense"; c.t = 0.0
	elif c.state == "undefense":
		c.defense = maxf(0.0, c.defense - dt * 1.5)
		if c.defense <= 0:
			var rng: Array = ph.get("core") if ph.get("core") else [15, 21]
			c.state = "normal"; c.t = 0.0; c.next = U.rand(rng[0], rng[1]); GAME.banner_set("")
	if c.state != "telegraph": c.alarm = U.damp(c.alarm, 0.0, 6, dt)
	c.gravity = c.dissolve < 0.5; c.solid = c.dissolve < 0.3
	World.core_uniforms(c.dissolve, c.defense, c.alarm)
	World.core_group.visible = c.dissolve < 0.999
	World.core_inner.rotation.y += dt * 0.3; World.core_shell.rotation.y -= dt * 0.05
	# core turrets are run by the turret system (threats.gd); defense mode makes them faster
	var def: float = c.defense
	c.fenceOn = def > 0.6
	World.fence.visible = c.fenceOn; World.fence_shell.visible = c.fenceOn
	World.fence_shell.material_override.set_shader_parameter("uOn", def)
	if c.fenceOn:
		if randf() < 0.6: World.rebuild_fence()
		World.fence_mat.albedo_color.a = 0.6 + randf() * 0.4
		var d := P.pos.length()
		if d < World.CORE_R + 7.5 and P.mode == "fly" and GAME.state == "play":
			if P.hurtCd <= 0: P.hurt(9, "FENCE"); P.hurtCd = 0.5; FX.sparks(P.pos, 20, FX.CYAN, 16)
	c.hum = 1.0 if c.state == "telegraph" else (0.5 if c.state == "defense" else 0.15) * U.smooth(60, 15, P.pos.length())

# ---------- orb state machine ----------
func update_orbs(dt: float) -> void:
	P.onRailNow = false
	var ph: Dictionary = ST.phase()
	for o in World.orbs:
		o["uHit"] = U.damp(o.get("uHit", 0.0), 0.0, 8, dt); World.orb_u(o, "uHit", o.uHit)
		if not o.alive:
			o.respawn -= dt; o.fade = 0.0; o.g.visible = false
			if o.respawn <= 0:
				o.alive = true; o.hp = 8; o["exposed"] = 0.0; o.fade = 0.0; o.g.visible = true; o.state = "idle"; o.t = 0.0; o.next = U.rand(5, 8)
				FX.shockwave(o.pos, 12, FX.LIME, 0.8)
			continue
		o.fade = minf(1.0, o.fade + dt * 0.8); World.orb_u(o, "uFade", o.fade); o.g.scale = Vector3.ONE * (0.2 + o.fade * 0.8)
		o.t += dt
		o.railG.rotate_object_local(Vector3.UP, dt * 0.12)
		var exposed: float = o.get("exposed", 0.0)
		o.glyph.rotate_object_local(Vector3.BACK, dt * (6.0 if exposed > 0 else (3.5 if o.state == "telegraph" else 0.5)))
		var dP: float = P.pos.distance_to(o.pos)
		if exposed > 0:
			o.exposed -= dt; o.state = "idle"; o.t = 0.0
			var fl := 0.5 + 0.5 * sin(Ctl.now * 18)
			o.uHit = 0.06 + fl * 0.1; World.orb_u(o, "uHit", o.uHit)
			o.glyphMat.set_shader_parameter("color", Color(1.5, 1.2, 0.5 + fl * 0.4))
			if randf() < 0.5: FX.spawn({"pos": o.pos + U.rand_unit() * (o.r * 1.3), "vel": U.rand_unit() * 4, "color": FX.GOLD, "size": 0.6, "life": 0.5, "shape": 5})
			if o.exposed <= 0:
				o.hp = 4; o.exposed = 0.0
				if dP < 80: FX.popup("ORB SHIELD RESTORED", "#c9a8ff")
		elif o.state == "idle":
			o["uAlarm"] = U.damp(o.get("uAlarm", 0.0), 0.0, 5, dt); World.orb_u(o, "uAlarm", o.uAlarm)
			o.glyphMat.set_shader_parameter("color", Color(0.9, 1.3, 0.6))
			if not ph.get("orb"): o.t = minf(o.t, 1.0)
			if o.t > o.next and ph.get("orb"):
				o.state = "telegraph"; o.t = 0.0; o.action = U.pick(ph.orb)
				if dP < 70: AudioSys.alarm(0.1 * U.smooth(70, 10, dP) + 0.03); AudioSys.ui("warning")
		elif o.state == "telegraph":
			o.uAlarm = 1.0; World.orb_u(o, "uAlarm", 1.0)
			var pulse := 0.5 + 0.5 * sin(o.t * 22)
			o.glyphMat.set_shader_parameter("color", Color(2.6, 0.5 + pulse * 0.6, 0.3))
			if o.action == "superblast":
				for k in 2: # the vortex draws in before it bursts
					var from: Vector3 = o.pos + U.rand_unit() * (o.r * U.rand(2.4, 3.6))
					FX.spawn({"pos": from, "vel": (o.pos - from) * 1.6, "color": Color(1.6, 0.45, 1.4), "size": U.rand(0.4, 0.8), "life": 0.5, "shape": U.pick([0, 5])})
			if o.t > 2:
				o.state = "act"; o.t = 0.0; o.shots = 0; o.shotCd = 0.0
				if o.action == "probes":
					for k in 3: spawn_probe(o.pos + U.rand_unit() * (o.r + 1.5))
					if dP < 80: FX.popup("PROBES INCOMING", "#ff8ad6")
				if o.action == "superblast":
					spawn_wave(o.pos); FX.shake(0.4 * U.smooth(90, 10, dP)); AudioSys.superblast()
					if dP < 80: FX.popup("SUPERBLAST — BOOST THROUGH", "#ff8ad6", true)
		elif o.state == "act":
			o.uAlarm = U.damp(o.get("uAlarm", 0.0), 0.0, 3, dt); World.orb_u(o, "uAlarm", o.uAlarm)
			if o.action == "turret":
				o.shotCd -= dt
				if o.shotCd <= 0 and o.shots < 6 and dP < 75 and GAME.state == "play":
					var tt: Dictionary = o.turrets[o.shots % 2]
					var wp: Vector3 = o.g.basis.orthonormalized() * tt.dir * (o.r + 1.5) + o.pos
					fire_proj(wp, P.pos - wp, 32, 0.4); o.shots += 1; o.shotCd = 0.32
			if o.t > 2.5: o.state = "idle"; o.t = 0.0; o.next = U.rand(7, 12)
		# charging rail
		var q: Vector3 = P.pos - o.pos
		var h: float = q.dot(o.railN)
		var planar: float = (q - o.railN * h).length()
		var rd: float = Vector2(planar - o.railR, h).length()
		var on_rail: bool = rd < 2.1 and P.mode == "fly"
		o["uRail"] = U.damp(o.get("uRail", 0.0), 1.0 if on_rail else 0.0, 8, dt); World.orb_u(o, "uRail", o.uRail)
		if on_rail:
			P.onRailNow = true; P.railT += dt
			if randf() < 0.7: FX.spawn({"pos": P.pos, "vel": U.rand_unit() * 6, "color": FX.LIME, "size": 0.4, "life": 0.4, "shape": 5})
			if P.railT > 0.3:
				P.railT = 0.0
				if BL.railBonus < 3:
					BL.railBonus += 1; FX.popup("RAIL CHARGE +1", "#dce9a9"); AudioSys.ring(BL.railBonus); ST.gain("rail", 6); TUT.note("rail")

## orb shields: damage drops them, an exposed orb must be primed and breached (glyph memory) to shatter
func damage_orb(o: Dictionary, amt: float, _by = null) -> void:
	if not o.alive or o.get("exposed", 0.0) > 0: return
	o.hp -= amt; o.uHit = 1.0; World.orb_u(o, "uHit", 1.0); FX.sparks(o.pos, 20, FX.LIME, 18)
	if o.hp <= 0:
		o.hp = 0; o.exposed = 14.0 if TUT.active else ST.COOL.exposed; o.state = "idle"
		FX.shockwave(o.pos, 10, FX.GOLD, 0.5); AudioSys.play("cell_full", {"vol": 0.8, "rate": 0.7})
		FX.popup("ORB EXPOSED · HOME INTO IT", "#ffd27a", true); Coach.hint("exposed")
		ST.gain("orbhit", 15); TUT.note("exposed")
	else:
		GAME.add_score(100, null); ST.gain("orbhit", 8)

func shatter_orb(o: Dictionary, by = null) -> void:
	o.alive = false; o.exposed = 0.0; o.respawn = 22.0; o.g.visible = false
	FX.shockwave(o.pos, 22, FX.LIME, 1.0); FX.burst_shapes(o.pos, 80, [1, 2, 3, 4, 5], 40, FX.LIME); FX.burst_shapes(o.pos, 40, [1, 2], 30)
	FX.event_text("ORB SHATTERED!", "gold"); AudioSys.orb_shatter(); FX.shake(0.8)
	GAME.add_score(1500, by if by else "ORB")
