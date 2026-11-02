extends Node
## GAME (port of 60_game.js): run state, score, the main loop (time scale, hit-stop, slow-mo), mode dispatch,
## world update order, lens grading, the audio mix and the screens. The main scene calls boot(self) once its
## nodes exist; until then this autoload idles.

var state := "title"
var time := 0.0
var utime := 0.0
var score := 0
var momentum := 0.0
var crystals := 0
var kills := 0
var bestChain := 0
var maxLevel := 0
var rifts := 0
var ts := 1.0
var slowT := 0.0
var slowV := 1.0
var hitT := 0.0
var nextPickup := 40.0
var boostHintT := 0.0
var overWhy := ""
var frames := 0
var attract_t := 0.0
var hud_t := 0.0
var fixed_dt := 0.0   # tests: a fixed timestep (window.__UB_DT in the web build); 0 = real time

var main: Node
var camera: Camera3D
var sky: MeshInstance3D
var sky_mat: ShaderMaterial
var root3d: Node3D
var doodle: TextureRect
var lens: ShaderMaterial
var env: Environment
var hud: Hud
var screens := {}
var overlays: Array = []
var booted := false
var sky_rot := 0.0
var sky_bright := 0.95

func mult() -> float: return 1 + ST.rank * 0.5

func add_score(base: float, label) -> void:
	var pts := roundi(base * mult())
	score += pts
	if label: FX.popup("%s +%d" % [label, pts], "#ffd27a")

func slowmo(v: float, d: float) -> void:
	slowV = minf(slowV if slowT > 0 else 1.0, v); slowT = maxf(slowT, d)

func hitstop(d: float) -> void: hitT = maxf(hitT, d)
func puzzle_active() -> bool: return state == "play" and P.mode == "puzzle"

func banner_set(text: String, blink := false) -> void:
	if hud: hud.set_banner(text, blink)

func pad_note(text: String) -> void:
	var t = screens.get("title")
	if t: t.set_pad_note(text)

# ---------- boot ----------
func boot(m: Node) -> void:
	main = m
	camera = m.get_node("%Camera")
	sky = m.get_node("%Sky")
	sky_mat = sky.material_override
	root3d = m.get_node("%World")
	doodle = m.get_node("%Doodle")
	lens = (m.get_node("%Lens") as ColorRect).material
	env = (m.get_node("%Env") as WorldEnvironment).environment
	hud = m.get_node("%Hud")
	for n in ["title", "pause", "over", "tutdone"]: screens[n] = m.get_node("%" + n.capitalize().replace(" ", ""))
	overlays = [m.get_node("%Overlay0"), m.get_node("%Overlay1"), m.get_node("%Overlay2")]
	World.setup(root3d); P.setup(root3d); FX.setup(root3d); Enemies.setup(root3d); Threats.setup(root3d); HOM.setup(root3d)
	Ctl.device_changed.connect(_on_device_changed)
	Ctl.invert_y = U.sget("ub_invY", false)
	reset_world()
	booted = true
	show_screen("title")

func _on_device_changed() -> void:
	TUT.on_device_change()
	if hud: hud.relabel()
	for sc in screens.values():
		if sc.has_method("relabel"): sc.relabel()

func show_screen(id: String) -> void:
	for k in screens:
		var s: Control = screens[k]
		s.visible = k == id
		if k == id and s.has_method("on_show"): s.on_show()

# ---------- run lifecycle ----------
func reset_world() -> void:
	time = 0; score = 0; momentum = 0; crystals = 0; kills = 0; bestChain = 0; maxLevel = 0; rifts = 0
	nextPickup = 40; slowT = 0; hitT = 0; boostHintT = 0.4
	ST.reset_style(); ST.DIR.phase = 0; Coach.reset(); BL.turboTier = 0; BL.breachOrb = null
	ST.reset_iris(); HOM.reset_homing(); World.clear_tunnels()
	if HOM.caches.is_empty(): HOM.place_caches()
	Threats.reset_turrets(); Threats.reset_player_bolts(); P.prime = null; BL.payload = null; BL.firedPayload = false
	World.bar_u("uCount", 0.0)
	P.reset_player()
	BL.cancel_charge(false)
	for w in BL.worldRings: FX.free_turbo_ring(w.r)
	BL.worldRings = []; BL.puzzle = null; BL.loadup = null; BL.sc = null; BL.railBonus = 0
	P.bubble.scale = Vector3.ONE * 0.001
	for e in Enemies.enemies: e.alive = false; e.j.visible = false; e.respawn = U.rand(2, 6)
	for p in Enemies.probes: p.alive = false; p.g.visible = false; p.passive = false
	for p in Enemies.projs: p.on = false; Enemies.proj_mm.multimesh.set_instance_transform(p.i, World.HIDDEN); Enemies.proj_sheath.multimesh.set_instance_transform(p.i, World.HIDDEN)
	Enemies.clear_waves()
	for k in World.pickups: k.mesh.queue_free()
	World.pickups.clear()
	for o in World.orbs:
		o.alive = true; o.hp = 8; o.exposed = 0.0; o.fade = 1.0; o.g.visible = true; o.state = "idle"; o.t = 0.0; o.next = U.rand(8, 12)
	var c: Dictionary = World.core
	c.state = "normal"; c.t = 0.0; c.next = 20.0; c.dissolve = 0.0; c.defense = 0.0; banner_set("")
	for cr in World.crystals: cr.alive = true; cr.home = World.random_free_spot(); cr.spawn = 1.0
	for h in World.homers: h.alive = true; h.home = World.random_free_spot(); h.pos = h.home; h.vel = Vector3.ZERO; h.spawn = 1.0
	P.ship.visible = true; FX.DOOD.base = 0.0
	for r in FX.ribbons: r.pts.clear()

func start_game() -> void:
	AudioSys.init()
	TUT.quit()
	reset_world()
	state = "play"; show_screen("")
	hud.set_on(true)
	FX.event_text("LAUNCH!", "gold", false); REC.start("run")
	AudioSys.ui("start"); AudioSys.attach_voices(Enemies.enemies); P.chargeArmed = false
	Ctl.pad_hold = true

func to_title() -> void:
	REC.stop("title"); TUT.quit(); state = "title"; show_screen("title"); hud.set_on(false); reset_world()

func end(why: String) -> void:
	if state != "play": return
	REC.ev("end", {"why": why, "score": score, "rank": ST.RANKS[ST.maxRank].l, "rifts": rifts}); REC.stop(why)
	state = "over"; overWhy = why; Coach.queue.clear(); Coach.hide()
	if BL.charging: BL.cancel_charge(false)
	if BL.sc: BL.end_supercut("")
	BL.puzzle = null; BL.loadup = null
	if P.mode == "puzzle" or P.mode == "loadup": P.mode = "fly"; BL.pop_bubble(false)
	FX.event_text("APERTURE SEALED" if why == "TIME" else "SHIP DOWN", "gold" if why == "TIME" else "red", false)
	if why != "TIME":
		FX.shockwave(P.pos, 14, FX.CORAL, 0.8); FX.sparks(P.pos, 80, FX.CORAL, 30); AudioSys.boom(1.3); AudioSys.event("fizzle"); P.ship.visible = false
	else: AudioSys.event("complete")
	var best := maxi(U.sget("ub_best", 0), score); U.sset("ub_best", best)
	_end_best = best
	get_tree().create_timer(2.3).timeout.connect(_show_over)

var _end_best := 0
func _show_over() -> void:
	screens.over.fill(overWhy, score, _end_best, bestChain, ST.RANKS[ST.maxRank].l, crystals, kills, rifts, REC.last_session != null)
	show_screen("over"); hud.set_on(false); FX.popups.clear(); FX.crashes.clear(); FX.clear_texts()

func toggle_pause(on: bool) -> void:
	if state == "play" and on:
		REC.ev("pause"); REC.save()
		if not TUT.active: Coach.hide()
		state = "paused"; show_screen("pause"); AudioSys.ui("pause"); hud.set_on(false)
	elif state == "paused" and not on:
		REC.ev("resume"); state = "play"; show_screen(""); AudioSys.ui("play"); hud.set_on(true)
		Ctl.pad_hold = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == "play" and not REC.typing and booted: toggle_pause(true)

# ---------- audio frame ----------
func audio_frame(rdt: float) -> void:
	var lvl: int = BL.sc.level if BL.sc else 0
	var mode := "pause" if state == "paused" else ("title" if state == "title" else ("over" if state == "over" else ("puzzle" if P.mode == "puzzle" else ("loadup" if P.mode == "loadup" else ("super" if P.mode == "supercut" else "play")))))
	var charge := 0.0
	if state == "play" and (BL.charging or (P.mode == "puzzle" and BL.puzzle and BL.puzzle.ctx == "turbo")): charge = minf(1, BL.rings / 4.0 + 0.1 + BL.forging)
	elif P.mode == "loadup" and state == "play": charge = 1.0
	AudioSys.update({
		"mode": mode, "speed": 0.0 if state == "paused" else (95.0 if P.mode == "tunnel" else P.speed),
		"boost": 50.0 + lvl * 10 if P.mode == "supercut" else (30.0 if P.mode == "tunnel" else (45.0 if P.mode == "homing" else P.boost)),
		"playing": state == "play", "tunnel": state == "play" and P.mode == "tunnel", "rank": ST.rank if state == "play" else 0,
		"iris": 0.0 if state != "play" else maxf(0.0 if ST.IRIS.state == "idle" else 0.8, U.smooth(World.R - 30, World.R - 3, P.pos.length())),
		"charge": charge, "slowmo": ts < 0.5})
	AudioSys.update_voices(rdt, P.pos, ts < 0.5 or state != "play")

# ---------- main loop ----------
func _process(delta: float) -> void:
	if not booted: return
	var rdt := fixed_dt if fixed_dt > 0 else clampf(delta, 0, 0.05)
	Ctl.poll(); frames += 1; REC.tick(rdt)
	var evs: Array = Ctl.events.duplicate()
	Ctl.events.clear()
	for e in evs:
		if e.t == "pause" and not REC.typing:
			if state == "play": toggle_pause(true)
			elif state == "paused": toggle_pause(false)
		if e.t == "mute":
			var m := not AudioSys.is_muted()
			AudioSys.set_muted(m); FX.popup("SOUND OFF" if m else "SOUND ON", "#b9a9c9")
			for sc in screens.values():
				if sc.has_method("sync"): sc.sync()
	if state == "paused":
		audio_frame(rdt); _redraw_overlays(); return
	# time scale
	var target := 1.0
	if state == "play":
		if P.mode == "puzzle": target = 0.1
		elif P.mode == "loadup": target = 0.28
		elif BL.sc and BL.sc.brink > 0: target = 0.06
	if slowT > 0: slowT -= rdt; target = minf(target, slowV)
	ts = U.damp(ts, target, 16, rdt)
	var tsc := ts
	if hitT > 0: hitT -= rdt; tsc = 0.03
	var dt := rdt * tsc
	utime += dt
	RenderingServer.global_shader_parameter_set("uTime", utime)
	if state == "play": play_update(dt, rdt, evs)
	elif state == "title": title_update(dt, rdt)
	elif state == "over": time += dt; world_update(dt, rdt)
	P.update_camera(rdt, dt)
	P.update_ship_visual(rdt, dt)
	FX.update_ribbons(rdt)
	FX.update_particles(dt * 0.85 + rdt * 0.15)
	FX.update_shockwaves(dt); FX.update_tentacles(rdt); FX.update_speed_lines(rdt)
	_grade(rdt)
	audio_frame(rdt)
	FX.tick_2d(rdt)
	_redraw_overlays()
	hud_t -= rdt
	if state == "play" and hud_t <= 0: hud_t = 0.05; hud.update_hud()

func _redraw_overlays() -> void:
	for o in overlays: o.queue_redraw()

## lens + grading
func _grade(rdt: float) -> void:
	var L: Dictionary = FX.LENS
	var sf := clampf((P.speed - 30) / 100, 0, 1)
	var lvl: int = BL.sc.level if BL.sc else 0
	var blur := sf * 0.7 + (0.4 if P.mode == "tunnel" else 0.0) + (0.7 + lvl * 0.25 if P.mode == "supercut" else 0.0) + (0.4 if P.mode == "loadup" else 0.0)
	L.blur = U.damp(L.blur, blur, 6, rdt)
	L.chroma = U.damp(L.chroma, 0.002 + sf * 0.004 + (0.006 * lvl if P.mode == "supercut" else 0.0) + (0.004 if P.mode == "puzzle" else 0.0), 6, rdt)
	L.warp = U.damp(L.warp, 0.12 if P.mode == "puzzle" else (0.18 if P.mode == "loadup" else (0.06 if P.mode == "supercut" else 0.0)), 5, rdt)
	L.sat = U.damp(L.sat, 0.35 if P.mode == "puzzle" else (1.15 + lvl * 0.08 if P.mode == "supercut" else 1.0), 6, rdt)
	var tint := Color(1, 1, 1)
	if P.mode == "puzzle": tint = Color(0.8, 0.85, 1.1)
	elif lvl == 3: tint = Color(1.15, 0.95, 0.85)
	elif lvl == 2: tint = Color(1.1, 0.9, 1.1)
	elif lvl == 1: tint = Color(1.08, 1.0, 0.9)
	elif P.hull < 30 and state == "play": tint = Color(1.08 + 0.06 * sin(Ctl.now * 6), 0.92, 0.92)
	var k := 1.0 - exp(-5 * rdt)
	L.tint = Color(lerpf(L.tint.r, tint.r, k), lerpf(L.tint.g, tint.g, k), lerpf(L.tint.b, tint.b, k))
	L.flash = L.flash * exp(-rdt * 7)
	lens.set_shader_parameter("uBlur", L.blur); lens.set_shader_parameter("uChroma", L.chroma); lens.set_shader_parameter("uWarp", L.warp)
	lens.set_shader_parameter("uSat", L.sat); lens.set_shader_parameter("uTint", Vector3(L.tint.r, L.tint.g, L.tint.b))
	lens.set_shader_parameter("uFlash", Vector3(L.flash.r, L.flash.g, L.flash.b))
	# a touch less glow inside rifts keeps the streaks readable
	env.glow_intensity = 0.72 + (0.2 if P.mode == "supercut" else 0.0) + (0.12 if P.mode == "loadup" else 0.0) - (0.14 if P.mode == "tunnel" else 0.0)
	sky_rot += rdt * 0.004
	sky_bright = U.damp(sky_bright, 0.55 if P.mode == "puzzle" else (1.1 if lvl else 0.92), 4, rdt)
	sky_mat.set_shader_parameter("uRot", sky_rot)
	sky_mat.set_shader_parameter("uBright", sky_bright)

func world_update(dt: float, rdt: float) -> void:
	World.place_orbs(utime)
	Enemies.update_core(dt); Enemies.update_orbs(dt); Enemies.update_enemies(dt); Enemies.update_probes(dt); Enemies.update_projs(dt); Enemies.update_waves(dt); Enemies.update_homing_rings(dt)
	BL.update_collectibles(dt); BL.update_world_rings(dt); HOM.update_charge(dt); HOM.update_caches(dt); Threats.update_turrets(dt); Threats.update_player_bolts(dt); BL.update_prime(dt)
	World.barrier.scale = Vector3.ONE * World.R
	for i in range(World.tunnels.size() - 1, -1, -1):
		var t = World.tunnels[i]
		t.update(dt)
		if t.dying and t.fade <= 0 and not is_same(P.tunnel, t):
			t.dispose(); World.tunnels.remove_at(i)
			World.gems = World.gems.filter(func(g): return not is_same(g.row.tunnel, t))
			World.reindex_gems()

func play_update(dt: float, rdt: float, evs: Array) -> void:
	time += dt
	if not TUT.active and time >= World.ROUND_TIME: end("TIME"); return
	ST.director_update(dt)
	var warn = World.bar_get("uWarn")
	World.bar_u("uWarn", U.damp(float(warn) if warn != null else 0.0, 0.0, 1.5, dt))
	if not TUT.active:
		if ST.phase().pickups:
			nextPickup -= dt
			if nextPickup <= 0:
				nextPickup = 16
				if World.pickups.size() < 2: World.spawn_pickup()
		if time > 30 or (rifts > 0 and P.mode == "fly" and time - P.lastTunnelT > 2): Coach.hint("boost")
		if ST.DIR.phase >= 1 and ST.boomCd <= 0 and Enemies.enemies.any(func(e): return e.alive and e.pos.distance_to(P.pos) < 30): Coach.hint("boom")
		if time > 45 and HOM.caches.any(func(c): return c.alive and c.pos.distance_to(P.pos) < 35): Coach.hint("cache")
	# timers
	P.invuln = maxf(0, P.invuln - dt); P.hurtCd = maxf(0, P.hurtCd - dt); P.stun = maxf(0, P.stun - dt); P.slowT = maxf(0, P.slowT - dt)
	P.tunCool = maxf(0, P.tunCool - dt); P.magnetT = maxf(0, P.magnetT - dt); P.homeCd = maxf(0, P.homeCd - dt)
	if time - P.lastHurt > 5 and P.hull < 100: P.hull = minf(100, P.hull + dt * 2.5)
	momentum = maxf(0, momentum - dt * 0.15)
	ST.style_update(dt)
	# modes
	var held := Ctl.charge_held
	var tap := evs.any(Ctl.is_tap_ev)
	var home_ev := evs.any(Ctl.is_home_ev)
	if (P.mode == "fly" or P.mode == "homing") and home_ev and ST.unlocked("homing"): HOM.press()
	elif (P.mode == "fly" or P.mode == "homing") and home_ev and BL.charging and BL.payload == null: BL.bundle_boom()
	HOM.homing_tick(rdt)
	match P.mode:
		"fly":
			P.fly_update(dt)
			if not held: P.chargeArmed = true
			if held and not BL.charging and P.chargeArmed and BL.can_charge(): BL.start_charge()
			if BL.charging:
				if not held: BL.release_charge()
				else: BL.charge_tick(dt)
			P.try_capture_tunnel()
			HOM.update_lock(rdt)
		"homing": HOM.homing_update(dt)
		"tunnel":
			if tap: BL.strobe_input()
			P.tunnel_update(dt)
		"puzzle": P.fly_update(dt); BL.puzzle_update(rdt, held, evs)
		"loadup": P.fly_update(dt); BL.loadup_update(rdt, held)
		"supercut": BL.supercut_update(dt, rdt, evs)
	BL.position_charge_rings(rdt)
	P.collisions(dt)
	world_update(dt, rdt)
	Coach.update(rdt)
	TUT.update(dt, rdt, evs)
	# thruster trail
	if P.mode == "fly" or P.mode == "tunnel" or P.mode == "homing":
		var n := 3 if P.boost > 15 else 1
		for i in n:
			FX.spawn({"pos": P.pos - P.fwd * 1.6 + P.right * (0.2 if randf() < 0.5 else -0.2), "vel": P.fwd * -6 + U.rand_unit() * 1.5,
				"color": FX.GOLD if P.boost > 15 else FX.PEACH, "size": U.rand(0.35, 0.6) if P.boost > 15 else 0.3, "life": 0.13,
				"shape": U.pick([1, 2]) if P.boost > 25 and randf() < 0.3 else 0, "drag": 2.0})

func title_update(dt: float, rdt: float) -> void:
	time += dt; attract_t += dt
	# autopilot: gentle orbit of the core
	Ctl.steer_x = sin(attract_t * 0.35) * 0.35; Ctl.steer_y = sin(attract_t * 0.21) * 0.5
	P.fly_update(dt); P.collisions(dt)
	P.hull = 100
	world_update(dt, rdt)
	if randf() < 0.6: FX.spawn({"pos": P.pos - P.fwd * 1.6, "vel": P.fwd * -6, "color": FX.PEACH, "size": 0.35, "life": 0.35, "shape": 0})
