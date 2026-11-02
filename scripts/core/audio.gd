extends Node
## AUDIO (port of 05_audio.js). Every cue is a designed sample: CC0 recordings of real glass, metal, firecrackers,
## rockets, plasma, air and electromagnetic noise, layered as crunch + body + tail + glass chime in C minor.
## The jet engine is four looping recordings (fan rumble, thruster, electric whine, afterburner) driven by speed
## and boost. Music is "Battle Theme A" by cynicmusic (CC0), 143.5 BPM in C minor.
## Buses (default_bus_layout.tres): Master (limiter) <- Music (low-pass), SFX, UI, Engine, Reverb, L_<loop>.

const MUSIC_LOOP := {"start": 3.364, "end": 85.7658}
const BEAT := {"first": 0.093, "period": 60.0 / 143.555}
const C_MINOR := [0, 3, 5, 7, 10] # pentatonic steps for pitched pickups
const LIMIT := {"gem": 6, "crystal": 6, "crunch": 3, "takedown": 3, "explode": 4, "enemy_shot": 4, "crackle": 3, "ring": 3, "ringpass": 3, "lock": 2, "hurt": 2, "puzzle_hit": 3, "sc_hit": 3, "slam": 2, "shatter": 2}
const LOOP_BUS := {"engine_bed": "Engine", "engine_thrust": "Engine", "engine_whine": "Engine", "afterburner": "Engine", "charge_hum": "SFX", "tunnel_wind": "SFX", "iris_drone": "SFX"}

var buf := {}          # name -> AudioStream
var groups := {}       # base -> [variant names]
var last_pick := {}
var playing: Array = []  # {p, base, end}
var loops := {}        # name -> {p, bus, gain, rate, lp}
var music: AudioStreamPlayer
var music_gain := 0.0
var music_target := 1.0
var music_lp := 2400.0
var duck_until := 0.0
var duck_amt := 0.0
var engine_gain := 0.0
var muted := false
var vols := {"music": 0.7, "sfx": 0.9}
var voices: Array = []
var started := false
var clock := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dir := DirAccess.open("res://assets/sfx")
	if dir == null: return
	var names := {}
	for f in dir.get_files():
		var fn := f.trim_suffix(".import").trim_suffix(".remap")
		if fn.ends_with(".mp3") or fn.ends_with(".ogg"): names[fn] = true
	for fn in names.keys():
		var n: String = fn.get_basename()
		var s = load("res://assets/sfx/" + fn)
		if s == null: continue
		if LOOP_BUS.has(n) or n == "enemy_jet": s.loop = true
		buf[n] = s
		var base := _base(n)
		if not groups.has(base): groups[base] = []
		groups[base].append(n)
	muted = U.sget("ub_muted", false)
	var v = U.sget("ub_vols", null)
	if v is Dictionary: vols.merge(v, true)
	_apply_vols()

static func _base(n: String) -> String:
	var i := n.rfind("_")
	if i > 0 and n.substr(i + 1).is_valid_int(): return n.substr(0, i)
	return n

func _bus(name: String) -> int: return AudioServer.get_bus_index(name)

## Starts the mix (called on the first menu press, like the web build's AudioContext unlock).
func init() -> void:
	if started: return
	started = true
	music = AudioStreamPlayer.new(); music.bus = "Music"
	var ms: AudioStream = load("res://assets/music/battle_theme_a.ogg")
	if ms:
		ms.loop = true; ms.loop_offset = MUSIC_LOOP.start
		music.stream = ms; music.volume_db = -80.0; add_child(music); music.play()
	for n in LOOP_BUS:
		if not buf.has(n): continue
		var p := AudioStreamPlayer.new(); p.stream = buf[n]; p.bus = "L_" + n; p.volume_db = -80.0
		add_child(p); p.play(randf() * buf[n].get_length() * 0.9)
		loops[n] = {"p": p, "bus": _bus("L_" + n), "gain": 0.0, "tg": 0.0, "rate": 1.0, "tr": 1.0, "lp": 18000.0, "tl": 18000.0, "tc": 0.12}

func _set_loop(n: String, gain: float, rate = null, lp = null, tc := 0.12) -> void:
	if not loops.has(n): return
	var l: Dictionary = loops[n]
	l.tg = gain; l.tc = tc
	if rate != null: l.tr = rate
	if lp != null: l.tl = lp

func _process(delta: float) -> void:
	clock += delta
	if not started: return
	for n in loops:
		var l: Dictionary = loops[n]
		var k := 1.0 - exp(-delta / maxf(l.tc, 0.01))
		l.gain = lerpf(l.gain, l.tg, k); l.rate = lerpf(l.rate, l.tr, k); l.lp = lerpf(l.lp, l.tl, k)
		var eng := engine_gain if LOOP_BUS[n] == "Engine" else 1.0
		l.p.volume_db = linear_to_db(maxf(l.gain * eng, 1e-5))
		l.p.pitch_scale = clampf(l.rate, 0.05, 4.0)
		var fx := AudioServer.get_bus_effect(l.bus, 0) as AudioEffectLowPassFilter
		if fx: fx.cutoff_hz = clampf(l.lp, 50, 20000)
	engine_gain = lerpf(engine_gain, 1.0 - (duck_amt * 0.8 if clock < duck_until else 0.0), 1.0 - exp(-delta / 0.25))
	if music and music.stream:
		var target := music_target * ((1.0 - duck_amt) if clock < duck_until else 1.0)
		music_gain = lerpf(music_gain, target, 1.0 - exp(-delta / (0.02 if clock < duck_until else 0.25)))
		music.volume_db = linear_to_db(maxf(music_gain, 1e-5))
		var fx := AudioServer.get_bus_effect(_bus("Music"), 0) as AudioEffectLowPassFilter
		if fx: fx.cutoff_hz = lerpf(fx.cutoff_hz, music_lp, 1.0 - exp(-delta / 0.25))

# ---------- enemy jets: positional loops ----------
func attach_voices(list: Array) -> void:
	if not started or voices.size() or not buf.has("enemy_jet"): return
	for e in list:
		var p := AudioStreamPlayer3D.new(); p.stream = buf.enemy_jet; p.bus = "SFX"; p.unit_size = 7.0; p.max_distance = 300.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE; p.volume_db = -80.0
		e.j.add_child(p); p.play(randf() * 2)
		voices.append({"e": e, "p": p, "prevD": 999.0, "flyCd": 0.0})

func update_voices(dt: float, player_pos: Vector3, slow: bool) -> void:
	for v in voices:
		var e: Dictionary = v.e
		v.p.volume_db = linear_to_db(0.7) if e.alive else -80.0
		if not e.alive: continue
		var d: float = e.pos.distance_to(player_pos)
		var closing: float = (v.prevD - d) / maxf(dt, 1e-3)
		v.prevD = d
		v.p.pitch_scale = clampf(1 + closing / 150, 0.7, 1.4) * (0.6 if slow else 1.0)
		v.flyCd -= dt
		if d < 11 and closing < -5 and v.flyCd <= 0: v.flyCd = 2.5; play("homing_dash", {"vol": 0.6, "rate": 0.8, "pos": e.pos})

# ---------- music timing ----------
## seconds until the next beat subdivision (div 1 = beat, 2 = eighth); used to land musical sweeteners in time
func until_beat(div := 2) -> float:
	if music == null or not music.playing: return 0.0
	var pos := music.get_playback_position() + AudioServer.get_time_since_last_mix()
	var p: float = BEAT.period / div
	var ph := fposmod(pos - BEAT.first, p)
	return p - ph

func _on_beat(mx := 0.16, div := 2) -> float:
	var w := until_beat(div)
	return w if w <= mx else 0.0

func duck(amt := 0.45, dur := 0.5) -> void:
	duck_until = clock + dur; duck_amt = amt

# ---------- one-shots ----------
func _pick_variant(name: String):
	if buf.has(name): return name
	var g: Array = groups.get(name, [])
	if g.is_empty(): return null
	var n: String = g.pick_random()
	if g.size() > 1 and n == last_pick.get(name, ""): n = g[(g.find(n) + 1) % g.size()]
	last_pick[name] = n
	return n

## o: vol, rate, jit, bus ("ui"), pos (Vector3: positional), delay, send (reverb), exact
func play(name: String, o := {}) -> void:
	if not started: return
	var n = name if o.get("exact", false) else _pick_variant(name)
	if n == null or not buf.has(n): return
	var delay: float = o.get("delay", 0.0)
	if delay > 0.0:
		var oo := o.duplicate(); oo.erase("delay"); oo["exact"] = true
		get_tree().create_timer(delay, true, false, true).timeout.connect(func(): play(n, oo))
		return
	var base := _base(name)
	var lim: int = LIMIT.get(base, 5)
	for i in range(playing.size() - 1, -1, -1):
		if playing[i].end < clock or not is_instance_valid(playing[i].p): playing.remove_at(i)
	var same := playing.filter(func(x): return x.base == base)
	if same.size() >= lim:
		var old = same[0]
		if is_instance_valid(old.p): old.p.queue_free()
		playing.erase(old)
	if playing.size() > 40:
		var old = playing.pop_front()
		if is_instance_valid(old.p): old.p.queue_free()
	var rate: float = o.get("rate", 1.0) * (1 + o.get("jit", 0.03) * randf_range(-1, 1))
	var vol: float = o.get("vol", 0.8)
	var bus := "UI" if o.get("bus", "") == "ui" else "SFX"
	var p: Node
	if o.has("pos"):
		var p3 := AudioStreamPlayer3D.new(); p3.unit_size = 10.0; p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.stream = buf[n]; p3.pitch_scale = maxf(0.05, rate); p3.volume_db = linear_to_db(maxf(vol, 1e-4)); p3.bus = bus
		add_child(p3); p3.global_position = o.pos; p3.play(); p = p3
		p3.finished.connect(p3.queue_free)
	else:
		var p2 := AudioStreamPlayer.new(); p2.stream = buf[n]; p2.pitch_scale = maxf(0.05, rate); p2.volume_db = linear_to_db(maxf(vol, 1e-4)); p2.bus = bus
		add_child(p2); p2.play(); p = p2
		p2.finished.connect(p2.queue_free)
	if o.get("send", 0.0) > 0.0:
		var r := AudioStreamPlayer.new(); r.stream = buf[n]; r.pitch_scale = maxf(0.05, rate); r.volume_db = linear_to_db(vol * o.send); r.bus = "Reverb"
		add_child(r); r.play(); r.finished.connect(r.queue_free)
	playing.append({"p": p, "base": base, "end": clock + buf[n].get_length() / rate})

func st(i: int) -> float:
	return pow(2.0, (C_MINOR[posmod(i, 5)] + 12 * floori(i / 5.0)) / 12.0)

# ---------- semantic cues ----------
func ui(k: String) -> void:
	var m := {"hover": "ui_hover", "select": "ui_select", "back": "ui_back", "start": "ui_start", "pause": "ui_pause", "play": "ui_play", "warning": "ui_warning"}
	if m.has(k): play(m[k], {"vol": 0.5 if k == "hover" else 0.8, "bus": "ui", "jit": 0.01})
# homing / charge crystals
func lock() -> void: play("lock", {"vol": 0.55, "jit": 0.01})
func homing_dash() -> void: play("homing_dash", {"vol": 0.75})
func whiff() -> void: play("homing_whiff", {"vol": 0.6})
func crunch(k := 0) -> void: play("crunch", {"vol": 1.0, "rate": [1.0, 1.122, 1.26, 1.335][mini(3, k)], "jit": 0.01, "send": 0.12}); duck(0.25, 0.25)
func chain_complete() -> void: play("chain_complete", {"vol": 1.0, "send": 0.25}); duck(0.5, 0.8)
func takedown(pos: Vector3) -> void: play("takedown", {"vol": 1.0, "pos": pos, "send": 0.12}); duck(0.3, 0.3)
# boost
func ring(i: int) -> void: play("ring", {"vol": 0.75, "rate": [1.0, 1.122, 1.26, 1.5][clampi(i - 1, 0, 3)], "jit": 0.0})
func blast(lvl: int) -> void: play("blast_%d" % clampi(lvl - 1, 0, 2), {"vol": 0.95, "exact": true, "send": 0.1 + lvl * 0.05}); duck(0.2 + lvl * 0.1, 0.3 + lvl * 0.15)
func ring_pass(i: int) -> void: play("ringpass", {"vol": 0.75, "rate": 1 + mini(i, 3) * 0.06})
func boom(_k := 1.0) -> void: play("boom", {"vol": 1.0, "send": 0.3}); duck(0.6, 0.8)
func crackle(amt: float) -> void:
	if randf() > amt * 0.35: return
	play("crackle", {"vol": 0.25 + amt * 0.35, "rate": randf_range(0.8, 1.3)})
# tunnels and pickups
func tunnel_open() -> void: play("tunnel_open", {"vol": 1.0, "send": 0.3})
func tunnel_enter() -> void: play("tunnel_enter", {"vol": 0.9})
func tunnel_exit() -> void: play("tunnel_exit", {"vol": 1.0, "send": 0.18}); duck(0.45, 0.6)
func gem(i: int) -> void: play("gem", {"vol": 0.55, "rate": 0.9 * st(i % 12), "jit": 0.0})
func crystal(i: int) -> void: play("crystal", {"vol": 0.5, "rate": st(i % 10), "jit": 0.0})
func row_clear() -> void: play("row_clear", {"vol": 0.85, "delay": _on_beat(), "send": 0.15})
func strobe(ok: bool) -> void: play("strobe_ok" if ok else "strobe_miss", {"vol": 0.85})
func homer() -> void: play("crystal", {"vol": 0.6, "rate": 0.8}); play("ringpass", {"vol": 0.4, "rate": 1.3})
func weapon() -> void: play("weapon_pickup", {"vol": 0.9})
func ring_launch() -> void: play("ring_launch", {"vol": 0.8})
func magnet() -> void: play("magnet_on", {"vol": 0.8})
# combat
func explode(pos: Vector3) -> void: play("explode", {"vol": 1.0, "pos": pos, "send": 0.1})
func shot(dist: float, pos: Vector3) -> void: play("enemy_shot", {"vol": 0.6 * clampf(18 / maxf(dist, 6), 0.1, 1), "pos": pos})
func hurt() -> void: play("hurt", {"vol": 0.95}); duck(0.3, 0.3)
func orb_shatter() -> void: play("orb_shatter", {"vol": 1.0, "send": 0.35}); duck(0.65, 1.2)
func alarm(vol := 0.5) -> void: play("alarm", {"vol": vol * 1.4})
func probe_spawn(pos: Vector3) -> void: play("probe_spawn", {"vol": 0.6, "pos": pos})
func superblast() -> void: play("superblast", {"vol": 0.9, "send": 0.2})
# turbo, puzzles, supercut
func turbo_ready() -> void: play("turbo_ready", {"vol": 0.9, "delay": _on_beat(0.2, 1), "send": 0.15})
func cell_full() -> void: play("cell_full", {"vol": 0.8, "delay": _on_beat()})
func forge() -> void: play("forge", {"vol": 0.8})
func puzzle_start() -> void: play("puzzle_start", {"vol": 0.9, "send": 0.2})
func puzzle_hit(i: int) -> void: play("puzzle_hit_%d" % clampi(i - 1, 0, 3), {"vol": 0.9, "exact": true, "jit": 0.0})
func success() -> void: play("match_boost", {"vol": 1.0, "send": 0.2}); duck(0.4, 0.5)
func fail() -> void: play("fizzle", {"vol": 0.9})
func loadup() -> void: play("loadup", {"vol": 0.85})
func release_cue() -> void: play("release_cue", {"vol": 0.9})
func pop() -> void: play("supercut_pop", {"vol": 1.0, "send": 0.3}); duck(0.6, 0.8)
func hit(n: int) -> void: play("sc_hit", {"vol": 1.0, "rate": minf(1.5, 0.94 + n * 0.04), "jit": 0.0, "send": 0.08})
func click() -> void: play("lock", {"vol": 0.6, "rate": 1.2})
func perfect() -> void: play("perfect", {"vol": 0.75})
func slam() -> void: play("slam", {"vol": 0.9, "send": 0.12}); duck(0.4, 0.4)
func shatter() -> void: play("shatter", {"vol": 0.6})
## legacy names used by the game for big moments
func event(k: String) -> void:
	match k:
		"complete": play("complete", {"vol": 0.9, "delay": _on_beat(0.2, 1), "send": 0.2})
		"fizzle": fail()
		"warning": play("ui_warning", {"vol": 0.9})
		"tunnel": tunnel_exit()
		"orb": orb_shatter()
		"match": success()
		_: play("step", {"vol": 0.8, "delay": _on_beat()})
func rank_up(r: int) -> void: play("rank_up", {"vol": 0.75, "rate": 0.9 + r * 0.05, "jit": 0.0, "delay": _on_beat(0.12)})
func rank_down() -> void: play("rank_down", {"vol": 0.7})
func step() -> void: play("step", {"vol": 0.8})
func tick(hi: bool) -> void: play("ui_hover", {"vol": 0.75 if hi else 0.5, "rate": 1.4 if hi else 1.1, "jit": 0.0, "bus": "ui"})
func ready_ping() -> void: play("ui_play", {"vol": 0.6, "bus": "ui"})
# the Iris
func iris_groan() -> void: play("iris_groan", {"vol": 1.0, "send": 0.3}); duck(0.35, 1.2)
func iris_tick(hi: bool) -> void: play("iris_tick", {"vol": 0.9 if hi else 0.65, "rate": 1.122 if hi else 1.0, "jit": 0.0})
func iris_bite() -> void: play("iris_bite", {"vol": 0.9})
func whoosh(up := true, vol := 0.5) -> void: play("ringpass", {"vol": vol * 1.2, "rate": 1.1 if up else 0.8})

# ---------- per-frame mix ----------
## s: speed, boost, slowmo, playing, charge, tunnel, iris, mode, rank
func update(s: Dictionary) -> void:
	if not started: return
	var sp := clampf(s.speed / 140, 0, 1)
	var bo := clampf(s.boost / 60, 0, 1)
	var slow: bool = s.slowmo
	var k := 1.0 if s.playing else 0.3
	var sr := 0.62 if slow else 1.0
	# engine: rumble bed + thruster + electric whine + afterburner, all following speed
	_set_loop("engine_bed", (0.55 + sp * 0.35) * k, (0.75 + sp * 0.55 + bo * 0.15) * sr, (500 + sp * 2200 + bo * 900) * (0.5 if slow else 1.0))
	_set_loop("engine_thrust", (0.12 + sp * 0.45 + bo * 0.25) * k, (0.85 + sp * 0.35) * sr, 2000 + sp * 9000)
	_set_loop("engine_whine", (0.1 + sp * 0.28) * k * (0.5 if slow else 1.0), (0.8 + sp * 0.7 + bo * 0.2) * sr, 9000)
	_set_loop("afterburner", bo * bo * 0.85 * k, (0.9 + bo * 0.3) * sr, 3000 + bo * 7000, 0.06)
	if s.playing and bo > 0.2: crackle(bo)
	var ch: float = s.charge
	_set_loop("charge_hum", 0.25 + ch * 0.55 if ch > 0 else 0.0, 0.8 + ch * 0.6, 1500 + ch * 8000, 0.05)
	_set_loop("tunnel_wind", 0.85 if s.tunnel else clampf((s.speed - 60) / 100, 0, 0.3) * k, 1.15 if s.tunnel else 0.9 + sp * 0.3, 9000.0 if s.tunnel else 3000.0, 0.2)
	_set_loop("iris_drone", clampf(s.iris, 0, 1) * 0.9 * k, 1.0, 600 + s.iris * 2400, 0.4)
	# music: muffled on menus and in slow-mo; opens up as style rank climbs
	if music:
		music.pitch_scale = lerpf(music.pitch_scale, 0.8 if s.mode == "puzzle" else (0.9 if s.mode == "loadup" else 1.0), 0.15)
		var rank_lp: float = [2200, 4200, 9000, 16000, 18000, 18000, 18000][clampi(s.rank, 0, 6)]
		var m: String = s.mode
		music_lp = 1600.0 if m == "title" else (500.0 if m == "pause" else (900.0 if m == "over" else (700.0 if m == "puzzle" else (1400.0 if m == "loadup" else (18000.0 if m == "super" else rank_lp)))))
		music_target = 1.15 if m == "super" else (0.8 if m == "title" else (1.1 if s.rank >= 4 else 1.0))

func set_muted(m: bool) -> void:
	muted = m; U.sset("ub_muted", m)
	AudioServer.set_bus_mute(0, m)

func is_muted() -> bool: return muted

func set_volumes(v: Dictionary) -> void:
	vols.merge(v, true); U.sset("ub_vols", vols); _apply_vols()

func _apply_vols() -> void:
	AudioServer.set_bus_mute(0, muted)
	var i := _bus("SFX")
	if i >= 0: AudioServer.set_bus_volume_db(i, linear_to_db(maxf(vols.sfx, 1e-4)))
	i = _bus("UI")
	if i >= 0: AudioServer.set_bus_volume_db(i, linear_to_db(maxf(vols.sfx * 0.85, 1e-4)))
	i = _bus("Music")
	if i >= 0: AudioServer.set_bus_volume_db(i, linear_to_db(maxf(vols.music * 0.5, 1e-4)))

func get_volumes() -> Dictionary: return vols.duplicate()
