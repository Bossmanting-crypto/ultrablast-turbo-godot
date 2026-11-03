extends Node
## Coach card (port of the Coach object in 45_style.js): one-time hints during runs and the step cards of
## Flight School. The card itself is the Coach panel in hud.tscn (coach_panel.gd); this autoload decides
## what it shows. Body text is BBCode: B() highlights, K() draws an inline key cap.

var seen := {}
var queue: Array = []
var t := 0.0
var mode := "off"

func panel() -> CoachPanel:
	return GAME.hud.coach if GAME.hud else null

static func B(s: String) -> String: return "[color=#ffd27a][b]%s[/b][/color]" % s
static func K(kb: String, pad: String = "") -> String:
	return "[bgcolor=#f4c6a0][color=#0a0b22][b] %s [/b][/color][/bgcolor]" % Ctl.kl(kb, pad)

func hint_text(key: String) -> Array:
	match key:
		"primed": return ["PRIMED", "The target is %s. Hold %s: its miniblast starts while you charge. Solve it, then %s to fire the charged shot." % [B("primed"), K("SPACE", "RT"), B("let go")]]
		"turret": return ["TURRETS", "A %s means a turret is aiming. When it turns %s it has locked: turn hard. Home into turrets to knock them out." % [B("red laser sight"), B("white")]]
		"barrier": return ["THE GLASS", "The glass shell pushes you back. It only %s (the glyphs etch, then it tightens)." % B("hurts while the Iris is closing")]
		"homing": return ["HOMING", "Gold ring = %s. %s dashes in (costs a charge). After a hit, press when the closing ring turns %s to chain. Five links = %s." % [B("lock"), K("E / RMB", "X"), B("gold"), B("finisher")]]
		"charge": return ["CHARGE CRYSTALS", "Three cyan crystals tear a %s open where you are looking. Chain them quickly for a %s rift." % [B("rift tunnel"), B("gold")]]
		"boost": return ["BOOST", "Hold %s to charge up to 3 rings. Let go to blast through them." % K("SPACE / LMB", "RT")]
		"tunnel": return ["RIFT TUNNEL", "Fly into the portal. Near the exit, tap when the pulse sits in the band for a %s." % B("perfect blast")]
		"boom": return ["BUNDLE BOOM", "While charging rings, press %s to detonate them around you. 7 second cooldown." % K("E / RMB", "X")]
		"turboUnlock": return ["RANK B · TURBO UNLOCKED", "Keep your style up. Once a %s fills (top right), you can launch a turbo run." % B("turbo cell")]
		"turboReady": return ["TURBO READY", "Hold %s past 3 rings. A gold 4th ring forges and starts the %s." % [K("SPACE", "RT"), B("miniblast")]]
		"variety": return ["VARIETY", "Repeating one move earns less style. Mix homing, rifts, rings and takedowns."]
		"exposed": return ["ORB EXPOSED", "Its shield is down. %s to open the glyph lock before the shield returns." % B("Home into it")]
		"cache": return ["CRYSTAL CACHE", "The blue crystal clusters on the core hold weapons. %s and crack its miniblast." % B("Home into one")]
		"iris": return ["THE IRIS", "The glass shell is closing. When the glyphs finish etching, the aperture tightens. Stay inside."]
		"fuel": return ["FUEL", "Cruising sips fuel and thrusting burns it. When it runs out the engine dies and gravity takes you. Fly low over a mini-planet to ride it and refuel, then pull up past escape velocity (or fire a blast) to leave."]
		"ride": return ["RIDING", "You are riding the surface and refuelling. %s sets your height. To leave, get past escape speed (boost) and pull up, or let go of a charged blast." % Ctl.kl("W / S", "STICK")]
		"jets": return ["ENEMY JETS", "Jets hunt in slots around you and fire 3-shot bursts after the red ticks. Turn across their line, or put your nose on them: they break and jink."]
		"phase1": return ["CONTACT", "Enemy jets and orb turrets join in. Home into them or boost through them."]
		"phase2": return ["THE IRIS", "The core starts shifting and the glass shell begins to close in stages."]
		"phase3": return ["LAST LIGHT", "Everything is active and the aperture keeps closing. Spend your turbo cells."]
	return []

func reset() -> void:
	seen.clear(); queue.clear(); hide()

func hide() -> void:
	var p := panel()
	if p: p.hide_card()
	mode = "off"

func render(step: String, title: String, body: String, count: String, prog, skip: bool, tut: bool, late := false) -> void:
	var p := panel()
	if p: p.render(step, title, body, count, prog, skip, tut, late)

func hint(key: String, urgent := false) -> void:
	if TUT.active or GAME.state != "play" or seen.has(key) or hint_text(key).is_empty(): return
	seen[key] = true
	if urgent:
		queue.push_front(key)
		if mode == "hint": hide()
	else: queue.append(key)

func update(rdt: float) -> void:
	if TUT.active: return
	var busy: bool = P.mode in ["puzzle", "loadup", "supercut"]
	if mode == "hint":
		t -= rdt
		if t <= 0 or busy: hide()
	if mode == "off" and queue.size() and not busy:
		var k: String = queue.pop_front()
		var h := hint_text(k)
		render("TIP", h[0], h[1], "", null, false, false); mode = "hint"; t = 6.5; AudioSys.ui("hover")
