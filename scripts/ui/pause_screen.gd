extends ScreenBase
## Pause: volumes, mute, resume / quit, credits.

func _ready() -> void:
	%ResumeBtn.pressed.connect(func(): AudioSys.ui("select"); GAME.toggle_pause(false))
	%QuitBtn.pressed.connect(func(): AudioSys.ui("back"); GAME.to_title())
	%MuteChk2.toggled.connect(func(v): AudioSys.set_muted(v); AudioSys.ui("select"))
	var v := AudioSys.get_volumes()
	%VolMusic.value = roundi(v.music * 100); %VolSfx.value = roundi(v.sfx * 100)
	%VolMusic.value_changed.connect(func(_x): _vols())
	%VolSfx.value_changed.connect(func(_x): _vols())
	%VolSfx.drag_ended.connect(func(_c): AudioSys.ui("select"))
	wire_sounds()

func _vols() -> void:
	AudioSys.set_volumes({"music": %VolMusic.value / 100.0, "sfx": %VolSfx.value / 100.0})

func on_show() -> void:
	super.on_show(); sync()

func sync() -> void:
	%MuteChk2.set_pressed_no_signal(AudioSys.is_muted())

func _unhandled_input(e: InputEvent) -> void:
	super._unhandled_input(e)
	if visible and e.is_action_pressed("ui_cancel"): GAME.toggle_pause(false); get_viewport().set_input_as_handled()
