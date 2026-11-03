extends Node
## TURRETS · CHARGED SHOTS · THREAT UI (port of 43_threats.js).
## Turrets sit on the mini-planets (from CONTACT) and on the core (from THE IRIS). Each one telegraphs:
##   TRACK  a red laser sight follows you and a red glow builds in the muzzle (0.65 s)
##   LOCK   the sight freezes on where you are heading and turns white, with a beep (0.25 s): turn now
##   BURST  three hot magenta bolts down the locked line, then a cooldown
## At most two turrets aim at you at once (three in core defense mode). Home into one, ram it or boom it.

var TUR := {"list": [], "aiming": 0}
const TUR_T := {"track": 0.65, "lock": 0.25, "gap": 0.11}
const N_PB := 16

var root: Node3D
var sight_mesh: ImmediateMesh
var pb_core: MultiMeshInstance3D
var pb_sheath: MultiMeshInstance3D
var pbolts: Array = []
var diamond_tex: Texture2D = preload("res://assets/textures/diamond_glow.tres")

func setup(r: Node3D) -> void:
	root = r
	sight_mesh = ImmediateMesh.new()
	var sl := MeshInstance3D.new(); sl.name = "TurretSights"; sl.mesh = sight_mesh; sl.extra_cull_margin = 16384.0
	var sm := Meshes.unshaded(Color(1, 1, 1, 0.9), true); sm.vertex_color_use_as_albedo = true
	sl.material_override = sm; root.add_child(sl)
	var core_mat := StandardMaterial3D.new(); core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; core_mat.vertex_color_use_as_albedo = true
	pb_core = World._mm(Enemies.bolt_mesh(0.2, 1.1), N_PB, core_mat)
	pb_sheath = World._mm(Enemies.bolt_mesh(0.55, 2.0), N_PB, World.glow_mat(Color(1, 1, 1, 0.6)))
	for i in N_PB:
		pb_core.multimesh.set_instance_color(i, Color(2.4, 2.4, 2.2)); pb_sheath.multimesh.set_instance_color(i, FX.CYAN)
		pb_core.multimesh.set_instance_transform(i, World.HIDDEN); pb_sheath.multimesh.set_instance_transform(i, World.HIDDEN)
		pbolts.append({"i": i, "on": false, "pos": Vector3.ZERO, "vel": Vector3.ZERO, "target": null, "payload": null, "life": 0.0, "big": 1.0})

func _muzzle_glow() -> Dictionary:
	var m := MeshInstance3D.new(); m.mesh = Meshes.quad(1, 1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED; mat.albedo_texture = diamond_tex
	mat.albedo_color = Color(0, 0, 0, 0)
	m.material_override = mat; m.scale = Vector3.ONE * 0.01
	root.add_child(m)
	return {"m": m, "mat": mat}

func _glow_set(g: Dictionary, col: Color, a: float) -> void:
	var c := col.linear_to_srgb(); c.a = clampf(a, 0, 1)
	g.mat.albedo_color = c

func build_turrets() -> void:
	TUR.list.clear()
	for ct in World.core_turrets:
		TUR.list.append({"kind": "turret", "host": World.core, "ref": ct.g, "dir": ct.dir, "pos": Vector3.ZERO, "n": Vector3.ZERO, "aim": Vector3.ZERO, "alive": true, "state": "idle", "t": 0.0, "cd": U.rand(2, 5), "shots": 0, "respawn": 0.0, "vis": 0.0, "glow": _muzzle_glow()})
	for o in World.orbs:
		for tt in o.turrets:
			TUR.list.append({"kind": "turret", "host": o, "ref": tt.t, "dir": tt.dir, "pos": Vector3.ZERO, "n": Vector3.ZERO, "aim": Vector3.ZERO, "alive": true, "state": "idle", "t": 0.0, "cd": U.rand(2, 5), "shots": 0, "respawn": 0.0, "vis": 1.0, "glow": _muzzle_glow()})

func turret_active(t: Dictionary) -> bool:
	if GAME.state != "play" or TUT.active: return false
	var mode = ST.phase().get("turrets")
	if not mode: return false
	if is_same(t.host, World.core): return (mode == "all" or World.core.defense > 0.9) and World.core.solid
	return t.host.alive and t.host.fade > 0.9

func turret_world(t: Dictionary) -> void:
	if is_same(t.host, World.core):
		var xf: Transform3D = World.core_group.global_transform
		t.n = (xf.basis * t.dir).normalized(); t.pos = t.n * (World.CORE_R + 1.8) + xf.origin
	else:
		t.n = (t.host.g.basis.orthonormalized() * t.dir).normalized(); t.pos = t.n * (t.host.r + 1.6) + t.host.pos

func destroy_turret(t: Dictionary, by = null) -> void:
	if not t.alive: return
	t.alive = false; t.respawn = 24.0; t.state = "idle"; _glow_set(t.glow, Color.BLACK, 0)
	FX.burst_shapes(t.pos, 36, [0, 2, 4], 22, FX.CORAL); FX.sparks(t.pos, 24, FX.GOLD, 22); FX.shockwave(t.pos, 6, FX.CORAL, 0.45)
	AudioSys.explode(t.pos); GAME.kills += 1; GAME.add_score(250, "TURRET DOWN" if by == "HOMING" else null)
	ST.gain("turretkill", 12); TUT.note("kill", by); REC.ev("turretDown", by)

func update_turrets(dt: float) -> void:
	if TUR.list.is_empty(): build_turrets()
	sight_mesh.clear_surfaces()
	var lines: Array = []
	TUR.aiming = 0
	for t in TUR.list:
		if t.state in ["track", "lock", "burst"]: TUR.aiming += 1
	var max_aim := 3 if World.core.defense > 0.9 else 2
	for t in TUR.list:
		turret_world(t)
		var active := turret_active(t)
		if not t.alive:
			t.respawn -= dt
			if t.respawn <= 0: t.alive = true; t.cd = U.rand(3, 5); FX.sparks(t.pos, 10, FX.CORAL, 6)
		# visibility: core turrets rise out of the core when active; dead ones are hidden
		var want := 1.0 if t.alive and (not is_same(t.host, World.core) or active or World.core.defense > 0.05) else 0.001
		t.vis = U.damp(t.vis, want, 4, dt)
		var ref: Node3D = t.ref
		ref.basis = ref.basis.orthonormalized().scaled_local(Vector3.ONE * maxf(0.001, t.vis)); ref.visible = t.vis > 0.02
		if not t.alive or not active:
			if t.state != "idle": t.state = "idle"; t.cd = U.rand(2, 4)
			_glow_set(t.glow, Color.BLACK, 0)
			continue
		var to_p: Vector3 = P.pos - t.pos
		var d := to_p.length()
		var facing: float = to_p.dot(t.n) / maxf(d, 1e-3)
		var can_see: bool = d < 72 and facing > 0.05 and (P.mode == "fly" or P.mode == "homing")
		if P.ram and d < 2.8: destroy_turret(t, "RAM"); continue
		if t.state == "idle":
			t.cd -= dt * (1.8 if World.core.defense > 0.9 and is_same(t.host, World.core) else 1.0)
			if t.cd <= 0 and can_see and TUR.aiming < max_aim:
				t.state = "track"; t.t = 0.0; TUR.aiming += 1
				AudioSys.play("lock", {"vol": 0.35, "rate": 0.6, "pos": t.pos}); Coach.hint("turret", true); REC.ev("turretAim")
		elif t.state == "track":
			t.t += dt; t.aim = P.pos
			if not can_see: t.state = "idle"; t.cd = 1.2
			elif t.t >= TUR_T.track: # lock onto where you are heading
				t.state = "lock"; t.t = 0.0
				t.aim = P.pos + P.fwd * (P.speed * minf(d / 38, 1.2) * 0.75)
				AudioSys.play("ui_warning", {"vol": 0.45, "rate": 1.7, "bus": "ui"})
		elif t.state == "lock":
			t.t += dt
			if t.t >= TUR_T.lock: t.state = "burst"; t.t = 0.0; t.shots = 0
		elif t.state == "burst":
			t.t += dt
			if t.t >= t.shots * TUR_T.gap and t.shots < 3:
				var muzzle: Vector3 = t.pos + t.n * 0.6
				var dir: Vector3 = (t.aim - muzzle).normalized() + U.rand_unit() * 0.025
				Enemies.fire_proj(muzzle, dir, 40, 0, Enemies.COL_TURRET, "turret"); t.shots += 1
			if t.shots >= 3:
				t.state = "idle"; t.cd = U.rand(2.2, 3.4) if World.core.defense > 0.9 and is_same(t.host, World.core) else U.rand(4.5, 7)
		# muzzle glow and the laser sight
		var aiming_now: bool = t.state == "track" or t.state == "lock"
		var k: float = t.t / TUR_T.track if t.state == "track" else (1.0 if t.state == "lock" else 0.0)
		t.glow.m.position = t.pos + t.n * 0.7; t.glow.m.scale = Vector3.ONE * (0.6 + k * 2.2)
		_glow_set(t.glow, FX.WHITE if t.state == "lock" else Enemies.COL_TURRET, 0.5 + 0.5 * k if aiming_now else 0.0)
		if aiming_now and lines.size() < 24:
			var pulse := 1.0 if t.state == "lock" else 0.35 + 0.35 * (0.5 + 0.5 * sin(Ctl.now * (10 + k * 30)))
			var c := Color(2, 2, 2) if t.state == "lock" else Color(1.6 * pulse + 0.3, 0.1, 0.4 * pulse)
			lines.append([t.pos, t.aim, c])
	if lines.size():
		sight_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for l in lines:
			sight_mesh.surface_set_color(l[2]); sight_mesh.surface_add_vertex(l[0])
			sight_mesh.surface_set_color(l[2]); sight_mesh.surface_add_vertex(l[1])
		sight_mesh.surface_end()

func reset_turrets() -> void:
	for t in TUR.list:
		t.alive = true; t.state = "idle"; t.cd = U.rand(3, 6); _glow_set(t.glow, Color.BLACK, 0)

# ---------- your charged shots: the blast fires lock-on bolts (Star Fox charged shot), a solved miniblast fires its payload ----------
func fire_player_bolt(target, payload = null):
	var b = null
	for x in pbolts:
		if not x.on: b = x; break
	if b == null: return null
	b.on = true; b.target = target; b.payload = payload; b.life = 2.2; b.big = 1.8 if payload else 1.0
	b.pos = P.pos + P.fwd * 2 + P.up * 0.3
	b.vel = P.fwd * 60 + U.rand_unit() * 14 + P.up * 10
	pb_sheath.multimesh.set_instance_color(b.i, FX.GOLD if payload else FX.CYAN)
	AudioSys.play("ring_launch", {"vol": 0.9 if payload else 0.6, "rate": 0.85 if payload else 1.15})
	return b

func fire_payload(pl) -> void:
	if pl == null or pl.target == null: return
	fire_player_bolt(pl.target, pl)
	FX.shake(0.3); P.CAM.punch += 6; FX.flash(0.22, 0.17, 0.06)
	REC.ev("payload", pl.kind)

## the blast's charged shot: with 2+ rings, one bolt per extra ring locks onto threats ahead
func fire_blast_bolts(n: int) -> void:
	var want := n - 1
	if want <= 0: return
	var cands := []
	for e in Enemies.enemies:
		if e.alive and e.spawnT <= 0: cands.append(e)
	for p in Enemies.probes:
		if p.alive and not p.passive: cands.append(p)
	for t in TUR.list:
		if t.alive and turret_active(t): cands.append(t)
	var scored := []
	for c in cands:
		var to: Vector3 = c.pos - P.pos
		var d := to.length()
		if d > 75 or d < 3: continue
		var f := to.dot(P.fwd) / d
		if f < 0.55: continue
		scored.append([c, d * (1.6 - f)])
	scored.sort_custom(func(a, b): return a[1] < b[1])
	var k := mini(want, scored.size())
	for i in k: fire_player_bolt(scored[i][0])
	if scored.size(): FX.popup("CHARGED SHOT ×%d" % k, "#8fe9ff")

func bolt_target_pos(t: Dictionary) -> Vector3:
	if t.kind == "cache": return World.core_group.global_transform * t.pos
	return HOM.target_pos(t)

func bolt_alive(t) -> bool:
	if t == null: return false
	if t.kind == "cache": return t.state == "ready"
	if t.kind == "orb": return t.alive
	return t.get("alive", true) != false

func update_player_bolts(dt: float) -> void:
	for b in pbolts:
		if not b.on: continue
		b.life -= dt
		var alive := bolt_alive(b.target)
		var hit := false
		if alive:
			var tp := bolt_target_pos(b.target)
			var to: Vector3 = tp - b.pos
			var d := to.length()
			var sp: float = maxf(b.vel.length(), 70) + dt * 160
			b.vel = b.vel.lerp(to * (sp / maxf(d, 1e-3)), 1.0 - exp(-9 * dt))
			if d < 1.8 + b.big: bolt_hit(b); hit = true
		elif not b.payload: # target gone: retarget the nearest threat ahead, else fizzle
			var nt = null
			var nd := 30.0
			var pool := []
			pool.append_array(Enemies.enemies); pool.append_array(Enemies.probes); pool.append_array(TUR.list)
			for e in pool:
				if e.alive and e.pos.distance_to(b.pos) < nd: nd = e.pos.distance_to(b.pos); nt = e
			if nt: b.target = nt
			else: b.life = minf(b.life, 0.15)
		if hit: _hide_bolt(b); continue
		b.pos += b.vel * dt
		if b.life <= 0: b.on = false; FX.sparks(b.pos, 8, FX.GOLD if b.payload else FX.CYAN, 6); _hide_bolt(b); continue
		FX.spawn({"pos": b.pos, "vel": U.rand_unit() * 2, "color": FX.GOLD if b.payload else FX.CYAN, "size": U.rand(0.4, 0.8) * b.big, "life": 0.25, "shape": U.pick([0, 5])})
		var xf := Transform3D(U.basis_face(b.vel.normalized()).scaled_local(Vector3.ONE * b.big), b.pos)
		pb_core.multimesh.set_instance_transform(b.i, xf); pb_sheath.multimesh.set_instance_transform(b.i, xf)

func _hide_bolt(b: Dictionary) -> void:
	pb_core.multimesh.set_instance_transform(b.i, World.HIDDEN); pb_sheath.multimesh.set_instance_transform(b.i, World.HIDDEN)

func bolt_hit(b: Dictionary) -> void:
	b.on = false
	var t: Dictionary = b.target
	var at := bolt_target_pos(t)
	# impact: a quick implosion flash, then the burst
	FX.shockwave(at, 12 if b.payload else 5, FX.GOLD if b.payload else FX.CYAN, 0.6 if b.payload else 0.35)
	FX.burst_shapes(at, 50 if b.payload else 18, [1, 2, 5], 30 if b.payload else 14, FX.GOLD if b.payload else FX.CYAN)
	if b.payload:
		GAME.hitstop(0.1); FX.shake(0.5); AudioSys.boom()
		if b.payload.kind == "cache": HOM.crack_cache(t)
		else: BL.breachOrb = t; BL.breach_success()
		return
	GAME.hitstop(0.04)
	match t.kind:
		"enemy": Enemies.kill_enemy(t, "SHOT")
		"probe": Enemies.kill_probe(t, "SHOT")
		"turret": destroy_turret(t, "SHOT")
		"orb": Enemies.damage_orb(t, 2, "SHOT")

func reset_player_bolts() -> void:
	for b in pbolts:
		b.on = false; _hide_bolt(b)

## A stroke with a soft glow under it (ctx.shadowBlur).
func _glow_poly(c: CanvasItem, pts: PackedVector2Array, col: Color, w: float) -> void:
	var g := col; g.a *= 0.25
	c.draw_polyline(pts, g, w + 6, true)
	c.draw_polyline(pts, col, w, true)

func edge_arrow(c: CanvasItem, pos: Vector3, col: String, max_d: float) -> void:
	var d := pos.distance_to(P.pos)
	if d > max_d: return
	var sp: Dictionary = FX.project(pos)
	var W: float = FX.W
	var H: float = FX.H
	var on: bool = not sp.behind and sp.x > 30 and sp.y > 30 and sp.x < W - 30 and sp.y < H - 30
	if on: return
	var cx := W / 2
	var cy := H / 2
	var dx: float = sp.x - cx
	var dy: float = sp.y - cy
	if sp.behind: dx = -dx; dy = -dy
	var ang := atan2(dy, dx)
	var m := 40.0
	var k := minf((W / 2 - m) / maxf(absf(cos(ang)), 1e-3), (H / 2 - m) / maxf(absf(sin(ang)), 1e-3))
	var x := cx + cos(ang) * k
	var y := cy + sin(ang) * k
	var s := 7 + 8 * U.smooth(max_d, 8, d)
	var a := 0.5 + 0.45 * U.smooth(max_d, 10, d)
	var pts: PackedVector2Array = Transform2D(ang, Vector2(x, y)) * PackedVector2Array([Vector2(s, 0), Vector2(-s * 0.7, -s * 0.75), Vector2(-s * 0.3, 0), Vector2(-s * 0.7, s * 0.75)])
	D2.poly_fill(c, pts, D2.col(col, a))
	D2.poly_line(c, pts, Color(0.04, 0.03, 0.12, 0.7 * a), 2, true)

# ---------- threat UI: turret locks, jets about to fire, orb shields, the primed target ----------
func draw_threats(c: CanvasItem) -> void:
	if GAME.state != "play" or P.mode in ["puzzle", "loadup", "supercut"]: return
	var W: float = FX.W
	var H: float = FX.H
	var locked := false
	for t in TUR.list:
		if not t.alive or (t.state != "track" and t.state != "lock"): continue
		var lock: bool = t.state == "lock"
		if lock: locked = true
		var sp: Dictionary = FX.project(t.pos)
		var on: bool = not sp.behind and sp.x > 20 and sp.y > 20 and sp.x < W - 20 and sp.y < H - 20
		if not on:
			if int(floor(Ctl.now * 8)) % 2 or lock: edge_arrow(c, t.pos, "#ffffff" if lock else "#ff3b6b", 90)
			continue
		var x: float = sp.x
		var y: float = sp.y
		var k: float = t.t / TUR_T.track if t.state == "track" else 1.0
		# red diamond with a closing ring: when the ring meets the diamond the turret locks
		var col := Color.WHITE if lock else Color.html("#ff3b6b")
		_glow_poly(c, PackedVector2Array([Vector2(x, y - 16), Vector2(x + 16, y), Vector2(x, y + 16), Vector2(x - 16, y), Vector2(x, y - 16)]), col, 2.5)
		if not lock: _glow_poly(c, D2.arc_points(x, y, 18 + (1 - k) * 34, 0, TAU, 40), col, 2)
		D2.text_base(c, D2.ui_bold, 13, "LOCKED" if lock else "!", x, y - 24, col)
	if locked:
		D2.text_base(c, D2.ui_bold, 14, "TURRET LOCK · TURN", W / 2, H * 0.68, Color.WHITE if int(floor(Ctl.now * 10)) % 2 else Color.html("#ff3b6b"))
	# jets: red ticks when about to fire (off-screen jets get the edge arrows from FX.draw_edge_threats)
	for e in Enemies.enemies:
		if not e.alive or e.spawnT > 0: continue
		var d: float = e.pos.distance_to(P.pos)
		if d > 60: continue
		var sp: Dictionary = FX.project(e.pos)
		var on: bool = not sp.behind and sp.x > 20 and sp.y > 20 and sp.x < W - 20 and sp.y < H - 20
		if not on: continue
		var aiming: bool = e.st == "aim" and (e.tele > 0 or e.shots > 0)
		if aiming:
			var s := clampf(600 / d, 12, 28)
			for i in 4:
				var a := i * PI / 2 + PI / 4
				D2.line(c, sp.x + cos(a) * s, sp.y + sin(a) * s, sp.x + cos(a) * (s + 8), sp.y + sin(a) * (s + 8), Color.html("#ff5b3d"), 2.5)
	# orb shields: hp pips over each nearby orb
	for o in World.orbs:
		if not o.alive or o.fade < 0.9: continue
		var d: float = o.pos.distance_to(P.pos)
		if d > 90: continue
		var sp: Dictionary = FX.project(o.pos + P.up * (o.r * 1.25))
		if sp.behind: continue
		var n := 8
		var w := 9.0
		for i in n:
			var x: float = sp.x + (i - (n - 1) / 2.0) * (w + 3)
			var cc: Color
			if o.exposed > 0: cc = Color.html("#ffd27a") if int(floor(Ctl.now * 8)) % 2 else Color.html("#fff3e4")
			else: cc = Color.html("#b8f55a") if i < o.hp else Color(0.72, 0.96, 0.35, 0.2)
			c.draw_rect(Rect2(x - w / 2, sp.y - 3, w, 5), cc)
		if o.exposed > 0:
			D2.text_base(c, D2.ui_bold, 11, "PRIMED" if P.prime and is_same(P.prime.t, o) else "EXPOSED · HOME IN", sp.x, sp.y - 10, Color.html("#ffd27a"))
	# the primed target: a cyan double ring with its remaining time
	if P.prime and P.mode == "fly":
		var pr: Dictionary = P.prime
		var tp := bolt_target_pos(pr.t)
		var sp: Dictionary = FX.project(tp)
		if sp.behind: edge_arrow(c, tp, "#8fe9ff", 120)
		else:
			var r := clampf(900 / maxf(8, tp.distance_to(P.pos)), 22, 54)
			var life: float = pr.life / (6.0 if pr.kind == "breach" else 9.0)
			var cy := Color.html("#8fe9ff")
			_glow_poly(c, D2.arc_points(sp.x, sp.y, r, -PI / 2, -PI / 2 + TAU * clampf(life, 0, 1), 40), cy, 3)
			_glow_poly(c, D2.arc_points(sp.x, sp.y, r * (0.7 + 0.08 * sin(Ctl.now * 8)), 0, TAU, 40), cy, 1.5)
			D2.text_base(c, D2.ui_bold, 12, "PRIMED · %s" % Ctl.kl("HOLD SPACE", "HOLD RT"), sp.x, sp.y + r + 18, cy)
