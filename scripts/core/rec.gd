extends Node
## PLAYTEST RECORDER (port of 07_rec.js). Logs what happens in a run or in Flight School (one compact event list
## per session) plus the player's own notes. Sessions are saved as JSON under user://playtests/ and EXPORT
## PLAYTESTS writes one combined file to your Downloads folder, in the same format as the web build, so the
## playtest analysis works unchanged. Notes while playing: T = type a note (the game freezes while you type).

const BUILD := "godot-2 (pc-v5)" # bump on every shipped build: printed on the title screen and in every export
const DIR := "user://playtests"

var on := true
var s = null              # live session
var last_session = null
var t0 := 0.0
var dirty := false
var last_save := 0.0
var sample_t := 0.0
var frames := 0
var fps_t := 0.0
var fps := 0.0
var fps_min := 999.0
var typing := false

signal changed

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	on = U.sget("ub_rec", true)
	DirAccess.make_dir_recursive_absolute(DIR)

func set_on(v: bool) -> void:
	on = v; U.sset("ub_rec", v)
	if not v and s: stop("recorder off")
	changed.emit()

func state_text() -> String:
	return "on, saving on this computer (export when done)" if on else "off"

# ---------- session lifecycle ----------
func start(mode: String) -> void:
	if s: stop("restart")
	if not on: return
	var now := Time.get_datetime_string_from_system(true)
	var id := now.replace(":", "-").replace("T", "-") + "-" + str(randi() % 46656).pad_zeros(4)
	var vs := get_viewport().get_visible_rect().size
	s = {"id": id, "part": 1, "mode": mode, "build": BUILD, "started": now + "Z", "view": [vs.x, vs.y], "touch": false,
		"ua": "Godot %s / %s" % [Engine.get_version_info().string, OS.get_name()], "ev": [], "notes": [], "summary": null, "ended": null}
	t0 = Ctl.now; sample_t = 0; fps_min = 999; frames = 0; fps_t = 0; last_save = Ctl.now
	ev("start", mode); changed.emit(); save()

func stop(why: String) -> void:
	if s == null: return
	ev("stop", why); s.ended = Time.get_datetime_string_from_system(true) + "Z"; s.endWhy = why
	save(); last_session = s; s = null; changed.emit()

## [real seconds since start, game seconds, type, value]
func ev(type: String, v = null) -> void:
	if s == null: return
	var row := [snappedf(Ctl.now - t0, 0.01), snappedf(GAME.time, 0.01), type]
	if v != null: row.append(snappedf(v, 0.001) if (v is float or v is int) else v)
	s.ev.append(row); dirty = true

func context() -> Dictionary:
	return {"mode": P.mode, "step": TUT.step_id() if TUT.active else null, "speed": roundi(P.speed * 9.5), "rank": ST.RANKS[ST.rank].l,
		"hull": roundi(P.hull), "lock": HOM.lock.kind if HOM.lock else null, "chain": HOM.chain}

func note(kind: String, text: String = "") -> void:
	if s == null: FX.popup("RECORDER IS OFF", "#c9a8ff"); return
	s.notes.append({"t": snappedf(Ctl.now - t0, 0.1), "gt": snappedf(GAME.time, 0.1), "kind": kind, "text": text, "at": context()})
	ev("note", kind); dirty = true
	FX.popup("NOTE SAVED", "#8fe9ff", true); AudioSys.ui("select")
	save()

# ---------- per frame ----------
func tick(rdt: float) -> void:
	frames += 1; fps_t += rdt
	if fps_t >= 1:
		fps = frames / fps_t; frames = 0; fps_t = 0
		if s and GAME.state == "play": fps_min = minf(fps_min, fps)
	if s == null or GAME.state != "play": return
	sample_t -= rdt
	if sample_t <= 0:
		sample_t = 1
		ev("s", [roundi(P.speed * 9.5), ST.rank, roundi(P.hull), P.mode, roundi(fps)])
	if dirty and Ctl.now - last_save > 20: save()

# ---------- summary + save ----------
func summarize(ss: Dictionary) -> Dictionary:
	var c := {}
	var gaps := []
	var strobe := []
	var hurt := {}
	var puzzles := {}
	var steps := {}
	var fps_sum := 0.0
	var fps_n := 0
	for row in ss.ev:
		var type: String = row[2]
		var v = row[3] if row.size() > 3 else null
		c[type] = c.get(type, 0) + 1
		if type == "press":
			var k := "press_lock" if v and v.get("lock") else "press_air"
			c[k] = c.get(k, 0) + 1
			if v and v.get("judge"): c["judge_" + v.judge] = c.get("judge_" + v.judge, 0) + 1
		if type == "homingHit": c["hit_" + str(v)] = c.get("hit_" + str(v), 0) + 1
		if type == "chargeGap": gaps.append(v)
		if type == "strobe": strobe.append(v.off)
		if type == "hurt":
			var why: String = v[1] if v[1] != "" else "other"
			hurt[why] = hurt.get(why, 0) + v[0]
		if type == "puzzleSuccess" or type == "puzzleFail":
			var k: String = v if v else "turbo"
			if not puzzles.has(k): puzzles[k] = {"ok": 0, "fail": 0}
			puzzles[k]["ok" if type == "puzzleSuccess" else "fail"] += 1
		if type == "breach":
			if not puzzles.has("breach"): puzzles.breach = {"ok": 0, "fail": 0}
			puzzles.breach["ok" if v else "fail"] += 1
		if type == "tut" and v.size() > 1:
			var id: String = v[1]
			if not steps.has(id): steps[id] = {}
			if v[0] == "pass": steps[id].pass = v[2]
			if v[0] == "next": steps[id].practice = v[2]
			if v[0] == "skip": steps[id].skipped = true
		if type == "s": fps_sum += v[4]; fps_n += 1
	return {"seconds": ss.ev[ss.ev.size() - 1][0] if ss.ev.size() else 0, "counts": c, "chargeGaps": gaps, "quickWindow": HOM.QUICK_WINDOW,
		"strobeOffsets": strobe, "hurtByCause": hurt, "puzzles": puzzles, "tutorialSteps": steps, "notes": ss.notes.size(),
		"fpsAvg": roundi(fps_sum / fps_n) if fps_n else null, "fpsMin": roundi(fps_min) if fps_min < 999 else null}

func save() -> void:
	var ss = s if s else last_session
	if ss == null: return
	dirty = false; last_save = Ctl.now
	ss.summary = summarize(ss); ss.savedAt = Time.get_datetime_string_from_system(true) + "Z"
	var f := FileAccess.open("%s/%s.json" % [DIR, ss.id], FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(ss)); f.close()
	changed.emit()

func local_sessions() -> Array:
	var out := []
	var d := DirAccess.open(DIR)
	if d == null: return out
	var files := d.get_files()
	files.sort()
	for fn in files:
		if not fn.ends_with(".json"): continue
		var txt := FileAccess.get_file_as_string(DIR + "/" + fn)
		var j = JSON.parse_string(txt)
		if j is Dictionary: out.append(j)
	return out

func session_count() -> int:
	var d := DirAccess.open(DIR)
	if d == null: return 0
	return Array(d.get_files()).filter(func(f): return f.ends_with(".json")).size()

## one JSON file to attach in the chat with Claude; returns the path written
func export_all() -> String:
	var list := local_sessions()
	if list.is_empty(): return ""
	var stamp := Time.get_datetime_string_from_system().substr(0, 16).replace(":", "-").replace("T", "-")
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if dir == "" or not DirAccess.dir_exists_absolute(dir): dir = ProjectSettings.globalize_path("user://")
	var path := "%s/ultrablast-playtests-%s.json" % [dir, stamp]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null: return ""
	f.store_string(JSON.stringify({"game": "ultrablast-turbo", "build": BUILD, "exported": Time.get_datetime_string_from_system(true) + "Z", "sessions": list}))
	f.close()
	AudioSys.ui("select")
	return path

func clear_local() -> void:
	var d := DirAccess.open(DIR)
	if d == null: return
	for fn in d.get_files(): d.remove(fn)
	changed.emit()

# ---------- typed note overlay ----------
func open_typed() -> void:
	if s == null or typing or GAME.state != "play": return
	typing = true; GAME.state = "paused"
	GAME.hud.open_note()

func close_typed(save_it: bool, text: String = "") -> void:
	if not typing: return
	typing = false; GAME.hud.close_note()
	GAME.state = "play"
	if save_it and text.strip_edges() != "": note("text", text.strip_edges().substr(0, 500))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and s: save()
