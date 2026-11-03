extends Node
## FLIGHT SCHOOL (port of 58_tutorial.js). One mechanic per step, taught by doing:
##   1. a card names the move, shows its keys and says what to do in one short line;
##   2. the step waits until you have actually done it (a live goal counter, never a timer);
##   3. it then turns gold and you choose when to move on (ENTER, the card button, or the pad's View button),
##      so you can keep practising first. Targets keep respawning ahead of you while you do.
## Sequences that only make sense in one go (charge into ride, turbo into align into release) chain on their own.
## Safe space: no timer, no Iris, no hostile fire, no barrier damage; the hull cannot drop below 25.
## Each step is a row in STEPS plus optional methods named _<id>_setup/_update/_on/_prog/_goal/_done/_after/_keys/_line.

var active := false
var i := 0
var d := {}
var wait := 0.0
var orb = null
var render_t := 0.0
var passed := false
var enter_t := 0.0
var pass_t := 0.0
var shown := {}

const STEPS := [
	{"id": "fly", "ch": "FLY", "title": "STEER"},
	{"id": "crystals", "ch": "FLY", "title": "CRYSTALS"},
	{"id": "homing", "ch": "HOMING", "title": "HOMING", "newMove": "HOMING!"},
	{"id": "chain", "ch": "HOMING", "title": "CHAIN"},
	{"id": "finisher", "ch": "HOMING", "title": "FINISHER"},
	{"id": "charge", "ch": "RIFTS", "title": "CHARGE CRYSTALS", "newMove": "RIFTS!", "auto": true},
	{"id": "ride", "ch": "RIFTS", "title": "RIDE THE RIFT"},
	{"id": "gold", "ch": "RIFTS", "title": "GOLD RIFT"},
	{"id": "takedown", "ch": "COMBAT", "title": "TAKEDOWNS", "newMove": "TAKEDOWNS!"},
	{"id": "boost", "ch": "BOOST", "title": "BOOST", "newMove": "BOOST!", "hl": ["thruster"]},
	{"id": "boom", "ch": "BOOST", "title": "BUNDLE BOOM", "hl": ["boomChip"]},
	{"id": "planet", "ch": "BOOST", "title": "RIDE A PLANET", "newMove": "GRAVITY!", "hl": ["fuelRow"]},
	{"id": "cache", "ch": "PUZZLES", "title": "CRYSTAL CACHE", "newMove": "MINIBLAST!"},
	{"id": "breach", "ch": "PUZZLES", "title": "ORB BREACH"},
	{"id": "rank", "ch": "TURBO", "title": "STYLE RANK", "newMove": "TURBO!", "hl": ["styleBox"]},
	{"id": "turbo", "ch": "TURBO", "title": "TURBO", "hl": ["styleBox", "thruster"], "auto": true},
	{"id": "align", "ch": "TURBO", "title": "ALIGN", "sub": true, "auto": true},
	{"id": "release", "ch": "TURBO", "title": "RELEASE", "sub": true, "auto": true},
	{"id": "supercut", "ch": "TURBO", "title": "SUPERCUT", "sub": true},
	{"id": "iris", "ch": "THE IRIS", "title": "THE IRIS"},
]

func step_id() -> String: return STEPS[i].id if i < STEPS.size() else ""
func step() -> Dictionary: return STEPS[i]

## numbered lessons: sub-steps (align, release, supercut) share the turbo lesson's number
func lessons() -> int: return STEPS.filter(func(s): return not s.get("sub", false)).size()
func lesson_no(k: int) -> int: return STEPS.slice(0, k + 1).filter(func(s): return not s.get("sub", false)).size()

func note(ev: String, v = null) -> void:
	REC.ev(ev, v)
	if not active: return
	if wait <= 0: _call("on", [ev, v, d])

func _call(hook: String, args := []):
	var m := "_%s_%s" % [step_id(), hook]
	if has_method(m): return callv(m, args)
	return null

func _has(hook: String) -> bool: return has_method("_%s_%s" % [step_id(), hook])

# ---------- placement helpers ----------
func snap_cam() -> void:
	P.CAM.pos = P.pos - P.fwd * 8 + P.up * 3
	P.CAM.look = P.pos + P.fwd * 9; P.CAM.up = P.up

func teleport(pos: Vector3, fwd: Vector3) -> void:
	P.pos = pos; P.fwd = fwd.normalized()
	P.up = pos.normalized(); P.up = P.up - P.fwd * P.up.dot(P.fwd)
	if P.up.length_squared() < 1e-4: P.up = Vector3(0, 1, 0) - P.fwd * P.fwd.y
	P.up = P.up.normalized(); P.ortho(); P.noGrav = 3.5; P.boost = 0; P.speed = 26; P.velSync = true; P.ride = null; P.rideCd = 3.5
	for r in FX.ribbons: r.pts.clear()
	snap_cam(); FX.doodle_flash(0.25); AudioSys.whoosh(true, 0.25)

func _clamp_r(p: Vector3) -> Vector3:
	if p.length() < World.CORE_R + 4: p = U.set_length(p, World.CORE_R + 5)
	if p.length() > World.R - 5: p = U.set_length(p, World.R - 6)
	return p

func ahead(dist: float, side := 0.0, up := 0.0) -> Vector3:
	return _clamp_r(P.pos + P.fwd * dist + P.right * side + P.up * up)

## placements follow the predicted flight line (the gravity skim curves it), not a straight ray
func line(n: int, spacing: float, lead: float) -> Array:
	var path: Array = HOM.predict_path(n, spacing, lead)
	while path.size() < n:
		path.append(path[path.size() - 1] if path.size() else {"pos": ahead(lead), "fwd": P.fwd, "up": P.up, "right": P.right})
	return path

func at(s: Dictionary, side: float, up: float) -> Vector3:
	return _clamp_r(s.pos + s.right * side + s.up * up)

func drones(n: int, dist: float, spread: float) -> void:
	var L := line(n, 8, dist)
	for k in n: Enemies.spawn_drone(at(L[k], U.rand(-spread, spread), U.rand(-spread, spread) * 0.4))

## a set is stale when nothing of it is left in front of you (missed pieces stay behind): respawn it ahead
func stale(list: Array) -> bool:
	for o in list:
		if not o.alive: continue
		var p: Vector3 = o.pos if o.pos.length_squared() > 0 else o.home
		var rel: Vector3 = p - P.pos
		if rel.dot(P.fwd) > -3 and rel.length() < 85: return false
	return P.mode == "fly"

func clear_drones() -> void:
	for p in Enemies.probes:
		if p.alive and p.passive: p.alive = false; p.g.visible = false

func crystals_ahead(n: int) -> void:
	var L := line(n, 6, 18)
	for k in n:
		var c: Dictionary = World.crystals[k]
		c.alive = true; c.spawn = 1.0; c["tut"] = true
		c.home = at(L[k], sin(k * 0.9) * 2.5, 0.5 + cos(k * 0.7) * 1.2)

func homers(n: int, dist: float, zig: bool) -> void:
	var L := line(n, 13, dist)
	for k in n:
		var h: Dictionary = World.homers[k]
		h.alive = true; h.spawn = 1.0; h.vel = Vector3.ZERO
		h.home = at(L[k], (4.0 if k % 2 else -4.0) if zig else 0.0, 1.5 if zig else 0.6); h.pos = h.home; h["tut"] = true

func tut_homers() -> Array: return World.homers.filter(func(h): return h.get("tut", false))

## chain lessons: when a window opens and nothing is waiting ahead, feed one gem onto the flight line
func feed(dist: float) -> void:
	for h in World.homers:
		if h.alive and h.get("tut", false) and (h.pos - P.pos).dot(P.fwd) > 4 and h.pos.distance_to(P.pos) < 45: return
	var h = null
	for x in World.homers:
		if not x.alive: h = x; break
	if h == null:
		for x in World.homers:
			if not x.get("tut", false): h = x; break
	if h == null: return
	var L := line(1, 1, dist)
	h.alive = true; h.spawn = 1.0; h.vel = Vector3.ZERO; h.home = at(L[0], U.rand(-2.5, 2.5), U.rand(0.2, 1.4)); h.pos = h.home; h["tut"] = true

func place_at_orb() -> void:
	var o: Dictionary = World.orbs[0]
	if not o.alive: o.alive = true; o.fade = 1.0; o.g.visible = true
	o.hp = 0; o.exposed = 16.0; o.state = "idle"; orb = o
	var out: Vector3 = o.pos.normalized()
	var side := out.cross(Vector3.UP)
	if side.length_squared() < 1e-3: side = Vector3.RIGHT
	side = side.normalized()
	var pos: Vector3 = o.pos + side * 30 + out * 4
	teleport(pos, o.pos - pos)

func place_at_cache() -> void:
	var c: Dictionary = HOM.caches[0]
	c.state = "ready"; c.t = 0.0
	var pos: Vector3 = c.dir * (World.CORE_R + 10) + c.dir.cross(Vector3.UP).normalized() * 26
	teleport(pos, c.pos - pos)

func unlock(keys: Array) -> void:
	for k in keys: ST.UNLOCK[k] = true

# ---------- key caps: KC(keyboard, pad) shows whichever device you are using right now ----------
func KC(kb: String, pad := "") -> String: return "kc:" + Ctl.kl(kb, pad)
func HOMEK() -> Array: return [KC("X")] if Ctl.is_pad() else [KC("E"), "or", KC("RIGHT CLICK")]
func HK() -> String: return KC("E", "X")
func BOOSTK() -> Array: return [KC("HOLD RT"), "or", KC("HOLD A")] if Ctl.is_pad() else [KC("HOLD SPACE"), "or", KC("HOLD LEFT CLICK")]
func HOLDK() -> String: return KC("HOLD SPACE", "HOLD RT")

func keys_for(id: String) -> Array:
	match id:
		"fly": return [KC("LEFT STICK")] if Ctl.is_pad() else [KC("MOUSE"), "or", KC("W A S D")]
		"crystals": return [KC("FLY THROUGH")]
		"homing", "charge", "gold", "takedown": return HOMEK()
		"chain": return [HK(), KC("ON GOLD")]
		"finisher": return [HK(), KC("× 5")]
		"ride", "supercut": return [HK(), "or", KC("SPACE", "A")]
		"boost": return BOOSTK()
		"boom": return [HOLDK(), "+", HK()]
		"planet": return [KC("FLY LOW"), "then", HOLDK(), "+", KC("W", "STICK UP")]
		"cache": return HOMEK() + ["then", HOLDK(), "+", HK()]
		"breach": return HOMEK() + ["then", HOLDK(), "+", KC("W A S D", "D-PAD")]
		"rank": return [KC("MIX MOVES")]
		"turbo": return [HOLDK(), KC("PAST 3 RINGS")]
		"align": return [KC("KEEP HOLDING"), "+", HK()]
		"release": return [KC("LET GO"), KC("ON RELEASE!")]
		"iris": return [KC("STAY INSIDE")]
	return []

func line_for(id: String) -> String:
	match id:
		"fly": return "Steer the ship. Pitch and yaw are free (loops are fine). Let go and it flies straight."
		"crystals": return "Fly through crystals. Every pickup builds your style rank."
		"homing": return "A gold ring means locked. Press to dash in. Each dash uses one of 3 charges (pips under your aim)."
		"chain": return "After a hit a ring closes on the next lock. Press when it turns gold. Too early breaks the chain."
		"finisher": return "Five links end in a finisher. Hitting the gold band is PERFECT and costs no charge."
		"charge": return "Home through all three cyan crystals to tear open a rift."
		"ride": return "Fly into the portal. At the exit, tap as the pulse crosses the band."
		"gold": return "Hit all three within 3 seconds of each other for a gold rift."
		"takedown": return "Drones lock on just like gems. Home into them."
		"boost": return "Hold to thrust and charge up to 3 rings. Let go to blast, then fly through them."
		"boom": return "While charging, press homing to detonate the rings around you."
		"planet": return "Mini-planets pull you in. Fly low over one to ride it and refuel. Cruising sips fuel, thrust burns it, and an empty tank means the engine dies and you fall. To leave, hold boost past escape speed and pull up."
		"cache": return "Home in to prime the cache. Hold boost: tap as the orb meets each gold zone, then let go to fire."
		"breach": return "An exposed orb works the same way: prime it, hold boost, repeat the glyphs, let go to fire."
		"rank": return "Mix your moves to climb to rank B. Repeats earn less."
		"turbo": return "Rank B and a full cell: keep holding past 3 rings to forge a gold 4th."
		"align": return "Keep holding. Tap homing as the green orb crosses the bright slot."
		"release": return "Keep holding until RELEASE! shows, then let go. Too late blows out."
		"supercut": return "An automatic chain. Tap as each closing ring meets its target."
		"iris": return "In a run the glass shell closes in stages. Etching glyphs are your countdown."
	return ""

# ---------- steps ----------
func _fly_setup(dd): dd.s = 0.0
# ride a planet: line up a low pass over mini-planet 0 (tangent, 13 m up) so its gravity pulls you into a ride
func planet_approach() -> void:
	var o: Dictionary = World.orbs[0]
	var n: Vector3 = o.pos.normalized()
	var side := n.cross(Vector3.UP)
	if side.length_squared() < 1e-4: side = Vector3.RIGHT
	side = side.normalized()
	teleport(o.pos + n * (o.r + 13) - side * 30, side)
	P.noGrav = 0; P.rideCd = 0; P.fuel = 45
func _planet_setup(dd): dd.rode = false; dd.esc = false; planet_approach()
func _planet_on(ev, _v, dd):
	if ev == "ride": dd.rode = true
	if ev == "escape" and dd.rode: dd.esc = true
func _planet_update(dd, _dt): if P.ride == null and not dd.esc and P.pos.distance_to(World.orbs[0].pos) > 75: planet_approach()
func _planet_prog(dd): return (0.5 if dd.rode else 0.0) + (0.5 if dd.esc else 0.0)
func _planet_goal(dd): return "FLY LOW OVER THE PLANET" if not dd.rode else ("ESCAPE: BOOST + PULL UP" if not dd.esc else "ESCAPE VELOCITY!")
func _planet_done(dd): return dd.esc
func _fly_update(dd, dt): if absf(Ctl.steer_x) + absf(Ctl.steer_y) > 0.25: dd.s += dt
func _fly_prog(dd): return dd.s / 3.0
func _fly_goal(_dd): return "STEER AROUND"
func _fly_done(dd): return dd.s >= 3

func _crystals_setup(dd): dd.n = 0; crystals_ahead(8)
func _crystals_on(ev, _v, dd): if ev == "crystal": dd.n += 1
func _crystals_update(_dd, _dt): if stale(World.crystals.slice(0, 8)): crystals_ahead(8)
func _crystals_prog(dd): return dd.n / 5.0
func _crystals_goal(dd): return "CRYSTALS %d / 5" % mini(dd.n, 5)
func _crystals_done(dd): return dd.n >= 5

func _homing_setup(dd): unlock(["homing"]); dd.n = 0; homers(3, 26, false); GAME.slowmo(0.4, 0.8)
func _homing_on(ev, v, dd): if ev == "homingHit" and v == "homer": dd.n += 1
func _homing_update(_dd, _dt): if stale(tut_homers()): homers(3, 26, false)
func _homing_prog(dd): return dd.n / 3.0
func _homing_goal(dd): return "HOMING HITS %d / 3" % mini(dd.n, 3)
func _homing_done(dd): return dd.n >= 3

func _chain_setup(dd): dd.best = 0; HOM.chain = 0; HOM.win = null; homers(5, 22, true) # chains from the last step do not count
func _chain_update(dd, _dt):
	HOM.charges = HOM.HOMING.max; dd.best = maxi(dd.best, HOM.chain)
	if HOM.win and P.mode == "fly": feed(18)
	elif P.mode == "fly" and stale(tut_homers()): homers(5, 22, true)
func _chain_prog(dd): return dd.best / 3.0
func _chain_goal(dd): return "BEST CHAIN %d / 3" % mini(dd.best, 3)
func _chain_done(dd): return dd.best >= 3

func _finisher_setup(dd): dd.ok = false; HOM.chain = 0; HOM.win = null; homers(7, 20, true)
func _finisher_on(ev, _v, dd): if ev == "finisher": dd.ok = true
func _finisher_update(_dd, _dt):
	HOM.charges = HOM.HOMING.max
	if HOM.win and P.mode == "fly": feed(18)
	elif P.mode == "fly" and stale(tut_homers()): homers(7, 20, true)
func _finisher_prog(_dd): return float(HOM.chain) / HOM.HOMING.cap
func _finisher_goal(_dd): return "CHAIN %d / %d" % [HOM.chain, HOM.HOMING.cap]
func _finisher_done(dd): return dd.ok

func _live_tunnel() -> bool: return World.tunnels.any(func(t): return not t.used and not t.dying)

func _charge_setup(dd): unlock(["charge", "tunnel"]); dd.ok = false; HOM.CHARGE.count = 0; HOM.spawn_charge_set()
func _charge_on(ev, _v, dd): if ev == "tunnelOpen": dd.ok = true
func _charge_update(dd, _dt):
	if not dd.ok and not HOM.CHARGE.items.any(func(c): return c.alive) and HOM.CHARGE.count < 3 and not _live_tunnel(): HOM.spawn_charge_set()
func _charge_prog(_dd): return HOM.CHARGE.count / 3.0
func _charge_goal(_dd): return "CHARGE %d / 3" % HOM.CHARGE.count
func _charge_done(dd): return dd.ok

func _ride_setup(dd): dd.out = false; dd.perfect = false; dd.w = 0.0
func _ride_on(ev, v, dd): if ev == "tunnelExit": dd.out = true; dd.perfect = v
func _ride_update(dd, dt):
	if P.mode != "tunnel" and not dd.out and not _live_tunnel():
		dd.w += dt
		if dd.w > 2: dd.w = 0.0; HOM.CHARGE.count = 2; HOM.spawn_charge_set(); FX.popup("ONE MORE CRYSTAL OPENS IT", "#8fe9ff")
func _ride_goal(_dd): return "RIDING THE RIFT" if P.mode == "tunnel" else "FLY INTO THE PORTAL"
func _ride_done(dd): return dd.out
func _ride_after(dd): return "PERFECT EXIT" if dd.perfect else "EXITED · PERFECT EXITS BOOST MORE"

func _gold_setup(dd): dd.ok = false; dd.tries = 0; dd.opened = false; HOM.CHARGE.count = 0; HOM.CHARGE.quick = 0; HOM.spawn_charge_set()
func _gold_on(ev, v, dd):
	if ev == "tunnelOpen":
		dd.tries += 1
		if v or dd.tries >= 2: dd.opened = true
		else: FX.popup("TOO SLOW · TRY THE CHAIN AGAIN", "#c9a8ff", true)
	if ev == "tunnelExit" and dd.opened: dd.ok = true
func _gold_update(dd, _dt):
	var live := _live_tunnel()
	if dd.opened and not live and P.mode == "fly": dd.ok = true
	if not dd.opened and P.mode == "fly" and not HOM.CHARGE.items.any(func(c): return c.alive) and not live: HOM.CHARGE.count = 0; HOM.spawn_charge_set()
func _gold_prog(dd): return 1.0 if dd.opened else HOM.CHARGE.count / 3.0
func _gold_goal(dd):
	if dd.opened: return "RIDING THE GOLD RIFT" if P.mode == "tunnel" else "FLY INTO THE RIFT"
	return "CHARGE %d / 3%s" % [HOM.CHARGE.count, " · QUICK" if HOM.CHARGE.quick >= 2 else ""]
func _gold_done(dd): return dd.ok and P.mode != "tunnel"

func _passive() -> Array: return Enemies.probes.filter(func(p): return p.passive)
func _takedown_setup(dd): unlock(["combat"]); dd.k = 0; clear_drones(); drones(4, 26, 6)
func _takedown_on(ev, _v, dd): if ev == "kill": dd.k += 1
func _takedown_update(_dd, _dt): if stale(_passive()): clear_drones(); drones(4, 26, 6)
func _takedown_prog(dd): return dd.k / 3.0
func _takedown_goal(dd): return "TAKEDOWNS %d / 3" % mini(dd.k, 3)
func _takedown_done(dd): return dd.k >= 3

func _boost_setup(dd): unlock(["boost"]); dd.n = 0; clear_drones()
func _boost_on(ev, _v, dd): if ev == "ringPass": dd.n += 1
func _boost_prog(dd): return dd.n / 4.0
func _boost_goal(dd): return "RINGS PASSED %d / 4" % mini(dd.n, 4)
func _boost_done(dd): return dd.n >= 4

func _boom_setup(dd): dd.k = 0; clear_drones(); drones(4, 20, 5)
func _boom_on(ev, v, dd): if ev == "kill" and v == "BOOM": dd.k += 1
func _boom_update(_dd, _dt):
	ST.boomCd = minf(ST.boomCd, 1.5) # short cooldown while learning
	if not BL.charging and stale(_passive()): clear_drones(); drones(4, 20, 5); ST.boomCd = 0
func _boom_prog(dd): return dd.k / 2.0
func _boom_goal(dd): return "BOOM TAKEDOWNS %d / 2" % mini(dd.k, 2)
func _boom_done(dd): return dd.k >= 2

func _cache_setup(dd): unlock(["cache"]); dd.ok = false; dd.tries = 0; place_at_cache()
func _cache_on(ev, v, dd):
	if ev == "cacheCrack": dd.ok = true
	if ev == "puzzleFail" and v == "cache":
		dd.tries += 1
		if dd.tries >= 3: FX.popup("GOOD TRY · MOVING ON", "#8fe9ff"); dd.ok = true
func _cache_update(_dd, _dt):
	var c: Dictionary = HOM.caches[0]
	if P.mode == "fly" and c.state == "ready" and P.prime == null and BL.payload == null and c.pos.distance_to(P.pos) > 70: place_at_cache()
	if passed and c.state != "ready" and P.mode == "fly": c.state = "ready"
func _cache_goal(_dd):
	if BL.payload: return "LET GO TO FIRE"
	if P.mode == "puzzle": return "KEEP HOLDING · TAP IN THE GOLD ZONE"
	return "PRIMED · HOLD BOOST" if P.prime else "HOME INTO THE CACHE"
func _cache_done(dd): return dd.ok and P.mode == "fly"

func _breach_setup(dd): unlock(["orb"]); clear_drones(); dd.res = null; dd.tries = 0; place_at_orb()
func _breach_update(dd, _dt):
	var o = orb
	if o == null or P.mode != "fly": return
	if typeof(dd.res) == TYPE_BOOL and dd.res == false:
		dd.tries += 1
		if dd.tries < 3:
			dd.res = null
			if o.pos.distance_to(P.pos) > 60: place_at_orb()
			FX.popup("TRY AGAIN", "#c9a8ff")
		else: dd.res = "skip"
	if dd.res == null and o.alive and not (o.exposed > 0): o.hp = 0; o.exposed = 14.0
func _breach_on(ev, v, dd):
	if ev == "breach" and not (typeof(dd.res) == TYPE_BOOL and dd.res == true) and not (typeof(dd.res) == TYPE_STRING and dd.res == "skip"): dd.res = v
func _breach_goal(_dd):
	if BL.payload: return "LET GO TO FIRE"
	if P.mode == "puzzle": return "KEEP HOLDING · REPEAT THE GLYPHS"
	return "PRIMED · HOLD BOOST" if P.prime else "HOME INTO THE GLOWING ORB"
func _breach_done(dd): return (typeof(dd.res) == TYPE_BOOL and dd.res == true) or (typeof(dd.res) == TYPE_STRING and dd.res == "skip")

func _rank_setup(dd): unlock(["turbo"]); crystals_ahead(10); drones(4, 30, 7); homers(4, 24, true); dd.refill = 0.0
func _rank_update(dd, dt):
	dd.refill += dt
	if dd.refill > 12 and ST.rank < ST.TURBO_RANK: dd.refill = 0.0; drones(3, 30, 7); crystals_ahead(8); homers(4, 24, true)
func _rank_prog(_dd): return clampf((ST.rank * 100 + ST.bar) / (ST.TURBO_RANK * 100.0), 0, 1)
func _rank_goal(_dd): return "RANK %s  →  B" % ST.RANKS[ST.rank].l
func _rank_done(_dd): return ST.rank >= ST.TURBO_RANK

func _turbo_setup(dd):
	clear_drones()
	if ST.rank < ST.TURBO_RANK: ST.rank = ST.TURBO_RANK; ST.bar = 40
	ST.cells = maxf(ST.cells, 1); ST.turboCd = 0; ST.blastCd = 0; dd.go = false
func _turbo_update(_dd, _dt):
	if ST.rank < ST.TURBO_RANK: ST.rank = ST.TURBO_RANK; ST.bar = 30
	if ST.cells < 1 and P.mode == "fly": ST.cells = 1
	ST.turboCd = minf(ST.turboCd, 0.5)
func _turbo_on(ev, _v, dd): if ev == "turboStart": dd.go = true
func _turbo_goal(_dd): return "HOLD PAST 3 RINGS" if ST.turbo_ready() else "CHARGING THE CELL…"
func _turbo_done(dd): return dd.go

func _align_setup(dd): dd.ok = false; dd.bad = null
func _align_on(ev, _v, dd):
	if ev == "puzzleSuccess": dd.ok = true
	if ev == "puzzleFail" or ev == "turboCancel": dd.bad = ev
func _align_update(dd, _dt): if dd.bad: goto("turbo", "LET GO TOO SOON · TRY AGAIN" if dd.bad == "turboCancel" else "MISSED · THE CELL IS BACK, TRY AGAIN")
func _align_goal(_dd): return "ALIGN THE ORB"
func _align_done(dd): return dd.ok

func _release_setup(dd): dd.ok = false; dd.bad = false
func _release_on(ev, _v, dd):
	if ev == "supercutStart": dd.ok = true
	if ev == "blowout": dd.bad = true
func _release_update(dd, _dt): if dd.bad: goto("turbo", "BLOWOUT · THE CELL IS BACK, TRY AGAIN")
func _release_goal(_dd): return "WAIT FOR RELEASE!"
func _release_done(dd): return dd.ok

func _supercut_setup(dd): dd.end = false; dd.n = 0; drones(6, 34, 12); homers(4, 30, true)
func _supercut_on(ev, v, dd):
	if ev == "scMatch": dd.n = v
	if ev == "supercutEnd": dd.end = true; dd.n = v
func _supercut_goal(dd): return "HITS %d" % dd.n
func _supercut_done(dd): return dd.end
func _supercut_after(dd): return "FULL CHAIN" if dd.n >= 5 else "%d HITS · TAP AS THE RING CLOSES" % dd.n

func _iris_setup(dd): dd.t = 0.0
func _iris_update(dd, dt): dd.t += dt; World.bar_u("uCount", fmod(dd.t / 4.0, 1.0)); World.bar_u("uProx", 0.6)
func _iris_prog(dd): return dd.t / 3.0
func _iris_goal(_dd): return "WATCH THE GLASS"
func _iris_done(dd): return dd.t > 3
func _iris_after(_dd): return "THAT IS FLIGHT SCHOOL"

# ---------- flow ----------
func goto(id: String, msg := "") -> void:
	for k in STEPS.size():
		if STEPS[k].id == id:
			if msg != "": FX.popup(msg, "#c9a8ff", true)
			enter(k); return

func render(late := false) -> void:
	var st: Dictionary = STEPS[i]
	var n := lesson_no(i)
	var prog = _call("prog", [d]) if _has("prog") else null
	Coach.render("STEP %d / %d · %s" % [n, lessons(), st.ch], st.title, line_for(st.id), _call("goal", [d]) if _has("goal") else "", prog, true, true, late)
	var p: CoachPanel = Coach.panel()
	if p:
		p.set_keys(keys_for(st.id))
		p.set_dots(lessons(), n)
	passed_ui()

## switching between keyboard and controller relabels the open card straight away
func on_device_change() -> void:
	if not active: return
	var p: CoachPanel = Coach.panel()
	if p: p.set_keys(keys_for(step_id()))
	passed_ui()

func passed_ui() -> void:
	var p: CoachPanel = Coach.panel()
	if p == null: return
	var ck := "VIEW ⧉" if Ctl.is_pad() else "ENTER"
	p.set_passed(passed, ("FINISH" if i + 1 >= STEPS.size() else "CONTINUE"), ck)

func enter(k: int) -> void:
	if active and i < STEPS.size(): REC.ev("tut", ["leave", step_id()])
	i = k; d = {}; wait = 0; passed = false; enter_t = Ctl.now
	var st: Dictionary = STEPS[k]
	REC.ev("tut", ["enter", st.id])
	_call("setup", [d])
	if GAME.hud: GAME.hud.highlight(st.get("hl", []))
	var nm: bool = st.has("newMove") and not shown.has(st.id)
	render(k == 0 or nm); AudioSys.step()
	if nm:
		shown[st.id] = true; FX.event_text(st.newMove, "cyan", false); FX.popup("NEW MOVE", "#8fe9ff", true)

func pass_step() -> void:
	var st: Dictionary = STEPS[i]
	REC.ev("tut", ["pass", st.id, snappedf(Ctl.now - enter_t, 0.1)])
	if st.get("auto", false): AudioSys.step(); advance(); return
	passed = true; pass_t = Ctl.now
	var nt: String = _call("after", [d]) if _has("after") else "PASSED"
	var p: CoachPanel = Coach.panel()
	if p:
		p.set_count("✓ " + nt)
		if _has("prog"): p.set_prog(1.0)
	passed_ui()
	FX.popup(nt, "#ffd27a", true); AudioSys.play("row_clear", {"vol": 0.6})

func advance() -> void:
	if i + 1 >= STEPS.size(): finish()
	else: enter(i + 1)

func continue_step() -> void:
	if not active or not passed: return
	if P.mode in ["puzzle", "loadup", "supercut", "tunnel"]: return # finish the move first
	REC.ev("tut", ["next", step_id(), snappedf(Ctl.now - pass_t, 0.1)])
	AudioSys.ui("select"); cleanup_modes(); advance()

func cleanup_modes() -> void:
	if P.mode == "puzzle" or P.mode == "loadup": BL.puzzle = null; BL.loadup = null; BL.pop_bubble(false); P.mode = "fly"; P.flameTarget = 1
	if P.mode == "supercut": BL.sc = null; P.mode = "fly"; P.flameTarget = 1; FX.DOOD.base = 0.0
	if P.mode == "homing": P.mode = "fly"; P.home = null
	if BL.charging: BL.cancel_charge(false)

func skip() -> void:
	if not active: return
	AudioSys.ui("select")
	var id := step_id()
	REC.ev("tut", ["skip", id])
	cleanup_modes()
	# grant whatever the skipped step would have unlocked
	match id:
		"homing": unlock(["homing"])
		"charge": unlock(["charge", "tunnel"])
		"takedown": unlock(["combat"])
		"boost": unlock(["boost"])
		"cache": unlock(["cache"])
		"breach": unlock(["orb"])
		"rank": unlock(["turbo"])
	if id in ["turbo", "align", "release", "supercut"]: goto("iris"); return
	advance()

func update(dt: float, rdt: float, evs: Array) -> void:
	if not active: return
	if evs.any(func(e): return e.t == "skip"): skip(); return
	if evs.any(func(e): return e.t == "next"):
		continue_step()
		if not active: return
	var st: Dictionary = STEPS[i]
	_call("update", [d, dt])
	if not is_same(STEPS[i], st) or i >= STEPS.size() or STEPS[i].id != st.id: return
	var modal: bool = P.mode in ["puzzle", "loadup", "supercut"]
	var p: CoachPanel = Coach.panel()
	if p:
		p.set_compact(modal or P.mode == "tunnel")
		p.set_hidden_pz(modal or (P.mode == "tunnel" and P.strobe != null and P.strobe.active)) # overlays and the exit pulse carry their own instructions
	if passed: return # practising: the goal stays met, targets keep coming
	render_t -= rdt
	if render_t <= 0:
		render_t = 0.12
		if p:
			p.set_count(_call("goal", [d]) if _has("goal") else "")
			if _has("prog"): p.set_prog(clampf(_call("prog", [d]), 0, 1))
	if _call("done", [d]): pass_step()

func start() -> void:
	AudioSys.init()
	active = true; ST.UNLOCK.clear(); shown.clear()
	GAME.reset_world()
	active = true
	GAME.state = "play"; GAME.show_screen("")
	GAME.hud.set_on(true)
	for e in Enemies.enemies: e.alive = false; e.j.visible = false; e.respawn = 999.0
	for h in World.homers: h.alive = false; h["respawnT"] = 999.0
	P.invuln = 1; AudioSys.ui("start"); AudioSys.attach_voices(Enemies.enemies); P.chargeArmed = false
	FX.event_text("FLIGHT SCHOOL", "cyan", false)
	REC.start("flight-school")
	enter(0)

func finish() -> void:
	REC.ev("tut", ["finish"]); REC.stop("flight school done")
	active = false
	if GAME.hud: GAME.hud.highlight([])
	Coach.hide(); cleanup_modes(); clear_drones(); World.bar_u("uCount", 0.0)
	U.sset("ub_tutDone", true)
	GAME.state = "over"; GAME.hud.set_on(false)
	FX.popups.clear(); FX.crashes.clear(); FX.clear_texts()
	AudioSys.event("complete")
	GAME.show_screen("tutdone")

func quit() -> void:
	if not active: return
	active = false
	if GAME.hud: GAME.hud.highlight([])
	Coach.hide(); clear_drones()
