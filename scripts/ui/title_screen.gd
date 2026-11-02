extends ScreenBase
## Title: controls card, LAUNCH / FLIGHT SCHOOL, settings checkboxes, recorder export, best score and build line.

func _ready() -> void:
	%StartBtn.pressed.connect(func(): GAME.start_game())
	%TutBtn.pressed.connect(func(): TUT.start())
	%InvY.button_pressed = U.sget("ub_invY", false)
	%InvY.toggled.connect(func(v): Ctl.invert_y = v; U.sset("ub_invY", v); AudioSys.ui("select"))
	%MuteChk.toggled.connect(func(v): AudioSys.set_muted(v); AudioSys.ui("select"))
	%RumbleChk.button_pressed = U.sget("ub_rumble", true)
	%RumbleChk.toggled.connect(func(v): U.sset("ub_rumble", v); AudioSys.ui("select"); if v: Ctl.rumble(0.6, 0.8, 180))
	%RecChk.toggled.connect(func(v): REC.set_on(v); AudioSys.ui("select"))
	%RecExport.pressed.connect(_export)
	%RecOpen.pressed.connect(func(): OS.shell_open(ProjectSettings.globalize_path(REC.DIR)))
	%RecClear.pressed.connect(func(): REC.clear_local(); _refresh())
	REC.changed.connect(_refresh)
	wire_sounds()
	relabel()

func on_show() -> void:
	super.on_show()
	sync(); _refresh()
	var best: int = U.sget("ub_best", 0)
	%BestLine.text = ("BEST %s" % Hud._commas(best)) if best else ""
	%VerLine.text = "BUILD %s · GODOT %s" % [REC.BUILD.to_upper(), Engine.get_version_info().string.to_upper()]

func sync() -> void:
	%MuteChk.set_pressed_no_signal(AudioSys.is_muted())
	%RecChk.set_pressed_no_signal(REC.on)

func _refresh() -> void:
	var n := REC.session_count()
	%RecExport.text = "EXPORT PLAYTESTS (%d)" % n
	%RecExport.visible = n > 0; %RecClear.visible = n > 0
	%RecLine.text = "Recorder %s. While playing, press T to type a note" % REC.state_text()

func _export() -> void:
	var path := REC.export_all()
	%RecLine.text = ("Exported to %s" % path) if path != "" else "Nothing to export yet"

func set_pad_note(t: String) -> void:
	%PadNote.text = t; %PadNote.visible = t != ""

## controls card follows the device in use
func relabel() -> void:
	var g: GridContainer = %Controls
	for c in g.get_children(): c.queue_free()
	var rows := [
		["MOUSE / WASD", "Steer. Near a planet, up/down changes altitude"],
		["E / RMB", "Homing: dash into the lock (3 charges). Chain when the ring turns gold; 5 links = finisher"],
		["HOLD SPACE / LMB", "Thrust and charge up to 3 rings, let go to blast through them"],
		["3 CRYSTALS", "Cyan charge crystals open a rift tunnel ahead. Quick chain = gold"],
		["PRIME + HOLD", "Home into a cache or exposed orb, hold boost to solve its miniblast, let go to fire"],
		["SPACE + E", "While charging: bundle boom (7 s cooldown)"],
		["RANK B + CELL", "Hold past 3 rings: turbo, miniblast, release, supercut"],
		["XBOX PAD", "Left stick steer · X homing · hold RT or A boost · D-pad puzzles · View continues Flight School"],
	]
	for r in rows:
		var k := Label.new(); k.text = r[0]; k.theme_type_variation = &"Kbd"; k.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var v := Label.new(); v.text = r[1]; v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.custom_minimum_size.x = 520
		v.add_theme_font_size_override("font_size", 14)
		g.add_child(k); g.add_child(v)
