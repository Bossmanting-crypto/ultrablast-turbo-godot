extends Node
## STYLE RANK · TURBO GAUGE · COOLDOWNS · PHASES · THE IRIS (port of 45_style.js; the coach card is coach.gd).
## Style rank works like DMC's D..SSS meter: varied moves raise it, repeats earn less, idling decays it, hits drop it.
## The turbo gauge (Devil Trigger analogue) fills from style. Turbo only qualifies at rank B with a full cell.

const RANKS := [
	{"l": "D", "n": "DRIFT", "c": "#b9a9c9"},
	{"l": "C", "n": "CRUISE", "c": "#8fe9ff"},
	{"l": "B", "n": "BLAST", "c": "#dce9a9"},
	{"l": "A", "n": "AFTERBURN", "c": "#ffd27a"},
	{"l": "S", "n": "SUPERSONIC", "c": "#ffa04a"},
	{"l": "SS", "n": "SKYSHATTER", "c": "#ff7ad6"},
	{"l": "SSS", "n": "ULTRABLAST", "c": "#fff6e8"},
]
const TURBO_RANK := 2           # B
const COOL := {"blast": 0.45, "boom": 7.0, "turboRun": 6.0, "turboFail": 4.0, "turboCancel": 1.5, "exposed": 5.0}

var rank := 0
var bar := 0.0
var idle := 0.0
var recent: Array = []
var repeats := 0
var cells := 0.0
var turboCd := 0.0
var boomCd := 0.0
var blastCd := 0.0
var rankFlash := 0.0
var maxRank := 0
var readyNoted := false

func reset_style() -> void:
	rank = 0; bar = 0; idle = 0; recent = []; repeats = 0; cells = 0; turboCd = 0; boomCd = 0; blastCd = 0; rankFlash = 0; maxRank = 0; readyNoted = false

func turbo_ready() -> bool: return rank >= TURBO_RANK and cells >= 1 and turboCd <= 0
func turbo_tier_avail() -> int: return mini(3, int(floor(cells + 1e-6)))

func gain(tag: String, base: float) -> void:
	if GAME.state != "play": return
	# homing variants count as one move for variety (playtest: alternating tags let chains farm the rank)
	if tag in ["homeperfect", "homekill", "homechain"]: tag = "homing"
	var mul := 1.0
	if recent.size() and recent[0] == tag: mul = 0.4
	elif tag in recent: mul = 0.7
	if mul < 0.5:
		repeats += 1
		if repeats == 4: Coach.hint("variety")
	else: repeats = 0
	recent.push_front(tag)
	if recent.size() > 5: recent.resize(5)
	var g := base * mul * (1.15 if TUT.active else 1.0)
	idle = 0
	bar += g * maxf(0.25, 1 - rank * 0.13)
	if bar >= 100: # one rank per move at most: no D-to-SSS in four seconds
		if rank >= RANKS.size() - 1: bar = 100
		else: bar = minf(40, bar - 100); rank_change(1)
	var before := int(floor(cells))
	cells = minf(3, cells + g * (0.0028 + rank * 0.0009) * (2.0 if TUT.active else 1.0))
	if int(floor(cells)) > before: AudioSys.cell_full(); FX.popup("TURBO CELL %d FULL" % int(floor(cells)), "#ffd27a")

func rank_change(d: int) -> void:
	var old := rank
	rank = clampi(rank + d, 0, RANKS.size() - 1)
	if rank == old: return
	rankFlash = 1
	if d > 0:
		AudioSys.rank_up(rank); maxRank = maxi(maxRank, rank)
		if rank >= 3: FX.popup("%s · %s" % [RANKS[rank].l, RANKS[rank].n], RANKS[rank].c, true)
		if rank == TURBO_RANK: Coach.hint("turboUnlock")
		TUT.note("rank", rank)
	else: AudioSys.rank_down()

func style_hit() -> void:
	if rank > 0: rank_change(-1)
	bar *= 0.5

func style_lose(amount: float) -> void:
	bar -= amount
	while bar < 0:
		if rank > 0: rank_change(-1); bar += 100
		else: bar = 0; break

func style_update(dt: float) -> void:
	idle += dt; rankFlash = maxf(0, rankFlash - dt * 2)
	if idle > 2.2 and not (P.mode in ["puzzle", "loadup", "supercut"]):
		bar -= (4 + rank * 2.2) * dt * (0.4 if TUT.active else 1.0)
		if bar < 0:
			if rank > 0: rank_change(-1); bar = 65
			else: bar = 0
	if boomCd > 0:
		boomCd = maxf(0, boomCd - dt)
		if boomCd == 0: AudioSys.ready_ping()
	if turboCd > 0: turboCd = maxf(0, turboCd - dt)
	blastCd = maxf(0, blastCd - dt)
	var ready := turbo_ready()
	if ready and not readyNoted:
		readyNoted = true; AudioSys.turbo_ready(); FX.popup("TURBO READY", "#ffd27a", true); Coach.hint("turboReady"); TUT.note("turboReady")
	if not ready and cells < 1: readyNoted = false

# ---------- phase director ----------
const PHASES := [
	{"name": "IGNITION", "t": 0, "enemies": 2, "firstEnemy": 12, "orb": null, "core": null, "pickups": false, "pal": "cyan"},
	{"name": "CONTACT", "t": 35, "enemies": 4, "orb": ["probes"], "core": null, "turrets": "orbs", "pickups": true, "pal": "gold"},
	{"name": "THE IRIS", "t": 85, "enemies": 5, "orb": ["probes", "superblast"], "core": [14, 20], "turrets": "all", "pickups": true, "pal": "mag"},
	{"name": "LAST LIGHT", "t": 135, "enemies": 7, "orb": ["probes", "superblast", "superblast"], "core": [9, 13], "turrets": "all", "pickups": true, "pal": "red"},
]
const TUT_PHASE := {"name": "FLIGHT SCHOOL", "enemies": 0, "orb": null, "core": null, "pickups": false}
var DIR := {"phase": 0}
func phase() -> Dictionary: return TUT_PHASE if TUT.active else PHASES[DIR.phase]

## The Iris: the hex-glass shell closes in stages. A glyph countdown etches into the glass first,
## then the glass groans and the aperture tightens.
var IRIS := {"stages": [{"t": 90, "r": 94}, {"t": 128, "r": 78}, {"t": 158, "r": 60}], "i": 0, "state": "idle", "t": 0.0, "from": 110.0, "to": 110.0, "warnT": 6.0, "closeT": 6.0}

func reset_iris() -> void:
	IRIS.i = 0; IRIS.state = "idle"; IRIS.t = 0.0; IRIS.from = World.R0; IRIS.to = World.R0; World.R = World.R0

func iris_update(dt: float) -> void:
	if TUT.active: World.R = World.R0; IRIS.state = "idle"; return
	var st = IRIS.stages[IRIS.i] if IRIS.i < IRIS.stages.size() else null
	if IRIS.state == "idle" and st and GAME.time >= st.t - IRIS.warnT:
		IRIS.state = "warn"; REC.ev("iris", ["warn", IRIS.i]); IRIS.t = 0.0; IRIS.from = World.R; IRIS.to = float(st.r)
		AudioSys.iris_groan(); World.bar_u("uWarn", 1.0); FX.popup("THE IRIS IS CLOSING", "#ff8ad6", true); Coach.hint("iris")
	if IRIS.state == "warn":
		var before := ceili(IRIS.warnT - IRIS.t)
		IRIS.t += dt
		var after := ceili(IRIS.warnT - IRIS.t)
		if after != before and after > 0: AudioSys.iris_tick(after <= 2)
		World.bar_u("uCount", clampf(IRIS.t / IRIS.warnT, 0, 1))
		if IRIS.t >= IRIS.warnT:
			IRIS.state = "close"; REC.ev("iris", ["close", IRIS.i]); IRIS.t = 0.0; AudioSys.iris_groan(); FX.shake(0.3)
			World.barrier_impact(U.set_length(P.pos, World.R), GAME.utime)
	elif IRIS.state == "close":
		IRIS.t += dt
		var k := U.smooth(0, 1, IRIS.t / IRIS.closeT)
		World.R = lerpf(IRIS.from, IRIS.to, k); World.bar_u("uCount", 1.0 - k)
		if IRIS.t >= IRIS.closeT:
			IRIS.state = "idle"; IRIS.i += 1; World.bar_u("uCount", 0.0); FX.popup("APERTURE %d" % roundi(World.R), "#c9a8ff")

func director_update(dt: float) -> void:
	if TUT.active: World.R = World.R0; return
	var idx := 0
	for i in PHASES.size():
		if GAME.time >= PHASES[i].t: idx = i
	if idx != DIR.phase:
		DIR.phase = idx
		var ph: Dictionary = PHASES[idx]
		FX.event_text(ph.name, ph.pal, false); FX.popup("PHASE %d OF 4" % (idx + 1), "#b9a9c9")
		Coach.hint("phase%d" % idx)
		if idx >= 2: AudioSys.event("warning"); World.core.t = 0.0; World.core.next = 6.0
	iris_update(dt)

# ---------- Flight School unlocks one system at a time; a normal run has everything ----------
var UNLOCK := {}
const ALL_SYSTEMS := ["homing", "charge", "tunnel", "combat", "boost", "orb", "cache", "turbo"]
func unlocked(k: String) -> bool: return not TUT.active or UNLOCK.has(k)
