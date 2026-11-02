extends SceneTree
## Writes the input map into project.godot (run once after changing bindings):
##   godot --headless --path . --script res://tools/setup_input.gd
## Keyboard + mouse match the web build; the Xbox layout matches its Gamepad API mapping
## (A / RT boost, X B Y RB LT homing, D-pad puzzle directions, Start pause, View continue).

func key(code: Key) -> InputEventKey:
	var e := InputEventKey.new(); e.physical_keycode = code; e.device = -1; return e

func joy(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new(); e.button_index = b; e.device = -1; return e

func axis(a: JoyAxis, v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new(); e.axis = a; e.axis_value = v; e.device = -1; return e

func mouse(b: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new(); e.button_index = b; e.device = -1; return e

func _init() -> void:
	var map := {
		"steer_left": [key(KEY_A), key(KEY_LEFT)],
		"steer_right": [key(KEY_D), key(KEY_RIGHT)],
		"steer_up": [key(KEY_W), key(KEY_UP)],
		"steer_down": [key(KEY_S), key(KEY_DOWN)],
		"dir_up": [key(KEY_W), key(KEY_UP), joy(JOY_BUTTON_DPAD_UP)],
		"dir_down": [key(KEY_S), key(KEY_DOWN), joy(JOY_BUTTON_DPAD_DOWN)],
		"dir_left": [key(KEY_A), key(KEY_LEFT), joy(JOY_BUTTON_DPAD_LEFT)],
		"dir_right": [key(KEY_D), key(KEY_RIGHT), joy(JOY_BUTTON_DPAD_RIGHT)],
		"boost": [key(KEY_SPACE), mouse(MOUSE_BUTTON_LEFT), joy(JOY_BUTTON_A), axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)],
		"homing": [key(KEY_E), key(KEY_F), key(KEY_K), key(KEY_J), key(KEY_Q), key(KEY_SHIFT), mouse(MOUSE_BUTTON_RIGHT),
			joy(JOY_BUTTON_X), joy(JOY_BUTTON_B), joy(JOY_BUTTON_Y), joy(JOY_BUTTON_RIGHT_SHOULDER), axis(JOY_AXIS_TRIGGER_LEFT, 1.0)],
		"pause": [key(KEY_ESCAPE), key(KEY_P), joy(JOY_BUTTON_START)],
		"mute": [key(KEY_M)],
		"next": [key(KEY_ENTER), key(KEY_KP_ENTER), joy(JOY_BUTTON_BACK)],
		"skip": [key(KEY_TAB)],
		"note": [key(KEY_T)],
	}
	for action in map:
		var evs: Array = []
		for e in map[action]: evs.append(e)
		ProjectSettings.set_setting("input/" + action, {"deadzone": 0.35, "events": evs})
	ProjectSettings.save()
	print("input map written: ", map.size(), " actions")
	quit()
