extends Node
## HOMING · CHARGE CRYSTALS · CRYSTAL CACHES · LOCK-ON (port of 47_homing.js).
## Homing is the core move: whatever sits in front of you gets a lock-on bracket; tap HOMING to dash into it,
## crunch through, bounce, and chain into the next lock (Sonic style).
## Three charge crystals tear a tunnel open where you are looking. Hit them in one quick chain for a gold tunnel.
## Homing v2 (playtest: chains never ended). Three rules, all telegraphed on screen and in sound:
##   CHARGES  every dash costs one of 3 charges. They refill over time, from crystals, rings, tunnel exits, caches.
##   WINDOW   after a hit a gold ring closes on the next lock. Press while it is open to chain; press inside the
##            sweet band for PERFECT (no charge). Pressing during the dash or before the window opens breaks it.
##   FINISHER the 5th link ends the chain in a burst that clears nearby drones and throws you forward.

const HOMING := {"max": 3, "regen": 2.4, "open": 0.10, "sweetA": 0.17, "sweetB": 0.34, "close": 0.62, "cap": 5, "lockout": 0.3}
const QUICK_WINDOW := 3.0   # seconds between charge crystals to keep a quick chain going

var lock = null
var lockT := 0.0
var lockSnd := 0.0
var chain := 0
var chainT := 0.0
var charges := 3.0
var win = null
var mash := false
var lockout := 0.0
var emptyT := 0.0
var perfectT := 0.0
var earlyT := 0.0
var hintN := 0
var CHARGE := {"items": [], "count": 0, "quick": 0, "lastHit": -99.0, "nextSet": 4.0, "setId": 0}
var caches: Array = []

var root: Node3D
var halo_mats: Array = []
var glyph_ring_tex: Texture2D = preload("res://assets/textures/glyph_ring_homing.png")
var cache_model_path := "res://assets/models/crystal_cache.glb"

func setup(r: Node3D) -> void:
	root = r
	# charge crystal meshes (CC BY 4.0 "Glowing Gem" by RiZoRuS77)
	var gem_mesh: Mesh = World.model_mesh("res://assets/models/charge_gem.glb", 2.6)
	var gem_mat := StandardMaterial3D.new()
	gem_mat.roughness = 0.25; gem_mat.metallic = 0.05; gem_mat.emission_enabled = true
	gem_mat.emission = Color(0.55, 1.0, 1.15).linear_to_srgb(); gem_mat.emission_energy_multiplier = 1.6
	var src = World.model_material("res://assets/models/charge_gem.glb")
	if src is BaseMaterial3D:
		gem_mat.albedo_texture = src.albedo_texture
		gem_mat.normal_enabled = src.normal_enabled; gem_mat.normal_texture = src.normal_texture
		gem_mat.emission_texture = src.emission_texture if src.emission_texture else src.albedo_texture
	if gem_mesh == null:
		gem_mesh = Meshes.octahedron(1.2)
		gem_mat.albedo_color = Color.html("#9ff5ff"); gem_mat.emission = Color.html("#3fd6ff"); gem_mat.emission_energy_multiplier = 1.4
	for i in 6:
		var g := Node3D.new()
		var gem := MeshInstance3D.new(); gem.mesh = gem_mesh; gem.material_override = gem_mat; g.add_child(gem)
		var halo := MeshInstance3D.new(); halo.mesh = Meshes.quad(6, 6)
		var hm := ShaderMaterial.new(); hm.shader = preload("res://shaders/halo.gdshader"); halo.material_override = hm; halo_mats.append(hm)
		g.add_child(halo)
		var ring := MeshInstance3D.new(); ring.mesh = Meshes.quad(5.2, 5.2); ring.material_override = World.glow_mat(Color(0.6, 1.6, 2.0), glyph_ring_tex)
		g.add_child(ring); g.visible = false; root.add_child(g)
		CHARGE.items.append({"kind": "charge", "g": g, "gem": gem, "halo": halo, "ring": ring, "pos": Vector3.ZERO, "alive": false, "t": 0.0, "life": 0.0, "set": 0, "k": 0, "r": 1.6})
	place_caches()

## where the ship would really go with no input (gravity skim included), sampled every `spacing` units
func predict_path(count: int, spacing: float, lead: float) -> Array:
	var keys := ["speed", "boost", "boostHold", "hTarget", "prevBody", "pitchVis", "bank", "stun", "inField", "fieldW", "ram", "noGrav", "slowT",
		"vel", "grav", "gdown", "yawV", "pitchV", "gspd", "eng", "fuel", "lit", "ride", "rideH", "rideVr", "rideCd", "rideBlastT", "throttle", "sinking", "gpull", "velSync", "escFrom", "escT", "fuelWarnT"]
	var save := {}
	for k in keys: save[k] = P.get(k)
	var sp: Vector3 = P.pos
	var sf: Vector3 = P.fwd
	var su: Vector3 = P.up
	var sr: Vector3 = P.right
	var sx := Ctl.steer_x
	var sy := Ctl.steer_y
	var ch: bool = BL.charging
	Ctl.steer_x = 0; Ctl.steer_y = 0; BL.charging = false
	P.SIM = true
	var out := []
	var trav := -lead
	var nxt := 0.0
	var guard := 0
	while out.size() < count and guard < 3000:
		guard += 1
		var b: Vector3 = P.pos
		P.fly_update(1.0 / 30.0)
		trav += b.distance_to(P.pos)
		if trav >= nxt:
			out.append({"pos": P.pos, "fwd": P.fwd, "up": P.up, "right": P.right}); nxt += spacing
	for k in keys: P.set(k, save[k])
	P.SIM = false
	P.pos = sp; P.fwd = sf; P.up = su; P.right = sr; Ctl.steer_x = sx; Ctl.steer_y = sy; BL.charging = ch
	return out

func spawn_charge_set() -> void:
	CHARGE.setId += 1
	var path := predict_path(3, 15, 24)
	var ph := U.rand(0, TAU)
	var made := 0
	for k in mini(3, path.size()):
		var c = null
		for x in CHARGE.items:
			if not x.alive: c = x; break
		if c == null: break
		var s: Dictionary = path[k]
		c.pos = s.pos + s.right * (sin(ph + k * 1.3) * 2.2) + s.up * (0.6 + cos(ph + k) * 1.0)
		if c.pos.length() > World.R - 8: c.pos = U.set_length(c.pos, World.R - 9)
		if World.core.solid and c.pos.length() < World.CORE_R + 4: c.pos = U.set_length(c.pos, World.CORE_R + 6)
		for o in World.orbs:
			if o.alive and c.pos.distance_to(o.pos) < o.r + 3: c.pos += U.set_length(c.pos - o.pos, 3)
		c.alive = true; c.t = 0.0; c.life = 15.0; c.set = CHARGE.setId; c.k = k; c.g.visible = true; c.g.scale = Vector3.ONE * 0.01
		made += 1
	if made:
		FX.popup("CHARGE CRYSTALS", "#8fe9ff"); AudioSys.play("lock", {"vol": 0.5, "rate": 0.8}); TUT.note("chargeSet"); Coach.hint("charge")

func collect_charge(c: Dictionary, via_homing: bool) -> void:
	if not c.alive: return
	c.alive = false; c.g.visible = false
	var quick: bool = GAME.time - CHARGE.lastHit <= QUICK_WINDOW and CHARGE.quick > 0
	if CHARGE.count > 0: REC.ev("chargeGap", GAME.time - CHARGE.lastHit)
	CHARGE.quick = CHARGE.quick + 1 if quick else 1
	CHARGE.lastHit = GAME.time
	CHARGE.count += 1
	AudioSys.crunch(CHARGE.count - 1)
	FX.burst_shapes(c.pos, 26, [2, 5], 22, FX.CYAN); FX.sparks(c.pos, 18, FX.WHITE, 18); FX.shockwave(c.pos, 5, FX.CYAN, 0.35)
	GAME.hitstop(0.055 if via_homing else 0.03); FX.shake(0.22); P.CAM.punch += 3
	GAME.add_score(60 * CHARGE.count, null); ST.gain("charge", 7)
	FX.popup("CHARGE %d/3%s" % [CHARGE.count, " · QUICK ×%d" % CHARGE.quick if CHARGE.quick >= 2 else ""], "#ffd27a" if CHARGE.quick >= 2 else "#8fe9ff")
	TUT.note("charge", CHARGE.count)
	if CHARGE.count >= 3:
		var gold: bool = CHARGE.quick >= 3
		CHARGE.count = 0; CHARGE.quick = 0
		for o in CHARGE.items:
			if o.alive and o.set == c.set: o.alive = false; o.g.visible = false; FX.sparks(o.pos, 8, FX.CYAN, 8)
		World.open_tunnel(gold); GAME.rifts += 1; Coach.hint("tunnel", true)
		AudioSys.chain_complete(); AudioSys.tunnel_open()
		FX.event_text("GOLD RIFT!" if gold else "RIFT OPEN!", "gold" if gold else "cyan")
		FX.doodle_flash(0.8 if gold else 0.5); FX.screen_crash(6 if gold else 4, [1, 2, 5])
		ST.gain("goldrift" if gold else "rift", 30 if gold else 16)
		CHARGE.nextSet = 9.0
		TUT.note("tunnelOpen", gold)

func update_charge(dt: float) -> void:
	for hm in halo_mats: hm.set_shader_parameter("uT", GAME.time)
	var alive := 0
	var cam: Camera3D = GAME.camera
	for c in CHARGE.items:
		if not c.alive: continue
		alive += 1
		c.t += dt; c.life -= dt
		var s := U.smooth(0, 0.35, c.t) * (1 + 0.08 * sin(GAME.time * 6 + c.k))
		c.g.scale = Vector3.ONE * maxf(0.001, s * ((1.0 if int(floor(c.life * 6)) % 2 else 0.55) if c.life < 3 else 1.0))
		c.g.position = c.pos + P.up * (sin(GAME.time * 2 + c.k) * 0.4)
		c.gem.rotation.y += dt * 1.6; c.gem.rotation.x = sin(GAME.time + c.k) * 0.3
		var dc: float = c.g.position.distance_to(cam.global_position)
		var near := clampf((dc - 3) / 18, 0.15, 1)
		var cb := cam.global_basis.orthonormalized()
		c.halo.global_basis = cb.scaled_local(Vector3.ONE * near * c.g.scale.x)
		c.ring.global_basis = cb.rotated(cb.z, GAME.time * (1 + c.k * 0.3)).scaled_local(Vector3.ONE * (0.5 + near * 0.5) * c.g.scale.x)
		if randf() < 0.25: FX.spawn({"pos": c.g.position, "vel": U.rand_unit() * 2, "color": FX.CYAN, "size": 0.45, "life": 0.5, "shape": 5})
		if (P.mode == "fly" or P.mode == "tunnel") and c.pos.distance_to(P.pos) < 2.8: collect_charge(c, false)
		elif c.life <= 0: c.alive = false; c.g.visible = false; FX.sparks(c.pos, 8, FX.CYAN, 6)
	if GAME.state != "play" or not ST.unlocked("charge"): return
	if TUT.active and TUT.step_id() != "rank": return # Flight School spawns its own sets, one lesson at a time
	var tunnel_busy: bool = P.mode == "tunnel" or World.tunnels.any(func(t): return not t.used and not t.dying)
	if not alive and not tunnel_busy and P.mode == "fly":
		CHARGE.nextSet -= dt
		if CHARGE.nextSet <= 0: CHARGE.nextSet = U.rand(7, 11); spawn_charge_set()

# ---------- crystal caches: crack them with a miniblast (CC BY 4.0 "Magic Crystal IX" by -X-ScornGames) ----------
func _make_cache_mesh() -> Node3D:
	var g := Node3D.new()
	var body: Node3D = World.model_node(cache_model_path, 5.2, true)
	if body == null:
		body = Node3D.new()
		var m := StandardMaterial3D.new(); m.albedo_color = Color.html("#5aa8ff"); m.emission_enabled = true; m.emission = Color.html("#1a4aa0"); m.emission_energy_multiplier = 0.8
		for i in 7:
			var o := MeshInstance3D.new(); o.mesh = Meshes.octahedron(U.rand(0.6, 1.2)); o.material_override = m
			o.scale.y = U.rand(1.8, 3); o.position = Vector3(U.rand(-1, 1), o.scale.y * 0.6, U.rand(-1, 1)); o.rotation.z = U.rand(-0.4, 0.4)
			body.add_child(o)
	g.add_child(body)
	var halo := MeshInstance3D.new(); halo.mesh = Meshes.quad(10, 10)
	var hm := World.glow_mat(Color(0.5, 1.0, 2.0), glyph_ring_tex); halo.material_override = hm
	halo.position.y = 2.6; g.add_child(halo)
	g.set_meta("body", body); g.set_meta("halo", halo); g.set_meta("halo_mat", hm); g.set_meta("base", 1.0)
	return g

func place_caches() -> void:
	for c in caches: c.g.queue_free()
	caches.clear()
	for d0 in [Vector3(0.8, 0.5, 0.3), Vector3(-0.6, -0.4, 0.7), Vector3(0.1, -0.7, -0.7)]:
		var d: Vector3 = d0.normalized()
		var g := _make_cache_mesh()
		g.position = d * (World.CORE_R - 0.2); g.basis = U.basis_from_up(d)
		World.core_group.add_child(g)
		caches.append({"kind": "cache", "g": g, "dir": d, "pos": d * (World.CORE_R + 2.4), "state": "ready", "t": 0.0, "r": 2.6, "alive": true})

func update_caches(dt: float) -> void:
	for c in caches:
		c.alive = c.state == "ready" and World.core.solid and ST.unlocked("cache")
		c.g.visible = World.core.dissolve < 0.5
		if c.state == "cool":
			c.t -= dt
			if c.t <= 0: c.state = "ready"; FX.sparks(c.pos, 14, FX.CYAN, 8)
		var k := 1.0 if c.state == "ready" else clampf(1 - c.t / 30, 0.15, 0.9)
		var body: Node3D = c.g.get_meta("body")
		body.scale = Vector3.ONE * (0.55 + 0.45 * k)
		var hm: ShaderMaterial = c.g.get_meta("halo_mat")
		hm.set_shader_parameter("color", Color(0.5, 1.0, 2.0, 0.6 + 0.3 * sin(GAME.time * 3) if c.state == "ready" else 0.1))
		(c.g.get_meta("halo") as Node3D).rotate_object_local(Vector3.UP, dt * 0.8)

func crack_cache(c: Dictionary) -> void:
	TUT.note("cacheCrack")
	c.state = "cool"; c.t = 30.0
	FX.shockwave(c.pos, 9, FX.CYAN, 0.6); FX.burst_shapes(c.pos, 40, [2, 3, 5], 26, FX.CYAN); AudioSys.orb_shatter()
	var n := 0
	for cr in World.crystals:
		if n >= 12: break
		if not cr.alive or cr.home.distance_to(c.pos) > 25:
			cr.alive = true; cr.spawn = 0.0; cr.home = c.pos + c.dir * U.rand(4, 9) + U.rand_unit() * 4; n += 1
	var type: String = U.pick(World.WEAPONS.keys())
	var pos: Vector3 = c.pos + c.dir * 6
	var pk := {"kind": "pickup", "type": type, "pos": pos, "mesh": World.make_pickup_mesh(type), "life": 25.0, "t": 0.0}
	pk.mesh.position = pos; World.pickups.append(pk)
	GAME.add_score(600, "CACHE CRACKED"); ST.gain("cache", 25); refill(3, "cache"); ST.cells = minf(3, ST.cells + 0.25)
	FX.event_text("CACHE CRACKED!", "cyan")

# ---------- lock-on ----------
func lockables() -> Array:
	var L := []
	for c in CHARGE.items:
		if c.alive and c.t > 0.15: L.append([c, 3.0])
	if ST.unlocked("combat"):
		for e in Enemies.enemies:
			if e.alive and e.spawnT <= 0: L.append([e, 2.0])
		for p in Enemies.probes:
			if p.alive: L.append([p, 2.0])
		for t in Threats.TUR.list:
			if t.alive and Threats.turret_active(t): L.append([t, 2.2])
	for h in World.homers:
		if h.alive and h.spawn >= 1: L.append([h, 1.0])
	for k in World.pickups: L.append([k, 1.5])
	if ST.unlocked("orb"):
		for o in World.orbs:
			if o.alive and o.fade > 0.9: L.append([o, 3.0 if o.exposed > 0 else 0.5])
	for c in caches:
		if c.alive: L.append([c, 1.5])
	return L

func target_pos(t: Dictionary) -> Vector3:
	if t.kind == "orb": return (P.pos - t.pos).normalized() * (t.r + 0.6) + t.pos
	if t.kind == "cache": return t.pos
	if t.kind == "charge" and t.has("g"): return t.g.position
	return t.pos

func homing_range() -> float: return 46 + clampf(P.speed - 24, 0, 80) * 0.3

func update_lock(rdt: float) -> void:
	lockSnd = maxf(0, lockSnd - rdt)
	if P.mode != "fly" or not ST.unlocked("homing") or GAME.state != "play": lock = null; return
	var cam_dir: Vector3 = -GAME.camera.global_basis.z
	var look := cam_dir.lerp(P.fwd, 0.4).normalized()
	var R := homing_range()
	var best = null
	var bs := 1e9
	var cur_s := 1e9
	for item in lockables():
		var t: Dictionary = item[0]
		var tp := target_pos(t)
		var to: Vector3 = tp - P.pos
		var d := to.length()
		if d < 3 or d > R: continue
		to /= d
		var c := to.dot(look)
		if c < 0.8 or to.dot(P.fwd) < 0.25: continue
		var s: float = (1 - c) * 160 + d * 0.9 - item[1] * 9
		if is_same(t, lock): cur_s = s
		if s < bs: bs = s; best = t
	if lock and cur_s < 1e9 and cur_s < bs * 1.25 + 6: best = lock # hysteresis: don't flicker between two targets
	if not is_same(best, lock):
		lock = best; lockT = 0
		if best and lockSnd <= 0: AudioSys.lock(); lockSnd = 0.12
		if best: Coach.hint("homing", true)
	lockT += rdt

func refill(n: float, why: String = "") -> void:
	var before := int(floor(charges + 1e-6))
	charges = minf(HOMING.max, charges + n)
	if int(floor(charges + 1e-6)) > before and why != "regen": AudioSys.play("lock", {"vol": 0.35, "rate": 1.7, "jit": 0.0})

func homing_empty() -> void:
	emptyT = 0.5; P.homeCd = 0.2; AudioSys.play("homing_whiff", {"vol": 0.4, "rate": 0.7})
	FX.popup("NO HOMING CHARGE", "#c9a8ff"); REC.ev("homingEmpty")

## a press the window did not ask for: the chain ends, short lockout
func homing_early(why: String) -> void:
	var had := chain
	win = null; chain = 0; lockout = HOMING.lockout; earlyT = 0.6
	AudioSys.play("fizzle", {"vol": 0.4, "rate": 1.35})
	if had > 0: FX.popup("EARLY · CHAIN %d BROKEN" % had, "#c9a8ff")
	REC.ev("homingEarly", [why, had])

func press() -> void:
	if BL.payload: return # a solved miniblast is waiting for you to let go: never boom it away
	if BL.charging and BL.rings > 0: BL.bundle_boom(); return
	if P.mode == "homing": mash = true; return # judged at impact: the chain breaks there
	if P.mode != "fly" or P.stun > 0: return
	if lockout > 0 or P.homeCd > 0: return
	var w = win
	var wt: float = Ctl.now - w.t0 if w else 99.0
	if w and wt < HOMING.open: homing_early("early"); return
	var judge = null
	if w and wt <= HOMING.close: judge = "perfect" if wt >= HOMING.sweetA and wt <= HOMING.sweetB else "good"
	var cost := 0 if judge == "perfect" else 1
	if charges < cost - 1e-6 or (cost and charges < 1 - 1e-6): homing_empty(); return
	if lock: REC.ev("press", {"lock": lock.kind, "d": roundi(target_pos(lock).distance_to(P.pos)), "judge": judge, "wt": snappedf(wt, 0.001) if w else null})
	else: REC.ev("press", {"lock": null, "judge": judge})
	if lock: charges -= cost; start_homing(lock, judge)
	else: # air dash: a short burst so the button never feels dead; it ends any chain
		charges -= 1; win = null; chain = 0
		P.boost += 14; P.boostHold = maxf(P.boostHold, 0.15); P.homeCd = 0.45; AudioSys.whiff(); P.CAM.punch += 2
		FX.burst_shapes(P.pos + P.fwd * 2, 8, [5], 10, FX.CYAN)

func start_homing(t: Dictionary, judge = null) -> void:
	P.use_fuel(P.FLIGHT.fuelDash)
	P.mode = "homing"; P.home = t; P.homeT = 0; P.homeFrom = P.pos; P.homeJudge = judge; mash = false; win = null
	var d := target_pos(t).distance_to(P.pos)
	P.homeDur = clampf(d / (125.0 if judge == "perfect" else 105.0), 0.12, 0.5); P.invuln = maxf(P.invuln, P.homeDur + 0.3)
	if BL.charging: BL.cancel_charge(false)
	AudioSys.homing_dash(); P.CAM.punch += 3; FX.shake(0.08); hintN += 1
	if judge == "perfect": AudioSys.perfect(); perfectT = 0.5; FX.popup("PERFECT", "#ffd27a"); FX.flash(0.18, 0.14, 0.05)
	TUT.note("homingStart", judge)

func _target_alive(t) -> bool:
	if t == null: return false
	if t.get("alive", true) == false: return false
	if t.kind == "cache" and t.state != "ready": return false
	return true

func homing_update(dt: float) -> void:
	var t = P.home
	var alive := _target_alive(t)
	if not alive and t and t.kind != "cache": # the target died mid-dash (a boom, a ram): carry on into the nearest one beside it
		var at := target_pos(t)
		var nt = null
		var nd := 10.0
		for item in lockables():
			var o: Dictionary = item[0]
			if is_same(o, t): continue
			var d := target_pos(o).distance_to(at)
			if d < nd: nd = d; nt = o
		if nt:
			P.home = nt; t = nt; P.homeFrom = P.pos; P.homeT = 0
			P.homeDur = clampf(target_pos(nt).distance_to(P.pos) / 110, 0.1, 0.32); alive = true; REC.ev("retarget", nt.kind)
	var tp := target_pos(t)
	P.homeT += dt
	var k := clampf(P.homeT / P.homeDur, 0, 1)
	var e := k * k * (3 - 2 * k)
	var ctrl: Vector3 = P.homeFrom.lerp(tp, 0.5) + P.up * 2.2
	var a: Vector3 = P.homeFrom.lerp(ctrl, e)
	var b := ctrl.lerp(tp, e)
	var prev: Vector3 = P.pos
	P.pos = a.lerp(b, e)
	var mv: Vector3 = P.pos - prev
	if mv.length_squared() > 1e-6: P.fwd = P.fwd.lerp(mv.normalized(), 1.0 - exp(-18 * dt)).normalized(); P.ortho()
	P.speed = 105
	if randf() < 0.9: FX.spawn({"pos": P.pos, "vel": U.rand_unit() * 3, "color": FX.GOLD if P.homeJudge == "perfect" else FX.CYAN, "size": U.rand(0.4, 0.8), "life": 0.3, "shape": U.pick([2, 5])})
	if k >= 1 or P.pos.distance_to(tp) < 1.2: homing_impact(t, alive)

func homing_impact(t, alive: bool) -> void:
	P.mode = "fly"; P.home = null
	var bounce := 1.0
	if alive:
		match t.kind:
			"charge": collect_charge(t, true)
			"homer":
				BL.collect_homer(t, true); AudioSys.crunch(mini(3, chain)); GAME.hitstop(0.035 + mini(chain, 4) * 0.006); FX.shake(0.12); P.CAM.punch += 2
			"enemy": Enemies.kill_enemy(t, "HOMING"); AudioSys.takedown(t.pos); GAME.hitstop(0.07)
			"probe": Enemies.kill_probe(t, "HOMING"); AudioSys.takedown(t.pos); GAME.hitstop(0.05)
			"turret": Threats.destroy_turret(t, "HOMING"); AudioSys.takedown(t.pos); GAME.hitstop(0.06)
			"orb":
				if t.exposed > 0: BL.prime_target(t, "breach")
				else: Enemies.damage_orb(t, 2, "HOMING"); AudioSys.takedown(t.pos)
				bounce = 2.2
				var n: Vector3 = (P.pos - t.pos).normalized(); P.fwd = P.fwd.bounce(n).normalized(); P.ortho()
			"cache":
				BL.prime_target(t, "cache"); P.fwd = ((P.pos - t.pos).normalized() + P.up * 0.4).normalized(); P.ortho(); P.velSync = true
			"pickup": t.pos = P.pos # pickups collect themselves on contact
	else: # nothing left to hit: not the player's fault, so the charge comes back
		AudioSys.whiff(); REC.ev("whiff", t.kind if t else null); refill(1, "whiff")
		chain = 0; win = null; lock = null; P.homeCd = 0.15; return
	# chain: a link only counts if it was pressed inside the previous window
	chain = chain + 1 if P.homeJudge else 1
	chainT = GAME.time
	P.pos += P.up * (0.8 * bounce); P.boost += 10 * bounce; P.boostHold = maxf(P.boostHold, 0.22)
	P.invuln = maxf(P.invuln, 0.35)
	ST.gain("homeperfect" if P.homeJudge == "perfect" else "homing", 5 if P.homeJudge == "perfect" else 3)
	TUT.note("homingHit", t.kind if t else null)
	lock = null
	if mash: mash = false; homing_early("dash"); return # pressed during the dash
	if chain >= HOMING.cap: homing_finisher(); return
	win = {"t0": Ctl.now, "n": chain, "cued": false} # progress shows as diamonds over the lock, no popup spam

func homing_finisher() -> void:
	var pos: Vector3 = P.pos
	FX.event_text("FINISHER!", "gold"); FX.shockwave(pos, 15, FX.GOLD, 0.6); FX.shockwave(pos, 8, FX.WHITE, 0.35)
	FX.burst_shapes(pos, 70, [1, 2, 3, 5], 36); FX.screen_crash(6, [1, 2, 5]); FX.doodle_flash(0.6)
	AudioSys.chain_complete(); AudioSys.boom(); GAME.hitstop(0.12); FX.shake(0.6); P.CAM.punch += 10; FX.flash(0.35, 0.26, 0.08)
	var k := 0
	for e in Enemies.enemies:
		if e.alive and e.pos.distance_to(pos) < 15: Enemies.kill_enemy(e, "FINISHER"); k += 1
	for p in Enemies.probes:
		if p.alive and p.pos.distance_to(pos) < 15: Enemies.kill_probe(p, "FINISHER"); k += 1
	for t in Threats.TUR.list:
		if t.alive and t.pos.distance_to(pos) < 15: Threats.destroy_turret(t, "FINISHER"); k += 1
	for o in World.orbs:
		if o.alive and o.pos.distance_to(pos) < 15 + o.r: Enemies.damage_orb(o, 2, "FINISHER")
	P.boost += 45; P.boostHold = 0.7; P.pos += P.up * 1.5
	refill(1, "finisher"); chain = 0; win = null; P.homeCd = 0.6
	GAME.add_score(800 + k * 100, "FINISHER"); ST.gain("finisher", 24)
	REC.ev("finisher", k); TUT.note("finisher", k)

## per frame: regen, lockout, the window's life and its "now" cue
func homing_tick(rdt: float) -> void:
	lockout = maxf(0, lockout - rdt); emptyT = maxf(0, emptyT - rdt)
	perfectT = maxf(0, perfectT - rdt); earlyT = maxf(0, earlyT - rdt)
	if GAME.state != "play" or not ST.unlocked("homing"): return
	if P.mode == "fly" and win == null: refill(rdt / HOMING.regen, "regen")
	var w = win
	if w == null: return
	var wt: float = Ctl.now - w.t0
	if not w.cued and wt >= HOMING.sweetA: w.cued = true; AudioSys.play("lock", {"vol": 0.6, "rate": 1.5, "jit": 0.0}) # the sweet band opens: ping
	if wt > HOMING.close or P.mode != "fly":
		win = null
		if wt > HOMING.close: chain = 0

func reset_homing() -> void:
	lock = null; chain = 0; charges = HOMING.max; win = null; mash = false; lockout = 0
	CHARGE.count = 0; CHARGE.quick = 0; CHARGE.lastHit = -99.0; CHARGE.nextSet = 4.0
	for c in CHARGE.items: c.alive = false; c.g.visible = false
	for c in caches: c.state = "ready"; c.t = 0.0

# ---------- indicators: brackets, the lock ring, charge pips, danger markers ----------
const LOCK_COL := {"charge": "#8fe9ff", "homer": "#ff8ad6", "enemy": "#b8f55a", "probe": "#ff6ad0", "orb": "#dce9a9", "cache": "#8fe9ff", "turret": "#ff3b6b", "pickup": "#ffd27a"}

func _bracket(c: CanvasItem, x: float, y: float, s: float, col: String, a: float) -> void:
	var cc := D2.col(col, a)
	for sv in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
		c.draw_polyline(PackedVector2Array([Vector2(x + sv[0] * s, y + sv[1] * s * 0.55), Vector2(x + sv[0] * s, y + sv[1] * s), Vector2(x + sv[0] * s * 0.55, y + sv[1] * s)]), cc, 2, true)

func _glow_arc(c: CanvasItem, x: float, y: float, r: float, a0: float, a1: float, col: Color, w: float, blur: float) -> void:
	var g := col; g.a *= 0.22
	D2.arc(c, x, y, r, a0, a1, g, w + blur * 0.6)
	D2.arc(c, x, y, r, a0, a1, col, w)

func draw_indicators(c: CanvasItem) -> void:
	if P.mode in ["puzzle", "loadup", "supercut"]: return
	var W: float = FX.W
	var H: float = FX.H
	var R := homing_range() * 1.25
	# available targets: thin brackets
	if P.mode == "fly" and ST.unlocked("homing"):
		for item in lockables():
			var t: Dictionary = item[0]
			if is_same(t, lock): continue
			var tp := target_pos(t)
			var d := tp.distance_to(P.pos)
			if d > R: continue
			var sp: Dictionary = FX.project(tp)
			if sp.behind or sp.x < 0 or sp.y < 0 or sp.x > W or sp.y > H: continue
			_bracket(c, sp.x, sp.y, clampf(500 / d, 9, 26), LOCK_COL.get(t.kind, "#f4c6a0"), 0.55)
	# the lock: spinning gold glyph ring (grey and dashed while there is no charge to spend)
	var Lk = lock
	var w = win
	var wt: float = Ctl.now - w.t0 if w else 0.0
	var sweet: bool = w != null and wt >= HOMING.sweetA and wt <= HOMING.sweetB
	var dry: bool = charges < 1 - 1e-6 and not sweet
	if Lk and P.mode == "fly":
		var tp := target_pos(Lk)
		var sp: Dictionary = FX.project(tp)
		if not sp.behind:
			var x: float = sp.x
			var y: float = sp.y
			var d := tp.distance_to(P.pos)
			var r := clampf(700 / d, 18, 40) * (1 + 0.5 * exp(-lockT * 12))
			if dry:
				D2.dashed(c, D2.arc_points(x, y, r, 0, TAU, 48), 5, 6, Color(0.725, 0.663, 0.788, 0.8), 2)
				D2.text_base(c, D2.ui_bold, 11, "RECHARGING", x, y + r + 20, Color.html("#b9a9c9"))
			else:
				for i in 3:
					var a0 := Ctl.now * 3 + i * TAU / 3
					_glow_arc(c, x, y, r, a0, a0 + 1.4, Color.html("#ffd27a"), 3, 12)
				D2.ring(c, x, y, r * 0.55, Color(1, 0.925, 0.745, 0.9), 1.6)
				for i in 6:
					var a := -Ctl.now * 1.2 + i * TAU / 6
					var xf := Transform2D(a + PI / 2, Vector2(x + cos(a) * (r + 12), y + sin(a) * (r + 12)))
					D2.glyph(c, 900 + i, 0, 0, 9, Color(1, 0.824, 0.478, 0.85), 1.6, xf)
				if w == null and (TUT.active or hintN < 6):
					D2.text_base(c, D2.ui_bold, 12, Ctl.kl("E · HOMING", "X · HOMING"), x, y + r + 24, Color.html("#ffd27a"))
			if w: draw_chain_window(c, x, y, r, wt)
	elif w and P.mode == "fly": # window open with nothing locked: show it on the reticle so the timing still reads
		var sp: Dictionary = FX.project(P.pos + P.fwd * 30)
		if not sp.behind: draw_chain_window(c, sp.x, sp.y, 22, wt, "NO TARGET", 0.55)
	# charge crystals off screen: cyan edge arrows
	for ci in CHARGE.items:
		if ci.alive: Threats.edge_arrow(c, ci.g.position, "#8fe9ff", 80)
	for ca in caches:
		if ca.alive and ca.pos.distance_to(P.pos) < 60: Threats.edge_arrow(c, World.core_group.global_transform * ca.pos, "#5aa8ff", 60)
	# danger: shots closing on you, superblast waves
	for p in Enemies.projs:
		if not p.on: continue
		var d: float = p.pos.distance_to(P.pos)
		if d > 26: continue
		var closing: float = (P.pos - p.pos).normalized().dot(p.vel.normalized())
		if closing < 0.6: continue
		var sp: Dictionary = FX.project(p.pos)
		if sp.behind: Threats.edge_arrow(c, p.pos, "#ff5b3d", 26); continue
		var s := 8 + 10 * U.smooth(26, 6, d)
		D2.poly_fill(c, PackedVector2Array([Vector2(sp.x, sp.y - s * 1.6), Vector2(sp.x + s, sp.y + s * 0.6), Vector2(sp.x - s, sp.y + s * 0.6)]), Color(1, 0.357, 0.239, 0.9))
	for wv in Enemies.waves:
		var d: float = P.pos.distance_to(wv.pos) - wv.r
		if d < 0 or d > 30: continue
		D2.text_base(c, D2.ui_bold, 14, "WAVE · BOOST THROUGH IT", W / 2, H * 0.24, Color.html("#ff5b3d") if int(floor(Ctl.now * 6)) % 2 else Color.html("#ff8ad6"))
	# charge count + quick-chain timer under the reticle
	if ST.unlocked("charge") and P.mode != "tunnel" and (CHARGE.count > 0 or CHARGE.items.any(func(x): return x.alive)):
		var cx := W / 2
		var cy := H * 0.58
		var q: float = 1 - (GAME.time - CHARGE.lastHit) / QUICK_WINDOW if CHARGE.quick >= 1 and GAME.time - CHARGE.lastHit <= QUICK_WINDOW else 0.0
		for i in 3:
			var x := cx + (i - 1) * 22
			var pts := PackedVector2Array([Vector2(x, cy - 8), Vector2(x + 6, cy), Vector2(x, cy + 8), Vector2(x - 6, cy)])
			if i < CHARGE.count: D2.poly_fill(c, pts, Color.html("#ffd27a") if q > 0 else Color.html("#8fe9ff"))
			else: D2.poly_line(c, pts, Color(0.56, 0.91, 1, 0.6), 1.5, true)
		if q > 0:
			D2.line(c, cx - 34, cy + 16, cx - 34 + 68 * q, cy + 16, Color.html("#ffd27a"), 2.5)
			D2.text_base(c, D2.ui_bold, 10, "QUICK CHAIN", cx, cy + 30, Color.html("#ffd27a"))

## the chain window: a ring closes on the target and meets it in the sweet band (red = wait, cyan = open, gold = NOW)
func draw_chain_window(c: CanvasItem, x: float, y: float, r: float, wt: float, label: String = "", alpha: float = 1.0) -> void:
	var mid: float = (HOMING.sweetA + HOMING.sweetB) / 2
	var span := r * 2.6
	var Rf := func(t: float) -> float: return maxf(r * 0.55, r + span * (1 - t / mid))
	var fade: float = (1 - U.smooth(HOMING.close - 0.12, HOMING.close, wt)) * alpha
	# the sweet band: where the closing ring has to be when you press
	var ra: float = Rf.call(HOMING.sweetA)
	var rb: float = Rf.call(HOMING.sweetB)
	D2.ring(c, x, y, (ra + rb) / 2, Color(1, 0.824, 0.478, 0.16 * fade), absf(ra - rb))
	var wait: bool = wt < HOMING.open
	var now: bool = wt >= HOMING.sweetA and wt <= HOMING.sweetB
	var col: Color = Color(1, 0.416, 0.29, 0.9) if wait else (Color.html("#ffd27a") if now else Color(0.56, 0.91, 1, 0.95))
	col.a *= fade
	_glow_arc(c, x, y, Rf.call(wt), 0, TAU, col, 5.0 if now else 3.0, 22.0 if now else 8.0)
	var tc: Color = Color.html("#ff8a6a") if wait else (Color.html("#ffd27a") if now else Color.html("#8fe9ff"))
	tc.a *= fade
	D2.text_base(c, D2.ui_bold, 15 if now else 12, label if label != "" else ("WAIT" if wait else ("NOW!" if now else "CHAIN")), x, y + maxf(Rf.call(wt), r) + 22, tc)
	# chain progress: five diamonds, the last one is the finisher
	for i in HOMING.cap:
		var dx: float = x + (i - (HOMING.cap - 1) / 2.0) * 15
		var dy := y - r - 22
		var s := 7.0 if i == HOMING.cap - 1 else 5.0
		var pts := PackedVector2Array([Vector2(dx, dy - s), Vector2(dx + s, dy), Vector2(dx, dy + s), Vector2(dx - s, dy)])
		if i < chain: D2.poly_fill(c, pts, D2.col("#ffd27a", fade))
		else: D2.poly_line(c, pts, D2.col("#ff8ad6", fade) if i == HOMING.cap - 1 else Color(1, 0.824, 0.478, 0.6 * fade), 1.5, true)
