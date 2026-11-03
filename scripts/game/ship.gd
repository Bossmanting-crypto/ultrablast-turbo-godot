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
	pos = Vector3(0, World.CORE_R + 24, 0); fwd = Vector3(0, 0, 1); up = Vector3(0, 1, 0); speed = 24; boost = 0; hull = 100; heat = 0
	mode = "fly"; hTarget = 6; stun = 0; invuln = 2; tunnel = null; weapon = null; magnetT = 0; slowT = 0; tunCool = 0; boostHold = 0; strobe = null; chargeArmed = false; flameTarget = 1
	home = null; homeT = 0; homeCd = 0; spin = 0; throttle = 0.0; sinking = 0.0
	vel = Vector3(0, 0, 24); yawV = 0; pitchV = 0; gspd = 0; eng = 24; fuel = 100; lit = true; ride = null; rideVr = 0; rideCd = 2.5; noGrav = 0; escFrom = null
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

# =================== FLIGHT v5 (playtest: "good gravity on the mini-planets so I can ride them to refuel till
# escape velocity; it flies itself when I leave the controls; pitch and yaw too restricted; when fuel runs out it falls")
# Same model as the web build's src/20_ship.js:
# - Velocity is a real vector that swings onto the nose with some grip, so hard turns drift a little.
# - Gravity is real acceleration from the core (1/d^1.5, felt everywhere) and every mini-planet (1/d^2). With the
#   engine lit you barely sag; with no fuel (or stalled) you fall and the nose weathervanes into the fall.
# - Near a surface you ride it: hover height on a spring, yaw free, refuel fast. Pull up past escape speed (or fire
#   a blast) to break away; below escape speed you only rise a little and gravity settles you back down.
# - Free pitch and yaw with a little angular inertia. Nothing steers for you in open space.
const FLIGHT := {
	"yawMax": 2.7, "pitchMax": 2.5, "angK": 9.0, "grip": 5.5,
	"gmCore": 3900.0, "gmOrb": 5200.0, "sagLit": 0.3,
	"rideAlt": 3.0, "rideMax": 12.0, "vEscOrb": 36.0, "vEscCore": 42.0,
	"fuelCruise": 0.9, "fuelThrust": 9.0, "fuelDash": 5.0, "refuelOrb": 28.0, "refuelCore": 14.0, "hardLanding": 18.0,
}
var SIM := false   # true while predict_path replays the flight model: no effects, no fuel
var vel := Vector3(0, 0, 24)
var grav := Vector3.ZERO
var yawV := 0.0
var pitchV := 0.0
var gspd := 0.0
var eng := 24.0
var fuel := 100.0
var lit := true
var ride = null
var rideH := 3.0
var rideVr := 0.0
var rideCd := 0.0
var rideBlastT := 0.0
var escFrom = null
var escT := 0.0
var fuelWarnT := 0.0
var velSync := false

## summed gravity acceleration at p; returns [acceleration, dominant body]
func gravity_at(p: Vector3) -> Array:
	var out := Vector3.ZERO
	var best = null
	var best_s := 0.0
	for b in World.bodies():
		var to: Vector3 = b.pos - p
		var d := maxf(to.length(), b.r + 0.5)
		var is_core: bool = b.kind == "core"
		var a: float = FLIGHT.gmCore / (d * sqrt(d)) if is_core else FLIGHT.gmOrb / (d * d)
		if not is_core and World.core.gravity: a *= 1.0 - U.smooth(b.field * 2.2, b.field * 3.4, d)   # wells end ~55 m out (everywhere once the core phases out)
		if a <= 0: continue
		out += to.normalized() * a
		var score := a if is_core else a * 2.5   # near a mini-planet, it is the body you are flying around
		if score > best_s: best_s = score; best = b
	return [out, best]

func v_esc_for(b) -> float:
	return FLIGHT.vEscCore if b and b.kind == "core" else FLIGHT.vEscOrb

func use_fuel(n: float) -> void:
	if SIM or GAME.state != "play" or (TUT.active and fuel <= 35): return
	fuel = maxf(0.0, fuel - n)

## after anything else moved or re-aimed the ship (homing, tunnels, supercut, bounces, placement)
func sync_vel() -> void:
	vel = fwd * speed; eng = speed; gspd = 0.0; velSync = false

func start_ride(b) -> void:
	ride = b; rideVr = 0.0; rideH = clampf(pos.distance_to(b.pos) - b.r, 1.8, FLIGHT.rideMax)
	if SIM: return
	REC.ev("ride", b.kind); TUT.note("ride", b.kind); Coach.hint("ride")
	FX.popup("RIDING · REFUELLING" if fuel < 99 else "RIDING", "#dce9a9"); AudioSys.play("match_boost", {"vol": 0.35, "rate": 0.8})

func escape_ride(via_blast: bool) -> void:
	var b = ride
	if b == null: return
	var n: Vector3 = (pos - b.pos).normalized()
	vel += n * 16.0; fwd = (fwd + n * 0.55).normalized(); ortho()
	ride = null; rideCd = 1.4; escFrom = b; escT = 6.0   # no re-capture by this body until you have left its well
	if SIM: return
	REC.ev("escape", [b.kind, snappedf(speed, 0.1), 1 if via_blast else 0]); TUT.note("escape", b.kind)
	FX.event_text("ESCAPE VELOCITY!", "cyan"); FX.shockwave(pos, 10, Color(0.7, 1.6, 0.6), 0.5); FX.shake(0.25); CAM.punch += 5
	AudioSys.play("tunnel_exit", {"vol": 0.6}); ST.gain("escape", 12); boost += 14; boostHold = maxf(boostHold, 0.4)

func fly_update(dt: float) -> void:
	if velSync: sync_vel()
	var ctl := 0.0 if stun > 0 else 1.0
	var sx := Ctl.steer_x * ctl
	var sy := Ctl.steer_y * ctl
	if rideCd > 0: rideCd -= dt
	if noGrav > 0: noGrav -= dt
	throttle = U.damp(throttle, 1.0 if BL.charging and fuel > 0 else 0.0, 7.0 if BL.charging else 1.6, dt)
	# ---- fuel: cruise sips it, thrust burns it; empty = the engine cuts out ----
	if mode == "fly" and ride == null: use_fuel((FLIGHT.fuelCruise + (FLIGHT.fuelThrust if BL.charging else 0.0)) * dt)
	var is_lit: bool = fuel > 0 or TUT.active
	if not SIM and is_lit != lit:
		lit = is_lit
		if not lit:
			FX.event_text("FUEL EMPTY", "red"); FX.popup("ENGINE OUT · GLIDE ONTO A PLANET TO REFUEL", "#ff6a4a", true)
			AudioSys.play("fizzle", {"vol": 0.7}); REC.ev("fuelOut"); Coach.hint("fuel")
		elif ride != null: FX.popup("ENGINE RELIT", "#dce9a9")
	if not SIM and is_lit and fuel < 25 and fuel > 0 and Ctl.now - fuelWarnT > 6:
		fuelWarnT = Ctl.now; FX.popup("LOW FUEL · RIDE A PLANET TO REFUEL", "#ffd27a"); AudioSys.play("ui_warning", {"vol": 0.35, "bus": "ui"}); Coach.hint("fuel")
	# ---- gravity ----
	var dom = null
	if noGrav > 0: grav = Vector3.ZERO
	else:
		var gr := gravity_at(pos); grav = gr[0]; dom = gr[1]
	gdown = grav.normalized() if grav.length_squared() > 1e-6 else -pos.normalized()
	gpull = grav.length()
	if escFrom != null:
		escT -= dt
		if escT <= 0 or pos.distance_to(escFrom.pos) > escFrom.field * 2.2: escFrom = null
	# ---- ride: capture onto a surface ----
	if ride == null and rideCd <= 0 and mode == "fly" and dom != null and noGrav <= 0 and not is_same(dom, escFrom):
		var n0: Vector3 = pos - dom.pos
		var d0 := n0.length(); n0 /= d0
		var alt0: float = d0 - dom.r
		var vr0 := vel.dot(n0)
		if alt0 < FLIGHT.rideMax and vr0 < 6:
			if vr0 < -FLIGHT.hardLanding and not SIM and not TUT.active:
				hurt(roundf(clampf((-vr0 - FLIGHT.hardLanding) * 0.6 + 4, 4, 15)), "HARD LANDING"); FX.shake(0.4)
			start_ride(dom)
	# ---- turning: free pitch and yaw with a little inertia ----
	var yaw_max: float = FLIGHT.yawMax * (0.9 if BL.charging else 1.0) * (1.0 if is_lit else 0.75)
	var pitch_max: float = FLIGHT.pitchMax * (1.0 if is_lit else 0.75)
	yawV = U.damp(yawV, sx * yaw_max, FLIGHT.angK, dt)
	fwd = fwd.rotated(up, -yawV * dt)
	bank = U.damp(bank, clampf(yawV / yaw_max, -1, 1) * 0.85, 7, dt)
	if ride != null and ride.kind == "orb" and (not ride.alive or ride.fade < 0.5):
		ride = null; rideCd = 0.8
	if ride != null:
		# ---- riding: hover on the surface, yaw free, the stick sets your height; escape needs the speed ----
		var b = ride
		var n: Vector3 = pos - b.pos
		var d := n.length(); n /= d
		var alt: float = d - b.r
		var v_esc := v_esc_for(b)
		var can_escape := speed >= v_esc
		rideH = clampf(rideH + sy * 7 * dt, 1.8, FLIGHT.rideMax + (4.0 if can_escape else 1.5))
		if sy < 0.1 and not can_escape: rideH = U.damp(rideH, FLIGHT.rideAlt, 0.8, dt)   # below escape speed gravity settles you back down
		rideVr += ((rideH - alt) * 30.0 - rideVr * 8.0) * dt
		pos += n * (rideVr * dt)
		up = up.lerp(n, 1.0 - exp(-8 * dt)).normalized()
		fwd = (fwd - n * fwd.dot(n)).normalized()
		pitchV = U.damp(pitchV, 0.0, 8, dt); pitchVis = U.damp(pitchVis, sy * 0.35, 6, dt)
		if not SIM:
			fuel = minf(100.0, fuel + (FLIGHT.refuelCore if b.kind == "core" else FLIGHT.refuelOrb) * dt)
			if randf() < dt * 30:
				FX.spawn({"pos": b.pos + (U.rand_unit() + n * 2.2).normalized() * b.r, "vel": (pos - b.pos).normalized() * U.rand(8, 14),
					"color": FX.LIME, "size": U.rand(0.2, 0.4), "life": 0.45, "shape": 5 if randf() < 0.3 else 0, "drag": 0.0})
		if rideBlastT > 0: rideBlastT -= dt
		if can_escape and rideBlastT > 0: escape_ride(true)                              # a blast off the surface launches you
		elif can_escape and sy > 0.35 and alt > FLIGHT.rideMax - 0.5: escape_ride(false) # or pull up past the ride zone
		elif alt > FLIGHT.rideMax + 5: ride = null; rideCd = 0.6                        # knocked off (dash, kick)
	else:
		pitchV = U.damp(pitchV, sy * pitch_max, FLIGHT.angK, dt)
		var ax := fwd.cross(up).normalized()
		fwd = fwd.rotated(ax, pitchV * dt); up = up.rotated(ax, pitchV * dt)
		pitchVis = U.damp(pitchVis, 0.0, 6, dt)
		# roll gently back toward level (away from whatever pulls you). Heading is untouched.
		if absf(sy) < 0.2 and gpull > 0.3:
			var want := -gdown
			want -= fwd * want.dot(fwd)
			if want.length_squared() > 1e-4: up = up.lerp(want.normalized(), 1.0 - exp(-0.7 * dt)).normalized()
	# close to a mini-planet (or low over the core) its gravity bends your path toward it, so a pass curves into it
	# and you can drop into a ride. In open space nothing bends the nose while the engine is lit.
	if ride == null and is_lit and dom != null and mode == "fly":
		var dd: float = pos.distance_to(dom.pos)
		if dom.kind == "orb" or dd < 45:
			var gp := grav - fwd * grav.dot(fwd)
			fwd = (fwd + gp * ((1.1 if dom.kind == "orb" else 0.6) / maxf(speed, 10.0) * dt)).normalized()
	ortho()
	# ---- speed: engine, boost and the energy you trade with gravity ----
	if boostHold > 0: boostHold -= dt
	else: boost = maxf(0.0, boost * exp(-1.25 * dt) - 2.2 * dt)   # Ace Combat: off the throttle you settle back to cruise
	if boost > 85: boost = U.damp(boost, 85.0, 5, dt)
	if not is_lit: boost = minf(boost, 6.0)
	var slow := 0.55 if slowT > 0 else 1.0
	var along := 0.0 if ride != null else grav.dot(fwd)   # climbing costs speed, diving gains it
	gspd = clampf(gspd * exp(-(0.45 if is_lit else 0.08) * dt) + along * (0.6 if is_lit else 1.0) * dt, -18, 40)
	var engine := (base + ST.rank * 2 + GAME.momentum * 0.5) * slow + boost if is_lit else 0.0
	eng = U.damp(eng, engine, 6.0 if engine > eng else (2.5 if is_lit else 0.25), dt)
	speed = maxf(6.0 if is_lit else 4.0, eng + gspd)
	if stun > 0: speed = U.damp(speed, 6.0, 3, dt)
	# ---- velocity: swings onto the nose (grip); gravity sags it, a lot more with the engine out ----
	vel = vel.lerp(fwd * speed, 1.0 - exp(-(FLIGHT.grip if is_lit else FLIGHT.grip * 0.35) * dt))
	if ride == null:
		var stall := 1.0 - U.smooth(9, 16, speed)
		var sag: float = maxf(FLIGHT.sagLit, stall) if is_lit else 1.0
		vel += grav * (sag * dt)
		if not is_lit or stall > 0.3:   # the nose weathervanes into the fall
			var vd := vel.normalized()
			var ax2 := fwd.cross(vd)
			var s2 := ax2.length()
			if s2 > 1e-4:
				var k := minf(1.0, (stall if is_lit else 1.0) * 1.6 * dt)
				var ang := asin(minf(1.0, s2)) * k
				fwd = fwd.rotated(ax2 / s2, ang); up = up.rotated(ax2 / s2, ang); ortho()
	else:
		vel -= up * vel.dot(up)   # riding: the spring owns the radial motion
	sinking = 0.0 if is_lit else 1.0
	pos += vel * dt
	inField = ride; fieldW = 1.0 if ride != null else 0.0
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
				pos = b.pos + n0 * mn; fwd = fwd.bounce(n0).normalized(); ortho(); sync_vel()
				continue
			var n: Vector3 = (pos - b.pos).normalized()
			pos = b.pos + n * mn
			var dn := fwd.dot(n)
			if dn < 0: fwd = (fwd - n * dn * 1.6).normalized()
			if hurtCd <= 0: hurt(5, "IMPACT"); hurtCd = 0.5; boost *= 0.5
			ortho(); vel += n * maxf(0.0, -vel.dot(n))
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
		ortho(); vel -= n * (maxf(0.0, vel.dot(n)) * 1.6)
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
	THR.vis = U.damp(THR.vis, (T[2] + (minf(boost / 70, 1) * 0.7 if st == "boost" else 0.0) + throttle * 0.25) * (1.0 if lit else 0.04), 2.2 if st == "idle" or not lit else 10.0, rdt)  # engine out: the flame gutters away
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
	if mode == "puzzle" or not ship.visible or GAME.state != "play" or not lit: drive = 0.0
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
