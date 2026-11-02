extends Node
## SHIP (port of 20_ship.js): the player state P, flight model, rift tunnel riding, collisions, chase camera,
## and the ship visual with coloured thruster states and shock diamonds.

# ---------- player state (P in the web build) ----------
var pos := Vector3(0, 18, 0)
var fwd := Vector3(0, 0, 1)
var up := Vector3(0, 1, 0)
var right := Vector3(-1, 0, 0)
var speed := 24.0
var base := 24.0
var boost := 0.0
var hull := 100.0
var heat := 0.0
var mode := "fly"
var hTarget := 6.0
var inField = null
var fieldW := 0.0
var lastHurt := -99.0
var hurtCd := 0.0
var stun := 0.0
var invuln := 0.0
var bank := 0.0
var pitchVis := 0.0
var slowT := 0.0
var flameScale := 1.0
var flameTarget := 1.0
var tunnel = null
var tunT := 0.0
var tunDir := 1
var tunOff := Vector2.ZERO
var tunCool := 0.0
var lastTunnel = null
var lastTunnelT := -99.0
var weapon = null
var magnetT := 0.0
var ram := false
var railT := 0.0
var boostHold := 0.0
var strobe = null
var chargeArmed := false
var home = null
var homeFrom := Vector3.ZERO
var homeT := 0.0
var homeDur := 0.0
var homeCd := 0.0
var homeJudge = null
var spin := 0.0
var noGrav := 0.0
var prevBody = null
var glassWarnT := -9.0
var prime = null
var cache = null
var onRailNow := false
## Ace Combat throttle (playtest): 1 while boost is held, eases back to 0 after you let go
var throttle := 0.0
## gravity readouts for the HUD / tests: how hard the strongest body is pulling, and what 'down' is right now
var gpull := 0.0
var gdown := Vector3.DOWN
var sinking := 0.0
var debug_cam := Vector3.ZERO
var debug_state := ""

# ---------- camera ----------
var CAM := {"pos": Vector3(0, 22, -10), "up": Vector3.UP, "fov": 72.0, "trauma": 0.0, "punch": 0.0, "look": Vector3.ZERO}

# ---------- visuals ----------
var ship: Jet
var diamonds: Array = []
var bubble: Node3D
var bubble_mat: ShaderMaterial
var bubble_shapes: Array = []
var bubble_line_mat: StandardMaterial3D
## Thruster states (playtest: "let go of the throttle and the jet slows, thrusters dim; prettier, coloured thrusters").
## Cruise is a dim blue, holding boost a bright cyan, a blast or rift exit burns gold, homing white-cyan, turbo magenta.
var THR := {"c1": Color(0.55, 0.75, 1.15), "c2": Color(0.2, 0.3, 1.0), "vis": 0.7, "dia": 0.0}
const THR_COL := {
	"idle": [Color(0.3, 0.5, 1.3), Color(0.12, 0.2, 1.0), 0.48, 0.0],
	"thrust": [Color(0.3, 1.1, 1.5), Color(0.08, 0.5, 1.4), 1.35, 0.7],
	"boost": [Color(1.35, 1.0, 0.5), Color(1.1, 0.32, 0.08), 1.2, 1.0],
	"home": [Color(1.1, 1.4, 1.5), Color(0.3, 0.9, 1.4), 1.5, 0.8],
	"gold": [Color(1.5, 1.2, 0.55), Color(1.2, 0.55, 0.1), 1.6, 1.0],
	"turbo": [Color(1.5, 0.7, 1.4), Color(0.85, 0.12, 1.0), 1.9, 1.0],
}
var diamond_tex: Texture2D = preload("res://assets/textures/diamond_glow.tres")
var trails: Array[WingTrail] = []
## thin shock rings that ride back down the exhaust (reference: realtime thruster FX, blender.fi 2024)
var shock_rings: Array = []
var ring_cd := 0.0
var ring_side := 0
var spark_acc := 0.0

func setup(root: Node3D) -> void:
	ship = Jet.make(Color.html("#d8262f"), Color(2.2, 1.5, 0.7), Color(1.0, 0.75, 0.35), Color(1.0, 0.25, 0.1), 1.3)
	ship.name = "PlayerShip"
	root.add_child(ship)
	ship.set_pearl(1.0)
	for i in 2:
		var tr := WingTrail.new(); tr.name = "WingTrail%d" % i
		root.add_child(tr); trails.append(tr)
	var ring_mesh := Meshes.torus(1.0, 0.04, 6, 64)
	for i in 10:
		var rm := MeshInstance3D.new(); rm.mesh = ring_mesh
		var mat := Meshes.unshaded(Color(1, 1, 1), true)
		rm.material_override = mat; rm.visible = false
		rm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ship.inner.add_child(rm)
		shock_rings.append({"m": rm, "mat": mat, "t": 9.0, "life": 0.3, "nz": Vector3.ZERO})
	# shock diamonds: bright beads in the exhaust when the engines are really pushing
	for sx in [0.2, -0.2]:
		for k in 3:
			var m := MeshInstance3D.new(); m.mesh = Meshes.quad(1, 1)
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			mat.albedo_texture = diamond_tex
			mat.albedo_color = Color(1, 1, 1, 0)
			m.material_override = mat
			m.position = Vector3(sx, 0, -1.55 - k * 0.42); m.scale = Vector3.ONE * 0.32
			ship.inner.add_child(m)
			diamonds.append({"m": m, "mat": mat, "k": k, "sx": sx})
	_make_bubble()
	bubble.position = Vector3(0, 0, -2.0); bubble.scale = Vector3.ONE * 0.001
	ship.inner.add_child(bubble)

## bubblegum thruster bubble with spinning shapes
func _make_bubble() -> void:
	bubble = Node3D.new()
	var m := MeshInstance3D.new(); m.mesh = Meshes.sphere(1, 32, 20)
	bubble_mat = ShaderMaterial.new(); bubble_mat.shader = preload("res://shaders/bubble.gdshader")
	m.material_override = bubble_mat
	bubble.add_child(m)
	bubble_line_mat = Meshes.unshaded(Color(2.4, 1.9, 0.9), true)
	var tri := PackedVector3Array(); for i in 4: tri.append(Vector3(cos(i / 3.0 * TAU + PI / 2) * 0.22, sin(i / 3.0 * TAU + PI / 2) * 0.22, 0))
	var circ := PackedVector3Array(); for i in 17: circ.append(Vector3(cos(i / 16.0 * TAU) * 0.18, sin(i / 16.0 * TAU) * 0.18, 0))
	var sq := PackedVector3Array(); for p in [[-1, -1], [1, -1], [1, 1], [-1, 1], [-1, -1]]: sq.append(Vector3(p[0] * 0.15, p[1] * 0.15, 0))
	var meshes := [Meshes.line_strip(tri), Meshes.line_strip(circ), Meshes.line_strip(tri), Meshes.line_strip(sq)]
	for i in 12:
		var l := MeshInstance3D.new(); l.mesh = U.pick(meshes); l.material_override = bubble_line_mat
		l.set_meta("ax", U.rand_unit()); l.set_meta("sp", U.rand(2, 6)); l.set_meta("orb", U.rand_unit() * U.rand(0.2, 0.7)); l.set_meta("ph", U.rand(0, TAU))
		bubble.add_child(l); bubble_shapes.append(l)

func reset_player() -> void:
	pos = Vector3(0, World.CORE_R + 6, 0); fwd = Vector3(0, 0, 1); up = Vector3(0, 1, 0); speed = 24; boost = 0; hull = 100; heat = 0
	mode = "fly"; hTarget = 6; stun = 0; invuln = 2; tunnel = null; weapon = null; magnetT = 0; slowT = 0; tunCool = 0; boostHold = 0; strobe = null; chargeArmed = false; flameTarget = 1
	home = null; homeT = 0; homeCd = 0; spin = 0; throttle = 0.0; sinking = 0.0
	for tr in trails: tr.clear()

func ortho() -> void:
	fwd = fwd.normalized()
	right = up.cross(fwd).normalized()           # ship +X axis (left on screen)
	up = fwd.cross(right).normalized()

func hurt(amount: float, why: String = "") -> bool:
	if invuln > 0 or mode in ["supercut", "puzzle", "loadup", "homing"]: return false
	if GAME.state != "play": return false
	REC.ev("hurt", [amount, why]); hull -= amount; lastHurt = GAME.time; ST.style_hit()
	if TUT.active: hull = maxf(25, hull)
	FX.shake(0.35 + amount * 0.02); FX.flash(0.5, 0.05, 0.03); AudioSys.hurt()
	FX.popup("-%d %s" % [amount, why], "#ff6a4a")
	if hull <= 0: hull = 0; GAME.end("HULL BREACHED")
	return true

func fly_update(dt: float) -> void:
	var ctl := 0.0 if stun > 0 else 1.0
	var sx := Ctl.steer_x * ctl
	var sy := Ctl.steer_y * ctl
	# dominant gravity body (Mario-Galaxy style orientation)
	var best = null
	var bw := 0.0
	if noGrav > 0: noGrav -= dt
	else:
		for b in World.bodies():
			var d: float = pos.distance_to(b.pos)
			if d < b.field:
				var w := 1.0 - U.smooth(b.field * 0.62, b.field, d)
				if w > bw: bw = w; best = b
	var escaping := boost > 26 and sy > -0.3
	var gw := bw * (0.18 if escaping else 1.0)
	fieldW = gw; inField = best if gw > 0.05 else null
	throttle = U.damp(throttle, 1.0 if BL.charging else 0.0, 7.0 if BL.charging else 1.6, dt)
	var yaw_rate := 1.95 if mode == "fly" and BL.charging else 2.1
	fwd = fwd.rotated(up, -sx * yaw_rate * dt)
	if best and gw > 0.05:
		var n: Vector3 = (pos - best.pos).normalized()
		up = up.lerp(n, 1.0 - exp(-4.5 * gw * dt)).normalized()
		var alt: float = pos.distance_to(best.pos) - best.r
		if not is_same(prevBody, best): hTarget = clampf(alt, 2.5, best.field - best.r - 3); prevBody = best
		hTarget = clampf(hTarget + sy * 10 * dt, 2.4, best.field - best.r - 2.5)
		pos += n * ((hTarget - alt) * 2.6 * gw * dt)
		var tang := (fwd - n * fwd.dot(n)).normalized()
		fwd = fwd.lerp(tang, 1.0 - exp(-7 * gw * dt)).normalized()
		pitchVis = U.damp(pitchVis, sy * 0.35, 6, dt)
		# free pitch blended in when weak field
		if gw < 0.6:
			var ax := fwd.cross(up).normalized()
			fwd = fwd.rotated(ax, sy * 1.5 * dt * (1 - gw))
	else:
		prevBody = null
		var ax := fwd.cross(up).normalized()
		fwd = fwd.rotated(ax, sy * 1.6 * dt); up = up.rotated(ax, sy * 1.6 * dt)
		pitchVis = U.damp(pitchVis, 0.0, 6, dt)
	# ---- gravity you can feel (playtest): every body pulls, the mini-planets most of all ----
	# Outside a body's field its pull bends your heading toward it, so you can slingshot round the mini-planets;
	# inside the field the orientation code above takes over. Holding the throttle or boosting resists the pull.
	var down := -pos.normalized()            # in open space 'down' is the core
	var pull_max := 0.0
	if noGrav <= 0:
		for b in World.bodies():
			var to: Vector3 = b.pos - pos
			var d := to.length()
			var is_core: bool = b.kind == "core"
			var reach: float = b.field * (2.0 if is_core else 3.2)
			if d > reach or d < 0.01: continue
			var w := 1.0 - U.smooth(b.field * 0.9, reach, d)
			var dirb := to / d
			if d > b.field:
				var gs: float = (0.3 if is_core else 0.85) * w * (0.35 if escaping else 1.0) * (1.0 - throttle * 0.45)
				fwd = (fwd + (dirb - fwd * fwd.dot(dirb)) * gs * dt).normalized()
			if not is_core:
				down = (down + dirb * w * 2.2).normalized()   # near a mini-planet, 'down' leans toward it
				pull_max = maxf(pull_max, w)
	gpull = pull_max; gdown = down
	# slow = heavy: below cruise the jet sinks a little and the nose drops, until you open the throttle again
	var slowness := 1.0 - U.smooth(base * 0.72, base * 1.0, speed)
	sinking = U.damp(sinking, slowness if stun <= 0 else 0.0, 4, dt)
	if sinking > 0.01:
		if best and gw > 0.05:
			hTarget = maxf(2.4, hTarget - 1.8 * sinking * dt)
		else:
			pos += down * (3.4 * sinking * dt)
			var pax := fwd.cross(down)
			if pax.length_squared() > 1e-6: fwd = fwd.rotated(pax.normalized(), 0.24 * sinking * dt)
	ortho()
	bank = U.damp(bank, sx * 0.75, 7, dt)
	# boost: a kick, a short hold, then a smooth ease back to cruise
	if boostHold > 0: boostHold -= dt
	else: boost = maxf(0.0, boost * exp(-1.25 * dt) - 2.2 * dt) # Ace Combat: off the throttle you settle back to cruise in a couple of seconds
	if boost > 85: boost = U.damp(boost, 85.0, 5, dt) # stacked kicks squash toward a ceiling instead of running away
	var slow := 0.55 if slowT > 0 else 1.0
	# a bit of gravity (playtest): climbing away from the core (or a mini-planet you are near) bleeds speed,
	# diving toward it gains some
	var climb := fwd.dot(-gdown)
	var grav := (0.35 if inField else 1.0) * -climb * 9.0
	var target := (base + ST.rank * 2 + GAME.momentum * 0.5) * slow + boost + grav
	speed = U.damp(speed, target, 6.0 if target > speed else 2.5, dt)
	if stun > 0: speed = U.damp(speed, 6.0, 3, dt)
	pos += fwd * speed * dt
	ram = boost > 22

func tunnel_update(dt: float) -> void:
	var tun = tunnel
	var flow := 44.0 + boost * 0.25 # real ride speed (it used to be 74); the walls, hoops and wind fake the rest
	tunT += tunDir * flow * dt / tun.len
	var TF: Dictionary = tun.frame_at(tunT)
	var dl := (right * -Ctl.steer_x + up * Ctl.steer_y) * (8 * dt)
	tunOff.x += dl.dot(TF.N); tunOff.y += dl.dot(TF.B)
	if tunOff.length() > 2.5: tunOff = tunOff.normalized() * 2.5
	pos = TF.p + TF.N * tunOff.x + TF.B * tunOff.y
	fwd = TF.T * tunDir
	up = (up - fwd * up.dot(fwd)).normalized()
	ortho()
	bank = U.damp(bank, Ctl.steer_x * 0.6 + sin(GAME.time * 3) * 0.1, 6, dt)
	speed = U.damp(speed, flow, 5, dt)
	tun.set_active(1.0); tun.set_flow(U.damp(tun.flow, 3.4, 4, dt))
	# fake speed: streaks rushing past close to the walls
	var ua: Vector3 = tun.mat.get_shader_parameter("uA")
	for k in 2:
		var a := U.rand(0, TAU)
		var r := World.TUNNEL_R * U.rand(0.75, 0.98)
		FX.spawn({"pos": pos + fwd * U.rand(6, 22) + TF.N * (cos(a) * r) + TF.B * (sin(a) * r), "vel": fwd * -U.rand(55, 85),
			"color": FX.GOLD if tun.gold else Color(ua.x, ua.y, ua.z), "size": U.rand(0.3, 0.6), "life": 0.35, "shape": 0, "drag": 0.0})
	CAM.trauma = maxf(CAM.trauma, 0.16)
	# exit strobe: appears for the last stretch of the tunnel
	var remain: float = (1.0 - tunT if tunDir > 0 else tunT) * tun.len
	if not strobe.active and remain < 50:
		strobe.active = true
		FX.popup(Ctl.kl("EXIT · TAP E ON THE PULSE", "EXIT · TAP X ON THE PULSE"), "#8fe9ff", true)
		AudioSys.play("ui_warning", {"vol": 0.5, "rate": 1.2, "bus": "ui"})
	if strobe.active:
		var before: float = BL.strobe_r(strobe.t)
		strobe.t += dt / maxf(GAME.ts, 0.05) if GAME.ts > 0 else dt
		# playtest: nobody tapped the exit. Every time the pulse enters the band it pings, so the rhythm is audible
		var tol := 15.0 if TUT.active else 11.0
		var nw: float = BL.strobe_r(strobe.t)
		if not strobe.judged and absf(nw - 60) < tol and absf(before - 60) >= tol: AudioSys.play("lock", {"vol": 0.55, "rate": 1.45, "jit": 0.0})
	if tunT <= 0 or tunT >= 1: exit_tunnel()

func try_capture_tunnel() -> void:
	if tunCool > 0 or mode != "fly" or stun > 0: return
	for tun in World.tunnels:
		if tun.dying or tun.used or tun.open < 0.3: continue
		# the mouth pulls you in when you fly at it (generous, so it never feels like a missed jump)
		var to_mouth: Vector3 = tun.mouth - pos
		var dm := to_mouth.length()
		var nr = null
		if dm < 11 and fwd.dot(tun.mouth_dir) > 0.15 and to_mouth.dot(fwd) > -4: nr = {"d": 0.0, "t": 0.004, "i": 1}
		else:
			var n2: Dictionary = tun.nearest(pos)
			if n2.d < World.TUNNEL_R * 1.1 and absf(fwd.dot(tun.tans[n2.i])) > 0.3 and n2.t < 0.85: nr = n2
		if dm < 40: Coach.hint("tunnel")
		if nr:
			if BL.charging: BL.cancel_charge(false)
			tun.used = true; tun.life = 99
			mode = "tunnel"; tunnel = tun; tunT = nr.t; tunDir = 1; strobe = {"active": false, "t": 0.0, "judged": null}
			ST.gain("tunnel_in", 5); TUT.note("tunnelEnter"); AudioSys.tunnel_enter()
			var TF: Dictionary = tun.frame_at(nr.t)
			var rel: Vector3 = pos - TF.p
			tunOff = Vector2(rel.dot(TF.N), rel.dot(TF.B))
			FX.popup("GOLD RIFT" if tun.gold else "RIFT TUNNEL", "#ffd27a" if tun.gold else "#8fe9ff"); FX.shake(0.2); CAM.punch += 4
			return

func exit_tunnel() -> void:
	var tun = tunnel
	tun.set_active(0.0); tun.set_flow(1.0); tun.collapse()
	mode = "fly"; lastTunnel = tun; lastTunnelT = GAME.time; tunnel = null; tunCool = 1.0
	var perfect: bool = strobe != null and strobe.judged == "perfect"
	strobe = null
	boost += (62.0 if perfect else 40.0) + (12.0 if tun.gold else 0.0); boostHold = 0.9 if perfect else 0.5; hTarget = 8
	if tun.gold: ST.cells = minf(3, ST.cells + 0.5); FX.popup("+½ TURBO CELL", "#ffd27a")
	FX.event_text("PERFECT BLAST!" if perfect else "TUNNEL BLAST!", "gold" if perfect or tun.gold else "cyan")
	ST.gain("tunnel", 35 if perfect else 18); TUT.note("tunnelExit", perfect); HOM.refill(3, "tunnel")
	FX.burst_shapes(pos + fwd * 6, 30, [1, 2], 30)
	FX.shockwave(pos, 14, Color(0.4, 0.9, 1.3), 0.6)
	FX.screen_crash(5, [1, 2, 3])
	FX.doodle_flash(0.6)
	AudioSys.tunnel_exit()
	GAME.add_score(450 if perfect else 250, "PERFECT EXIT" if perfect else "TUNNEL BLAST")

func collisions(dt: float) -> void:
	if mode == "supercut": return
	var list := [World.core]
	list.append_array(World.orbs)
	for b in list:
		if is_same(b, World.core) and not World.core.solid: continue
		if b.kind == "orb" and (not b.alive or b.fade < 0.5): continue
		var d: float = pos.distance_to(b.pos)
		var mn: float = b.r + 1.1
		if b.kind == "orb" and b.get("exposed", 0.0) > 0 and d < b.r + 2.4 and mode == "fly" and not (prime and is_same(prime.t, b)): BL.prime_target(b, "breach")
		if d < mn:
			if b.kind == "orb" and ram and hurtCd <= 0: # boosting into an orb chips its shield instead of hurting you
				Enemies.damage_orb(b, 2, "RAM"); hurtCd = 0.5; FX.shake(0.3)
				var n0: Vector3 = (pos - b.pos).normalized()
				pos = b.pos + n0 * mn; fwd = fwd.bounce(n0).normalized(); ortho()
				continue
			var n: Vector3 = (pos - b.pos).normalized()
			pos = b.pos + n * mn
			var dn := fwd.dot(n)
			if dn < 0: fwd = (fwd - n * dn * 1.6).normalized()
			if hurtCd <= 0: hurt(5, "IMPACT"); hurtCd = 0.5; boost *= 0.5
			ortho()
	# barrier
	var L := pos.length()
	var lim := World.R - 1.4
	World.bar_u("uProx", U.smooth(World.R - 26, World.R - 2, L))
	World.bar_u("uPlayer", pos)
	# playtest: the glass took 148 hull in each run (37 scrapes). Now a soft push steers you back before you touch it,
	# and touching it only hurts while the Iris is actively closing
	var near := U.smooth(World.R - 14, World.R - 2, L)
	if near > 0 and mode == "fly":
		var n := pos.normalized()
		var dn := fwd.dot(n)
		if dn > -0.2: fwd = (fwd - n * ((dn + 0.25) * near * 4.5 * dt)).normalized(); ortho()
		if near > 0.35 and GAME.state == "play" and Ctl.now - glassWarnT > 1.4:
			glassWarnT = Ctl.now; AudioSys.play("ui_warning", {"vol": 0.25 + near * 0.3, "rate": 1.4, "bus": "ui"}); Coach.hint("barrier")
	if L > lim:
		var n := pos.normalized()
		pos = n * lim
		var dn := fwd.dot(n)
		if dn > 0: fwd = (fwd - n * dn * 1.8).normalized()
		ortho()
		if hurtCd <= 0:
			World.barrier_impact(n * World.R, GAME.utime); hurtCd = 0.4; boost *= 0.7
			FX.burst_shapes(pos, 20, [0, 5], 12, Color(0.6, 1.5, 2))
			if not TUT.active and ST.IRIS.state == "close": hurt(3, "IRIS")
			else: AudioSys.play("shatter", {"vol": 0.35, "rate": 1.3}); FX.shake(0.2); REC.ev("glass")

# ---------- camera ----------
func update_camera(rdt: float, gdt: float) -> void:
	var cam: Camera3D = GAME.camera
	var sf := clampf((speed - 24) / 90, 0, 1)
	var dist := 7.6 + sf * 2.8
	var height := 2.9
	match mode:
		"puzzle": dist = 5.5; height = 1.6
		"loadup": dist = 6.2; height = 1.4
		"supercut": dist = 9.5; height = 2.6
		"homing": dist = 8.4; height = 2.4
		"tunnel": dist = 6.8; height = 1.6
	var t := pos - fwd * dist + up * height
	var k := maxf(gdt, rdt * 0.3)
	CAM.pos = CAM.pos.lerp(t, 1.0 - exp(-9 * k))
	CAM.up = CAM.up.lerp(up, 1.0 - exp(-5 * k)).normalized()
	CAM.look = CAM.look.lerp(pos + fwd * 9 + up * 0.9, 1.0 - exp(-14 * k))
	CAM.trauma = maxf(0.0, CAM.trauma - rdt * 1.5)
	var sh: float = CAM.trauma * CAM.trauma
	var cp: Vector3 = CAM.pos
	var cu: Vector3 = CAM.up
	if sh > 0:
		var n := Ctl.now * 31
		cp += right * ((sin(n * 1.7) + sin(n * 2.9)) * sh * 0.5) + up * ((sin(n * 2.3) + cos(n * 3.1)) * sh * 0.5)
		cu = cu.rotated(fwd, sin(Ctl.now * 40) * sh * 0.05)
	if debug_cam != Vector3.ZERO: # test hook: a fixed offset in ship space for thruster close-ups
		cp = pos + right * debug_cam.x + up * debug_cam.y + fwd * debug_cam.z; CAM.look = pos - fwd * 1.5; cu = up
	cam.global_position = cp
	if cp.distance_to(CAM.look) > 0.01: cam.look_at(CAM.look, cu)
	CAM.punch = U.damp(CAM.punch, 0.0, 4, rdt)
	var fov: float = 70 + sf * 26 + CAM.punch
	if mode == "puzzle": fov = 58
	if mode == "tunnel": fov += 12 + sin(Ctl.now * 9) * 1.5
	if mode == "homing": fov += 8
	CAM.fov = U.damp(CAM.fov, fov, 6, rdt)
	cam.fov = CAM.fov
	GAME.sky.global_position = cp

func update_ship_visual(rdt: float, _gdt: float) -> void:
	ship.basis = Basis(right, up, fwd); ship.position = pos
	ship.scale = Vector3.ONE * 1.3
	var tumble := GAME.time * 14 if stun > 0 else 0.0
	spin = spin + rdt * 22 if mode == "homing" else U.damp(spin, roundf(spin / TAU) * TAU, 10, rdt)
	ship.inner.rotation = Vector3(-pitchVis, 0, bank + tumble + spin)
	flameScale = U.damp(flameScale, flameTarget, 10, rdt)
	# throttle state -> colour and size of the exhaust
	var turboing: bool = mode == "supercut" or mode == "loadup" or (mode == "puzzle" and BL.puzzle and BL.puzzle.ctx == "turbo") or BL.forgeRing != null
	var st := "turbo" if turboing else ("gold" if homeJudge == "perfect" else "home") if mode == "homing" else ("thrust" if BL.charging else ("boost" if boost > 18 or mode == "tunnel" else "idle"))
	if debug_state != "": st = debug_state # test hook for look-dev shots
	var T: Array = THR_COL[st]
	var k := 1.0 - exp(-9 * rdt)
	THR.c1 = THR.c1.lerp(T[0], k); THR.c2 = THR.c2.lerp(T[1], k)
	# let go of the throttle: the flame shrinks and dims over about a second instead of snapping off
	THR.vis = U.damp(THR.vis, T[2] + (minf(boost / 70, 1) * 0.7 if st == "boost" else 0.0) + throttle * 0.25, 2.2 if st == "idle" else 10.0, rdt)
	THR.dia = U.damp(THR.dia, T[3], 8, rdt)
	# tint the hot core too, so the colour reads through the glow
	ship.set_flame_colors(THR.c1, THR.c2, Color(1, 1, 1).lerp(THR.c1, 0.6), THR.c1)
	var fs: float = flameScale * THR.vis
	var fl: float = fs * (0.7 + clampf(speed / 60, 0, 1.6) * 0.6)
	# flames come in threes per nozzle: sheath, jet, needle (see thruster.gdshader)
	for i in ship.flames.size():
		var f: MeshInstance3D = ship.flames[i]
		var layer := i % 3
		var wr := (0.9 + fs * 0.12) if layer == 2 else (0.9 + fs * 0.25) * minf(2.2, 0.8 + fs * 0.35)
		var ln: float = (0.35 + fl) * [2.1, 1.1, 2.3][layer] * (0.97 + randf() * 0.06)
		f.scale = Vector3(wr, wr, maxf(0.001, ln))
	# one 'throttle slider' drives the whole plume: brightness, tendril reach, rings and sparks
	var thr_pow := clampf(fs * 0.62, 0.18, 1.05)
	ship.set_flame_pow(thr_pow, thr_pow)
	_update_shock_rings(rdt, thr_pow, fl, st)
	# heat haze grows with the throttle and fades as you ease off
	var haze := clampf(0.15 + throttle * 0.7 + minf(boost / 60.0, 1.0) * 0.45 + (0.5 if st == "turbo" else 0.0), 0.0, 1.3) * minf(1.0, THR.vis)
	_update_haze(haze, fl)
	_update_trails(st)
	for d in diamonds:
		var flick := 0.75 + 0.25 * sin(Ctl.now * 70 + d.k * 2.1 + d.sx * 9)
		var c: Color = THR.c1 * 0.55
		c.a = clampf(THR.dia * flick * (1 - d.k * 0.25) * 0.7, 0, 1)
		d.mat.albedo_color = Color(c.r, c.g, c.b).linear_to_srgb()
		d.mat.albedo_color.a = c.a
		d.m.position.z = -1.45 - d.k * (0.32 + fl * 0.12)
		d.m.scale = Vector3.ONE * (0.26 - d.k * 0.05) * (0.8 + THR.dia * 0.4)
	ship.visible = not (invuln > 0 and GAME.state == "play" and int(floor(Ctl.now * 16)) % 2 == 0 and mode == "fly" and invuln < 1.95)

## wingtip vapour trails: bloom with speed and hard turns, in the thruster colour
func _update_trails(st: String) -> void:
	var cam: Camera3D = GAME.camera
	var fast := clampf((speed - base * 1.15) / 45.0, 0.0, 1.0)
	var turn := clampf(absf(bank) / 0.75, 0.0, 1.0) * clampf(speed / 40.0, 0.0, 1.0)
	var it := clampf(fast * 0.85 + turn * 0.55 + throttle * 0.2, 0.0, 1.0)
	if st == "turbo" or mode == "homing": it = maxf(it, 0.7)
	if mode == "tunnel": it *= 0.5
	if mode in ["puzzle", "loadup", "supercut"]: it = 0.0   # the camera sits too close for trails to read
	if not ship.visible or GAME.state != "play": it = 0.0
	for i in trails.size():
		trails[i].set_color(THR.c1, 1.0)
		trails[i].push(ship.wingtip_world(i), it, Ctl.now, cam.global_position)

## heat haze: project each exhaust plume to a screen-space segment for the lens shader to refract along
func _update_haze(amt: float, flame_len: float) -> void:
	var cam: Camera3D = GAME.camera
	var vs := cam.get_viewport().get_visible_rect().size
	var segs := []
	for i in 2:
		var a: Vector3 = ship.nozzle_world(i)
		var b: Vector3 = a - fwd * (0.9 + flame_len * 1.5) * 1.3
		if cam.is_position_behind(a) or cam.is_position_behind(b):
			segs.append(Vector4(-9, -9, -9, -9)); continue
		var sa := cam.unproject_position(a) / vs
		var sb := cam.unproject_position(b) / vs
		segs.append(Vector4(sa.x, sa.y, sb.x, sb.y))
	# plume width on screen: a fixed world width seen from the current distance
	var d := maxf(1.0, cam.global_position.distance_to(pos))
	var w := clampf(0.55 / (d * tan(deg_to_rad(cam.fov) * 0.5)) * 0.5, 0.006, 0.08)
	GAME.lens.set_shader_parameter("uHazeSeg", segs)
	GAME.lens.set_shader_parameter("uHazeAmt", amt if mode != "puzzle" else 0.0)
	GAME.lens.set_shader_parameter("uHazeW", w)

## shock rings and sparks: spawn faster the harder the engines push; none at idle cruise
func _update_shock_rings(rdt: float, thr_pow: float, flame_len: float, st: String) -> void:
	var drive := clampf((thr_pow - 0.35) / 0.8, 0.0, 1.0)
	if st == "turbo" or st == "gold": drive = maxf(drive, 0.9)
	if mode == "puzzle" or not ship.visible or GAME.state != "play": drive = 0.0
	ring_cd -= rdt
	if drive > 0.05 and ring_cd <= 0.0:
		ring_cd = lerpf(0.2, 0.06, drive)
		for r in shock_rings:
			if r.t >= r.life:
				r.t = 0.0; r.life = lerpf(0.26, 0.38, drive)
				r.nz = ship.nozzles[ring_side % ship.nozzles.size()]; ring_side += 1
				r.m.visible = true
				break
	for r in shock_rings:
		if r.t >= r.life:
			r.m.visible = false
			continue
		r.t += rdt
		var k: float = clampf(r.t / r.life, 0.0, 1.0)
		var m: MeshInstance3D = r.m
		var rad := 0.13 + k * 0.22
		m.position = r.nz + Vector3(0, 0, -0.2 - k * (0.6 + flame_len * 1.9))
		m.scale = Vector3(rad, rad, rad)
		var c: Color = THR.c1.lerp(Color(1.3, 1.3, 1.3), 0.45) * (1.6 * (1.0 - k * k * k))  # crisp until the very end
		r.mat.albedo_color = Color(c.r, c.g, c.b).linear_to_srgb()
	# sparks shed from the jets, drifting back past the camera
	spark_acc += drive * rdt * 70.0
	while spark_acc >= 1.0:
		spark_acc -= 1.0
		var nz: Vector3 = ship.nozzle_world(randi() % ship.nozzles.size())
		FX.spawn({"pos": nz - fwd * U.rand(0.2, 1.2), "vel": fwd * (speed - U.rand(28, 46)) + U.rand_unit() * 1.6,
			"color": THR.c1 * 1.3, "size": U.rand(0.14, 0.3), "life": U.rand(0.18, 0.32), "shape": 0, "drag": 0.0})
