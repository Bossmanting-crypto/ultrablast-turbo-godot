extends Node
## Scripted playthroughs for headless / virtual-display testing. Launch with:
##   godot --path . -- --test --scenario=<name> [--shots=<dir>] [--frames=<n>]
## Scenarios: title, run, tutorial, puzzle, supercut, turrets. Prints one status line per second and
## "AUTOTEST DONE errors=<n>" at the end; screenshots land in --shots as PNG.

var scenario := "title"
var shots := ""
var max_frames := 600
var f := 0
var log_t := 0.0
var notes: Array = []

func _ready() -> void:
	process_priority = 100
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scenario="): scenario = a.split("=")[1]
		if a.begins_with("--shots="): shots = a.split("=")[1]
		if a.begins_with("--frames="): max_frames = int(a.split("=")[1])
	if shots != "": DirAccess.make_dir_recursive_absolute(shots)
	GAME.fixed_dt = 1.0 / 30.0
	print("AUTOTEST start scenario=", scenario)

func shot(name: String) -> void:
	if shots == "": return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [shots, name])
	print("AUTOTEST shot ", name)

func status() -> String:
	return "f=%d state=%s mode=%s t=%.1f score=%d rank=%s hull=%d speed=%d lock=%s chain=%d charges=%.1f rings=%d tut=%s" % [
		f, GAME.state, P.mode, GAME.time, GAME.score, ST.RANKS[ST.rank].l, P.hull, P.speed * 9.5,
		HOM.lock.kind if HOM.lock else "-", HOM.chain, HOM.charges, BL.rings, TUT.step_id() if TUT.active else "-"]

## steer toward the current lock or the nearest lockable ahead
func autopilot(press_every := 12) -> void:
	var best = null
	var bd := 1e9
	for item in HOM.lockables():
		var t: Dictionary = item[0]
		var tp: Vector3 = HOM.target_pos(t)
		var d := tp.distance_to(P.pos)
		if d < bd and d > 3: bd = d; best = tp
	if best != null:
		var to: Vector3 = (best - P.pos).normalized()
		var sx := clampf(-to.dot(P.right) * 3.0, -1, 1)
		var sy := clampf(to.dot(P.up) * 3.0, -1, 1)
		Ctl.test_steer = Vector2(sx, sy)
	else: Ctl.test_steer = Vector2(0.2, 0)
	if HOM.lock and f % press_every == 0: Ctl.events.append({"t": "home", "aim": false, "pad": false})

func _process(_d: float) -> void:
	f += 1
	match scenario:
		"title": _title()
		"run": _run()
		"tutorial": _tutorial()
		"puzzle": _puzzle()
		"supercut": _supercut()
		"turrets": _turrets()
		"ab": _ab()
		"thrusters": _thrusters()
		"fxlab": _fxlab()
		"iso": _iso()
	log_t += 1
	if int(log_t) % 30 == 0: print("AUTOTEST ", status())
	if f >= max_frames: _finish()

func _finish() -> void:
	print("AUTOTEST ", status())
	for n in notes: print("AUTOTEST note ", n)
	print("AUTOTEST DONE")
	get_tree().quit()

func _title() -> void:
	if f == 60: shot("title")

func _run() -> void:
	if f == 30: shot("title")
	if f == 40: GAME.start_game()
	if f > 40 and GAME.state == "play":
		autopilot()
		# hold boost in bursts to exercise rings and blasts
		Ctl.test_hold = (f / 45) % 3 == 1
	if f == 120: shot("run_early")
	if f == 260: shot("run_mid")
	if f == 300: GAME.time = 88.0 # jump to THE IRIS: core turrets, superblasts, iris warning
	if f == 420: shot("run_iris")
	if f == 560: shot("run_late")

func _tutorial() -> void:
	if f == 20: TUT.start()
	if not TUT.active: return
	autopilot(10)
	# every 40 frames, satisfy the current step directly so each step's setup/update/render runs
	if f % 40 == 0:
		var id := TUT.step_id()
		shot("tut_%02d_%s" % [TUT.i, id])
		if TUT.passed: Ctl.events.append({"t": "next"})
		else: Ctl.events.append({"t": "skip"})

func _puzzle() -> void:
	if f == 20: GAME.start_game()
	if f == 40:
		var c: Dictionary = HOM.caches[0]
		TUT.place_at_cache(); ST.UNLOCK["cache"] = true
		BL.prime_target(c, "cache")
	if f == 50: Ctl.test_hold = true
	if f == 70: shot("puzzle_cache")
	if f == 80 and BL.puzzle: BL.puzzle_success()
	if f == 90: shot("payload_armed")
	if f == 95: Ctl.test_hold = false
	if f == 110: shot("payload_fired")
	if f == 130:
		var o: Dictionary = World.orbs[0]
		TUT.place_at_orb(); o.hp = 0; o.exposed = 12.0
		BL.prime_target(o, "breach")
	if f == 140: Ctl.test_hold = true
	if f == 160: shot("puzzle_glyph")
	if f == 200: notes.append("glyph puzzle active=%s" % (BL.puzzle != null))

func _supercut() -> void:
	if f == 20: GAME.start_game()
	if f == 40: ST.rank = 2; ST.cells = 2; ST.turboCd = 0; Ctl.test_hold = true
	if f == 70: shot("turbo_forge")
	if f > 70 and P.mode == "puzzle" and f % 3 == 0 and BL.puzzle and BL.puzzle.inZone: Ctl.events.append({"t": "home"})
	if f == 80: shot("turbo_align")
	if P.mode == "loadup" and BL.loadup and BL.loadup.t > (BL.loadup.w0 + BL.loadup.w1) / 2: Ctl.test_hold = false
	if P.mode == "supercut":
		Ctl.test_hold = false
		if BL.sc and BL.sc.target and BL.sc.tta < 0.1 and not BL.sc.pressed: Ctl.events.append({"t": "home"})
		if f % 25 == 0: shot("supercut_%d" % f)
	if f == 300: notes.append("bestChain=%d maxLevel=%d" % [GAME.bestChain, GAME.maxLevel])

func _turrets() -> void:
	if f == 20: GAME.start_game()
	if f == 30: GAME.time = 90.0; P.invuln = 999
	if f > 30:
		Ctl.test_steer = Vector2(0.3, 0.1)
		P.hull = 100
	if f == 120: shot("turrets_a")
	if f == 200: shot("turrets_b")
	if f % 60 == 0: notes.append("aiming=%d" % Threats.TUR.aiming)

func _ab() -> void:
	if f == 20: GAME.start_game()
	if f > 20: Ctl.test_steer = Vector2(0.1, 0.0); P.invuln = 99
	if f == 60: shot("ab_barrier_on")
	if f == 61: World.barrier.visible = false
	if f == 64: shot("ab_barrier_off")
	if f == 65: World.barrier.visible = true; GAME.env.glow_enabled = false
	if f == 68: shot("ab_glow_off")

## throttle feel, thruster colours, haze, trails, mini-planet gravity and the slow sink
func _thrusters() -> void:
	if f == 20: GAME.start_game()
	if f < 30: return
	P.invuln = 99; P.hull = 100
	if f == 30: notes.append("cruise speed=%.1f vis=%.2f" % [P.speed, P.THR.vis])
	if f >= 40 and f < 100: Ctl.test_hold = true; Ctl.test_steer = Vector2(0, 0)
	if f == 70: P.debug_cam = Vector3(2.4, 0.8, -2.4)
	if f == 76: shot("thr_close_thrust")
	if f == 78: P.debug_cam = Vector3.ZERO
	if f == 80: shot("thr_thrust"); notes.append("thrust speed=%.1f vis=%.2f throttle=%.2f" % [P.speed, P.THR.vis, P.throttle])
	if f == 100: Ctl.test_hold = false
	if f == 106: shot("thr_release")
	if f == 115: notes.append("release+0.5s speed=%.1f vis=%.2f throttle=%.2f" % [P.speed, P.THR.vis, P.throttle])
	if f == 145: notes.append("release+1.5s speed=%.1f vis=%.2f throttle=%.2f" % [P.speed, P.THR.vis, P.throttle])
	if f >= 150 and f < 200: Ctl.test_steer = Vector2(1, 0.2); P.boost = 50.0
	if f == 185: shot("thr_trails_turn")
	if f == 200:
		Ctl.test_steer = Vector2(0, 0); P.boost = 0
		ST.rank = 2; ST.cells = 2; ST.turboCd = 0; Ctl.test_hold = true
	if f == 225: P.debug_cam = Vector3(2.4, 0.8, -2.4)
	if f == 231: shot("thr_close_turbo")
	if f == 233: P.debug_cam = Vector3.ZERO
	if f == 235: shot("thr_turbo")
	if f == 30: P.debug_cam = Vector3(2.4, 0.8, -2.4)
	if f == 36: shot("thr_close_cruise")
	if f == 38: P.debug_cam = Vector3.ZERO
	if f == 260:
		Ctl.test_hold = false; BL.cancel_charge(false)
		if P.mode != "fly": P.mode = "fly"
		# gravity: park beside a mini-planet just outside its field, flying past it
		var o: Dictionary = World.orbs[0]
		var side: Vector3 = (o.pos.cross(Vector3.UP)).normalized()
		P.pos = o.pos + side * (o.field + 9.0); P.fwd = (o.pos - Vector3.ZERO).normalized().cross(side).normalized()
		P.up = side; P.ortho(); P.boost = 0; P.speed = 24
		set_meta("toward", -side); set_meta("g0", -side.dot(P.fwd))
	if f > 260 and f < 320: Ctl.test_steer = Vector2(0, 0)
	if f == 290: shot("thr_gravity")
	if f == 320:
		var o: Dictionary = World.orbs[0]
		notes.append("gravity: heading bent toward the mini-planet %.2f -> %.2f, now %.1f from its centre (field %.0f)" % [get_meta("g0"), (get_meta("toward") as Vector3).dot(P.fwd), P.pos.distance_to(o.pos), o.field])
		# slow sink: open space, well below cruise
		P.pos = Vector3(0, 60, 0); P.fwd = Vector3(1, 0, 0); P.up = Vector3(0, 1, 0); P.ortho(); P.slowT = 3.0; P.speed = 12
		set_meta("h0", P.pos.length())
	if f == 360: notes.append("slow sink: radius %.1f -> %.1f in 1.3s, sinking=%.2f speed=%.1f" % [get_meta("h0"), P.pos.length(), P.sinking, P.speed])

## isolate what makes the light at the nozzles (debug)
func _iso() -> void:
	if f == 20: GAME.start_game()
	if f < 30: return
	P.invuln = 99; P.debug_cam = Vector3(2.4, 0.8, -2.4)
	if f == 40: shot("iso_all")
	if f == 41:
		for fl in P.ship.flames: fl.visible = false
	if f == 44: shot("iso_noflames")
	if f == 45:
		for d in P.diamonds: d.m.visible = false
		P.bubble.visible = false
	if f == 48: shot("iso_nodiamonds")
	if f == 49:
		for c in P.ship.inner.get_children(): if c is MeshInstance3D: c.visible = false
	if f == 52: shot("iso_noship")

## look-dev bench for the exhaust, set up like the Blender reference: grey void, side camera, one throttle sweep
func _fxlab() -> void:
	if f == 20:
		GAME.start_game()
	if f < 26: return
	P.invuln = 99; P.hull = 100; P.stun = 0
	if f == 26:
		GAME.sky.visible = false
		GAME.env.background_color = Color(0.16, 0.16, 0.18)
		GAME.env.glow_hdr_threshold = 0.9
		for c in GAME.root3d.get_children():
			if c != P.ship and not (c is WingTrail) and c.name != "FX": c.visible = false
		for n in ["HudLayer", "FxLayer", "DoodleLayer", "ScreenLayer"]:
			var l = GAME.main.get_node_or_null(n)
			if l: l.visible = false
		P.debug_cam = Vector3(5.5, 1.4, -1.2)
	Ctl.test_steer = Vector2.ZERO
	var plan := [[30, "idle", false], [70, "thrust", true], [110, "release", false]]
	if f == 36: shot("lab_cruise")
	if f >= 50 and f < 100: Ctl.test_hold = true
	if f == 76: shot("lab_thrust_a")
	if f == 82: shot("lab_thrust_b")
	if f == 100: Ctl.test_hold = false; BL.cancel_charge(false)
	if f == 112: shot("lab_release")
	if f == 115: Ctl.test_hold = true
	if f == 120: P.debug_state = "gold"
	if f == 132: shot("lab_gold")
	if f == 133: P.debug_state = "turbo"
	if f == 145: shot("lab_turbo")
	if f == 146: P.debug_state = "home"
	if f == 158: shot("lab_home")
	if f == 159: P.debug_state = ""; Ctl.test_hold = false
