class_name Hud
extends Control
## In-run HUD (updateHUD in 60_game.js): score, timer and phase, the Iris dial, style rank and turbo cells,
## hull, thruster pips with the boom and homing chips, prompt line, speed gauge, recorder badge and note box.

@onready var score_lbl: Label = %Score
@onready var mult_lbl: Label = %Mult
@onready var weapon_lbl: Label = %Weapon
@onready var timer_lbl: Label = %Timer
@onready var world_lbl: Label = %WorldLbl
@onready var iris_w: HudWidget = %Iris
@onready var iris_txt: Label = %IrisTxt
@onready var banner: Label = %Banner
@onready var style_box: Control = %StyleBox
@onready var rank_n: Label = %RankN
@onready var rank_l: Label = %RankL
@onready var rank_bar: HudWidget = %RankBar
@onready var turbo_row: Control = %TurboRow
@onready var cells_w: HudWidget = %Cells
@onready var turbo_state: Label = %TurboState
@onready var hull_w: HudWidget = %Hull
@onready var fuel_w: HudWidget = %Fuel
@onready var fuel_lbl: Label = %FuelLbl
@onready var thruster: Control = %Thruster
@onready var home_chip: HudWidget = %HomeChip
@onready var pips_w: HudWidget = %Pips
@onready var boom_chip: HudWidget = %BoomChip
@onready var prompt: Label = %Prompt
@onready var speed_lbl: Label = %Speed
@onready var gauge: HudWidget = %Gauge
@onready var coach: CoachPanel = %Coach
@onready var rec_badge: Control = %RecBadge
@onready var rec_note: Control = %RecNote
@onready var rec_input: LineEdit = %RecNoteIn
@onready var tl: Control = %TL
@onready var tc: Control = %TC
@onready var tr_box: Control = %TR
@onready var bl: Control = %BL

var on := false
var cache := {}
var banner_blink := false
var rank_pop := 0.0
var hl: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	rec_note.visible = false
	rec_input.text_submitted.connect(func(t): REC.close_typed(true, t))
	rec_input.gui_input.connect(_note_input)

func _note_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		REC.close_typed(false); get_viewport().set_input_as_handled()

func open_note() -> void:
	rec_note.visible = true; rec_input.text = ""; rec_input.grab_focus()

func close_note() -> void:
	rec_note.visible = false; rec_input.release_focus()

func set_on(v: bool) -> void:
	on = v
	var tw := create_tween(); tw.tween_property(self, "modulate:a", 1.0 if v else 0.0, 0.4)
	if not v: coach.hide_card()

func set_banner(text: String, blink := false) -> void:
	banner.text = text; banner_blink = blink

func highlight(ids: Array) -> void:
	hl = ids

func relabel() -> void:
	cache.clear()

func _txt(lbl: Label, key: String, v: String) -> void:
	if cache.get(key) != v: cache[key] = v; lbl.text = v

func _process(delta: float) -> void:
	if banner_blink: banner.modulate.a = 1.0 if int(Ctl.now / 0.175) % 2 == 0 else 0.25
	else: banner.modulate.a = 1.0
	rank_pop = maxf(0, rank_pop - delta / 0.45)
	rank_l.scale = Vector2.ONE * (1 + 0.7 * rank_pop * rank_pop)
	rank_l.pivot_offset = rank_l.size / 2
	rec_badge.visible = on and REC.s != null
	for n in [thruster, style_box, boom_chip]:
		var name_id: String = "thruster" if n == thruster else ("styleBox" if n == style_box else "boomChip")
		n.self_modulate = Color(1, 1, 1) if not hl.has(name_id) else Color(1, 1, 1).lerp(Color(0.7, 1.3, 1.5), 0.5 + 0.5 * sin(Ctl.now * 7))

func update_hud() -> void:
	_txt(score_lbl, "score", _commas(GAME.score))
	_txt(mult_lbl, "mult", "×%s" % str(GAME.mult()).trim_suffix(".0"))
	if TUT.active:
		_txt(timer_lbl, "timer", "FLIGHT SCHOOL")
		_txt(world_lbl, "world", "STEP %d OF %d · %s" % [TUT.lesson_no(TUT.i), TUT.lessons(), TUT.step().ch])
	else:
		var rem := maxf(0, World.ROUND_TIME - GAME.time)
		_txt(timer_lbl, "timer", "%d:%02d" % [floori(rem / 60), floori(fmod(rem, 60))])
		_txt(world_lbl, "world", "PHASE %d · %s" % [ST.DIR.phase + 1, ST.PHASES[ST.DIR.phase].name])
	# the Iris dial: aperture size, glows while the glyphs etch
	var IR: Dictionary = ST.IRIS
	iris_w.value = clampf((World.R - 50) / (World.R0 - 50), 0.1, 1)
	iris_w.flags = {"warn": IR.state == "warn", "close": IR.state == "close"}
	var nxt = IR.stages[IR.i] if IR.i < IR.stages.size() else null
	var it := ""
	if not TUT.active:
		if IR.state == "warn": it = "CLOSING %d" % ceili(IR.warnT - IR.t)
		elif IR.state == "close": it = "CLOSING"
		elif nxt: it = "IRIS %ds" % maxi(0, ceili(nxt.t - IR.warnT - GAME.time))
		else: it = "SEALED"
	_txt(iris_txt, "iris", it)
	hull_w.value = P.hull / 100.0
	# flight v5: fuel gauge (lime while riding, blinking coral when low)
	fuel_w.value = clampf(P.fuel / 100.0, 0, 1)
	fuel_w.color = Color.html("#dce9a9") if P.ride != null else Color.html("#4fd2ff")
	fuel_lbl.add_theme_color_override("font_color", Color.html("#dce9a9") if P.ride != null else (Color.html("#ff5b3d") if P.fuel < 25 and int(Ctl.now * 4) % 2 == 0 else Color.html("#b9a9c9")))
	# style rank
	var R: Dictionary = ST.RANKS[ST.rank]
	if cache.get("rank") != ST.rank:
		cache["rank"] = ST.rank
		var rc := Color.html(R.c)
		rank_l.text = R.l; rank_n.text = R.n
		rank_l.add_theme_color_override("font_color", rc); rank_n.add_theme_color_override("font_color", rc)
		rank_bar.color = rc; rank_bar.color2 = rc
		rank_pop = 1.0
	rank_bar.value = clampf(ST.bar / 100, 0, 1)
	# turbo gauge
	var locked := ST.rank < ST.TURBO_RANK
	var ready: bool = ST.turbo_ready()
	cells_w.flags = {"locked": locked, "ready": ready}
	for k in 3: cells_w.cells[k] = clampf(ST.cells - k, 0, 1)
	var tss := ""
	if P.mode == "puzzle" and BL.puzzle and BL.puzzle.ctx == "turbo": tss = "MINIBLAST · TIER %d" % BL.puzzle.tier
	elif P.mode == "loadup": tss = "LOADING UP"
	elif P.mode == "supercut" and BL.sc: tss = "%s %d/%d" % [BL.LEVEL_NAMES[BL.sc.level], BL.sc.matches, BL.sc.max]
	elif locked: tss = "LOCKED · REACH RANK B"
	elif ST.turboCd > 0: tss = "COOLING %ds" % ceili(ST.turboCd)
	elif ready: tss = "READY · TIER %d" % ST.turbo_tier_avail()
	else: tss = "FILLING"
	_txt(turbo_state, "tstate", tss)
	turbo_state.add_theme_color_override("font_color", Color.html("#ffd27a") if ready and P.mode == "fly" else Color.html("#b9a9c9"))
	# thruster: pips, gold turbo pip, boom dial, homing chip
	var rings: int = BL.rings if BL.charging or (P.mode == "puzzle" and BL.puzzle and BL.puzzle.ctx == "turbo") or P.mode == "loadup" else 0
	for k in 3:
		pips_w.pips[k] = k < rings
		pips_w.rail[k] = not BL.charging and k < BL.railBonus
	pips_w.gold_avail = ready; pips_w.gold_on = rings >= 4 or BL.forging > 0.25
	pips_w.flags = {"cool": ST.blastCd > 0}
	boom_chip.value = 1.0 - ST.boomCd / ST.COOL.boom
	boom_chip.flags = {"ready": ST.boomCd <= 0}
	home_chip.flags = {"locked": HOM.lock != null and P.mode == "fly", "dash": P.mode == "homing"}
	pips_w.visible = not (TUT.active and not ST.UNLOCK.has("boost"))
	boom_chip.visible = pips_w.visible
	home_chip.visible = not (TUT.active and not ST.UNLOCK.has("homing"))
	turbo_row.modulate.a = 0.0 if TUT.active and not ST.UNLOCK.has("turbo") else 1.0
	turbo_state.modulate.a = turbo_row.modulate.a
	_txt(speed_lbl, "speed", str(roundi(P.speed * 9.5)))
	gauge.value = clampf(P.boost / 70, 0, 1); gauge.value2 = clampf(GAME.momentum / 24, 0, 1)
	var w := ""
	if P.weapon: w = "%s ×%d" % [World.WEAPONS[P.weapon.type].name, P.weapon.ammo]
	if P.magnetT > 0: w += ("  ·  " if w != "" else "") + "MAGNET %ds" % ceili(P.magnetT)
	_txt(weapon_lbl, "weapon", w)
	var pr := ""
	var bk := Ctl.kl("SPACE", "RT")
	var hk := Ctl.kl("E", "X")
	if P.mode == "fly":
		if P.stun > 0: pr = "STUNNED"
		elif BL.payload: pr = "MATCHED · LET GO TO FIRE"
		elif BL.charging and BL.forgeRing: pr = "FORGING THE TURBO RING…"
		elif P.prime and not BL.charging: pr = "PRIMED · HOLD %s" % bk
		elif BL.charging and BL.rings >= 3: pr = "KEEP HOLDING FOR TURBO" if ready else "FULL · LET GO TO BLAST · %s = BOOM" % hk
		elif BL.charging: pr = "THRUSTING · LET GO TO BLAST"
		elif HOM.win and HOM.lock: pr = "%s WHEN THE RING HITS GOLD · CHAIN %d / %d" % [hk, HOM.chain, HOM.HOMING.cap]
		elif HOM.lock and ST.unlocked("homing") and HOM.charges < 1: pr = "HOMING RECHARGING"
		elif HOM.lock and ST.unlocked("homing"): pr = "LOCKED · %s TO HOME IN" % hk
		elif ready: pr = "TURBO READY · HOLD %s PAST 3 RINGS" % bk
		elif ST.unlocked("boost"): pr = "HOLD %s TO CHARGE · %s TO HOME" % [bk, hk]
		elif ST.unlocked("homing"): pr = "%s TO HOME IN ON A LOCK" % hk
	if P.mode == "fly" and P.stun <= 0 and BL.payload == null:
		if P.ride != null:
			var ve: float = P.v_esc_for(P.ride)
			if P.speed >= ve: pr = "ESCAPE SPEED · PULL UP OR BLAST · FUEL %d%%" % roundi(P.fuel)
			else: pr = "RIDING · FUEL %d%% · ESCAPE %d/%d · HOLD %s" % [roundi(P.fuel), roundi(P.speed * 9.5), roundi(ve * 9.5), bk]
		elif not P.lit: pr = "ENGINE OUT · GLIDE ONTO A PLANET"
	if P.mode == "tunnel": pr = "RIFT TUNNEL · STEER TO GRAB GEMS"
	elif P.mode == "homing": pr = "WAIT FOR THE RING…"
	_txt(prompt, "prompt", pr)
	var hide: bool = P.mode in ["puzzle", "loadup", "supercut"]
	thruster.modulate.a = 0.0 if hide else 1.0
	var dim := 0.08 if P.mode == "puzzle" or P.mode == "loadup" else 1.0
	tc.modulate.a = dim; tr_box.modulate.a = dim; bl.modulate.a = dim

static func _commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
