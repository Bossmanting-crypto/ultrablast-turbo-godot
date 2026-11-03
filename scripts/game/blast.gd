extends Node
## THE BLAST LOOP (port of 50_blast.js).
## Boost (always): hold to charge up to 3 rings, release to dash through them. A short cooldown follows each blast.
## Turbo (earned): rank B + a full turbo cell lets a gold 4th ring forge -> alignment miniblast -> load-up -> release cue -> supercut.
## Puzzles live in their own contexts: turbo = alignment, crystal cache = alignment, orb breach = glyph memory,
## tunnel exit = strobe timing (no slow-mo). Cache and breach puzzles are primed by homing and start with the charge.

const MAX_RINGS := 3
const LEVEL_NAMES := ["", "SUPERCUT", "HYPERCUT", "ULTRABLAST"]
const RING_COL := Color(1.7, 1.2, 0.6)
const RING_GOLD := Color(2.6, 1.8, 0.4)

var charging := false
var ct := 0.0
var rings := 0
var ringEvery := 0.34
var ringMeshes: Array = []
var railBonus := 0
var worldRings: Array = []
var puzzle = null
var loadup = null
var sc = null
var turboTier := 0
var forging := 0.0
var forgeRing = null
var holdMax := 0.0
var breachOrb = null
var payload = null
var firedPayload := false

var tex_ring_orb: Texture2D = preload("res://assets/textures/puzzle_ring_orb.png")
var tex_ring_outer: Texture2D = preload("res://assets/textures/puzzle_ring_outer.png")
var tex_ring_inner: Texture2D = preload("res://assets/textures/puzzle_ring_inner.png")
var tex_ring_info: Texture2D = preload("res://assets/textures/puzzle_ring_info.png")
var backdrop_tex: GradientTexture2D
var orb_core_tex: GradientTexture2D

func _ready() -> void:
	backdrop_tex = _radial([Color(0.04, 0.043, 0.133, 0.35), Color(0.04, 0.043, 0.133, 0.8)], [0.11, 1.0])
	orb_core_tex = _radial([Color.html("#f6fbdc"), Color.html("#b9cc6a")], [0.0, 1.0], Vector2(0.36, 0.36))

func _radial(cols: Array, offs: Array, from := Vector2(0.5, 0.5)) -> GradientTexture2D:
	var g := Gradient.new(); g.offsets = PackedFloat32Array(offs); g.colors = PackedColorArray(cols)
	var t := GradientTexture2D.new(); t.gradient = g; t.width = 256; t.height = 256
	t.fill = GradientTexture2D.FILL_RADIAL; t.fill_from = from; t.fill_to = from + Vector2(0.5, 0)
	return t

func can_charge() -> bool: return ST.blastCd <= 0 and P.stun <= 0 and ST.unlocked("boost")

func start_charge() -> void:
	charging = true; rings = 0; ct = 0; forging = 0; forgeRing = null; holdMax = 0; payload = null
	var pre := mini(MAX_RINGS, railBonus); railBonus = 0
	for i in pre: add_ring()
	ct = rings * ringEvery
	if prime_valid() and Threats.bolt_target_pos(P.prime.t).distance_to(P.pos) < 90: start_primed_puzzle()

# ---------- primed targets (playtest: "blast puzzles should be player-triggered and start with the charge") ----------
## Homing (or flying) into a cache or an exposed orb PRIMES it. Holding boost then starts its miniblast while you
## charge; solve it and let go to fire the charged shot that cracks it. Letting go early keeps the prime.
func prime_target(t: Dictionary, kind: String) -> void:
	P.prime = {"t": t, "kind": kind, "life": maxf(6.0, t.get("exposed", 0.0)) if kind == "breach" else 9.0}
	if kind == "breach": t.exposed = maxf(t.exposed, P.prime.life + 0.5)
	AudioSys.play("lock", {"vol": 0.75, "rate": 0.85}); AudioSys.play("cell_full", {"vol": 0.4, "rate": 1.4})
	FX.shockwave(World.core_group.global_transform * t.pos if kind == "cache" else t.pos, 6, FX.CYAN, 0.4)
	var nm := "CACHE" if kind == "cache" else "ORB"
	FX.popup(Ctl.kl("%s PRIMED · HOLD SPACE" % nm, "%s PRIMED · HOLD RT" % nm), "#8fe9ff", true)
	Coach.hint("primed", true); TUT.note("primed", kind)

func prime_valid() -> bool:
	var pr = P.prime
	if pr == null or pr.life <= 0: return false
	if pr.kind == "cache": return pr.t.state == "ready" and World.core.solid
	return pr.t.alive and pr.t.exposed > 0

func update_prime(dt: float) -> void:
	var pr = P.prime
	if pr == null or P.mode == "puzzle": return
	pr.life -= dt
	if pr.kind == "breach" and pr.t.alive and pr.t.exposed < pr.life: pr.t.exposed = pr.life + 0.3
	if not prime_valid():
		if pr.life <= 0 and GAME.state == "play": FX.popup("PRIME FADED", "#c9a8ff")
		P.prime = null

func start_primed_puzzle() -> void:
	var pr: Dictionary = P.prime
	if pr.kind == "cache": P.cache = pr.t; open_puzzle("cache", "orbit", 2); FX.popup("CACHE MINIBLAST", "#8fe9ff", true)
	else:
		breachOrb = pr.t; open_puzzle("breach", "glyph", 1 if TUT.active else (2 if ST.DIR.phase >= 2 else 1))
		FX.popup("GLYPH BREACH", "#dce9a9", true); TUT.note("breachStart")
	REC.ev("primedStart", pr.kind)

## solved: the rings fill, and letting go fires the charged shot at the target
func arm_payload(kind: String, target) -> void:
	P.mode = "fly"; P.prime = null; puzzle = null
	payload = {"kind": kind, "target": target, "t": 0.0}
	while rings < MAX_RINGS: add_ring()
	AudioSys.success(); AudioSys.release_cue(); FX.shake(0.25); P.CAM.punch += 4
	FX.event_text("RELEASE!", "gold", false); FX.popup("MATCHED · LET GO TO FIRE", "#ffd27a", true)
	TUT.note("puzzleSuccess", kind)

func add_ring() -> void:
	rings += 1
	var r: Dictionary = FX.get_turbo_ring(); r.tor_mat.albedo_color = Color(RING_COL.r, RING_COL.g, RING_COL.b).linear_to_srgb()
	r.g.position = P.pos + P.fwd * 3; ringMeshes.append(r)
	AudioSys.ring(rings); P.CAM.punch += 1.5
	FX.sparks(P.pos + P.fwd * (7 + (rings - 1) * 4.6), 10, FX.GOLD, 8)

func charge_tick(dt: float) -> void:
	ct += dt * (1.8 if P.onRailNow else 1.0)
	if payload:
		payload.t += dt
		if payload.t > 3: release_charge()
		return
	# holding boost thrusts straight away (ramps in over ~0.5 s, kept just under ram speed); letting go still blasts
	P.boost = maxf(P.boost, minf(20, 6 + ct * 30)); P.boostHold = maxf(P.boostHold, 0.08)
	while rings < MAX_RINGS and ct >= (rings + 1) * ringEvery: add_ring()
	if rings < MAX_RINGS: return
	holdMax += dt
	if ST.turbo_ready():
		# forge the gold turbo ring
		if forgeRing == null:
			forgeRing = FX.get_turbo_ring(); forgeRing.tor_mat.albedo_color = Color(RING_GOLD.r, RING_GOLD.g, RING_GOLD.b).linear_to_srgb()
			forgeRing.g.position = P.pos + P.fwd * 3; ringMeshes.append(forgeRing); AudioSys.forge()
		forging += dt
		if randf() < 0.6: FX.spawn({"pos": forgeRing.g.position, "vel": U.rand_unit() * 5, "color": FX.GOLD, "size": 0.5, "life": 0.35, "shape": 5})
		if forging >= 0.55: rings = 4; AudioSys.ring(4); start_turbo()

func position_charge_rings(rdt: float) -> void:
	for i in ringMeshes.size():
		var r: Dictionary = ringMeshes[i]
		var target: Vector3
		var scl: float
		if P.mode == "loadup": target = P.pos - P.fwd * 2.2; scl = 0.25
		else:
			target = P.pos + P.fwd * (7 + i * 4.6)
			scl = clampf(forging / 0.55, 0.05, 1) * 1.25 if is_same(r, forgeRing) else 1 + 0.08 * sin(Ctl.now * 10 + i)
		r.g.position = r.g.position.lerp(target, 1.0 - exp(-(6.0 if P.mode == "loadup" else 18.0) * rdt))
		var s := U.damp(r.g.scale.x, scl, 10, rdt)
		r.g.basis = P.ship.basis.orthonormalized().scaled_local(Vector3.ONE * s)
		r.gl.rotate_object_local(Vector3.BACK, rdt * (2 + i) * (-1.0 if i % 2 else 1.0))

func drop_forge_ring() -> void:
	if forgeRing == null: return
	FX.free_turbo_ring(forgeRing); ringMeshes = ringMeshes.filter(func(r): return not is_same(r, forgeRing)); forgeRing = null; forging = 0; rings = mini(rings, MAX_RINGS)

func release_charge() -> void:
	drop_forge_ring()
	if payload:
		var pl = payload
		payload = null; Threats.fire_payload(pl); firedPayload = true
	var n := rings
	charging = false
	if P.ride != null and n > 0: P.rideBlastT = 1.0   # a blast off a planet's surface launches you if you have the speed
	if n == 0:
		for r in ringMeshes: FX.free_turbo_ring(r)
		ringMeshes = []; return
	# the rings ride ahead along your flight path and are consumed one by one: a cumulative charge-forward boost
	for i in ringMeshes.size():
		var r: Dictionary = ringMeshes[i]
		var dist := 7 + i * 4.6
		r.g.position = P.pos + P.fwd * dist; r.g.scale = Vector3.ONE * 1.25
		worldRings.append({"r": r, "pos": r.g.position, "dist": dist, "passed": false, "life": 2.6, "idx": i, "t": 0.0})
	ringMeshes = []; rings = 0
	P.boost += 8 + n * 6; P.boostHold = 0.35 + n * 0.2
	P.CAM.punch += 3 + n * 2; FX.shake(0.12 * n); AudioSys.blast(n)
	if n >= 3: FX.popup("RING BLAST ×3", "#ffd27a"); FX.screen_crash(2, [0, 2])
	if P.weapon and P.weapon.type == "homing": Enemies.launch_homing_rings(n); use_ammo()
	if not firedPayload: Threats.fire_blast_bolts(n)
	firedPayload = false
	ST.gain("blast", 2 + n * 2)
	ST.blastCd = ST.COOL.blast
	if n >= 2: Coach.hint("boom")
	TUT.note("blast", n)

func cancel_charge(fizzle: bool) -> void:
	for r in ringMeshes:
		if fizzle: FX.burst_shapes(r.g.position, 10, [2, 0], 8, Color(0.8, 0.6, 1.4))
		FX.free_turbo_ring(r)
	ringMeshes = []; rings = 0; charging = false; forgeRing = null; forging = 0

func update_world_rings(dt: float) -> void:
	for i in range(worldRings.size() - 1, -1, -1):
		var w = worldRings[i]
		w.life -= dt; w.t += dt
		w.r.gl.rotate_object_local(Vector3.BACK, dt * 3)
		if not w.passed:
			w.dist -= maxf(P.speed, 30) * dt * 0.55
			w.pos = P.pos + P.fwd * maxf(0.0, w.dist); w.r.g.position = w.pos
			w.r.g.basis = P.ship.basis.orthonormalized().scaled_local(w.r.g.scale)
		if not w.passed and w.dist <= 0.5:
			w.passed = true; w.life = minf(w.life, 0.35)
			P.boost += 14; P.boostHold = maxf(P.boostHold, 0.45); P.CAM.punch += 3; FX.shake(0.12)
			AudioSys.ring_pass(w.idx); FX.burst_shapes(w.pos, 18, [1, 2], 16)
			GAME.add_score(20, null); ST.gain("ringpass", 5 + w.idx * 2)
			TUT.note("ringPass"); HOM.refill(1, "ring")
		if w.passed:
			w.r.g.scale *= 1 + dt * 6
			FX.ring_opacity(w.r, maxf(0.0, w.life / 0.35))
		if w.life <= 0: FX.free_turbo_ring(w.r); worldRings.remove_at(i)

func use_ammo() -> void:
	if P.weapon == null: return
	P.weapon.ammo -= 1
	if P.weapon.ammo <= 0: P.weapon = null

func bundle_boom() -> void:
	var n := rings
	if n < 1: return
	if ST.boomCd > 0: FX.popup("BOOM COOLING %ds" % ceili(ST.boomCd), "#c9a8ff"); AudioSys.ui("back"); return
	var R := 9.0 + n * 4.5
	var nova: bool = P.weapon != null and P.weapon.type == "nova"
	if nova: R *= 2; use_ammo()
	cancel_charge(false)
	ST.boomCd = ST.COOL.boom; P.chargeArmed = false
	FX.shockwave(P.pos, R, FX.MAG if nova else FX.GOLD, 0.7)
	FX.shockwave(P.pos, R * 0.6, FX.WHITE, 0.4)
	FX.burst_shapes(P.pos, 60 + n * 15, [1, 2, 3, 0], 30 + R)
	FX.screen_crash(3 + n, [0, 1, 2, 4])
	FX.shake(0.5 + n * 0.1); FX.flash(0.3, 0.22, 0.12); P.CAM.punch += 8; AudioSys.boom(); GAME.hitstop(0.06)
	var kills := 0
	for e in Enemies.enemies:
		if e.alive and e.pos.distance_to(P.pos) < R: Enemies.kill_enemy(e, "BOOM"); kills += 1
	for p in Enemies.probes:
		if p.alive and p.pos.distance_to(P.pos) < R: Enemies.kill_probe(p, "BOOM"); kills += 1
	for t in Threats.TUR.list:
		if t.alive and t.pos.distance_to(P.pos) < R + 1: Threats.destroy_turret(t, "BOOM"); kills += 1
	Enemies.kill_projs_in_radius(P.pos, R)
	for o in World.orbs:
		if o.alive and o.pos.distance_to(P.pos) < R + o.r: Enemies.damage_orb(o, 3, "BOOM")
	for c in World.crystals:
		if c.alive and c.pos.distance_to(P.pos) < R: collect_crystal(c)
	for c in World.homers:
		if c.alive and c.pos.distance_to(P.pos) < R: collect_homer(c)
	if kills >= 2 or nova: FX.event_text("BUNDLE BOOM!", "mag")
	else: FX.popup("BOOM", "#ff8ad6", true)
	ST.gain("boom", 6)
	TUT.note("boom", kills)

# ---------- turbo ----------
func start_turbo() -> void:
	var tier: int = ST.turbo_tier_avail()
	if tier < 1: drop_forge_ring(); return
	ST.cells -= tier; turboTier = tier; forging = 0
	open_puzzle("turbo", "orbit", tier)
	TUT.note("turboStart", tier)

# ---------- puzzles (shared overlay, drawn in a 2014 x 840 virtual space) ----------
const PZ := {"orb": {"x": 612, "y": 545, "r": 140, "core": 73}, "big": {"x": 1040, "y": 435, "rin": 202, "rout": 263}, "info": {"x": 1470, "y": 172, "r": 72}, "path": 232}

func pz_xform() -> Dictionary:
	var s := minf(FX.W * 0.94 / 1120, FX.H * 0.78 / 640)
	return {"s": s, "ox": FX.W / 2 - 1007 * s, "oy": FX.H * 0.5 - 420 * s}

func to_v(x: float, y: float) -> Vector2:
	var X := pz_xform()
	return Vector2((x - X.ox) / X.s, (y - X.oy) / X.s)

func open_puzzle(ctx: String, type: String, tier: int) -> void:
	REC.ev("puzzle", [ctx, type, tier])
	P.mode = "puzzle"
	var tut: bool = TUT.active
	var p := {"ctx": ctx, "type": type, "tier": tier, "t": 0.0, "dur": 7.0 if tut else (4.5 if ctx == "cache" else 3.5), "flash": 0.0, "flashCol": "#dce9a9"}
	if type == "orbit":
		var n := tier
		var slots := []
		var a0 := U.rand(0, TAU)
		for i in n: slots.append(a0 + (i + 1) * (TAU / (n + 1)) + U.rand(-0.25, 0.25))
		p.slots = slots; p.idx = 0; p.ang = a0; p.speed = (1.8 if tut else 2.5 + tier * 0.3) * (1.0 if randf() < 0.5 else -1.0)
		# playtest: the cache failed 15 of 22 times. Wider hit zone (drawn on the path), and a spare miss
		p.tol = (0.42 if tut else 0.34) if ctx == "cache" else (0.38 if tut else 0.29)
		p.lives = (2 if tut else 1) if ctx == "cache" else (1 if tut else 0)
		p.inZone = false
	if type == "glyph":
		p.n = 4 if tier >= 2 else 3
		if p.n == 4: p.nodes = [{"a": -PI / 2, "d": "up"}, {"a": 0.0, "d": "right"}, {"a": PI / 2, "d": "down"}, {"a": PI, "d": "left"}]
		else: p.nodes = [{"a": -PI / 2, "d": "up"}, {"a": PI / 6, "d": "right"}, {"a": PI * 5 / 6, "d": "left"}]
		for nd in p.nodes: nd.seed = randi_range(1, 999); nd.hl = 0.0
		p.len = 4 if tier >= 3 else 3
		p.seq = []
		for i in p.len:
			var k := randi_range(0, p.n - 1)
			while p.seq.size() and k == p.seq[p.seq.size() - 1]: k = randi_range(0, p.n - 1)
			p.seq.append(k)
		p.step = 0.5 if tut else 0.42; p.show = true; p.inIdx = 0; p.lives = 1 if ctx == "breach" else 0 # playtest: 0 of 5 breaches
	puzzle = p
	AudioSys.puzzle_start(); FX.shake(0.25); P.CAM.punch -= 6

func puzzle_fail(reason: String) -> void:
	var p: Dictionary = puzzle
	puzzle = null; P.mode = "fly"
	if p.ctx == "turbo":
		cancel_charge(true)
		ST.cells = minf(3, ST.cells + maxi(0, p.tier - 1)); ST.turboCd = ST.COOL.turboFail
		FX.event_text("FIZZLE", "violet", false); FX.popup("%s · LOST 1 CELL" % reason, "#c9a8ff", true)
		GAME.score = maxi(0, GAME.score - 150); GAME.momentum *= 0.5; ST.style_lose(40)
		P.boost = 0; P.slowT = 1.2; AudioSys.fail(); P.invuln = maxf(P.invuln, 0.8)
		P.chargeArmed = false; TUT.note("puzzleFail", "turbo")
	elif p.ctx == "breach": breach_fail(reason)
	elif p.ctx == "cache":
		var c = P.cache
		P.cache = null; P.prime = null; cancel_charge(true)
		if c: P.fwd = (P.pos - World.core_group.global_transform * c.pos).normalized(); P.ortho(); P.velSync = true # home into it again to retry
		FX.event_text("LOCKED OUT", "violet", false); FX.popup(reason, "#c9a8ff", true); AudioSys.fail(); P.invuln = maxf(P.invuln, 1.0)
		TUT.note("puzzleFail", "cache")

func puzzle_success() -> void:
	var p: Dictionary = puzzle
	puzzle = null
	if p.ctx == "turbo":
		AudioSys.success(); FX.event_text("MATCH BOOST!", "gold", false); GAME.add_score(300, null)
		P.mode = "loadup"; loadup = {"t": 0.0, "dur": 1.25, "w0": 0.7 if TUT.active else 0.62, "w1": 1.6 if TUT.active else 1.12, "cue": false}; AudioSys.loadup()
		TUT.note("puzzleSuccess", "turbo")
	elif p.ctx == "breach":
		var o = breachOrb
		breachOrb = null; arm_payload("breach", o)
	elif p.ctx == "cache":
		var c = P.cache
		P.cache = null; arm_payload("cache", c)

func node_at(p: Dictionary, vx: float, vy: float) -> Dictionary:
	var best := -1
	var bd := 1e9
	for i in p.nodes.size():
		var nd: Dictionary = p.nodes[i]
		var nx: float = PZ.big.x + cos(nd.a) * PZ.path
		var ny: float = PZ.big.y + sin(nd.a) * PZ.path
		var d := Vector2(vx - nx, vy - ny).length()
		if d < bd: bd = d; best = i
	return {"i": best, "d": bd}

func glyph_press(p: Dictionary, i: int) -> void:
	if p.show or i < 0: return
	p.nodes[i].hl = 1.0
	if i == p.seq[p.inIdx]:
		p.inIdx += 1; AudioSys.puzzle_hit(p.inIdx); p.flash = 0.25; p.flashCol = "#dce9a9"
		if p.inIdx >= p.len: puzzle_success()
	elif p.lives > 0:
		p.lives -= 1; p.flash = 0.3; p.flashCol = "#ff6a4a"; AudioSys.play("fizzle", {"vol": 0.4, "rate": 1.4}); FX.popup("WRONG · ONE SPARE USED", "#ff8a6a")
	else: puzzle_fail("WRONG GLYPH")

func puzzle_update(rdt: float, held: bool, evs: Array) -> void:
	var p: Dictionary = puzzle
	if (p.ctx == "cache" or p.ctx == "breach") and not held: # let go mid-puzzle: no penalty, the target stays primed
		puzzle = null; P.mode = "fly"; cancel_charge(false); P.cache = null; breachOrb = null
		FX.popup("LET GO TOO SOON · STILL PRIMED", "#f4c6a0"); REC.ev("primeCancel", p.ctx); return
	if p.ctx == "turbo" and not held: # let go mid-miniblast: refund the cells, keep a normal 3-ring blast
		puzzle = null; P.mode = "fly"; ST.cells = minf(3, ST.cells + p.tier); ST.turboCd = ST.COOL.turboCancel
		FX.popup("TURBO CANCELLED · CELLS KEPT", "#f4c6a0"); rings = mini(rings, MAX_RINGS); release_charge(); TUT.note("turboCancel"); return
	p.t += rdt; p.flash = maxf(0, p.flash - rdt)
	var remain: float = p.dur - p.t
	if floor(remain * 2) != floor((remain + rdt) * 2): AudioSys.tick(remain < 1.2)
	if p.type == "orbit":
		p.ang += p.speed * rdt
		var tgt: float = p.slots[p.idx]
		var dd := absf(atan2(sin(p.ang - tgt), cos(p.ang - tgt)))
		var z: bool = dd < p.tol
		if z and not p.inZone: AudioSys.play("lock", {"vol": 0.5, "rate": 1.5, "jit": 0.0}) # "now" ping
		p.inZone = z
		for e in evs:
			if Ctl.is_tap_ev(e): # steering keys no longer count as a tap: you may be steering while you hold boost
				var target: float = p.slots[p.idx]
				var d := atan2(sin(p.ang - target), cos(p.ang - target))
				if absf(d) < p.tol:
					p.idx += 1; p.flash = 0.3; p.flashCol = "#ffd27a"; AudioSys.puzzle_hit(p.idx)
					if p.idx >= p.slots.size(): puzzle_success(); return
				elif p.lives > 0:
					p.lives -= 1; p.flash = 0.3; p.flashCol = "#ff6a4a"; AudioSys.play("fizzle", {"vol": 0.4, "rate": 1.4}); REC.ev("puzzleMiss", p.ctx)
				else: puzzle_fail("MISSED SLOT"); return
	elif p.type == "glyph":
		var show_t: float = p.len * p.step + 0.15
		if p.show:
			var k := int(floor(p.t / p.step))
			for nd in p.nodes: nd.hl = maxf(0, nd.hl - rdt * 4)
			if k < p.len:
				var nd: Dictionary = p.nodes[p.seq[k]]
				nd.hl = 1.0
				if int(floor((p.t - rdt) / p.step)) != k: AudioSys.play("puzzle_hit", {"vol": 0.45, "rate": [0.84, 1.0, 1.19, 1.33][p.seq[k]], "jit": 0.0})
			if p.t > show_t:
				p.show = false
				for nd in p.nodes: nd.hl = 0.0
				p.dur = maxf(p.dur, show_t + (6.0 if TUT.active else 3.6))
		else:
			for nd in p.nodes: nd.hl = maxf(0, nd.hl - rdt * 5)
			for e in evs:
				if e.t == "dir":
					var i := -1
					for j in p.nodes.size():
						if p.nodes[j].d == e.d: i = j; break
					if i >= 0:
						glyph_press(p, i)
						if puzzle == null: return
				if e.t == "home" and e.get("aim", false):
					var vx: float
					var vy: float
					if e.get("pad", false):
						var ang := atan2(Ctl.aim_y, Ctl.aim_x)
						vx = PZ.big.x + cos(ang) * PZ.path; vy = PZ.big.y + sin(ang) * PZ.path
					else:
						var v := to_v((Ctl.mx * 0.5 + 0.5) * FX.W, (Ctl.my * 0.5 + 0.5) * FX.H); vx = v.x; vy = v.y
					glyph_press(p, node_at(p, vx, vy).i)
					if puzzle == null: return
	if p.t >= p.dur: puzzle_fail("TOO SLOW")

# ---------- orb breach (glyph memory) ----------
func breach_success() -> void:
	var o: Dictionary = breachOrb
	breachOrb = null; P.mode = "fly"
	Enemies.shatter_orb(o, "BREACH")
	ST.cells = minf(3, ST.cells + 1); FX.popup("+1 TURBO CELL", "#ffd27a")
	ST.gain("breach", 45); P.boost += 30; P.boostHold = 0.6
	P.fwd = P.fwd.bounce((P.pos - o.pos).normalized()).normalized(); P.ortho(); P.velSync = true
	TUT.note("breach", true)

func breach_fail(reason: String) -> void:
	var o = breachOrb
	breachOrb = null; P.mode = "fly"
	P.prime = null; cancel_charge(true)
	if o: P.fwd = (P.pos - o.pos).normalized(); P.ortho(); P.velSync = true # still exposed while its timer runs: home in again
	FX.event_text("LOCKED OUT", "violet", false); FX.popup(reason, "#c9a8ff", true); AudioSys.fail()
	ST.style_lose(30); P.invuln = maxf(P.invuln, 1.2)
	TUT.note("breach", false)

# ---------- load-up and release ----------
func loadup_update(rdt: float, held: bool) -> void:
	var L: Dictionary = loadup
	L.t += rdt
	var k := clampf(L.t / L.w1, 0, 1)
	P.flameTarget = 1 + k * 3.2
	P.bubble.scale = Vector3.ONE * (0.3 + k * 1.7); P.bubble_mat.set_shader_parameter("uAmt", minf(1, k * 1.3))
	for s in P.bubble_shapes:
		var sp: float = s.get_meta("sp")
		s.position = (s.get_meta("orb") as Vector3).rotated(s.get_meta("ax"), Ctl.now * sp)
		s.rotation.x += rdt * sp; s.rotation.y += rdt * sp * 0.7
	if L.t >= L.w0 and not L.cue: L.cue = true; AudioSys.release_cue()
	if randf() < 0.5: FX.spawn({"pos": P.pos - P.fwd * 2.2 + U.rand_unit() * (k * 1.5), "vel": U.rand_unit() * 2, "color": U.pick([FX.GOLD, FX.MAG]), "size": U.rand(0.4, 0.9), "life": 0.4, "shape": U.pick([1, 2])})
	if not held:
		var perfect := absf(L.t - (L.w0 + L.w1) / 2) < 0.12
		var early: bool = L.t < L.w0
		start_supercut("early" if early else ("perfect" if perfect else "good"))
		return
	if L.t > L.w1: blowout("LATE RELEASE")

func pop_bubble(good := true) -> void:
	var bp: Vector3 = P.pos - P.fwd * 2.2
	P.bubble.scale = Vector3.ONE * 0.001; P.bubble_mat.set_shader_parameter("uAmt", 0.0)
	if good:
		FX.spawn_tentacles(bp, 14, P.fwd)
		FX.burst_shapes(bp + P.fwd * 4, 40, [1, 2, 5], 34)
		FX.screen_crash(9, [0, 1, 2, 3, 5])
	else: FX.burst_shapes(bp, 50, [0, 4], 20, Color(1.2, 0.5, 0.3))
	for r in ringMeshes: FX.free_turbo_ring(r)
	ringMeshes = []; rings = 0; charging = false; forgeRing = null

func blowout(reason: String) -> void:
	puzzle = null; loadup = null
	pop_bubble(false)
	P.mode = "fly"; P.flameTarget = 1
	FX.shockwave(P.pos, 10, Color(1.2, 0.3, 0.15), 0.6); FX.sparks(P.pos, 40, FX.CORAL, 30); FX.burst_shapes(P.pos, 40, [0, 4], 25, Color(0.6, 0.6, 0.6))
	FX.event_text("BLOWOUT!", "red", false); FX.popup("%s · CELLS LOST" % reason, "#ff6a4a", true)
	AudioSys.boom(1.1); AudioSys.event("fizzle"); FX.shake(1.0); FX.flash(0.45, 0.08, 0.02)
	P.invuln = 0; P.hurt(18, ""); P.invuln = 1.2
	P.stun = 1.1; P.boost = 0; ST.turboCd = ST.COOL.turboRun
	GAME.score = maxi(0, GAME.score - 250); GAME.momentum = 0
	P.chargeArmed = false; TUT.note("blowout")

# ---------- supercut (tier set by cells spent) ----------
func start_supercut(q: String) -> void:
	loadup = null
	pop_bubble(true)
	P.mode = "supercut"; P.flameTarget = 1.8
	var tier := maxi(1, turboTier)
	var sp := 72.0 if q == "perfect" else (64.0 if q == "good" else 54.0)
	sc = {"tier": tier, "level": 1, "max": [0, 5, 8, 12][tier], "matches": 0, "target": null, "pressed": false, "judge": "", "speed": sp, "brink": 0.0, "t": 0.0,
		"last": null, "lockFlash": 0.0, "startQ": q, "early": false, "earlyUntil": 0.0, "tta": 0.0, "cap": 999.0}
	FX.doodle_flash(1.0); FX.flash(0.22, 0.17, 0.1); FX.shake(0.8); P.CAM.punch += 16
	FX.shockwave(P.pos, 16, FX.GOLD, 0.6)
	AudioSys.pop()
	FX.popup("PERFECT LAUNCH" if q == "perfect" else ("EARLY LAUNCH" if q == "early" else "LAUNCH"), "#ffd27a" if q == "perfect" else "#f4c6a0", true)
	GAME.maxLevel = maxi(GAME.maxLevel, 1)
	if q == "perfect": GAME.add_score(200, null); ST.gain("launch", 15)
	TUT.note("supercutStart")
	pick_target()

func target_alive(t) -> bool: return t != null and t.get("alive", true) != false

func pick_target() -> void:
	var best = null
	var bs := 1e9
	var best_d := 0.0
	var min_d := maxf(16, sc.speed * 0.42)
	var cands := []
	for e in Enemies.enemies:
		if e.alive: cands.append([e, -20.0])
	for p in Enemies.probes:
		if p.alive: cands.append([p, -15.0])
	for o in World.orbs:
		if o.alive and o.fade > 0.9 and not (o.exposed > 0): cands.append([o, -10.0])
	for h in World.homers:
		if h.alive and h.spawn >= 1: cands.append([h, -5.0])
	for c in World.crystals:
		if c.alive and c.spawn >= 1: cands.append([c, 8.0])
	for c in HOM.CHARGE.items:
		if c.alive: cands.append([c, -12.0])
	for item in cands:
		var t: Dictionary = item[0]
		if not target_alive(t) or is_same(t, sc.last): continue
		var to: Vector3 = t.pos - P.pos
		var d := to.length()
		if d < 8 or d > 140: continue
		var dot := (to / d).dot(P.fwd)
		if dot < -0.3: continue
		var s: float = absf(d - min_d * 1.3) * 0.7 + (40.0 if d < min_d else 0.0) + (1 - dot) * 45 + item[1]
		if s < bs: bs = s; best = t; best_d = d
	sc.target = best; sc.pressed = false; sc.judge = ""; sc.brink = 0.0; sc.early = false
	sc.cap = maxf(18, best_d / 0.55) if best else 999.0
	if best == null: end_supercut("NO TARGETS")

func target_point(t: Dictionary) -> Vector3:
	if t.kind == "orb": return (P.pos - t.pos).normalized() * (t.r + 0.8) + t.pos
	return t.pos

func supercut_update(dt: float, rdt: float, evs: Array) -> void:
	sc.t += dt; sc.lockFlash = maxf(0, sc.lockFlash - rdt)
	if not target_alive(sc.target) or (sc.target.kind == "orb" and sc.target.exposed > 0):
		pick_target()
		if sc == null: return
	var tp := target_point(sc.target)
	var to: Vector3 = tp - P.pos
	var dist := to.length()
	to /= maxf(dist, 1e-4)
	P.fwd = P.fwd.lerp(to, 1.0 - exp(-10 * dt)).normalized()
	P.up = P.up.lerp(P.pos.normalized(), 1.0 - exp(-1.5 * dt))
	P.ortho()
	P.speed = U.damp(P.speed, minf(sc.speed, sc.cap), 8, dt)
	P.pos += P.fwd * minf(P.speed * dt, maxf(0.0, dist - 0.5))
	P.bank = U.damp(P.bank, sin(sc.t * 6) * 0.4, 4, dt)
	if P.pos.length() > World.R - 2: P.pos = U.set_length(P.pos, World.R - 2)
	var tta: float = maxf(0.0, dist - 1.6) / maxf(20, P.speed)
	sc.tta = tta
	var win := 0.34 if TUT.active else 0.24
	for e in evs:
		if Ctl.is_tap_ev(e):
			if sc.pressed or Ctl.now < sc.earlyUntil: continue
			if tta <= win or sc.brink > 0:
				sc.pressed = true; sc.judge = "LATE" if sc.brink > 0 else ("PERFECT" if tta < 0.08 else "GOOD"); sc.lockFlash = 0.25; AudioSys.click()
				if sc.judge == "PERFECT": AudioSys.perfect()
			elif not sc.early: # playtest: one early tap ended 6 of 11 supercuts. Now the first one is a warning
				sc.early = true; sc.earlyUntil = Ctl.now + 0.18; FX.popup("EARLY · WAIT FOR THE RING", "#c9a8ff"); AudioSys.play("fizzle", {"vol": 0.35, "rate": 1.4}); REC.ev("scEarly")
			else: end_supercut("TOO EARLY"); return
	var arrived := dist < 2.0
	if arrived and sc.pressed: supercut_impact(); return
	if arrived and not sc.pressed:
		if sc.brink == 0: sc.brink = 0.4 if TUT.active else 0.2
		else:
			sc.brink -= rdt
			if sc.brink <= 0: smash_target(sc.target, 1); end_supercut("CHAIN BREAK"); return
	if randf() < 0.9: FX.spawn({"pos": P.pos - P.fwd * 1.6, "vel": P.fwd * -12 + U.rand_unit() * 5, "color": FX.MAG if sc.level == 2 else FX.GOLD, "size": U.rand(0.5, 0.9), "life": 0.14, "shape": U.pick(level_shapes(sc.level))})

func level_shapes(l: int) -> Array: return [1, 2] if l == 1 else ([1, 2, 3] if l == 2 else [1, 2, 3, 4, 5])

func smash_target(t: Dictionary, power: int) -> void:
	match t.kind:
		"enemy": Enemies.kill_enemy(t, "SUPERCUT")
		"probe": Enemies.kill_probe(t, "SUPERCUT")
		"orb":
			Enemies.damage_orb(t, 2 + power, "SUPERCUT")
			P.fwd = P.fwd.bounce((P.pos - t.pos).normalized()).normalized(); P.ortho()
		"homer": collect_homer(t)
		"crystal": collect_crystal(t)
		"charge": HOM.collect_charge(t, true)

func supercut_impact() -> void:
	var t: Dictionary = sc.target
	var perfect: bool = sc.judge == "PERFECT"
	smash_target(t, 2 if perfect else 1)
	sc.matches += 1
	var pts := roundi(120 * sc.level * (1 + sc.matches * 0.2) * (1.5 if perfect else 1.0))
	GAME.add_score(pts, null); ST.gain("supercut", 12 if perfect else 8)
	FX.popup("%s %d/%d" % [sc.judge, sc.matches, sc.max], "#ffd27a" if perfect else "#f4c6a0")
	FX.burst_shapes(P.pos + P.fwd * 3, 22 + sc.level * 8, level_shapes(sc.level), 30, FX.MAG if sc.level == 2 else null)
	FX.screen_crash(1 + sc.level, [0, 2] if sc.level == 1 else ([0, 1, 2] if sc.level == 2 else [0, 1, 2, 3, 4, 5, 6]))
	FX.shockwave(P.pos, 6 + sc.level * 2, FX.MAG if sc.level == 2 else FX.GOLD, 0.4)
	GAME.hitstop(0.07); FX.shake(0.4); P.CAM.punch += 5; AudioSys.hit(sc.matches)
	sc.speed = minf(150, sc.speed + 8)
	if sc.matches == 3 and sc.tier >= 2: sc.level = 2; FX.event_text("HYPERCUT!", "mag"); AudioSys.event("hyper"); FX.doodle_flash(0.7)
	if sc.matches == 6 and sc.tier >= 3: sc.level = 3; FX.event_text("ULTRABLAST!", "gold"); AudioSys.event("ultra"); FX.doodle_flash(1); FX.DOOD.base = 0.22
	GAME.maxLevel = maxi(GAME.maxLevel, sc.level)
	TUT.note("scMatch", sc.matches)
	sc.last = t
	if sc.matches >= sc.max:
		FX.event_text("%s FINISH" % LEVEL_NAMES[sc.level], "gold", false); AudioSys.event("complete"); end_supercut("COMPLETE"); return
	pick_target()

func end_supercut(reason: String) -> void:
	if sc == null: return
	var s: Dictionary = sc
	sc = null; REC.ev("scEnd", [reason, s.matches])
	P.mode = "fly"; P.flameTarget = 1; FX.DOOD.base = 0.0
	P.boost = maxf(P.boost, s.speed * 0.55); P.boostHold = 0.6
	GAME.momentum = minf(24, GAME.momentum + s.matches * 0.8)
	var bonus := roundi(s.matches * s.matches * 25 * s.level * (1.5 if reason == "COMPLETE" else 1.0))
	if s.matches > 0:
		GAME.add_score(bonus, null); FX.popup("%s %d/%d  +%d" % [LEVEL_NAMES[s.level], s.matches, s.max, roundi(bonus * GAME.mult())], "#ffd27a", true)
	if reason != "" and reason != "NO TARGETS" and reason != "COMPLETE": FX.popup(reason, "#c9a8ff")
	GAME.bestChain = maxi(GAME.bestChain, s.matches)
	ST.turboCd = ST.COOL.turboRun
	P.invuln = maxf(P.invuln, 1.0); P.hTarget = 8; P.chargeArmed = false
	TUT.note("supercutEnd", s.matches)

# ---------- tunnel exit strobe (timing, real time, no slow-mo) ----------
func strobe_r(t: float) -> float: return 18 + 92 * (0.5 - 0.5 * cos(TAU * t / 0.66))

func strobe_input() -> void:
	var s = P.strobe
	if s == null or not s.active or s.judged: return
	var r := strobe_r(s.t)
	var ok := absf(r - 60) < (15.0 if TUT.active else 11.0)
	s.judged = "perfect" if ok else "miss"; AudioSys.strobe(ok); REC.ev("strobe", {"ok": ok, "off": roundi(r - 60)})
	if ok: P.CAM.punch += 2; FX.shake(0.12)

# ---------- overlay drawing ----------
func _glow_arc(c: CanvasItem, x: float, y: float, r: float, a0: float, a1: float, col: Color, w: float, blur: float = 14.0) -> void:
	if blur > 0:
		var g := col; g.a *= 0.22
		D2.arc(c, x, y, r, a0, a1, g, w + blur * 0.6)
	D2.arc(c, x, y, r, a0, a1, col, w)

func _draw_lock(c: CanvasItem) -> void:
	if sc == null or sc.target == null: return
	var W: float = FX.W
	var H: float = FX.H
	var tp := target_point(sc.target)
	var sp: Dictionary = FX.project(tp)
	var x: float = sp.x
	var y: float = sp.y
	var off: bool = sp.behind or x < 0 or y < 0 or x > W or y > H
	if off:
		var cx := W / 2
		var cy := H / 2
		var dx := x - cx
		var dy := y - cy
		if sp.behind: dx = -dx; dy = -dy
		var k := minf((W / 2 - 40) / maxf(absf(dx), 1), (H / 2 - 40) / maxf(absf(dy), 1))
		x = cx + dx * k; y = cy + dy * k
	var tta: float = sc.tta
	var r0 := 28.0
	var rr := r0 + minf(tta, 1.2) * 200
	var lc: Color = Color.html("#ffd27a") if sc.pressed else Color(0.957, 0.776, 0.627, 0.95)
	_glow_arc(c, x, y, r0, 0, TAU, lc, 3, 12)
	for i in 3:
		var a := Ctl.now * 2 + i * TAU / 3
		_glow_arc(c, x, y, r0 + 9, a, a + 0.6, lc, 3, 12)
	if not sc.pressed:
		var good := tta <= 0.24
		_glow_arc(c, x, y, rr, 0, TAU, Color.html("#ffd27a") if good else Color.html("#dce9a9"), 5.0 if good else 3.5, 12)
		if sc.brink > 0: D2.text_base(c, D2.ui_bold, 16, "NOW!", x, y - r0 - 26, Color.html("#ff7a5a"))
	else:
		D2.disc(c, x, y, r0, Color(1, 0.824, 0.478, minf(1.0, 0.25 + sc.lockFlash * 2)))
		D2.text_base(c, D2.ui_bold, 15, sc.judge, x, y - r0 - 22, Color.html("#ffd27a"))
	# chain counter near center bottom
	D2.text_base(c, D2.display, 26, "%s  %d/%d" % [LEVEL_NAMES[sc.level], sc.matches, sc.max], W / 2, H * 0.8, Color.html("#ff8ad6") if sc.level == 2 else Color.html("#ffd27a"), HORIZONTAL_ALIGNMENT_CENTER, 6, Color(0, 0, 0, 0.5))
	D2.text_base(c, D2.ui_bold, 12, Ctl.kl("TAP E / SPACE WHEN THE RING CLOSES", "TAP X / A WHEN THE RING CLOSES"), W / 2, H * 0.8 + 22, Color.html("#f4c6a0"))

func _draw_strobe(c: CanvasItem) -> void:
	var s = P.strobe
	var tun = P.tunnel
	if s == null or not s.active or tun == null: return
	var f: Dictionary = tun.frame_at(0.995 if P.tunDir > 0 else 0.005)
	var sp: Dictionary = FX.project(f.p)
	if sp.behind: return
	var x := clampf(sp.x, 80, FX.W - 80)
	var y := clampf(sp.y, 80, FX.H - 80)
	var tol := 15.0 if TUT.active else 11.0
	var a := minf(1.0, s.t * 4)
	D2.ring(c, x, y, 60, Color(1, 0.824, 0.478, 0.35 * a) if s.judged == "perfect" else Color(0.56, 0.91, 1, 0.14 * a), tol * 2)
	_glow_arc(c, x, y, 60 + tol, 0, TAU, Color(0.56, 0.91, 1, 0.8 * a), 1.5, 8)
	_glow_arc(c, x, y, 60 - tol, 0, TAU, Color(0.56, 0.91, 1, 0.8 * a), 1.5, 8)
	if not s.judged:
		var r := strobe_r(s.t)
		var hot := absf(r - 60) < tol
		var col: Color = Color.html("#ffd27a") if hot else Color.html("#dce9a9"); col.a = a
		_glow_arc(c, x, y, r, 0, TAU, col, 6.0 if hot else 4.0, 18)
	var tc: Color = Color.html("#ffd27a") if s.judged == "perfect" else Color.html("#8fe9ff"); tc.a = a
	var label: String = "PERFECT EXIT LOCKED" if s.judged == "perfect" else ("NORMAL EXIT" if s.judged else Ctl.kl("TAP E OR SPACE IN THE BAND", "TAP X OR A IN THE BAND"))
	D2.text_base(c, D2.ui_bold, 13, label, x, y + 60 + tol + 22, tc)

func draw_puzzle_and_lock(c: CanvasItem) -> void:
	if P.mode == "supercut": _draw_lock(c); return
	if P.mode == "tunnel": _draw_strobe(c); return
	var W: float = FX.W
	var H: float = FX.H
	if P.mode == "loadup" and loadup:
		var L: Dictionary = loadup
		var sp: Dictionary = FX.project(P.pos - P.fwd)
		var in_win: bool = L.t >= L.w0
		var k := clampf((L.t - L.w0) / (L.w1 - L.w0), 0, 1)
		_glow_arc(c, sp.x, sp.y, 70, 0, TAU, Color(0.957, 0.776, 0.627, 0.8), 2)
		if in_win: _glow_arc(c, sp.x, sp.y, 70, -PI / 2, -PI / 2 + TAU * (1 - k), Color.html("#ff6a45") if k > 0.75 else Color.html("#ffd27a"), 6, 18)
		var label := "RELEASE!" if in_win else "LOADING…"
		var s := 1 + 0.08 * sin(Ctl.now * 30) if in_win else 1.0
		var fs := roundi((44 if in_win else 26) * s)
		c.draw_set_transform_matrix(Transform2D(Vector2(1, 0), Vector2(-0.2, 1), Vector2(W / 2, H * 0.72)))
		D2.text_base(c, D2.display, fs, label, 0, 0, Color.html("#ffd27a") if in_win else Color.html("#f4c6a0"), HORIZONTAL_ALIGNMENT_CENTER, 8, Color.html("#2a0a22"))
		D2.pop(c)
		return
	var p = puzzle
	if p == null or P.mode != "puzzle": return
	var X := pz_xform()
	var S: float = X.s
	# dim backdrop
	c.draw_texture_rect(backdrop_tex, Rect2(W / 2 - H * 0.9, H / 2 - H * 0.9, H * 1.8, H * 1.8), false)
	var outside := Color(0.04, 0.043, 0.133, 0.8)
	if W > H * 1.8:
		c.draw_rect(Rect2(0, 0, W / 2 - H * 0.9, H), outside); c.draw_rect(Rect2(W / 2 + H * 0.9, 0, W / 2 - H * 0.9, H), outside)
	var base := Transform2D(0.0, Vector2(S, S), 0.0, Vector2(X.ox, X.oy))
	c.draw_set_transform_matrix(base)
	var remain := maxf(0.0, p.dur - p.t)
	var frac: float = remain / p.dur
	var peach := Color(0.957, 0.776, 0.627, 0.95)
	# charge orb + countdown
	var O: Dictionary = PZ.orb
	_glow_arc(c, O.x, O.y, O.r, 0, TAU, peach, 3)
	_glow_arc(c, O.x, O.y, O.r + 12, -PI / 2, -PI / 2 + TAU * frac, Color.html("#ff6a45") if frac < 0.34 else Color.html("#ffd27a"), 6, 16)
	_draw_rot(c, base, tex_ring_orb, O.x, O.y, 420, -Ctl.now * 0.4)
	var cr: float = O.core * (0.85 + 0.15 * frac)
	D2.disc(c, O.x, O.y, cr * 1.5, Color(0.86, 0.91, 0.66, 0.12))
	c.draw_texture_rect(orb_core_tex, Rect2(O.x - cr, O.y - cr, cr * 2, cr * 2), false)
	D2.text(c, D2.display, 38, "%.1f" % remain, O.x, O.y + 2, Color.html("#2a3010"))
	# big double ring
	var Bg: Dictionary = PZ.big
	_glow_arc(c, Bg.x, Bg.y, Bg.rout, 0, TAU, peach, 2.6)
	_glow_arc(c, Bg.x, Bg.y, Bg.rin, 0, TAU, peach, 4)
	_draw_rot(c, base, tex_ring_outer, Bg.x, Bg.y, 720, Ctl.now * 0.15)
	_draw_rot(c, base, tex_ring_inner, Bg.x, Bg.y, 480, -Ctl.now * 0.25)
	# info ring
	var I: Dictionary = PZ.info
	_glow_arc(c, I.x, I.y, I.r, 0, TAU, peach, 3)
	_draw_rot(c, base, tex_ring_info, I.x, I.y, 240, Ctl.now * 0.6)
	D2.text(c, D2.ui_bold, 20, "ALIGN" if p.type == "orbit" else "MEMORY", I.x, I.y - 8, Color.html("#f4c6a0"))
	D2.text(c, D2.ui_bold, 14, ("TIER %d" % p.tier) if p.ctx == "turbo" else ("CACHE" if p.ctx == "cache" else "ORB LOCK"), I.x, I.y + 16, Color.html("#b9a9c9"))
	# header
	var head := "MINIBLAST" if p.ctx == "turbo" else ("CACHE LOCK" if p.ctx == "cache" else "GLYPH BREACH")
	c.draw_set_transform_matrix(base * Transform2D(Vector2(1, 0), Vector2(-0.2, 1), Vector2(480, 150)))
	D2.text_base(c, D2.display, 54, head, 0, 0, Color.html("#ffd27a"), HORIZONTAL_ALIGNMENT_LEFT, 8, Color.html("#2a0a22"))
	c.draw_set_transform_matrix(base)
	var hint := ""
	if p.type == "orbit":
		for i in p.slots.size():
			var a: float = p.slots[i]
			var sx: float = Bg.x + cos(a) * PZ.path
			var sy: float = Bg.y + sin(a) * PZ.path
			var col: Color = Color.html("#ffd27a") if i < p.idx else (Color.html("#fff3e4") if i == p.idx else Color(0.957, 0.776, 0.627, 0.6))
			if i < p.idx: D2.disc(c, sx, sy, 50, Color(1, 0.824, 0.478, 0.4))
			D2.dashed(c, D2.arc_points(sx, sy, 50, 0, TAU, 48), 10.0 if i == p.idx else 4.0, 8.0 if i == p.idx else 10.0, col, 4.0 if i == p.idx else 2.0)
		# the hit zone of the active slot, drawn on the orbit path; it lights up while the orb is inside it
		if p.idx < p.slots.size():
			var a: float = p.slots[p.idx]
			_glow_arc(c, Bg.x, Bg.y, PZ.path, a - p.tol, a + p.tol, Color(1, 0.824, 0.478, 0.85) if p.inZone else Color(1, 0.824, 0.478, 0.28), 26.0 if p.inZone else 16.0, 24.0 if p.inZone else 0.0)
		var tx: float = Bg.x + cos(p.ang) * PZ.path
		var ty: float = Bg.y + sin(p.ang) * PZ.path
		D2.disc(c, tx, ty, 44, Color(1, 0.824, 0.478, 0.45) if p.inZone else Color(0.86, 0.91, 0.66, 0.35))
		_glow_arc(c, tx, ty, 44, 0, TAU, Color.html("#ffd27a") if p.inZone else Color.html("#dce9a9"), 5, 20)
		if p.inZone: D2.text_base(c, D2.ui_bold, 26, "NOW!", tx, ty + 9, Color.html("#ffd27a"))
		for i in p.lives: D2.disc(c, Bg.x - (p.lives - 1) * 14 + i * 28, Bg.y + 40, 7, Color.html("#8fe9ff"))
		hint = "ALIGN: PRESS WHEN THE ORB IS IN THE GOLD ZONE (%d/%d)%s" % [p.idx, p.slots.size(), (" · %d SPARE" % p.lives) if p.lives else ""]
	else:
		for i in p.nodes.size():
			var nd: Dictionary = p.nodes[i]
			var nx: float = Bg.x + cos(nd.a) * PZ.path
			var ny: float = Bg.y + sin(nd.a) * PZ.path
			if nd.hl > 0: D2.disc(c, nx, ny, 56, Color(1, 0.824, 0.478, 0.65 * nd.hl))
			_glow_arc(c, nx, ny, 56, 0, TAU, Color.html("#fff3e4") if nd.hl > 0.3 else peach, 3.5, 24.0 if nd.hl > 0.3 else 8.0)
			D2.glyph(c, nd.seed, nx, ny, 62, Color.html("#2a0a22") if nd.hl > 0.3 else Color.html("#f4c6a0"), 4)
			var keys := {"up": "D-PAD ▲", "down": "D-PAD ▼", "left": "◀ D-PAD", "right": "D-PAD ▶"} if Ctl.is_pad() else {"up": "W ▲", "down": "S ▼", "left": "A ◀", "right": "D ▶"}
			D2.text_base(c, D2.ui_bold, 15, keys[nd.d], nx, ny + 80, Color.html("#b9a9c9"))
		for i in p.len:
			var px: float = Bg.x - (p.len - 1) * 16 + i * 32
			if not p.show and i < p.inIdx: D2.disc(c, px, Bg.y, 9, Color.html("#dce9a9"))
			_glow_arc(c, px, Bg.y, 9, 0, TAU, peach, 2, 6)
		hint = "MEMORISE THE SEQUENCE…" if p.show else ("REPEAT IT WITH THE D-PAD" if Ctl.is_pad() else "REPEAT IT: WASD / ARROWS, OR AIM AND RIGHT-CLICK THE GLYPHS")
	if p.flash > 0:
		var fc := Color.html(p.flashCol); fc.a = p.flash / 0.3
		D2.ring(c, Bg.x, Bg.y, Bg.rout + 30 + (0.3 - p.flash) * 200, fc, 10)
	D2.text_base(c, D2.ui_bold, 22, hint, 1007, 760, Color.html("#fff3e4"))
	var sub: String
	if p.ctx == "turbo": sub = Ctl.kl("KEEP HOLDING SPACE / LMB. HIT WITH E OR RMB", "KEEP HOLDING RT. HIT WITH X")
	elif p.ctx == "cache": sub = Ctl.kl("KEEP HOLDING SPACE. HIT WITH E OR RMB", "KEEP HOLDING RT. HIT WITH X")
	else: sub = Ctl.kl("KEEP HOLDING SPACE. ANSWER WITH ARROWS / WASD", "KEEP HOLDING RT. ANSWER WITH THE D-PAD")
	D2.text_base(c, D2.ui_bold, 15, sub, 1007, 792, Color.html("#b9a9c9"))
	D2.pop(c)

func _draw_rot(c: CanvasItem, base: Transform2D, tex: Texture2D, x: float, y: float, size: float, rot: float) -> void:
	c.draw_set_transform_matrix(base * Transform2D(rot, Vector2(x, y)))
	c.draw_texture_rect(tex, Rect2(-size / 2, -size / 2, size, size), false, Color(1, 1, 1, 0.85))
	c.draw_set_transform_matrix(base)

# ---------- collectibles ----------
func collect_crystal(c: Dictionary) -> void:
	if not c.alive: return
	c.alive = false; c["respawnT"] = 4.0
	GAME.crystals += 1; GAME.add_score(10, null); ST.gain("crystal", 2.2); TUT.note("crystal"); HOM.refill(0.25, "crystal")
	P.fuel = minf(100.0, P.fuel + 3.0)  # a sip of fuel per crystal: enough to relight and limp to a planet
	AudioSys.crystal(GAME.crystals); FX.sparks(c.pos, 8, c.color * 1.8, 10)

func collect_homer(c: Dictionary, via_homing := false) -> void:
	if not c.alive: return
	c.alive = false; c["respawnT"] = 999.0 if TUT.active else 8.0; c["tut"] = false
	GAME.crystals += 1; GAME.add_score(50, null)
	if not via_homing: ST.gain("homer", 6)
	if P.mode == "fly" and not via_homing: P.boost += 18; P.boostHold = maxf(P.boostHold, 0.3); FX.popup("HOMING BOOST", "#ff8ad6") # a homing hit already bounces
	if not via_homing: AudioSys.homer()
	FX.burst_shapes(c.pos, 16, [5, 2], 14, FX.MAG)

func update_collectibles(dt: float) -> void:
	var t: float = GAME.time
	var mag_r := 16.0 if P.magnetT > 0 else (5.0 if P.boost > 40 else 0.0)
	var grab := 2.6
	var cmm: MultiMesh = World.crystal_mm.multimesh
	for c in World.crystals:
		if not c.alive:
			c["respawnT"] = c.get("respawnT", 0.0) - dt
			if c.respawnT <= 0 and GAME.state != "over" and not TUT.active: c.home = World.random_free_spot(); c.alive = true; c.spawn = 0.0; c["tut"] = false
			cmm.set_instance_transform(c.idx, World.HIDDEN); continue
		c.spawn = minf(1, c.spawn + dt * 1.5)
		if c.home.length() > World.R * 0.9: c.home = World.random_free_spot()
		var bob := 0.3 if c.get("tut", false) else 1.0 # tutorial crystals sit where they were placed
		c.pos = Vector3(c.home.x + sin(t * 0.3 + c.ph) * 3 * bob, c.home.y + sin(t * 0.23 + c.ph * 1.7) * 2.5 * bob, c.home.z + cos(t * 0.27 + c.ph * 0.6) * 3 * bob)
		var d: float = c.pos.distance_to(P.pos)
		if mag_r and d < mag_r: c.home = c.home.lerp(P.pos, 1.0 - exp(-6 * dt))
		elif d < 5.5 and P.mode == "fly" and (c.pos - P.pos).dot(P.fwd) > 0: c.home = c.home.lerp(P.pos, 1.0 - exp(-4 * dt)) # soft pull: near misses still land
		if d < grab and (P.mode == "fly" or P.mode == "tunnel"): collect_crystal(c)
		var s: float = maxf(0.001, c.spawn * (1 + 0.1 * sin(t * 4 + c.ph)))
		cmm.set_instance_transform(c.idx, Transform3D(Basis.from_euler(Vector3(0, t * 1.5 + c.ph, sin(t + c.ph) * 0.3), EULER_ORDER_XYZ).scaled(Vector3.ONE * s), c.pos))
	var hmm: MultiMesh = World.homing_mm.multimesh
	for c in World.homers:
		if not c.alive:
			c["respawnT"] = c.get("respawnT", 0.0) - dt
			if c.respawnT <= 0: c.home = World.random_free_spot(); c.pos = c.home; c.vel = Vector3.ZERO; c.alive = true; c.spawn = 0.0
			hmm.set_instance_transform(c.idx, World.HIDDEN); continue
		c.spawn = minf(1, c.spawn + dt)
		var d: float = c.pos.distance_to(P.pos)
		if d < 20 and P.mode != "supercut" and P.mode != "homing" and not c.get("tut", false):
			c.active = true; c.vel += (P.pos - c.pos).normalized() * (70 * dt); c.vel *= exp(-1.5 * dt); c.pos += c.vel * dt
			if randf() < 0.4: FX.spawn({"pos": c.pos, "color": FX.MAG, "size": 0.4, "life": 0.3, "shape": 5})
		else:
			c.active = false
			c.pos = c.pos.lerp(Vector3(c.home.x + sin(t * 0.5 + c.ph) * 4, c.home.y + cos(t * 0.4 + c.ph) * 4, c.home.z), 1.0 - exp(-0.8 * dt))
		if d < grab + 0.5 and (P.mode == "fly" or P.mode == "tunnel"): collect_homer(c)
		var s: float = maxf(0.001, c.spawn * (1 + 0.25 * sin(t * 8 + c.ph)))
		hmm.set_instance_transform(c.idx, Transform3D(Basis.from_euler(Vector3(t * 2 + c.ph, t * 3, 0), EULER_ORDER_XYZ).scaled(Vector3.ONE * s), c.pos))
	var gmm: MultiMesh = World.gem_mm.multimesh
	for g in World.gems:
		if not g.alive: gmm.set_instance_transform(g.idx, World.HIDDEN); continue
		var d: float = g.pos.distance_to(P.pos)
		if mag_r and d < mag_r: g.pos = g.pos.lerp(P.pos, 1.0 - exp(-8 * dt))
		if d < grab + 0.3 and P.mode != "puzzle":
			g.alive = false; g.row.got += 1; GAME.add_score(25, null); ST.gain("gem", 2.5); AudioSys.gem(g.row.got); FX.sparks(g.pos, 6, FX.GOLD, 8)
			if g.row.got == g.row.total:
				GAME.add_score(500, null); FX.popup("ROW CLEAR +%d" % roundi(500 * GAME.mult()), "#ffd27a", true); AudioSys.row_clear(); FX.burst_shapes(P.pos, 24, [1, 3], 18); ST.gain("row", 14)
			gmm.set_instance_transform(g.idx, World.HIDDEN)
			continue
		var s := 1 + 0.15 * sin(t * 6 + g.ph)
		gmm.set_instance_transform(g.idx, Transform3D(Basis(Vector3.UP, t * 3 + g.ph).scaled(Vector3.ONE * s), g.pos))
	# weapon pickups
	var cam: Camera3D = GAME.camera
	for i in range(World.pickups.size() - 1, -1, -1):
		var k = World.pickups[i]
		k.life -= dt; k.t += dt
		var cage: Node3D = k.mesh.get_meta("cage")
		var ring: Node3D = k.mesh.get_meta("ring")
		cage.rotation.x += dt; cage.rotation.y += dt * 1.4
		var rp: Vector3 = ring.global_position
		if rp.distance_to(cam.global_position) > 0.01: ring.global_basis = U.basis_face((cam.global_position - rp).normalized()).rotated((cam.global_position - rp).normalized(), k.t)
		k.mesh.scale = Vector3.ONE * maxf(0.001, minf(1, k.t * 2) * ((1.0 if int(floor(k.life * 6)) % 2 else 0.6) if k.life < 3 else 1.0))
		if k.pos.distance_to(P.pos) < 3.4 and P.mode != "puzzle":
			ST.gain("pickup", 8)
			var w: Dictionary = World.WEAPONS[k.type]
			if k.type == "magnet": P.magnetT = w.time; P.weapon = P.weapon if P.weapon and P.weapon.type != "magnet" else null
			else: P.weapon = {"type": k.type, "ammo": w.ammo}
			FX.popup("%s%s" % [w.name, " 15s" if k.type == "magnet" else " ×%d" % w.ammo], w.css, true); AudioSys.weapon(); FX.burst_shapes(k.pos, 30, [3, 5], 16, w.color)
			k.life = 0.0
		if k.life <= 0: k.mesh.queue_free(); World.pickups.remove_at(i)
